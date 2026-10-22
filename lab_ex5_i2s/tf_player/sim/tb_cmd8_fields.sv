`timescale 1ns/1ps
module tb_cmd8_fields;
 parameter CASE_ID=0;
 function automatic [31:0] reply(input integer c);
  case(c)
   0:reply=32'h000001aa;1:reply=32'h000101aa;2:reply=32'hf00001aa;
   3:reply=32'h000031aa;4:reply=32'h00fff1aa;5:reply=32'hfffff1aa;
   6:reply=32'ha5a5a1aa;7:reply=32'h100001aa;8:reply=32'h000801aa;9:reply=32'h555551aa;
   default:if(c<26)reply=32'h123450aa|((c-10)<<8);
    else reply=32'h567891aa^(32'b1<<(c-26));
  endcase
 endfunction
 localparam [31:0] R7=reply(CASE_ID);
 localparam OK=(R7[11:0]==12'h1aa);
 reg clk=0,rst=1;always #5 clk=~clk;
 wire cs,sclk,mosi,miso,ready,error,rr,valid,done,rerror;
 wire ocs,osclk,omosi,omiso,oready,oerror;wire [19:0] diag,odiag;
 wire [31:0] sectors,tag,last_arg,olast_arg;wire [7:0] data;integer reads,oreads;
 reg request=0;integer bytes=0;
 sd_spi_reader #(.LOW_DIV(1),.POWER_CYCLES(20),.INIT_CYCLES(1000000)) dut(
 .clk(clk),.rst(rst),.reinit(1'b0),.SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso),
 .media_ready(ready),.init_error(error),.media_sectors(sectors),.block_addressed(),.init_diagnostic(diag),
 .req_valid(request),.req_ready(rr),.req_lba(32'd7),.req_tag(32'd73),.cancel_valid(1'b0),.cancel_tag(32'd0),
 .rsp_tag(tag),.rsp_valid(valid),.rsp_data(data),.rsp_done(done),.rsp_error(rerror));
 sd_spi_reader_reference #(.LOW_DIV(1),.POWER_CYCLES(20),.INIT_CYCLES(1000000)) original(
 .clk(clk),.rst(rst),.reinit(1'b0),.SD_nCS(ocs),.SD_DCLK(osclk),.SD_MOSI(omosi),.SD_MISO(omiso),
 .media_ready(oready),.init_error(oerror),.media_sectors(),.block_addressed(),.init_diagnostic(odiag),
 .req_valid(1'b0),.req_ready(),.req_lba(32'd0),.req_tag(32'd0),.cancel_valid(1'b0),.cancel_tag(32'd0),
 .rsp_tag(),.rsp_valid(),.rsp_data(),.rsp_done(),.rsp_error());
 sd_card_model #(.CMD8_R7(R7)) card(cs,sclk,mosi,miso,1'b1,1'b0,4'b0,reads,last_arg);
 sd_card_model #(.CMD8_R7(R7)) ocard(ocs,osclk,omosi,omiso,1'b1,1'b0,4'b0,oreads,olast_arg);
 always @(posedge clk)if(valid)begin
  if(tag!==73 || data!==((bytes*37+7)&255))$fatal(1,"FAIL read payload %0d",bytes);
  bytes=bytes+1;
 end
 initial begin
  repeat(5)@(negedge clk);rst=0;wait(ready || error);#1;
  if(ready!==OK || error===OK)$fatal(1,"FAIL field decision R7=%h diag=%h",R7,diag);
  if(OK)begin
   if(sectors!==8388608 || diag!==0)$fatal(1,"FAIL initialized metadata");
   wait(rr);@(negedge clk);request=1;@(negedge clk);request=0;wait(done || rerror);
   if(!done || rerror)$fatal(1,"FAIL sector result after CMD8");
   @(posedge clk);@(negedge clk);if(bytes!=512)$fatal(1,"FAIL sector byte count after CMD8 got=%0d",bytes);
  end else begin
   if(R7[7:0]!=8'haa)begin if(diag!=={4'hd,8'h08,R7[7:0]})$fatal(1,"FAIL echo diagnostic %h",diag);end
   else if(diag!=={4'hc,8'h08,4'b0,R7[11:8]})$fatal(1,"FAIL voltage diagnostic %h",diag);
  end
  wait(oready || oerror);#1;
  if(R7!=32'h1aa && (!oerror || odiag!=={4'h2,8'h08,R7[7:0]}))$fatal(1,"FAIL old rejection counterexample");
  $display("CMD8_FIELDS_PASS case=%0d R7=%h accepted=%b old_error=%b old_diag=%05h bytes=%0d",CASE_ID,R7,ready,oerror,odiag,bytes);$finish;
 end
 initial begin #20000000;$fatal(1,"FAIL field watchdog");end
endmodule
