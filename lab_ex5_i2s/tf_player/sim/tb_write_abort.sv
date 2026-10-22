`timescale 1ns/1ps
module tb_write_abort;
 reg clk=0;always #4 clk=~clk;reg rst=1,req=0,abort_req=0,busy=0;
 wire ack,finish,clear,abort_done,we,wb;wire [20:0] addr;
 integer writes=0,finishes=0,cycles=0;
 frame_fifo_write #(.FRAME_WIDTH(8),.FRAME_HEIGHT(8),.BURST_SIZE(16)) dut(
 .rst(rst),.abort_req(abort_req),.abort_done(abort_done),.mem_clk(clk),.Sdr_init_done(1'b1),
 .Sdr_init_ref_vld(1'b0),.Sdr_busy(busy),.App_rd_busy(1'b0),.O_wr_busy(wb),.App_wr_en(we),
 .App_wr_addr(addr),.write_req(req),.write_req_ack(ack),.write_finish(finish),
 .write_addr_0(21'd0),.write_addr_1(21'd64),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(2'd1),.write_len(21'd64),.fifo_aclr(clear),.rdusedw(9'd64));
 task check(input bit ok,input string why);begin if(!ok) $fatal(1,"FAIL %s",why);end endtask
 always @(posedge clk) begin
  cycles<=cycles+1;if(cycles>5000)$fatal(1,"watchdog");
  if(we) begin check(addr>=64 && addr<128,"background address");writes=writes+1;end
  if(finish) finishes=finishes+1;
  if(abort_done) check(!we && !busy && clear,"abort drain");
  if(finish) check(!busy && !we,"completion drain");
 end
 task request;begin @(negedge clk);req=1;wait(ack);@(negedge clk);req=0;wait(!ack);end endtask
 initial begin
  repeat(5) @(negedge clk);rst=0;request();wait(writes==3);@(negedge clk);abort_req=1;busy=1;
  wait(dut.state==6);repeat(8) @(negedge clk);check(!abort_done && finishes==0,"abort waits controller");
  busy=0;wait(abort_done);check(writes==16,"complete current burst");
  @(negedge clk);abort_req=0;wait(!abort_done);repeat(8) @(negedge clk);
  writes=0;request();wait(writes==64);@(negedge clk);busy=1;
  repeat(20) @(negedge clk);check(finishes==0,"success waits controller");busy=0;
  wait(finish);@(posedge clk);@(negedge clk);check(writes==64 && finishes==1,"fresh frame after abort");
  $display("WRITE_ABORT_PASS writes=%0d",writes);$finish;
 end
endmodule
