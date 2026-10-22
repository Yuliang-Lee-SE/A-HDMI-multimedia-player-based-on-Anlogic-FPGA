`timescale 1ns/1ps
// Full actual-top frame: R7 extension bits and CRC-off dummy trailers.
module tb_board_cmd8_rgb;
 tb_board_top_rgb check_top();
 defparam check_top.card.CMD8_R7=32'h000101aa;
 defparam check_top.card.CRC_OFF_POLICY=1;
 integer last_reads=0;
 always @(negedge check_top.dut.sd_card_clk) begin
  if(check_top.dut.sd_card_bmp_m0.init_error)
   $fatal(1,"FAIL SD board initialization diagnostic=%05h",check_top.dut.tf_init_diagnostic);
  if(check_top.reads>0 && (!check_top.card.crc_enabled || check_top.card.crc_on_calls!=1))
   $fatal(1,"FAIL sector read without negotiated CRC mode");
  if(check_top.reads>=last_reads+128)begin
   last_reads=check_top.reads;
   $display("SD_E2E_PROGRESS reads=%0d state=%h t=%0t",last_reads,check_top.dut.state_code,$time);
  end
 end
endmodule
