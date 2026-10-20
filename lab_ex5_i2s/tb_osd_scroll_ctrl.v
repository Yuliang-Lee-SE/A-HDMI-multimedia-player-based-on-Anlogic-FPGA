`timescale 1ns/1ps
module tb_osd_scroll_ctrl;
reg clk=0;always #5 clk=~clk;
reg rst=1,tick=0,enable=1,pause=0;
reg [1:0] item=0;
reg [6:0] length=36;
wire [10:0] offset;
integer errors=0,completed=0,frames=0,n,saved;
osd_scroll_ctrl #(.STEP_FRAMES(2),.HEAD_FRAMES(3),.TAIL_FRAMES(2)) dut(
 clk,rst,tick,enable,pause,item,length,offset);
task check;
input integer want;
begin if(offset!==want) begin errors=errors+1;$display("[FAIL] frame=%0d offset=%0d expected=%0d",frames,offset,want);end end
endtask
task frame;
begin
 @(negedge clk);tick=1;
 @(negedge clk);tick=0;frames=frames+1;
 saved=offset;
 repeat(7) @(negedge clk);
 check(saved); // All intervening pixels must retain the same offset.
end
endtask
task restart;
input [6:0] size; input [1:0] id;
begin
 @(negedge clk);rst=1;length=size;item=id;pause=0;enable=1;
 @(negedge clk);rst=0;frame;check(0);
end
endtask
initial begin
 restart(36,0);
 // Exact head wait then 1px per two frames, including a character crossing.
 repeat(3) begin frame;check(0);end
 for(n=1;n<=16;n=n+1) begin frame;check(n-1);frame;check(n);end
 pause=1;repeat(5)begin frame;check(16);end
 pause=0;repeat(2)begin frame;check(16);end // Tail pause preserved.
 frame;check(16);frame;check(17);
 pause=1;repeat(5)begin frame;check(17);end
 pause=0;frame;check(17);frame;check(18);
 // No new item ID: a bank swap / failed load must not restart scrolling.
 repeat(2)frame;check(19);
 item=3;frame;check(0); // Simultaneous two-bit ID change.
 pause=1;repeat(6)begin frame;check(0);end
 pause=0;repeat(3)frame;frame;check(0);frame;check(1);
 item=1;frame;check(0);item=2;frame;check(0); // Rapid committed changes.
 enable=0;repeat(3)begin frame;check(0);end
 enable=1;frame;check(0);
 // Max 64 glyphs: last full window, final pixel, blank gap and wrap.
 restart(64,0);repeat(3)frame;
 for(n=1;n<=1056;n=n+1) begin
  frame;check((n-1)%1056);frame;check(n%1056);
  if(n==464) repeat(2)begin frame;check(464);end
 end
 repeat(3)begin frame;check(0);end
 frame;check(0);frame;check(1);
 restart(0,0);repeat(10)begin frame;check(0);end
 restart(1,1);repeat(10)begin frame;check(0);end
 restart(35,2);repeat(10)begin frame;check(0);end
 completed=1;$display("OSD SCROLL CONTROL COMPLETE frames=%0d errors=%0d",frames,errors);$finish;
end
initial begin #10000000;errors=errors+1;$display("[FAIL] scroll control timeout");$finish;end
endmodule
