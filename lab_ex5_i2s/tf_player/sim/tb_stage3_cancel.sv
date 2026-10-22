`timescale 1ns/1ps
// Focused 512-word transactions at real bank bases. Full 640x480 behavior is
// covered separately. Exercise real controller tails, refresh and read contention.
module tb_stage3_cancel;
 parameter SELF_REFRESH_OPEN=1;
 parameter FORCED_REFRESH=1;
 reg clk=0,mem_clk=0,vclk=0,rst=1,req=0,abort_req=0,wen=0,rreq=0,ren=0;
 always #5 clk=~clk;always #4 mem_clk=~mem_clk;always #20 vclk=~vclk;
 reg [31:0] data=0;reg [1:0] wbank=0,rbank=0;
 wire ready,ack,finish,abort_done,rack,rf;
 wire init_done,refresh,busy,sclk,ras,cas,we,aw,ar,rv;
 wire [20:0] wa,ra;wire [31:0] wd,rd,dq,rdata;wire [3:0] dm,pdm;
 wire [1:0] ba;wire [10:0] pa;wire [31:0] protocol;
 reg refresh_req=0;integer refresh_clock=0;
 integer sent=0,received=0,checks=0,finishes=0,app_count=0,physical_writes=0;
 integer refresh_count=0,contended=0;reg count_reads=0,after_ack=0;
 reg previous_finish_drained=0;
 reg previous_abort_done=0,previous_abort_drained=0;
 frame_read_write #(.WRITE_V_FLIP(0)) store(.rst(rst),.mem_clk(mem_clk),.Sdr_init_done(init_done),
  .Sdr_init_ref_vld(refresh),.Sdr_busy(busy),.App_rd_en(ar),.App_rd_addr(ra),.Sdr_rd_en(rv),.Sdr_rd_dout(rd),
  .read_clk(vclk),.read_req(rreq),.read_req_ack(rack),.read_finish(rf),
  .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
  .read_addr_index(rbank),.read_len(21'd512),.read_en(ren),.read_data(rdata),
  .App_wr_en(aw),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(dm),
  .write_clk(clk),.write_req(req),.write_req_ack(ack),.write_finish(finish),
  .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(wbank),.write_len(21'd512),.write_en(wen),.write_data(data),
  .write_ready(ready),.write_abort(abort_req),.write_abort_done(abort_done));
 sdr_as_ram #(.self_refresh_open(SELF_REFRESH_OPEN)) core(.Sdr_clk(mem_clk),.Sdr_clk_sft(~mem_clk),.Rst(rst),
  .Sdr_init_done(init_done),.Sdr_init_ref_vld(refresh),.Sdr_busy(busy),.App_ref_req(refresh_req),
  .App_wr_en(aw),.App_wr_addr(wa),.App_wr_dm(dm),.App_wr_din(wd),.App_rd_en(ar),.App_rd_addr(ra),
  .Sdr_rd_en(rv),.Sdr_rd_dout(rd),.SDRAM_CLK(sclk),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),
  .SDR_BA(ba),.SDR_ADDR(pa),.SDR_DM(pdm),.SDR_DQ(dq));
 sdram_pin_model memory(.clk(sclk),.ras_n(ras),.cas_n(cas),.we_n(we),.addr(pa),.ba(ba),.dq(dq),.dm(pdm),.protocol_errors(protocol));
 task check(input bit ok,input string msg);if(!ok) $fatal(1,"FAIL %s t=%0t state=%0d app=%0d",msg,$time,store.frame_fifo_write_m0.state,app_count);endtask
 function automatic [31:0] gold(input integer idx,bank);gold=32'ha5000000+bank*65536+idx;endfunction
 always @(negedge mem_clk) begin
  refresh_clock=refresh_clock+1;
  refresh_req=FORCED_REFRESH && init_done && refresh_clock%512<16;
 end
 always @(posedge mem_clk) if(!rst) begin
  if(aw) app_count=app_count+1;
  if(finish) begin finishes=finishes+1;check(previous_finish_drained && memory.write_left==0 && !aw,"finish physical tail");end
  previous_finish_drained<=store.frame_fifo_write_m0.state==7 && store.frame_fifo_write_m0.controller_drained && !store.frame_fifo_write_m0.abort_sync[2];
  if(abort_done) begin
   after_ack=1;
   if(!previous_abort_done) check(previous_abort_drained,"abort acknowledgement without drained controller");
   // A held acknowledgement permits later reads and refreshes, but no writes.
   check(!aw && memory.write_left==0,"abort_done before physical write tail");
  end
  previous_abort_done<=abort_done;
  previous_abort_drained<=store.frame_fifo_write_m0.controller_drained &&
                          store.frame_fifo_write_m0.state==6 && store.frame_fifo_write_m0.abort_sync[2];
  if(req) after_ack=0;
  if(rv && count_reads) begin check(rd===gold(received,rbank),"readback retains exact words");received=received+1;end
  if(ar && abort_req) contended=contended+1;
 end
 // Sample settled pin outputs on the falling edge, avoiding the model's
 // same-edge blocking counter updates in write_left.
 always @(negedge sclk) if(!rst) begin
  if({ras,cas,we}==3'b001) refresh_count=refresh_count+1;
  if(memory.write_left>0 || {ras,cas,we}==3'b100) begin
   check(!after_ack,"physical writes after abort acknowledgement");
   check(^dq!==1'bx,"unknown physical write data");physical_writes=physical_writes+1;
  end
 end
 task request_write(input integer bank);
  begin @(negedge clk);wbank=bank;req=1;app_count=0;sent=0;
   wait(ack);@(negedge clk);req=0;wait(!ack && ready);end
 endtask
 task feed;
  begin
   while(sent<512 && !abort_req) begin
    @(negedge clk);wen=ready && !abort_req;data=gold(sent,wbank);
    if(wen) sent=sent+1;
    @(negedge clk);wen=0;
   end
   wen=0;
  end
 endtask
 task readback(input integer bank);
  integer i;
  begin
   @(negedge vclk);rbank=bank;rreq=1;received=0;count_reads=1;
   wait(rack);@(negedge vclk);rreq=0;
   wait(store.read_buf.rdusedw>=256);
   for(i=0;i<512;i=i+1) begin @(negedge vclk);ren=1;check(!store.read_buf.empty_flag,"cancel read FIFO underflow");end
   @(negedge vclk);ren=0;wait(received==512);wait(!store.App_rd_busy);count_reads=0;
  end
 endtask
 integer mode,prior_finishes;
 initial begin
  repeat(10) @(negedge clk);rst=0;wait(init_done);
  request_write(0);feed();wait(finish);wait(!finish);readback(0);
  for(mode=0;mode<5;mode=mode+1) begin
   prior_finishes=finishes;request_write(1);
   fork
    feed();
    begin
     case(mode)
      0: wait(app_count==32); // Current active App burst.
      1: wait(app_count==512); // Last App word and physical pipeline tail.
      2: begin wait(app_count>=16);wait(refresh);end
      3: wait(app_count>=32);
      4: wait(store.frame_fifo_write_m0.state==4); // Burst-end pipeline boundary.
     endcase
     @(negedge clk);abort_req=1;
    end
    begin if(mode==3) begin wait(app_count>=16);readback(0);end end
   join
   wait(abort_done);check(finishes==prior_finishes,"aborted transaction signalled finish");
   @(negedge clk);abort_req=0;wait(!abort_done && ready);
   request_write(1);feed();wait(finish);wait(!finish);readback(1);readback(0);
   checks=checks+1;$display("CANCEL case=%0d PASS physical_words=%0d refresh=%0d",mode,physical_writes,refresh_count);
  end
  check(protocol==0 && refresh_count>0 && contended>0,"protocol, refresh and read contention coverage");
  $display("STAGE3_CANCEL_PASS cancel_checks=%0d refresh=%0d read_contention=%0d",checks,refresh_count,contended);$finish;
 end
 initial begin #20000000;$fatal(1,"cancel watchdog mode=%0d state=%0d sent=%0d",mode,store.frame_fifo_write_m0.state,sent);end
endmodule
