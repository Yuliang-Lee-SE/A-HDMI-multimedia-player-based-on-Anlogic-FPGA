`timescale 1ns/1ps
`include "osd_sim_inputs/config.vh"
module tb_osd_rom;
reg clk=0;always #5 clk=~clk;
reg [8:0] ta=0;reg [11:0] ga=0;
wire [7:0] tid;wire [15:0] grow;
osd_resources dut(clk,ta,tid,ga,grow);
reg [7:0] text_gold[0:511];reg [15:0] glyph_gold[0:`OSD_GLYPH_ROWS-1];
integer errors=0,completed=0,n;
initial begin
 $readmemh("osd_sim_inputs/text_rom.hex",text_gold);
 $readmemh("osd_sim_inputs/glyph_rows.hex",glyph_gold);
 for(n=0;n<`OSD_GLYPH_ROWS;n=n+1) begin
  @(negedge clk);ga=n;ta=n%512;
  @(posedge clk);#1;
  if(tid!==text_gold[n%512] || grow!==glyph_gold[n]) begin errors=errors+1;$display("ROM FAIL addr=%0d",n);end
 end
 completed=1;$display("OSD ROM COMPLETE errors=%0d",errors);$finish;
end
endmodule
