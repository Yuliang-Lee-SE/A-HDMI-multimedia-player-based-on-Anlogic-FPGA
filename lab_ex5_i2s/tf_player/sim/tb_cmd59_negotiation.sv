`timescale 1ns/1ps
module tb_cmd59_negotiation;
 parameter integer CASE_ID=0;
 localparam integer POLICY=CASE_ID<9 ? CASE_ID%3:1;
 localparam integer BEHAVIOR=CASE_ID==9 ? 1:CASE_ID==10 ? 2:CASE_ID==11 ? 3:0;
 localparam integer HC=CASE_ID<3 || CASE_ID>=9;
 localparam integer LEGACY=CASE_ID>=6 && CASE_ID<9;
 reg clk=0,rst=1,reinit=0,req=0;always #5 clk=~clk;
 reg [3:0] fault=CASE_ID==12 ? 9:0;
 wire cs,sclk,mosi,miso,ready,error,rr,valid,done,rerror;
 wire ocs,osclk,omosi,omiso,oready,oerror;
 wire [19:0] diag,odiag;wire [31:0] sectors,tag,last_arg,olast_arg;
 wire [7:0] data;integer reads,oreads,bytes=0;
 sd_spi_reader #(.LOW_DIV(1),.POWER_CYCLES(20),.INIT_CYCLES(1000000),.TOKEN_CYCLES(5000)) dut(
 .clk(clk),.rst(rst),.reinit(reinit),.SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso),
 .media_ready(ready),.init_error(error),.media_sectors(sectors),.block_addressed(),.init_diagnostic(diag),
 .req_valid(req),.req_ready(rr),.req_lba(32'd7),.req_tag(32'd73),.cancel_valid(1'b0),.cancel_tag(32'd0),
 .rsp_tag(tag),.rsp_valid(valid),.rsp_data(data),.rsp_done(done),.rsp_error(rerror));
 sd_spi_reader_previous #(.LOW_DIV(1),.POWER_CYCLES(20),.INIT_CYCLES(1000000),.TOKEN_CYCLES(5000)) previous(
 .clk(clk),.rst(rst),.reinit(1'b0),.SD_nCS(ocs),.SD_DCLK(osclk),.SD_MOSI(omosi),.SD_MISO(omiso),
 .media_ready(oready),.init_error(oerror),.media_sectors(),.block_addressed(),.init_diagnostic(odiag),
 .req_valid(1'b0),.req_ready(),.req_lba(32'd0),.req_tag(32'd0),.cancel_valid(1'b0),.cancel_tag(32'd0),
 .rsp_tag(),.rsp_valid(),.rsp_data(),.rsp_done(),.rsp_error());
 sd_card_model #(.CRC_OFF_POLICY(POLICY),.CMD59_BEHAVIOR(BEHAVIOR),.CMD8_R7(32'h000101aa))
 card(cs,sclk,mosi,miso,HC!=0,LEGACY!=0,fault,reads,last_arg);
 sd_card_model #(.CRC_OFF_POLICY(POLICY),.CMD59_BEHAVIOR(BEHAVIOR),.CMD8_R7(32'h000101aa))
 ocard(ocs,osclk,omosi,omiso,HC!=0,LEGACY!=0,fault,oreads,olast_arg);
 always @(posedge clk)if(valid)begin
  if(tag!==73 || data!==((bytes*37+(HC ? 7:3584))&255))$fatal(1,"FAIL read payload %0d",bytes);
  bytes=bytes+1;
 end
 task check(input bit ok,input string why);
  if(!ok)$fatal(1,"FAIL %s case=%0d new=%05h old=%05h",why,CASE_ID,diag,odiag);
 endtask
 task request;
  begin wait(rr);@(negedge clk);req=1;@(negedge clk);req=0;end
 endtask
 initial begin
  // Independent long-division model known CRC7 vectors.
  check(card.wire_crc7(40'h4000000000)==8'h95,"CMD0 known CRC7");
  check(card.wire_crc7(40'h48000001aa)==8'h87,"CMD8 known CRC7");
  check(card.wire_crc7(40'h7b00000001)==8'h83,"CMD59 known CRC7");
  repeat(5)@(negedge clk);rst=0;wait(ready || error);#1;
  if(CASE_ID>=9 && CASE_ID<=12)begin
   check(error && !ready,"must reject negotiation or corrupt CRC");
   if(CASE_ID==9)check(diag==20'h23b05,"CMD59 reject preserved");
   if(CASE_ID==10)check(diag==20'h13bff,"CMD59 response timeout bounded");
   if(CASE_ID==11)check(diag==20'h50900,"CRC failure still checked after false ACK");
   if(CASE_ID==12)check(diag[19:8]==12'h509,"CSD CRC corruption rejected");
  end else begin
   check(ready && !error && diag==0,"CRC on init");
   check(card.crc_on_calls==1 && card.crc_enabled && card.protected_blocks==1,"one negotiated CSD");
   check(sectors==(HC ? 8388608:2097152),"capacity retained");
   if(CASE_ID==13)fault=1;else if(CASE_ID==14)fault=2;
   request();wait(done || rerror);@(posedge clk);@(negedge clk);
   if(CASE_ID==13)check(rerror || (!done && bytes==0 && !ready),"bad sector CRC rejected");
   else check(bytes==512,"complete sector after CRC negotiation");
   if(CASE_ID==13)check(bytes==0 && reads==3,"bad retry never leaks data");
   if(CASE_ID==14)check(reads==2,"first CRC failure retry recovers");
   if(CASE_ID==15)begin
    reinit=1;@(negedge clk);reinit=0;wait(!ready);wait(ready || error);#1;
    check(ready && card.crc_on_calls==2 && card.crc_enabled,"reinit renegotiates CRC");
   end
  end
  wait(oready || oerror);#1;
  check(ocard.crc_on_calls==0,"previous source has no CMD59");
  if(POLICY==0 && CASE_ID<9)check(oready,"historical model also accepted previous");
  else if(CASE_ID!=12)begin
   check(oerror && odiag[19:8]==12'h509,"old CSD failure counterexample");
   if(POLICY==1)check(odiag==20'h50900,"old 50900 counterexample");
  end
  $display("CMD59_NEGOTIATION_PASS case=%0d policy=%0d behavior=%0d hc=%0d legacy=%0d old=%05h new=%05h bytes=%0d calls=%0d",CASE_ID,POLICY,BEHAVIOR,HC,LEGACY,odiag,diag,bytes,card.crc_on_calls);
  $finish;
 end
 initial begin #30000000;$fatal(1,"FAIL negotiation watchdog");end
endmodule
