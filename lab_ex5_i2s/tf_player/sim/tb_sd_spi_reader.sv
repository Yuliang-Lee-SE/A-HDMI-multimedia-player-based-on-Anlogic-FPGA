`timescale 1ns/1ps
module tb_sd_spi_reader;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,reinit=0,hc=1,legacy=0;reg [3:0] fault=0;
 wire cs,sclk,mosi,miso,ready,init_error,block_addr,req_ready;
 wire [31:0] sectors,tag,last_arg;wire valid,done,error;wire [7:0] data;
 reg req=0,cancel=0;reg [31:0] reqtag=1,canceltag=0,lba=7;
 integer reads,cycles=0,bytes=0,errors=0,passes=0;reg expect_data=0;
 sd_spi_reader #(.LOW_DIV(1),.HIGH_DIV(0),.POWER_CYCLES(20),
 .INIT_CYCLES(1000000),.TOKEN_CYCLES(5000),.READ_CYCLES(200000)) dut(
 .clk(clk),.rst(rst),.reinit(reinit),.SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso),
 .media_ready(ready),.init_error(init_error),.block_addressed(block_addr),.media_sectors(sectors),
 .req_valid(req),.req_ready(req_ready),.req_lba(lba),.req_tag(reqtag),
 .cancel_valid(cancel),.cancel_tag(canceltag),.rsp_tag(tag),.rsp_valid(valid),.rsp_data(data),.rsp_done(done),.rsp_error(error));
 sd_card_model card(cs,sclk,mosi,miso,hc,legacy,fault,reads,last_arg);
 task check(input bit b,input string why);begin if(!b) begin $display("FAIL %s state=%0d phase=%0d",why,dut.state,dut.phase);$fatal(1);end end endtask
 always @(posedge clk) begin
  if(!rst) begin
   check(!$isunknown(dut.state) && $onehot(dut.state),"onehot control state");
   if(dut.state==dut.BYTE_WAIT || dut.state==dut.BYTE_GAP) check(!$isunknown(dut.resume) && $onehot(dut.resume),"onehot byte return");
   if(dut.state==dut.DESELECT) check(!$isunknown(dut.after_release) && $onehot(dut.after_release),"onehot deselect return");
  end
  cycles<=cycles+1;if(cycles>15000000) $fatal(1,"watchdog state=%0d phase=%0d ready=%0d fault=%0d tag=%0d",dut.state,dut.phase,ready,fault,reqtag);
  if(valid) begin
   check(expect_data,"unexpected old response");check(tag==reqtag,"tag mismatch");
   check(data==((bytes*37+(hc ? lba:(lba<<9)))&255),"byte mismatch");bytes=bytes+1;
  end
 end
 task reset_card(input bit h,input bit old);
 begin @(negedge clk);rst=1;hc=h;legacy=old;fault=0;expect_data=0;repeat(5) @(negedge clk);rst=0;
 wait(ready || init_error);check(ready,"init");check(block_addr==h,"CCS");
 check(sectors==(h ? 8388608:2097152),"CSD capacity");end endtask
 task request(input integer id);
 begin wait(req_ready);@(negedge clk);reqtag=id;req=1;bytes=0;expect_data=1;
 @(negedge clk);req=0;end endtask
 task good_read(input integer id);
 begin $display("READ id=%0d hc=%0d legacy=%0d fault=%0d",id,hc,legacy,fault);request(id);wait(done || error);check(done && !error,"read success");
 @(posedge clk);@(negedge clk);check(bytes==512,"512 bytes");check(last_arg==(hc ? lba:(lba<<9)),"address unit");expect_data=0;passes=passes+1;end endtask
 integer f,r;
 initial begin
  reset_card(1,0);good_read(1);reset_card(0,0);good_read(2);reset_card(0,1);good_read(3);
  reset_card(1,0);fault=2;card.reads=0;good_read(4);check(reads==2,"CRC retry once");
  for(f=1;f<=6;f=f+1) if(f!=2) begin
   reset_card(1,0);fault=f;r=reads;$display("FAULT %0d",f);request(10+f);wait(error || done);
   check(error && !done && bytes==0,"failure isolation");check(reads-r==3,"bounded attempts");
   @(negedge clk);expect_data=0;fault=0;wait(ready);good_read(30+f);passes=passes+1;
  end
  reset_card(1,0);request(50);wait(card.reads>0 && dut.state==dut.DATA);@(negedge clk);
  canceltag=50;cancel=1;expect_data=0;@(negedge clk);cancel=0;
  check(!req_ready,"cancel closes ready");wait(ready);good_read(51);passes=passes+1;
  request(60);wait(dut.state==dut.DATA);@(negedge clk);rst=1;expect_data=0;
  repeat(5) @(negedge clk);rst=0;wait(ready);good_read(1);passes=passes+1;
  @(negedge clk);fault=7;reinit=1;@(negedge clk);reinit=0;wait(init_error);check(!ready,"init failure");passes=passes+1;
  fault=0;@(negedge clk);reinit=1;@(negedge clk);reinit=0;wait(ready);good_read(70);
  for(f=8;f<=11;f=f+1) begin
   @(negedge clk);fault=f;reinit=1;@(negedge clk);reinit=0;
   wait(init_error);check(!ready,"reject invalid CSD/CRC/OCR/R7");passes=passes+1;
  end
  fault=0;@(negedge clk);reinit=1;@(negedge clk);reinit=0;wait(ready);
  request(80);wait(dut.state==dut.DATA);@(negedge clk);cancel=1;canceltag=79;@(negedge clk);cancel=0;
  wait(done || error);check(done && !error,"stale cancel ignored");@(posedge clk);@(negedge clk);
  check(bytes==512 && tag==80,"new response retains tag");expect_data=0;passes=passes+1;
  request(90);wait(valid && bytes>=100);@(negedge clk);cancel=1;canceltag=89;
  @(negedge clk);cancel=0;wait(done || error);check(done && !error,"stale cancel during emission ignored");
  @(posedge clk);@(negedge clk);check(bytes==512 && tag==90,"stale emit cancel loses no bytes");
  expect_data=0;passes=passes+1;
  for(f=0;f<4;f=f+1) begin
   request(100+f);
   if(f==0) wait(dut.state==dut.BYTE_WAIT && dut.resume==dut.DATA_GOT && dut.spi.clk_edge_cnt==5);
   if(f==1) wait(dut.state==dut.BYTE_WAIT && dut.resume==dut.DATA_GOT && dut.ack);
   if(f==2) wait(dut.state==dut.BYTE_GAP && dut.resume==dut.DATA_GOT);
   if(f==3) wait(valid && bytes>=100);
   @(negedge clk);cancel=1;canceltag=reqtag;
   @(negedge clk);cancel=0;expect_data=0;
   check(!req_ready,"cancel busy boundary");wait(ready);good_read(110+f);passes=passes+1;
  end
  request(120);wait(dut.state==dut.BYTE_WAIT && dut.resume==dut.DATA_GOT && dut.spi.clk_edge_cnt==5);
  @(negedge clk);rst=1;expect_data=0;repeat(5) @(negedge clk);rst=0;
  wait(ready);good_read(1);passes=passes+1;
  // An initialization finishing just below its deadline must not poison recovery.
  @(negedge clk);dut.init_timer=999999;@(negedge clk);
  check(dut.init_timer==0,"ready clears old initialization budget");passes=passes+1;
  $display("SD_SPI_PASS checks=%0d",passes);$finish;
 end
endmodule
