`timescale 1ns/1ps
module tb_osd_layers_config;
reg clk=0;always #5 clk=~clk;
reg rst=1,hs=0,vs=0,de=0,en=1,am=0;reg [1:0] item=0;
wire oh,ov,od,ready;wire [23:0] rgb;
reg cv=0,show=1,shadow=1,pause=0;
reg [9:0] x=24,y=380;reg [2:0] a=3;reg [3:0] step=2;
integer errors=0,completed=0,n,saved;
osd_layer_renderer dut(clk,rst,en,am,item,item,1'b1,hs,vs,de,24'h123456,oh,ov,od,rgb,
 cv,ready,show,x,y,a,shadow,pause,step);
task frame;
begin @(negedge clk);vs=1;@(negedge clk);vs=0;repeat(4)@(negedge clk);end
endtask
task check;
input condition;input [255:0] message;
begin if(!condition)begin errors=errors+1;$display("[FAIL] %0s",message);end end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;
 check(dut.show && dut.alpha==3 && dut.origin_x==24 && dut.origin_y==380,"reset defaults");
 x=1000;y=0;a=7;step=0;shadow=0;pause=1;show=0;cv=1;
 @(negedge clk);cv=0;
 check(!ready && dut.alpha==3 && dut.show,"latched pending, not applied");
 x=0;y=404;a=0;step=8;shadow=1;pause=0;show=1;
 repeat(10)@(negedge clk);
 check(dut.alpha==3 && dut.origin_y==380,"no midframe update");
 frame;
 check(ready && !dut.show && dut.origin_x==48 && dut.origin_y==96 && dut.alpha==4 && dut.step==1 && !dut.shadow && dut.pause,"clamped atomic config");
 // Accept on VS edge: do not expose half-new fields in that frame.
 cv=1;vs=1;@(negedge clk);cv=0;vs=0;
 check(!ready && dut.alpha==4 && !dut.show,"same-edge request defers");
 frame;
 check(ready && dut.show && dut.alpha==0 && dut.origin_x==0 && dut.origin_y==404 && dut.step==8 && dut.shadow && !dut.pause,"next-frame commit");
 // Frame-local pause changes apply to the scroll controller on that edge.
 pause=1;cv=1;@(negedge clk);cv=0;frame;
 check(dut.scroll.pause && dut.scroll_offset==0,"pause coherent at commit");
 // A held request while not ready must not overwrite its accepted payload.
 pause=0;step=15;cv=1;@(negedge clk);step=3;
 repeat(3)@(negedge clk);frame;cv=0;
 check(dut.step==8,"backpressure preserves first payload");
 // A valid request may be accepted immediately after ready returns.
 @(negedge clk);cv=1;@(negedge clk);cv=0;frame;
 check(dut.step==3 && !dut.pause,"new speed committed");
 // Reach moving state, hide/freeze, then move and resume at a new origin.
 for(n=0;n<60;n=n+1)frame;
 saved=dut.scroll_offset;check(saved>0,"running scroll before hide");
 show=0;cv=1;@(negedge clk);cv=0;frame;
 check(dut.scroll_offset==saved,"hide freezes without reset");
 repeat(10)frame;check(dut.scroll_offset==saved,"hidden keeps progress");
 show=1;step=1;x=24;y=380;cv=1;@(negedge clk);cv=0;frame;
 check(dut.scroll_offset==saved+1 && dut.origin_x==24,"show/move/speed resume coherent");
 completed=1;$display("OSD P3 CONFIG COMPLETE errors=%0d",errors);$finish;
end
initial begin #100000;errors=errors+1;$display("[FAIL] config timeout");$finish;end
endmodule
