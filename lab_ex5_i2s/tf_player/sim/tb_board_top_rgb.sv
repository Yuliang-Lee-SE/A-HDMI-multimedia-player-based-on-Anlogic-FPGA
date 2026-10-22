`timescale 1ns/1ps
// Actual top RTL through RGB/AXIS. Clock/PLL and HDMI serializer are boundaries.
module tb_board_top_rgb;
 reg clk=0,rst_n=0;
 always #10 clk=~clk;
 wire cs,sclk,mosi,miso;integer reads;wire [31:0] last_arg;
 top dut(.clk(clk),.rst_n(rst_n),.key1(1'b1),.key2(1'b1),.key3(1'b1),
  .sd_ncs(cs),.sd_dclk(sclk),.sd_mosi(mosi),.sd_miso(miso));
 sd_card_model card(cs,sclk,mosi,miso,1'b1,1'b0,4'b0,reads,last_arg);
 function automatic [23:0] gold(input integer x,y);
  reg [7:0] r,g,b;
  begin b=x+1;g=y*3+1;r=x^y^1;gold={r,g,b};end
 endfunction
 task check(input bit ok,input string why);
  if(!ok) $fatal(1,"FAIL %s state=%0d card=%h fs=%h files=%0d t=%0t",why,
    dut.sd_card_bmp_m0.state,dut.sd_card_bmp_m0.card.state,
    dut.sd_card_bmp_m0.fs.state,dut.sd_card_bmp_m0.fs.file_count,$time);
 endtask
 integer raw_pixels=0,axis_pixels=0,axis_checked=0,frames=0,axis_nonzero=0;
 reg last_de=0;integer row=0,col=0;
 reg tracking=0;
 always @(negedge dut.video_clk) if(!dut.rst_all) begin
  if(dut.video_display_valid && dut.de) begin
   check(dut.vout_data===gold(raw_pixels%640,479-raw_pixels/640),"final raw RGB pixel");
   raw_pixels=raw_pixels+1;
   if(raw_pixels==307200) begin
    raw_pixels=0;frames=frames+1;
    $display("TOP_RGB_FRAME %0d t=%0t",frames,$time);
   end
  end
  if(dut.axis_s_user && dut.axis_s_valid && dut.video_display_valid) begin
   if(tracking) begin
    check(axis_pixels==307200,"AXIS full frame length");
    check(axis_checked>=172800 && axis_nonzero>170000,"AXIS visible image");
    check(dut.audio_enabled && dut.audio_track_idx==0,"first image audio mapping");
    $display("BOARD_TOP_RGB_PASS frames=%0d raw_pixels=%0d axis_pixels=%0d image_pixels=%0d nonzero=%0d reads=%0d",
      frames,frames*307200+raw_pixels,axis_pixels,axis_checked,axis_nonzero,reads);
    $finish;
   end
   tracking=1;axis_pixels=0;axis_checked=0;axis_nonzero=0;
  end
  if(tracking && dut.axis_s_valid) begin
   // Center region is outside status/caption/waveform overlays.
   if(axis_pixels/640>=100 && axis_pixels/640<370) begin
    check(dut.axis_s_data===gold(axis_pixels%640,479-axis_pixels/640),"RGB through overlays to AXIS");
    axis_checked=axis_checked+1;
    if(dut.axis_s_data!=0) axis_nonzero=axis_nonzero+1;
   end
   axis_pixels=axis_pixels+1;
  end
 end
 reg [3:0] prev_state=15;
 always @(negedge dut.sd_card_clk) if(!dut.rst_all && dut.state_code!==prev_state) begin
  $display("TOP_STATE %h files=%0d reads=%0d t=%0t",dut.state_code,dut.sd_card_bmp_m0.fs.file_count,reads,$time);
  prev_state=dut.state_code;
 end
 initial begin #1137;rst_n=1;end
 initial begin #1000000000;check(0,"top watchdog");end
endmodule

// Ideal oscillators and staggered lock times exercise the actual top reset gate.
module sys_pll(input refclk,reset,output reg clk0_out=0,clk1_out=0,clk2_out=1,output reg extlock=0);
 always #5 clk0_out=~clk0_out;
 always #4 clk1_out=~clk1_out;
 always #4 clk2_out=~clk2_out;
 initial #2311 extlock=1;
endmodule
module video_pll(input refclk,reset,output reg clk0_out=0,clk1_out=0,output reg extlock=0);
 always #20 clk0_out=~clk0_out;
 always #4 clk1_out=~clk1_out;
 initial #3333 extlock=1;
endmodule
module PLL_HDMI_AUDIO(input refclk,reset,output clk0_out,clk1_out,output reg clk2_out=0,output reg extlock=0);
 assign clk0_out=0;assign clk1_out=0;
 always #40.667 clk2_out=~clk2_out;
 initial #5207 extlock=1;
endmodule
module EG_LOGIC_BUFG(input i,output o);assign o=i;endmodule
// Original encrypted SDRAM controller drives the existing custom pin model.
module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input [10:0] addr,input [1:0] ba,
 inout [31:0] dq,input cs_n,dm0,dm1,dm2,dm3,cke);
 wire [31:0] errors;
 sdram_pin_model model(.clk(clk),.ras_n(ras_n),.cas_n(cas_n),.we_n(we_n),.addr(addr),
  .ba(ba),.dq(dq),.dm({dm3,dm2,dm1,dm0}),.protocol_errors(errors));
 always @(posedge clk) if(cke && errors!=0) $fatal(1,"FAIL physical SDRAM protocol");
endmodule
// Audio ROM contents are converted byte-for-byte from the actual MIF by runner.
module AUDIO_SPEECH_ROM(input clka,input [15:0] addra,output reg [7:0] doa);
 reg [7:0] rom[0:49151];string path;
 initial begin
  if(!$value$plusargs("ROMHEX=%s",path)) $fatal(1,"ROMHEX missing");
  $readmemh(path,rom);
 end
 always @(posedge clka) doa<=rom[addra];
endmodule
module hdmi_phy_wrapper #(parameter DEVICE="EG")(
 input I_pixel_clk,I_serial_clk,I_rst,input [9:0] I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,
 output O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p);
 assign {O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p}=0;
endmodule
