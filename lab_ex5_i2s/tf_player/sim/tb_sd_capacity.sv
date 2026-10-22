`timescale 1ns/1ps
module tb_sd_capacity;
 parameter HC=1,LEGACY=0,HC_SIZE=8191,SC_SIZE=4095,SC_MULT=7,READ_BL=9,EXPECT_OK=1;
 parameter [31:0] EXPECT_SECTORS=8388608;
 reg clk=0,rst=1;always #5 clk=~clk;
 wire cs,sclk,mosi,miso,ready,init_error,block_addr;
 wire [31:0] sectors,last_arg;integer reads;
 sd_spi_reader #(.LOW_DIV(1),.POWER_CYCLES(20),.INIT_CYCLES(1000000)) dut(
  .clk(clk),.rst(rst),.reinit(1'b0),.SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso),
  .media_ready(ready),.init_error(init_error),.block_addressed(block_addr),.media_sectors(sectors),
  .req_valid(1'b0),.req_ready(),.req_lba(32'd0),.req_tag(32'd0),.cancel_valid(1'b0),.cancel_tag(32'd0),
  .rsp_tag(),.rsp_valid(),.rsp_data(),.rsp_done(),.rsp_error());
 sd_card_model #(.CSD_HC_SIZE(HC_SIZE),.CSD_SC_SIZE(SC_SIZE),.CSD_SC_MULT(SC_MULT),.CSD_READ_BL(READ_BL))
  card(cs,sclk,mosi,miso,HC!=0,LEGACY!=0,4'd0,reads,last_arg);
 initial begin
  repeat(10) @(negedge clk);rst=0;wait(ready || init_error);#1;
  if(EXPECT_OK) begin
   if(!ready || init_error || block_addr!=(HC!=0) || sectors!==EXPECT_SECTORS)
    $fatal(1,"FAIL capacity hc=%0d got=%0d expected=%0d ready=%b",HC,sectors,EXPECT_SECTORS,ready);
  end else if(ready || !init_error) $fatal(1,"FAIL capacity rejection");
  $display("SD_CAPACITY_PASS hc=%0d legacy=%0d read_bl=%0d accepted=%0d sectors=%0d",HC,LEGACY,READ_BL,ready,sectors);$finish;
 end
 initial begin #20000000;$fatal(1,"capacity watchdog");end
endmodule
