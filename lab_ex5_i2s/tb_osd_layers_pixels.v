`timescale 1ns/1ps
module tb_osd_layers_pixels;
reg clk=0;always #5 clk=~clk;
reg rst=1,enable=1,hs=0,vs=0,de=0;
reg [1:0] item=0;
reg am=0,cfg_valid=0,cfg_show=1,cfg_shadow=1;
reg [9:0] cfg_x=24,cfg_y=380;
reg [2:0] cfg_alpha=3;
reg [10:0] selected_offset;
wire ready;
reg [23:0] rgb=0;
wire oh,ov,od;wire [23:0] out;
osd_layer_renderer dut(clk,rst,enable,am,item,item,1'b1,hs,vs,de,rgb,oh,ov,od,out,
 cfg_valid,ready,cfg_show,cfg_x,cfg_y,cfg_alpha,cfg_shadow,1'b0,4'd2);
reg [23:0] golden[0:307199];
reg [26:0] queue0,queue1,queue2,expected;
integer errors=0,completed=0,checked=0,p=0,x,y,f,n;
reg [23:0] exp_rgb;
always @(posedge clk) begin
 if(rst) begin queue0=0;queue1=0;queue2=0;end
 else begin
  expected=queue2;
  queue2=queue1;
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
 for(f=0;f<9;f=f+1) begin
  $readmemh($sformatf("osd_sim_inputs/layers_%0d.hex",f),golden);
  `include "osd_sim_inputs/layers_config.vh"
  p=0;cfg_valid=1;
  tick(0,0,0,0);cfg_valid=0;
  force dut.scroll_offset=selected_offset;
  tick(0,1,0,0);repeat(6) tick(0,0,0,0);
  for(y=0;y<480;y=y+1) begin
   for(x=0;x<640;x=x+1) tick(0,0,1,{x[7:0],y[7:0],(x[7:0]^y[7:0])});
   repeat(8) tick(1,0,0,24'habcdef);
  end
  repeat(8) tick(0,0,0,0);
  $display("FRAME %0d checked pixels=%0d errors=%0d",f,checked,errors);
 end
 completed=1;$display("OSD P3 PIXELS COMPLETE checked=%0d errors=%0d",checked,errors);$finish;
end
initial begin #100000000;errors=errors+1;$display("TIMEOUT");$finish;end
endmodule
