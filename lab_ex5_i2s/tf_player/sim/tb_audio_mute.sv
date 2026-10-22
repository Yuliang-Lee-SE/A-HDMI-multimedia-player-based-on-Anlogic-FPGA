`timescale 1ns/1ps
module tb_audio_mute;
 reg clk=0;always #1 clk=~clk;reg rst=1,enabled=0,toggle=0;reg [1:0] track=0;
 wire [15:0] addr;wire bclk,lrck,dout;integer nonzero=0;
 audio_rom_player #(.ENABLE_MUTE(1),.RAMP_FRAMES(4)) dut(.I_mclk(clk),.I_rst(rst),.I_track_idx(track),
 .I_enabled(enabled),.I_track_toggle(toggle),.I_rom_data(8'd64),.O_rom_addr(addr),.O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
 task silence;integer j;begin for(j=0;j<2048;j=j+1) begin @(negedge clk);if(dout!==0)$fatal(1,"FAIL mute serial");end end endtask
 initial begin
  repeat(5) @(negedge clk);rst=0;repeat(2048) @(negedge clk);silence();
  enabled=1;track=2;toggle=!toggle;repeat(8192) @(negedge clk);
  if(!dut.enabled_lat || dut.S_track_base!=24576)$fatal(1,"FAIL mapped track capture");
  repeat(2048) begin @(negedge clk);if(dout)nonzero=nonzero+1;end
  if(nonzero==0)$fatal(1,"FAIL active audio silent");
  enabled=0;toggle=!toggle;repeat(8192) @(negedge clk);silence();
  $display("AUDIO_MUTE_PASS active_bits=%0d",nonzero);$finish;
 end
endmodule
