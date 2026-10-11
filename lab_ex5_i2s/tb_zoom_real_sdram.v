`timescale 1ns/1ps
// Diagnostic: real FIFO/schedulers and vendor controller, custom command-level SDRAM model.
// 100MHz source, 125MHz memory, 25MHz pixel clock; 640 active + 160 blank clocks/line.
// Does not simulate full HDMI timing or official device timing/electrical behavior.
module tb_zoom_real_sdram;
parameter H=48;
parameter FORCED_REFRESH=0;
parameter OUTPUT_DIV=1;
parameter PACE_ZOOM=1;
integer integer_placeholder;
localparam W=640, N=W*H;
localparam BANK_BASE=307200;
reg [1:0] read_bank=0;
reg [1:0] read_zoom=0;
integer expected_source_x, expected_source_y;
reg [31:0] expected_read_data;
reg clk=0, mem_clk=0, rst=1, start=0, valid=0, req=0;
integer output_cycles=0;
always @(posedge clk) output_cycles<=output_cycles+1;
reg [1:0] zoom=0;
wire source_permit;
reg request_seen=0,writer_armed=0;
wire writer_allowed=zoom!=2 || writer_armed;
// Match sd_card_bmp's request-withdrawal gate before padding transfers.
always @(posedge clk) begin
 if(rst || start) begin request_seen<=0; writer_armed<=0; end
 else begin
  if(req) request_seen<=1;
  if(request_seen && !req) writer_armed<=1;
 end
end
wire output_slot=!zoom || output_cycles%OUTPUT_DIV==0;
always #5 clk=~clk;
always #4 mem_clk=~mem_clk;
reg [23:0] rgb=0;
reg [1:0] bank=0;
reg finished_seen=0;
reg video_clk=0, read_req=0, consume=0, seed_only=0;
always #20 video_clk=~video_clk;
wire read_ack;
wire out_valid, ready, source_done, output_done, overflow, ack, finish, wr_en;
wire [23:0] out_rgb;
wire [20:0] address;
wire [31:0] data;
wire [3:0] dm;
wire init_done, refresh_active, sdr_busy, sdram_clk, ras, cas, we;
wire [1:0] ba;
wire [10:0] physical_addr;
wire [3:0] physical_dm;
wire [31:0] dq, core_data;
wire core_valid;
wire [31:0] protocol_errors;
reg app_ref_req=0;
integer ref_clock_count=0;
always @(negedge mem_clk) begin
 if(rst || !init_done) begin ref_clock_count=0; app_ref_req=0; end
 else begin
  ref_clock_count=ref_clock_count+1;
  app_ref_req=FORCED_REFRESH && ref_clock_count%5000<16;
 end
end
sdr_as_ram #(.self_refresh_open(!FORCED_REFRESH)) core (
 .Sdr_clk(mem_clk),.Sdr_clk_sft(~mem_clk),.Rst(rst),.Sdr_init_done(init_done),
 .Sdr_init_ref_vld(refresh_active),.Sdr_busy(sdr_busy),.App_ref_req(app_ref_req),
 .App_wr_en(wr_en),.App_wr_addr(address),.App_wr_dm(dm),.App_wr_din(data),
 .App_rd_en(store.App_rd_en),.App_rd_addr(store.App_rd_addr),.Sdr_rd_en(core_valid),.Sdr_rd_dout(core_data),
 .SDRAM_CLK(sdram_clk),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),
 .SDR_BA(ba),.SDR_ADDR(physical_addr),.SDR_DM(physical_dm),.SDR_DQ(dq));
sdram_pin_model memory (
 .clk(sdram_clk),.ras_n(ras),.cas_n(cas),.we_n(we),.addr(physical_addr),.ba(ba),
 .dq(dq),.dm(physical_dm),.protocol_errors(protocol_errors));
integer requests=0, returns=0, bad_returns=0, refresh_cycles=0, physical_write_commands=0;
integer physical_write_words=0, physical_unknown_words=0;
integer frame_physical_start=0, frame_unknown_start=0;
integer finish_command_snapshot=0, physical_refresh_commands=0, refresh_snapshot=0;
time finish_time=0, last_write_time=0, last_write_end=0;
always @(posedge sdram_clk) begin
 if(memory.write_left>0 || {ras,cas,we}==3'b100) begin
   physical_write_words=physical_write_words+1;
   if(^dq===1'bx) begin
     if(physical_unknown_words<8) $display("[BAD DQ WRITE] t=%0t mode=%0d dq=%h appwr=%b apprd=%b busy=%b read_driving=%b",$time,zoom,dq,wr_en,store.App_rd_en,sdr_busy,memory.read_driving);
     physical_unknown_words=physical_unknown_words+1;
   end
 end
 if({ras,cas,we}==3'b001) physical_refresh_commands=physical_refresh_commands+1;
 if({ras,cas,we}==3'b100) last_write_time=$time;
 if(memory.write_left>0) last_write_end=$time;
end
always @(posedge sdram_clk) if({ras,cas,we}==3'b100) physical_write_commands=physical_write_commands+1;
always @(posedge mem_clk) if(!rst) begin
 if(store.App_rd_en) requests=requests+1;
 if(core_valid) begin
   returns=returns+1;
   expected_source_x=read_zoom==1 ? W/4+((returns-1)%W)/2 : (returns-1)%W;
   expected_source_y=read_zoom==1 ? H/4+(H-1-(returns-1)/W)/2 : H-1-(returns-1)/W;
   expected_read_data=(24'h112200+expected_source_y*W+expected_source_x)<<8;
   if(read_zoom==2) begin
     expected_source_x=2*((returns-1)%W-W/4);
     expected_source_y=2*(H-1-(returns-1)/W-H/4)+1;
     expected_read_data=((returns-1)%W>=W/4 && (returns-1)%W<3*W/4 &&
         (returns-1)/W>=H/4 && (returns-1)/W<3*H/4) ?
         (24'h112200+expected_source_y*W+expected_source_x)<<8 : 0;
   end
   if(core_data!==expected_read_data) begin
     if(bad_returns<4) $display("[BAD RETURN] index=%0d data=%h expected=%h",returns-1,core_data,expected_read_data);
     bad_returns=bad_returns+1;
   end
 end
 if(refresh_active) refresh_cycles=refresh_cycles+1;
 if(finish) begin finish_command_snapshot=physical_write_commands; finish_time=$time; end
end
integer underflows=0, consumed=0, overlap_samples=0;
always @(posedge video_clk) if(consume) begin
    consumed=consumed+1;
    if(store.App_wr_busy) overlap_samples=overlap_samples+1;
    if(store.read_buf.empty_flag) underflows=underflows+1;
end

integer errors=0, completed=0, count=0, sx, sy, expected_addr, full_checks=0;
reg [23:0] expected;
bmp_center_zoom_2x #(.WIDTH(W),.HEIGHT(H),.PACE_ZOOM_OUTPUT(PACE_ZOOM), .ENABLE_HALF(1)) scaler (
    .clk(clk),.rst(rst),.frame_start(start),.zoom_enable(zoom==1),.half_enable(zoom==2),.source_permit(source_permit),.in_valid(valid),.in_rgb(rgb),
    .out_valid(out_valid),.out_ready(ready && output_slot && writer_allowed),.out_rgb(out_rgb),.out_last(),.out_frame_last(),
    .source_done(source_done),.output_done(output_done),.overflow(overflow)
);
frame_read_write #(.BURST_SIZE(256),.FRAME_WIDTH(W),.FRAME_HEIGHT(H)) store (
    .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(init_done),.Sdr_init_ref_vld(refresh_active),.Sdr_busy(sdr_busy),
    .App_rd_en(),.App_rd_addr(),.Sdr_rd_en(core_valid),.Sdr_rd_dout(core_data),
    .read_clk(video_clk),.read_req(read_req),.read_req_ack(read_ack),.read_finish(),
    .read_addr_0(21'd0),.read_addr_1(BANK_BASE),.read_addr_2(21'd0),.read_addr_3(21'd0),
    .read_addr_index(read_bank),.read_len(N),.read_en(consume),.read_data(),
    .App_wr_en(wr_en),.App_wr_addr(address),.App_wr_din(data),.App_wr_dm(dm),
    .write_clk(clk),.write_req(req),.write_req_ack(ack),.write_finish(finish),
    .write_addr_0(21'd0),.write_addr_1(BANK_BASE),.write_addr_2(21'd0),.write_addr_3(21'd0),
    .write_addr_index(bank),.write_len(N),.write_en(out_valid&&ready&&output_slot&&writer_allowed),
    .write_data({out_rgb,8'b0}),.write_ready(ready)
);
always @(posedge mem_clk) if(!rst && wr_en) begin
    sx=zoom==1 ? W/4+(count%W)/2 : count%W;
    sy=zoom==1 ? H/4+(count/W)/2 : count/W;
    expected=24'h112200+sy*W+sx;
    if(zoom==2) begin
      sx=2*(count%W-W/4); sy=2*(count/W-H/4)+1;
      expected=(count%W>=W/4 && count%W<3*W/4 && count/W>=H/4 && count/W<3*H/4) ?
               24'h112200+sy*W+sx : 0;
    end
    expected_addr=bank*BANK_BASE+(H-1-count/W)*W+count%W;
    if(count>=N || data !== {expected,8'b0} || address!==expected_addr || dm!==0) begin
        if(errors<8) $display("[FAIL] FIFO word=%0d data=%h expected=%h address=%0d expected=%0d",count,data,{expected,8'b0},address,expected_addr);
        errors=errors+1;
    end
    count=count+1;
end
always @(posedge mem_clk)
    if(rst || start) finished_seen<=0;
    else if(finish) finished_seen<=1;
task frame;
input [1:0] mode;
integer i, j;
begin
    @(negedge clk); zoom=mode; start=1; req=1; count=0;
    frame_physical_start=physical_write_words; frame_unknown_start=physical_unknown_words; refresh_snapshot=physical_refresh_commands; read_req=!seed_only; underflows=0; consumed=0; overlap_samples=0; requests=0; returns=0; bad_returns=0; refresh_cycles=0;
    @(negedge clk); start=0;
    wait(ack); @(negedge clk); req=0;
    wait(ready);
    wait(source_permit);
    fork
        begin
            for(i=0;i<N;i=i+1) begin
                @(negedge clk); valid=1; rgb=24'h112200+i;
                @(negedge clk); valid=0;
                repeat(6) @(negedge clk);
            end
        end
        begin
            if(!seed_only) begin
            wait(read_ack); @(negedge video_clk); read_req=0;
            wait(store.read_buf.rdusedw >= 256);
            for(j=0;j<N;j=j+1) begin
                @(negedge video_clk); consume=1;
                if(j%640==639) begin
                    @(negedge video_clk); consume=0;
                    repeat(159) @(negedge video_clk);
                end
            end
            @(negedge video_clk); consume=0;
            $display("[DIAGNOSTIC] mode=%0d consumed=%0d underflows=%0d write_overlap=%0d",mode,consumed,underflows,overlap_samples);
            if(consumed!=N || overlap_samples==0) begin errors=errors+1; $display("[FAIL] Read/write overlap or read length missing"); end
            end
        end
    join
    wait(finished_seen); repeat(5) @(negedge clk);
    $display("[WRITE BUS] mode=%0d words=%0d unknown=%0d",mode,physical_write_words-frame_physical_start,physical_unknown_words-frame_unknown_start);
    if(count!=N || overflow || !source_done || !output_done) begin
        errors=errors+1; $display("[FAIL] FIFO completion count=%0d overflow=%b",count,overflow);
    end else $display("[PASS] Real async FIFO / vertical address flip mode=%b buffer=%0d words=%0d",mode,bank,count);
end
endtask
task read_new_frame;
input [1:0] mode;
integer k;
begin
    repeat(100) @(negedge mem_clk);
    read_bank=1; read_zoom=mode;
    requests=0; returns=0; bad_returns=0; consumed=0; underflows=0;
    @(negedge video_clk); read_req=1;
    wait(read_ack); @(negedge video_clk); read_req=0;
    wait(store.read_buf.rdusedw>=256);
    for(k=0;k<N;k=k+1) begin
        @(negedge video_clk); consume=1;
        if(k%640==639) begin
            @(negedge video_clk); consume=0;
            repeat(159) @(negedge video_clk);
        end
    end
    @(negedge video_clk); consume=0;
    repeat(100) @(negedge mem_clk);
    $display("[NEW FRAME] mode=%0d base=%0d requests=%0d returns=%0d bad=%0d underflows=%0d",mode,BANK_BASE,requests,returns,bad_returns,underflows);
    if(requests!=N || returns!=N || bad_returns!=0 || underflows!=0) errors=errors+1;
    read_bank=0; read_zoom=0;
end
endtask
initial begin
    repeat(5) @(negedge clk); rst=0;
    wait(init_done);
    // Seed the displayed frame through the real write path; no physical address assumption.
    seed_only=1; bank=0; frame(0);
    repeat(100) @(negedge mem_clk);
    seed_only=0;
    bank=1; frame(0);
    repeat(100) @(negedge mem_clk);
    $display("[CORE] mode=0 requests=%0d returns=%0d bad=%0d refresh=%0d trailing_writes=%0d protocol=%0d",requests,returns,bad_returns,refresh_cycles,physical_write_commands-finish_command_snapshot,protocol_errors);
    if(requests!=N || returns!=N || bad_returns!=0) errors=errors+1;
    $display("[PHYSICAL] mode=0 refresh_cmds=%0d last_cmd_after_finish_ns=%0d last_write_after_finish_ns=%0d",physical_refresh_commands-refresh_snapshot,last_write_time-finish_time,last_write_end-finish_time);
    read_new_frame(0);
    frame(1);
    repeat(100) @(negedge mem_clk);
    $display("[CORE] mode=1 requests=%0d returns=%0d bad=%0d refresh=%0d trailing_writes=%0d protocol=%0d",requests,returns,bad_returns,refresh_cycles,physical_write_commands-finish_command_snapshot,protocol_errors);
    if(requests!=N || returns!=N || bad_returns!=0) errors=errors+1;
    $display("[PHYSICAL] mode=1 refresh_cmds=%0d last_cmd_after_finish_ns=%0d last_write_after_finish_ns=%0d",physical_refresh_commands-refresh_snapshot,last_write_time-finish_time,last_write_end-finish_time);
    read_new_frame(1);
    frame(2);
    repeat(100) @(negedge mem_clk);
    if(requests!=N || returns!=N || bad_returns!=0) errors=errors+1;
    read_new_frame(2);
    if(FORCED_REFRESH && physical_refresh_commands==0) begin errors=errors+1; $display("[FAIL] No forced refresh observed"); end
    completed=1;
    if(errors==0) $display("[TEST PASS] Center zoom to original FIFO/address scheduler is correct.");
    else $display("[TEST FAIL] FIFO errors=%0d",errors);
    $finish;
end
initial begin #200000000; errors=errors+1; $display("[TEST FAIL] FIFO timeout count=%0d state=%0d",count,store.frame_fifo_write_m0.state); $finish; end
endmodule
