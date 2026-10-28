// Read-only SD transaction layer. Reuses the project's spi_master byte RTL.
// No third party implementation source. rst must be shared with fat32_ro.
module sd_spi_reader #(
 parameter integer CLK_HZ=100000000, LOW_DIV=248, HIGH_DIV=0,
 parameter integer POWER_CYCLES=CLK_HZ/500, INIT_CYCLES=CLK_HZ*2,
 parameter integer TOKEN_CYCLES=CLK_HZ/10, READ_CYCLES=CLK_HZ/2,
 parameter integer MAX_ATTEMPTS=3
)(input wire clk,rst,input wire reinit,
 output wire SD_nCS,SD_DCLK,SD_MOSI,input wire SD_MISO,
 output reg media_ready,init_error,output reg block_addressed,
 output reg [31:0] media_sectors,
 output reg [19:0] init_diagnostic,
 input wire req_valid,output wire req_ready,input wire [31:0] req_lba,req_tag,
 input wire cancel_valid,input wire [31:0] cancel_tag,
 output reg [31:0] rsp_tag,output reg rsp_valid,output reg [7:0] rsp_data,
 output reg rsp_done,rsp_error);
 localparam integer STATE_W=36;
 // Explicit one-hot control avoids decoding binary dynamic return states.
 localparam [STATE_W-1:0] POWER=(36'b1<<0),
 CLOCKS=(36'b1<<1),
 CLOCKED=(36'b1<<2),
 CMD_PRE=(36'b1<<3),
 CMD_SELECT=(36'b1<<4),
 CMD_SEND=(36'b1<<5),
 CMD_SENT=(36'b1<<6),
 R1=(36'b1<<7),
 R1_GOT=(36'b1<<8),
 TAIL=(36'b1<<9),
 TAIL_GOT=(36'b1<<10),
 DISPATCH=(36'b1<<11),
 TOKEN=(36'b1<<12),
 TOKEN_GOT=(36'b1<<13),
 DATA=(36'b1<<14),
 DATA_GOT=(36'b1<<15),
 CRC_HI=(36'b1<<16),
 CRC_LO=(36'b1<<17),
 CRC_CHECK=(36'b1<<18),
 GUARD=(36'b1<<19),
 GUARDED=(36'b1<<20),
 DESELECT=(36'b1<<21),
 RELEASED=(36'b1<<22),
 IDLE=(36'b1<<23),
 EMIT=(36'b1<<24),
 FINISH=(36'b1<<25),
 FAILED=(36'b1<<26),
 ABORT=(36'b1<<27),
 ABORTED=(36'b1<<28),
 BYTE_WAIT=(36'b1<<29),
 BYTE_GAP=(36'b1<<30),
 CSD_CHECK=(36'b1<<31),
 CSD_CAPACITY=(36'b1<<32),
 CSD_BOUNDS=(36'b1<<33),
 CSD_ACCEPT=(36'b1<<34),
 EMIT_WAIT=(36'b1<<35);
reg [STATE_W-1:0] state,resume,after_release;
reg cs,nCS_q,wr_req; reg [7:0] tx; wire [7:0] rx; wire ack;
 reg [15:0] divider;
 reg [31:0] timer,init_timer,read_timer,token_timer,lba;
 reg [3:0] gap; reg [9:0] count,emit_pos;
 reg [3:0] phase; reg [5:0] cmd_num; reg [31:0] cmd_arg;
 reg [47:0] command; reg [2:0] cmd_pos,tail_pos;
 reg [7:0] response; reg [31:0] tail; reg v2,active;
 reg [7:0] init_last_rx;
 reg [7:0] poll_count,attempt; reg [15:0] crc,card_crc;
 reg [127:0] csd; reg [7:0] buffer[0:511];
 reg [7:0] buffer_q;reg cancel_hit_q;
 wire [8:0] buffer_raddr=((|(state & FINISH)) && !cancel_valid && emit_pos<511) ? emit_pos[8:0]+1'b1:emit_pos[8:0];
 always @(posedge clk) begin
  buffer_q<=buffer[buffer_raddr];
  if(rst) cancel_hit_q<=0;
  else cancel_hit_q<=cancel_valid && active && cancel_tag==rsp_tag;
 end
 reg [12:0] v1_units;reg [22:0] v2_units;reg [4:0] v1_shift;
 reg cap_v2,capacity_bad;reg [32:0] capacity;
assign req_ready=media_ready && (|(state & IDLE)) && !reinit && !cancel_valid && !cancel_hit_q;
// Register the final chip-select output. DESELECT always inserts a complete
// byte transaction before the next command, so a one-clock output delay cannot
// place a DCLK edge after CS is released or before CS is asserted.
always @(posedge clk or posedge rst)
 if(rst) nCS_q<=1;
 else nCS_q<=cs;
 spi_master spi(.sys_clk(clk),.rst(rst),.nCS(SD_nCS),.DCLK(SD_DCLK),
 .MOSI(SD_MOSI),.MISO(SD_MISO),.CPOL(1'b0),.CPHA(1'b0),.nCS_ctrl(nCS_q),
 .clk_div(divider),.wr_req(wr_req),.wr_ack(ack),.data_in(tx),.data_out(rx));
 function automatic [15:0] crc16(input [15:0] c,input [7:0] d);
 reg [15:0] t; integer i; begin t=c;
 for(i=7;i>=0;i=i-1) t={t[14:0],1'b0} ^ ((t[15]^d[i]) ? 16'h1021:16'h0);
 crc16=t; end endfunction
 function automatic [7:0] crc7(input [39:0] d);
 reg [6:0] c; integer i; begin c=0;
 for(i=39;i>=0;i=i-1) c={c[5:0],1'b0} ^ ((c[6]^d[i]) ? 7'h09:7'h0);
 crc7={c,1'b1}; end endfunction
 task automatic byte_io(input [7:0] d,input [STATE_W-1:0] r);
 begin tx<=d;wr_req<=1;resume<=r;state<=BYTE_WAIT;end endtask
 task automatic command_io(input [5:0] n,input [31:0] a,input [3:0] p);
 begin cmd_num<=n;cmd_arg<=a;phase<=p;state<=CMD_PRE;end endtask
 task automatic release_to(input [STATE_W-1:0] r);
 begin cs<=1;after_release<=r;state<=DESELECT;end endtask
 task automatic read_fail(input [3:0] reason);
 begin
  // Observation only: reason, command (hex), last received byte. Frozen on
  // initialization failure; never used by protocol or frame control.
  if(!active && !init_error) init_diagnostic<={reason,2'b0,cmd_num,rx};
  // A retry never emits a partial buffer and never changes rsp_tag.
  if(active && attempt+1<MAX_ATTEMPTS && read_timer<READ_CYCLES) begin
   attempt<=attempt+1;release_to(CMD_PRE);
  end else begin
   if(active) rsp_error<=1;
   active<=0;media_ready<=0;init_error<=!active;state<=active ? ABORT:FAILED;
  end
 end endtask
 always @(posedge clk) begin
  if(rst) begin
   state<=POWER;timer<=0;init_timer<=0;read_timer<=0;token_timer<=0;
   media_ready<=0;media_sectors<=0;init_error<=0;block_addressed<=0;init_diagnostic<=0;init_last_rx<=8'hff;
   cs<=1;wr_req<=0;tx<=255;divider<=LOW_DIV;gap<=0;active<=0;
   rsp_tag<=0;rsp_valid<=0;rsp_data<=0;rsp_done<=0;rsp_error<=0;
   count<=0;attempt<=0;v2<=0;phase<=0;crc<=0;csd<=0;
  end else begin
   if(ack) init_last_rx<=rx;
   rsp_valid<=0;rsp_done<=0;rsp_error<=0;
   if(media_ready) init_timer<=0;
   else if(!(|(state & FAILED))) init_timer<=init_timer+1;
   if(active) read_timer<=read_timer+1;
   if((|(state & TOKEN)) || (|(state & TOKEN_GOT)) ||
      (((|(state & BYTE_WAIT)) || (|(state & BYTE_GAP))) && (|(resume & TOKEN_GOT)))) token_timer<=token_timer+1;
   // Finish the in-flight byte before aborting; CS stays high until a new CMD0.
   if(reinit || cancel_hit_q) begin
    active<=0;media_ready<=0;init_error<=0;init_timer<=0;cs<=1;init_diagnostic<=0;init_last_rx<=8'hff;
    if((|(state & BYTE_WAIT))) begin resume<=ABORT;if(ack) begin wr_req<=0;gap<=3;state<=BYTE_GAP;end end
    else if((|(state & BYTE_GAP))) begin resume<=ABORT;if(gap==0) state<=ABORT;else gap<=gap-1;end
    else state<=ABORT;
   end else if(active && read_timer>=READ_CYCLES && !(|(state & ABORT)) && !(|(state & ABORTED))) begin
    rsp_error<=1;active<=0;media_ready<=0;cs<=1;
    if((|(state & BYTE_WAIT))) begin resume<=ABORT;if(ack) begin wr_req<=0;gap<=3;state<=BYTE_GAP;end end
    else if((|(state & BYTE_GAP))) begin resume<=ABORT;if(gap==0) state<=ABORT;else gap<=gap-1;end
    else state<=ABORT;
   end else if(!media_ready && !init_error && init_timer>=INIT_CYCLES && !(|(state & FAILED)) && !(|(state & ABORT))) begin
    init_error<=1;cs<=1;
    init_diagnostic<={4'ha,((|(state & (POWER|CLOCKS|CLOCKED))) ? 8'hff:{2'b0,cmd_num}),(ack ? rx:init_last_rx)};
    if((|(state & BYTE_WAIT))) begin resume<=FAILED;if(ack) begin wr_req<=0;gap<=3;state<=BYTE_GAP;end end
    else if((|(state & BYTE_GAP))) begin resume<=FAILED;if(gap==0) state<=FAILED;else gap<=gap-1;end
    else state<=FAILED;
   end else case(1'b1) // synthesis parallel_case
    (|(state & BYTE_WAIT)): if(ack) begin wr_req<=0;gap<=3;state<=BYTE_GAP;end
    (|(state & BYTE_GAP)): if(gap==0) state<=resume;else gap<=gap-1;
    (|(state & POWER)): if(timer>=POWER_CYCLES) begin count<=0;state<=CLOCKS;end else timer<=timer+1;
    (|(state & CLOCKS)): byte_io(255,CLOCKED);
    (|(state & CLOCKED)): if(count==9) command_io(0,0,0);else begin count<=count+1;state<=CLOCKS;end
    (|(state & CMD_PRE)): begin cs<=1;byte_io(255,CMD_SELECT);end
    (|(state & CMD_SELECT)): begin
     cs<=0;command<={{2'b01,cmd_num},cmd_arg,crc7({2'b01,cmd_num,cmd_arg})};
     cmd_pos<=0;state<=CMD_SEND;
    end
    (|(state & CMD_SEND)): byte_io(command[47:40],CMD_SENT);
    (|(state & CMD_SENT)): begin command<={command[39:0],8'hff};
     if(cmd_pos==5) begin poll_count<=0;state<=R1;end
     else begin cmd_pos<=cmd_pos+1;state<=CMD_SEND;end
    end
    (|(state & R1)): byte_io(255,R1_GOT);
    (|(state & R1_GOT)): if(!rx[7]) begin
     response<=rx;tail<=0;tail_pos<=0;
     if((phase==1 && rx==1) || (phase==4 && rx==0)) state<=TAIL;else state<=DISPATCH;
    end else if(poll_count==15) read_fail(4'h1);else begin poll_count<=poll_count+1;state<=R1;end
    (|(state & TAIL)): byte_io(255,TAIL_GOT);
    (|(state & TAIL_GOT)): begin tail<={tail[23:0],rx};
     if(tail_pos==3) state<=DISPATCH;else begin tail_pos<=tail_pos+1;state<=TAIL;end
    end
    (|(state & DISPATCH)): case(phase)
     0: if(response==1) begin release_to(RELEASED);phase<=1;end else read_fail(4'h2);
     1: if(response==1) begin
         // Validate the echoed pattern and accepted-voltage fields, not
         // reserved/extension bits outside this host's negotiation.
         if(tail[7:0]!=8'haa) read_fail(4'hd);
         else if(tail[11:8]!=4'h1) begin
          read_fail(4'hc);
          init_diagnostic<={4'hc,8'h08,4'b0,tail[11:8]};
         end else begin v2<=1;release_to(RELEASED);phase<=8;end
        end else if(response==5) begin v2<=0;release_to(RELEASED);phase<=8;end else read_fail(4'h2);
     // CRC mode must be negotiated before ACMD41; keep data CRC checks.
     8: if(response==1) begin release_to(RELEASED);phase<=2;end else read_fail(4'h2);
     2: if(response==1 || response==0) begin release_to(RELEASED);phase<=3;end else read_fail(4'h2);
     3: if(response==0) begin release_to(RELEASED);phase<=4;end
        else if(response==1) begin release_to(RELEASED);phase<=2;end else read_fail(4'h2);
     4: if(response==0 && tail[31] && |tail[23:15] && (!tail[30] || v2)) begin
         block_addressed<=tail[30];release_to(RELEASED);phase<=tail[30] ? 6:5;
        end else read_fail(4'h2);
     5: if(response==0) begin release_to(RELEASED);phase<=6;end else read_fail(4'h2);
     6,7: if(response==0) begin count<=0;crc<=0;csd<=0;token_timer<=0;state<=TOKEN;end else read_fail(4'h2);
     default: read_fail(4'h2);
    endcase
    (|(state & RELEASED)): case(phase)
     1:command_io(8,32'h1aa,1);
     8:command_io(59,1,8);
     2:command_io(55,0,2);
     3:command_io(41,v2 ? 32'h40000000:0,3);
     4:command_io(58,0,4);
     5:command_io(16,512,5);
     6:command_io(9,0,6);
     default:read_fail(4'h2);
    endcase
    (|(state & TOKEN)): if(token_timer>=TOKEN_CYCLES) read_fail(4'h3);else byte_io(255,TOKEN_GOT);
    (|(state & TOKEN_GOT)): if(rx==8'hfe) state<=DATA;
      else if(rx!=255) read_fail(4'h4);else state<=TOKEN;
    (|(state & DATA)): byte_io(255,DATA_GOT);
    (|(state & DATA_GOT)): begin
     crc<=crc16(crc,rx);if(phase==6) csd<={csd[119:0],rx};else buffer[count[8:0]]<=rx;
     if(count==(phase==6 ? 15:511)) state<=CRC_HI;else begin count<=count+1;state<=DATA;end
    end
    (|(state & CRC_HI)): byte_io(255,CRC_LO);
    (|(state & CRC_LO)): begin card_crc[15:8]<=rx;byte_io(255,CRC_CHECK);end
    (|(state & CRC_CHECK)): if({card_crc[15:8],rx}!=crc) read_fail(4'h5);else state<=GUARD;
    (|(state & GUARD)): byte_io(255,GUARDED);
    (|(state & GUARDED)): if(rx!=255) read_fail(4'h6);else if(phase==6) release_to(CSD_CHECK);else release_to(EMIT);
    (|(state & DESELECT)): byte_io(255,after_release);
    (|(state & CSD_CHECK)): begin
     if((csd[127:126]!=0 && csd[127:126]!=1) ||
       (block_addressed!=(csd[127:126]==1)) ||
       (!block_addressed && (csd[83:80]<9 || csd[83:80]>11))) read_fail(4'h7);
     else begin
      cap_v2<=csd[127:126]==1;
      v1_units<={1'b0,csd[73:62]}+13'd1;
      v2_units<={1'b0,csd[69:48]}+23'd1;
      v1_shift<={2'b0,csd[49:47]}+{1'b0,csd[83:80]}-5'd7;
      state<=CSD_CAPACITY;
     end
    end
    (|(state & CSD_CAPACITY)): begin
     capacity<=cap_v2 ? {v2_units,10'b0}:({20'b0,v1_units}<<v1_shift);
     state<=CSD_BOUNDS;
    end
    (|(state & CSD_BOUNDS)): begin
     capacity_bad<=capacity==0 || capacity[32] || (!block_addressed && capacity>4194304);
     state<=CSD_ACCEPT;
    end
    (|(state & CSD_ACCEPT)): begin
     if(capacity_bad) read_fail(4'h8);
     else begin media_sectors<=capacity[31:0];media_ready<=1;init_error<=0;divider<=HIGH_DIV;state<=IDLE;end
    end
    (|(state & IDLE)): if(req_valid && req_ready) begin
     rsp_tag<=req_tag;lba<=req_lba;attempt<=0;read_timer<=0;
     if(req_lba>=media_sectors) begin rsp_error<=1;end
     else begin active<=1;command_io(17,block_addressed ? req_lba:(req_lba<<9),7);end
    end
    (|(state & EMIT)): begin emit_pos<=0;state<=EMIT_WAIT;end
    (|(state & EMIT_WAIT)): state<=FINISH;
    // Pause output on any cancel pulse while its tag is being checked. A
    // stale tag only introduces a legal valid-low gap; it cannot lose a byte.
    (|(state & FINISH)): if(!cancel_valid) begin
     rsp_valid<=1;rsp_data<=buffer_q;
     if(emit_pos==511) begin rsp_done<=1;active<=0;state<=IDLE;end else emit_pos<=emit_pos+1;
    end
    (|(state & ABORT)): begin cs<=1;count<=0;wr_req<=0;state<=ABORTED;end
    (|(state & ABORTED)): begin
     // 80 clocks deselected, then bounded initialization at <=400 kHz.
     divider<=LOW_DIV;init_timer<=0;timer<=0;v2<=0;state<=CLOCKS;
    end
    (|(state & FAILED)): begin media_ready<=0;cs<=1;end
    default: read_fail(4'h2);
   endcase
  end
 end
endmodule
