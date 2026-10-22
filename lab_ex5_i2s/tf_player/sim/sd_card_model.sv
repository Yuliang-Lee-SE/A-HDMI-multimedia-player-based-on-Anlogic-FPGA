// Test-only pin-level SPI card. No ideal sector interface to the DUT.
module sd_card_model #(
 // 0 preserves historical valid trailers; 1/2 use 0000/FFFF while CRC is off.
 parameter integer CRC_OFF_POLICY=0, CMD59_BEHAVIOR=0,
 parameter [31:0] CMD8_R7=32'h000001aa,
 parameter CSD_HC_SIZE=8191,CSD_SC_SIZE=4095,CSD_SC_MULT=7,CSD_READ_BL=9
)(input cs,sclk,mosi,output reg miso=1,
 input hc,legacy,input [3:0] fault,output integer reads=0,
 output reg [31:0] last_arg=0);
 reg [7:0] queue[0:2047]; integer head=0,tail=0,bits=0,cmdpos=0;
 reg [7:0] outgoing=255,incoming=0,packet[0:5];
 reg crc_enabled=0;integer crc_on_calls=0,protected_blocks=0;
 reg idle=1;reg [127:0] csd;integer i,j,n;reg [31:0] arg;
 reg [15:0] crc; reg [7:0] value;
 string image;integer image_fd=0,seek_result,read_size;
 reg [7:0] image_sector[0:511];
 initial if($value$plusargs("IMAGE=%s",image)) begin image_fd=$fopen(image,"rb");if(!image_fd) $fatal(1,"model image open");end
 // Independent CRC implementation: XOR byte into high byte before polynomial steps.
 function automatic [15:0] crc_byte(input [15:0] c,input [7:0] d);
 reg [15:0] t;integer k;begin t=c^{d,8'b0};
 for(k=0;k<8;k=k+1) if(t & 16'h8000) t=(t<<1)^16'h1021;else t=t<<1;
 crc_byte=t;end endfunction
 // Polynomial long division, independent of the DUT shift-register recurrence.
 function automatic [7:0] wire_crc7(input [39:0] message);
 reg [46:0] remainder;integer bitno;begin
  remainder={message,7'b0};
  for(bitno=46;bitno>=7;bitno=bitno-1)
   if(remainder[bitno])remainder=remainder^(47'h89<<(bitno-7));
  wire_crc7={remainder[6:0],1'b1};
 end endfunction
 task push(input [7:0] b);begin queue[tail]=b;tail=tail+1;end endtask
 task command;
 begin
  arg={packet[1],packet[2],packet[3],packet[4]};
  if(crc_enabled && packet[5]!==wire_crc7({packet[0],packet[1],packet[2],packet[3],packet[4]}))
   $fatal(1,"MODEL_HOST_CRC7 command=%0d got=%h",packet[0]&63,packet[5]);
  push(255);
  case(packet[0]&63)
   0:begin if(packet[5]!=8'h95)$fatal(1,"CMD0 CRC7");idle=1;crc_enabled=0;if(fault!=13)push(1);end
   8:begin if(packet[5]!=8'h87)$fatal(1,"CMD8 CRC7");
    if(legacy) push(5);else begin
     push(1);push(CMD8_R7[31:24]);push(CMD8_R7[23:16]);push(CMD8_R7[15:8]);
     push(fault==11 ? 8'hab:CMD8_R7[7:0]);end end
   59:begin
    crc_on_calls=crc_on_calls+1;
    if(CMD59_BEHAVIOR==1)push(5);
    else if(CMD59_BEHAVIOR!=2)begin
     push(idle ? 1:0);
     if(CMD59_BEHAVIOR!=3)crc_enabled=arg[0];
    end
   end
   55:push(idle ? 1:0);
   41:begin if(fault==7) push(1);else begin idle=0;push(0);end end
   58:begin push(0);push(fault==10 ? 0:hc ? 8'hc0:8'h80);push(8'hff);push(8'h80);push(0);end
   16:push(arg==512 ? 0:64);
   9:begin
    push(0);push(255);
    if(fault!=15) begin
    push(fault==14 ? 8'h0b:8'hfe);csd=0;
    if(hc) begin csd[127:126]=1;csd[69:48]=CSD_HC_SIZE;end
    else begin csd[83:80]=CSD_READ_BL;csd[73:62]=CSD_SC_SIZE;csd[49:47]=CSD_SC_MULT;end
    if(fault==8) csd[127:126]=2;
    crc=0;
    for(i=15;i>=0;i=i-1) begin value=csd[i*8+:8];push(value);crc=crc_byte(crc,value);end
    if(crc_enabled)protected_blocks=protected_blocks+1;
    else if(CRC_OFF_POLICY==1)crc=0;else if(CRC_OFF_POLICY==2)crc=16'hffff;
    if(fault==9)crc=crc^1;
    push(crc[15:8]);push(crc[7:0]);
    if(fault==12)push(8'h12);
    end
   end
   17:begin
    reads=reads+1;last_arg=arg;
    if(fault==6) push(4);else begin
     push(0);push(255);
     if(fault!=3) begin
      push(8'hfe);crc=0;n=(fault==4 ? 31:512);
      if(image_fd) begin
       seek_result=$fseek(image_fd,(hc ? arg:(arg>>9))*512,0);
       read_size=$fread(image_sector,image_fd);if(read_size!=512) $fatal(1,"model image read");
      end
      for(j=0;j<n;j=j+1) begin value=image_fd ? image_sector[j]:(j*37+arg)&255;push(value);crc=crc_byte(crc,value);end
      if(crc_enabled)protected_blocks=protected_blocks+1;
      else if(CRC_OFF_POLICY==1)crc=0;else if(CRC_OFF_POLICY==2)crc=16'hffff;
      if(fault==1 || (fault==2 && reads==1)) crc=crc^1;
      push(crc[15:8]);push(crc[7:0]);if(fault==5) push(8'h12);
     end
    end
   end
   default:push(4);
  endcase
 end endtask
 always @(posedge cs) begin head=0;tail=0;bits=0;cmdpos=0;outgoing=255;miso=1;end
 always @(posedge sclk) if(!cs) begin
  incoming={incoming[6:0],mosi};bits=bits+1;
  if(bits==8) begin
   bits=0;
   if(cmdpos!=0 || incoming[7:6]==2'b01) begin
    packet[cmdpos]=incoming;
    if(cmdpos==5) begin cmdpos=0;command();end else cmdpos=cmdpos+1;
   end
  end
 end
 always @(negedge sclk) if(!cs) begin
  if(bits==0) begin
   if(head<tail) begin outgoing=queue[head];head=head+1;end else outgoing=255;
  end else outgoing={outgoing[6:0],1'b1};
  miso=outgoing[7];
 end else miso=1;
endmodule
