`timescale 1ns/1ps
module tb_board_init_diagnostic;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 wire cs,sclk,mosi,miso;wire [5:0] sel;wire [7:0] segments;
 reg [3:0] fault=9;integer reads;wire [31:0] last_arg;
 top dut(.clk(clk),.rst_n(rst_n),.key1(1'b1),.key2(1'b1),.key3(1'b1),
 .sd_ncs(cs),.sd_dclk(sclk),.sd_mosi(mosi),.sd_miso(miso),.seg_sel(sel),.seg_data(segments));
 defparam dut.sd_card_bmp_m0.card.POWER_CYCLES=5;
 defparam dut.sd_card_bmp_m0.card.LOW_DIV=1;
 defparam dut.seg_scan_m0.SCAN_COUNT=4; // Scan acceleration only, no production parameter change.
 sd_card_model card(cs,sclk,mosi,miso,1'b1,1'b0,fault,reads,last_arg);
 function automatic [7:0] decode(input [3:0] n);
 case(n)
 0:decode=8'hc0;1:decode=8'hf9;2:decode=8'ha4;3:decode=8'hb0;
 4:decode=8'h99;5:decode=8'h92;6:decode=8'h82;7:decode=8'hf8;
 8:decode=8'h80;9:decode=8'h90;10:decode=8'h88;11:decode=8'h83;
 12:decode=8'hc6;13:decode=8'ha1;14:decode=8'h86;15:decode=8'h8e;
 endcase endfunction
 reg [5:0] seen=0;reg [19:0] captured;integer digit;
 initial begin
  #1137;rst_n=1;
  wait(dut.sd_card_bmp_m0.init_error);captured=dut.tf_init_diagnostic;
  if(captured[19:8]!==12'h509 || dut.state_code!==4'hf)$fatal(1,"FAIL top init diagnostic %h",captured);
  repeat(15)@(negedge clk);
  repeat(60)begin
   @(negedge clk);
   for(digit=0;digit<6;digit=digit+1)if(sel===(6'b111111^(6'b1<<digit)))begin
    if(segments!==(digit==5 ? decode(15):decode(captured[19-digit*4 -: 4])))
     $fatal(1,"FAIL physical scan digit=%0d got=%h word=%h",digit,segments,captured);
    seen[digit]=1;
   end
  end
  if(seen!==6'b111111)$fatal(1,"FAIL not all scan positions checked");
  fault=0;rst_n=0;repeat(5)@(negedge clk);rst_n=1;
  repeat(15)@(negedge clk);
  if(dut.tf_init_diagnostic!==0 || dut.init_diag_settle!==0)$fatal(1,"FAIL top reset clear");
  wait(dut.sd_card_bmp_m0.media_ready);
  if(dut.tf_init_diagnostic!==0)$fatal(1,"FAIL top recovery clear");
  $display("BOARD_INIT_DIAGNOSTIC_PASS scan_positions=6 snapshot=%05h recovery=1",captured);$finish;
 end
 initial begin #10000000;$fatal(1,"FAIL top diagnostic watchdog");end
endmodule
