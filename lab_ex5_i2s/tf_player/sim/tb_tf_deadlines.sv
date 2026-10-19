`timescale 1ns/1ps
// Focused scheduler deadline/bank ownership test; not an SPI/pixel simulation.
module tb_tf_deadlines;
 reg clk=0,rst=1;always #5 clk=~clk;
 wire wr_req,wr_en,abort_req;wire [1:0] bank,disp;wire [13:0] asset;wire [6:0] ordinal;
 tf_file_player #(.CLK_FREQ_HZ(1000)) dut(.clk(clk),.rst(rst),.key_next(1'b1),.key_auto(1'b1),.key_zoom(1'b1),
 .write_ready(1'b1),.write_req_ack(1'b0),.write_finish_toggle(1'b0),.write_abort_done(1'b0),
 .write_req(wr_req),.write_en(wr_en),.write_data(),.write_abort(abort_req),.write_buf_idx(bank),.disp_buf_idx(disp),
 .display_valid(),.display_commit_toggle(),.display_commit_ack(1'b0),.display_asset(asset),.display_ordinal(ordinal),
 .osd_auto_mode(),.audio_track_idx(),.audio_track_toggle(),.audio_enabled(),.state_code(),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1));
 task check(input bit ok,input string msg);if(!ok)$fatal(1,"FAIL deadline %s state=%0d count=%0d",msg,dut.state,dut.wait_count);endtask
 task reset_test;begin rst=1;repeat(5)@(negedge clk);rst=0;@(negedge clk);end endtask
 initial begin
  force dut.media_ready=1;force dut.init_error=0;force dut.mount_done=0;force dut.mount_ready=1;
  force dut.ferror=0;force dut.berror=0;force dut.zoverflow=0;force dut.bmp_ok=0;force dut.fvalid=0;force dut.fready=1;
  reset_test();dut.state=5;dut.wait_count=9998;
  force dut.fvalid=1;@(negedge clk);check(dut.wait_count==0 && !abort_req,"progress clears timer");force dut.fvalid=0;
  repeat(5)@(negedge clk);check(dut.state==5 && !abort_req,"no stale deadline after progress");
  dut.wait_count=9998;@(negedge clk);check(dut.wait_count==9999 && dut.state==5,"load before limit");
  @(negedge clk);check(dut.wait_count==10000 && dut.state==5,"load reaches limit");
  @(negedge clk);check(dut.state==7 && abort_req,"load deadline exact");
  dut.wait_count=3998;@(negedge clk);check(dut.state==7 && dut.wait_count==3999,"clean before limit");
  @(negedge clk);check(dut.state==7 && dut.wait_count==4000,"clean reaches limit");
  @(negedge clk);check(dut.state==9,"clean deadline locks unknown bank");
  reset_test();dut.state=6;dut.display_commit_toggle=1;dut.display_valid=1;dut.disp_buf_idx=1;
  dut.display_asset=9999;dut.display_ordinal=32;dut.wait_count=1998;
  @(negedge clk);check(dut.state==6 && dut.wait_count==1999,"commit before limit");
  @(negedge clk);check(dut.state==6 && dut.wait_count==2000,"commit reaches limit");
  @(negedge clk);check(dut.state==9,"commit timeout locks bank");
  force dut.next_press=1;force dut.zoom_press=1;repeat(100)@(negedge clk);
  check(dut.state==9 && !wr_req && !wr_en && disp==1 && asset==9999 && ordinal==32,"no reuse without video memory ack");
  $display("TF_DEADLINES_PASS exact_load=10000 exact_clean=4000 exact_commit=2000 locked=100");$finish;
 end
 initial begin #1000000;$fatal(1,"deadline watchdog");end
endmodule
