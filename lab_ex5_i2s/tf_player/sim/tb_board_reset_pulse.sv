`timescale 1ns/1ps
// Reset asserted during a real selected SPI command, between SD clock edges.
module tb_board_reset_pulse;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 wire cs,sclk,mosi,miso;integer reads;wire [31:0] last_arg;
 top dut(.clk(clk),.rst_n(rst_n),.key1(1'b1),.key2(1'b1),.key3(1'b1),
  .sd_ncs(cs),.sd_dclk(sclk),.sd_mosi(mosi),.sd_miso(miso));
 // Test acceleration only; actual reset tree, byte SPI and TF control stay real.
 defparam dut.sd_card_bmp_m0.card.POWER_CYCLES=5;
 defparam dut.sd_card_bmp_m0.card.LOW_DIV=0;
 sd_card_model card(cs,sclk,mosi,miso,1'b1,1'b0,4'b0,reads,last_arg);
 integer cases=0;
 task pulse(input integer offset_ns,width_ns);
 begin
  @(negedge dut.sd_card_clk);
  #(offset_ns);rst_n=0;
  #(width_ns);rst_n=1;
  // The old byte engine has already reset asynchronously. All new control
  // must also see reset on the next SD edge, even though raw reset is now low.
  @(posedge dut.sd_card_clk);#1;
  if(dut.sd_card_bmp_m0.card.state!==dut.sd_card_bmp_m0.card.POWER ||
     dut.sd_card_bmp_m0.state!==0 || cs!==1'b1 ||
     dut.sd_card_bmp_m0.card.wr_req!==0)
   $fatal(1,"FAIL partial TF reset: player=%0d card=%h SPI=%0d cs=%b wr_req=%b",
    dut.sd_card_bmp_m0.state,dut.sd_card_bmp_m0.card.state,
    dut.sd_card_bmp_m0.card.spi.state,cs,dut.sd_card_bmp_m0.card.wr_req);
  if(dut.sd_card_bmp_m0.fs.req_tag!==0 || dut.sd_card_bmp_m0.fs.mounted!==0)
   $fatal(1,"FAIL FAT state survived reset");
  cases=cases+1;
  repeat(6) @(negedge dut.sd_card_clk);
 end endtask
 initial begin
  #1137;rst_n=1;
  wait(!cs && dut.sd_card_bmp_m0.card.spi.state==1);pulse(1,1);
  wait(!cs && dut.sd_card_bmp_m0.card.spi.state==1);pulse(3,1);
  wait(!cs && dut.sd_card_bmp_m0.card.spi.state==1);pulse(2,2);
  wait(!cs && dut.sd_card_bmp_m0.card.spi.state==1);pulse(1,25);
  // Interrupt an actual filesystem-sector transaction, not just boot commands.
  wait(dut.sd_card_bmp_m0.fs.state==dut.sd_card_bmp_m0.fs.RECEIVE &&
       !cs && dut.sd_card_bmp_m0.card.spi.state==1);pulse(1,1);
  // A physical-controller write has started: flush the whole TF transaction
  // and original FIFO/controller reset path, then require a fresh mount.
  wait(dut.App_wr_en===1'b1);pulse(1,1);
  wait(dut.sd_card_bmp_m0.mount_done);
  #1;
  if(dut.sd_card_bmp_m0.fs.file_count!==32 || !dut.sd_card_bmp_m0.fs.mounted)
   $fatal(1,"FAIL remount after short reset");
  $display("BOARD_RESET_PULSE_PASS cases=%0d remount_count=%0d all TF control resets together",
    cases,dut.sd_card_bmp_m0.fs.file_count);
  $finish;
 end
 initial begin #10000000; $fatal(1,"FAIL reset test watchdog");end
endmodule
