`timescale 1ns/1ps
module tb_sd_init_diagnostic;
 parameter CASE_ID=0;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,reinit=0,hc=1,req=0;reg [3:0] fault=0;
 wire cs,sclk,mosi,miso,ready,init_error,ba,rr,valid,done,error;
 wire cs_old,sclk_old,mosi_old,ready_old,ie_old,ba_old,rr_old,v_old,d_old,e_old;
 wire [31:0] sectors,tag,sectors_old,tag_old,last_arg;wire [7:0] data,data_old;
 wire [19:0] diagnostic;integer reads,checks=0;reg [19:0] frozen;
 reg [7:0] last_completed_rx=8'hff;
 always @(posedge clk) begin
  if(rst || reinit)last_completed_rx<=8'hff;
  else if(original.ack)last_completed_rx<=original.rx;
 end
 sd_spi_reader #(.LOW_DIV(1),.POWER_CYCLES(20),.INIT_CYCLES(150000),.TOKEN_CYCLES(5000)) dut(
 .clk(clk),.rst(rst),.reinit(reinit),.SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso),
 .media_ready(ready),.init_error(init_error),.block_addressed(ba),.media_sectors(sectors),.init_diagnostic(diagnostic),
 .req_valid(req),.req_ready(rr),.req_lba(32'd7),.req_tag(32'd42),.cancel_valid(1'b0),.cancel_tag(32'd0),
 .rsp_tag(tag),.rsp_valid(valid),.rsp_data(data),.rsp_done(done),.rsp_error(error));
 sd_spi_reader_reference #(.LOW_DIV(1),.POWER_CYCLES(20),.INIT_CYCLES(150000),.TOKEN_CYCLES(5000)) original(
 .clk(clk),.rst(rst),.reinit(reinit),.SD_nCS(cs_old),.SD_DCLK(sclk_old),.SD_MOSI(mosi_old),.SD_MISO(miso),
 .media_ready(ready_old),.init_error(ie_old),.block_addressed(ba_old),.media_sectors(sectors_old),
 .req_valid(req),.req_ready(rr_old),.req_lba(32'd7),.req_tag(32'd42),.cancel_valid(1'b0),.cancel_tag(32'd0),
 .rsp_tag(tag_old),.rsp_valid(v_old),.rsp_data(data_old),.rsp_done(d_old),.rsp_error(e_old));
 sd_card_model #(.CSD_HC_SIZE(CASE_ID==9 ? 4194303:8191)) card(cs,sclk,mosi,miso,hc,1'b0,fault,reads,last_arg);
 always @(negedge clk) if(!rst) begin
  if({cs,sclk,mosi,ready,init_error,ba,rr,valid,done,error,sectors,tag,data} !==
     {cs_old,sclk_old,mosi_old,ready_old,ie_old,ba_old,rr_old,v_old,d_old,e_old,sectors_old,tag_old,data_old})
   $fatal(1,"FAIL observable behavior differs from published reference case=%0d",CASE_ID);
  checks=checks+1;
 end
 function automatic [3:0] reason;
 case(CASE_ID) 1:reason=1;2:reason=13;3:reason=2;4:reason=3;5:reason=4;6:reason=5;
 7:reason=6;8:reason=7;9:reason=8;10:reason=10;default:reason=0;endcase
 endfunction
 initial begin
  case(CASE_ID) 1:fault=13;2:fault=11;3:fault=10;4:fault=15;5:fault=14;6:fault=9;
   7:fault=12;8:fault=8;10:fault=7;default:fault=0;endcase
  repeat(5)@(negedge clk);rst=0;
  wait(ready || init_error);@(negedge clk);
  if(CASE_ID==0 || CASE_ID==11) begin
   if(!ready || diagnostic!==0)$fatal(1,"FAIL successful init diagnostic");
   if(CASE_ID==11) fault=1;
   req=1;@(negedge clk);req=0;wait(done || error);@(negedge clk);
   if((CASE_ID==0 && !done) || (CASE_ID==11 && !error) || diagnostic!==0)
    $fatal(1,"FAIL read diagnostic isolation");
  end else begin
   if(!init_error || diagnostic[19:16]!==reason())$fatal(1,"FAIL reason case=%0d diag=%h",CASE_ID,diagnostic);
   if(CASE_ID==10 && diagnostic[7:0]!==last_completed_rx)$fatal(1,"FAIL timeout captured partial SPI byte");
   if((CASE_ID==1 && diagnostic[15:8]!==0) || (CASE_ID==2 && diagnostic[15:8]!==8) ||
      (CASE_ID==3 && diagnostic[15:8]!==58) || (CASE_ID>=4 && CASE_ID<=9 && diagnostic[15:8]!==9))
    $fatal(1,"FAIL failed command diag=%h",diagnostic);
   frozen=diagnostic;repeat(100)begin @(negedge clk);if(diagnostic!==frozen)$fatal(1,"FAIL sticky snapshot");end
   $display("INIT_DIAG_OBSERVED case=%0d word=%05h",CASE_ID,diagnostic);
   fault=0;if(CASE_ID==9)hc=0;
   reinit=1;@(negedge clk);reinit=0;@(negedge clk);
   if(diagnostic!==0)$fatal(1,"FAIL reinit does not clear snapshot");
   wait(ready || init_error);if(!ready)$fatal(1,"FAIL recovery");
  end
  $display("INIT_DIAG_PASS case=%0d lockstep_cycles=%0d",CASE_ID,checks);$finish;
 end
 initial begin #10000000;$fatal(1,"FAIL watchdog case=%0d",CASE_ID);end
endmodule
