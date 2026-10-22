`timescale 1ns/1ps
module tb_osd_identity;
 reg clk=0;always #5 clk=~clk;reg rst=1,tick=0;reg [13:0] asset=1;
 wire [10:0] offset;reg [6:0] slot=0;wire [23:0] rgb;
 osd_scroll_ctrl #(.ITEM_W(14),.STEP_FRAMES(1),.HEAD_FRAMES(0),.TAIL_FRAMES(0)) scroll(
 .clk(clk),.rst(rst),.frame_tick(tick),.enable(1'b1),.pause(1'b0),.item_index(asset),.length(7'd64),.offset(offset));
 osd_overlay #(.TWO_DIGIT(1)) status(.clk(clk),.rst(rst),.enable(1'b1),.auto_mode(1'b0),.item_index(slot),
 .hs_in(1'b0),.vs_in(1'b0),.de_in(1'b0),.rgb_in(24'd0),.hs_out(),.vs_out(),.de_out(),.rgb_out(rgb));
 task frame;begin @(negedge clk);tick=1;@(negedge clk);tick=0;end endtask
 integer n,saved;
 initial begin
  repeat(5) @(negedge clk);rst=0;repeat(8) frame();if(offset==0)$fatal(1,"FAIL no scroll");
  saved=offset;repeat(2) frame();if(offset<=saved)$fatal(1,"FAIL same ID restarted");
  asset=8193;frame();if(offset!=0 || scroll.seen_item!=8193)$fatal(1,"FAIL stable ID truncated");
  for(n=0;n<64;n=n+1) begin
   slot=n;force status.x=100;force status.y=390;
   force status.text_glyph=5;#1;if(status.glyph_code!=16+(n+1)/10)$fatal(1,"FAIL tens n=%0d",n);
   force status.text_glyph=6;#1;if(status.glyph_code!=16+(n+1)%10)$fatal(1,"FAIL ones n=%0d",n);
  end
  if(status.glyph_row(16,0)!=5'b01110 || status.glyph_row(25,3)!=5'b01111)$fatal(1,"FAIL digit glyphs");
  $display("OSD_IDENTITY_PASS ordinals=64 stable_id=8193");$finish;
 end
endmodule
