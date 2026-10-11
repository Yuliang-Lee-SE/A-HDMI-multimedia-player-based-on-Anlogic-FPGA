`timescale 1ns/1ps
`include "osd_sim_inputs/config.vh"
module tb_osd_pixels;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=1,hs=0,vs=0,de=0;
reg [1:0] item=0;
reg [23:0] rgb=0;
wire oh,ov,od;wire [23:0] out;
osd_text_renderer #(.SCROLL_ENABLE(0)) dut(clk,rst,enable,item,hs,vs,de,rgb,oh,ov,od,out,1'b0);
reg [23:0] golden[0:307199];
reg [26:0] queue0,queue1,queue2,expected;
integer errors=0,completed=0,checked=0,p=0,x,y,f,n;
reg [23:0] exp_rgb;
always @(posedge clk) begin
 if(rst) begin queue0=0;queue1=0;queue2=0;end
 else begin
  expected=queue1;
  queue1=queue0;
  exp_rgb=de ? golden[p] : 24'd0;
  queue0={hs,vs,de,exp_rgb};
  if(de) p=p+1;
  #1;
  if({oh,ov,od,out}!==expected) begin
   if(errors<8) $display("PIXEL FAIL f=%0d p=%0d actual=%h expected=%h",f,p,{oh,ov,od,out},expected);
   errors=errors+1;
  end
  if(od) checked=checked+1;
 end
end
task tick;
input ih,iv,id;input [23:0] data;
begin @(negedge clk);hs=ih;vs=iv;de=id;rgb=data;end
endtask
initial begin
 repeat(4) @(negedge clk);rst=0;
 for(f=0;f<7;f=f+1) begin
  case(f)
   0:$readmemh("osd_sim_inputs/golden_0.hex",golden);
   1:$readmemh("osd_sim_inputs/golden_1.hex",golden);
   2:$readmemh("osd_sim_inputs/golden_2.hex",golden);
   3:$readmemh("osd_sim_inputs/golden_3.hex",golden);
   4:$readmemh("osd_sim_inputs/golden_4.hex",golden);
   5:$readmemh("osd_sim_inputs/golden_5.hex",golden);
   6:$readmemh("osd_sim_inputs/golden_6.hex",golden);
  endcase
  item=f<4 ? f : 0;enable=f!=4;p=0;
  if(f==5) begin
   for(n=0;n<16;n=n+1) dut.resources.text_rom[n]=`OSD_LAST_GLYPH;
   for(n=32;n<96;n=n+1) dut.resources.text_rom[n]=`OSD_LAST_GLYPH;
  end
  if(f==6) for(n=0;n<128;n=n+1) dut.resources.text_rom[n]=0;
  tick(0,1,0,0);repeat(6) tick(0,0,0,0);
  for(y=0;y<480;y=y+1) begin
   for(x=0;x<640;x=x+1) tick(0,0,1,{x[7:0],y[7:0],(x[7:0]^y[7:0])});
   repeat(8) tick(1,0,0,24'habcdef);
  end
  repeat(8) tick(0,0,0,0);
  $display("FRAME %0d checked pixels=%0d errors=%0d",f,checked,errors);
 end
 completed=1;$display("OSD PIXELS COMPLETE checked=%0d errors=%0d",checked,errors);$finish;
end
initial begin #30000000;errors=errors+1;$display("TIMEOUT");$finish;end
endmodule
