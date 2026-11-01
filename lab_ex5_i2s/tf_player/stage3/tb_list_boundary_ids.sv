`timescale 1ns/1ps
// Scheduler unit test: controlled file completion, not a card/pixel test.
module tb_list_boundary_ids;
 parameter MAX_FILES=32;
 reg clk=0;always #5 clk=~clk;reg rst=1;
 wire commit,ack,dvalid,aenabled,atoggle,abort_req,cs,sclk,mosi;
 wire [1:0] wbank,dbank,track,vbank;wire [13:0] asset;wire [6:0] ordinal;wire [20:0] vitem;
 reg frame=0,memack=0;wire rr,vvalid;integer checks=0;reg reinit_seen=0;reg audio_before;
 always @(posedge clk) if(dut.card_reinit) reinit_seen<=1;
    tf_file_player #(.MAX_FILES(MAX_FILES)) dut(.clk(clk),.rst(rst),.key_next(1'b0),.key_auto(1'b1),.key_zoom(1'b1),
 .rotation_period_s(5'd3),.rotation_period_toggle(1'b0),
 .write_ready(1'b1),.write_req_ack(1'b0),.write_finish_toggle(1'b0),.write_abort_done(1'b0),
 .write_req(),.write_en(),.write_data(),.write_abort(abort_req),.write_buf_idx(wbank),.disp_buf_idx(dbank),
 .display_valid(dvalid),.display_commit_toggle(commit),.display_commit_ack(ack),.display_asset(asset),.display_ordinal(ordinal),
 .osd_auto_mode(),.audio_track_idx(track),.audio_track_toggle(atoggle),.audio_enabled(aenabled),.state_code(),
 .SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(1'b1));
 osd_display_commit #(.ITEM_W(21)) bridge(.clk(clk),.rst(rst),.src_toggle(commit),.src_bank(dbank),
 .src_item({ordinal,asset}),.src_valid(dvalid),.frame_read_req(frame),.mem_read_ack(memack),
 .read_req(rr),.ack_toggle(ack),.bank(vbank),.item(vitem),.valid(vvalid));
 function automatic [13:0] id_for(input integer slot);
 begin if(slot==31)id_for=9999;else if(slot==30)id_for=8192;
 else if(slot==29)id_for=32;else if(slot==28)id_for=31;else id_for=slot+1;end endfunction
 task check(input bit b,input string why);begin if(!b)$fatal(1,"FAIL %s n=%0d state=%0d asset=%0d ord=%0d",why,MAX_FILES,dut.state,asset,ordinal);checks=checks+1;end endtask
 task next_key;begin @(negedge clk);force dut.next_press=1;@(negedge clk);force dut.next_press=0;@(negedge clk);release dut.next_press;end endtask
 task commit_load(input integer slot);
 reg [1:0] oldbank;reg [20:0] olditem;reg oldaudio;
 begin
  wait(dut.state==6);oldbank=vbank;olditem=vitem;oldaudio=atoggle;
  check(asset==id_for(slot) && ordinal==slot+1,"slot, ID and ordinal");
  repeat(15) @(negedge clk);
  check(dut.state==6 && vbank==oldbank && vitem==olditem && atoggle==oldaudio,"hold until boundary and ack");
  frame=1;@(negedge clk);frame=0;repeat(4) @(negedge clk);
  check(vitem=={ordinal,asset} && vbank==dbank,"atomic wide packet");
  check(dut.state==6,"no bank reuse before memory ack");
  memack=1;repeat(5) @(negedge clk);memack=0;wait(dut.state==2);repeat(3) @(negedge clk);
  check(aenabled==(asset>=1 && asset<=4),"explicit audio validity");
  if(aenabled) check(track==asset-1,"explicit audio track");
 end endtask
 integer slot_init;
 initial begin
  for(slot_init=0;slot_init<MAX_FILES;slot_init=slot_init+1)
   dut.fs.index_mem[slot_init]={id_for(slot_init),32'd2,32'd921654};
  force dut.fs.index_we=0;force dut.fs.mounted=1;force dut.fs.file_count=MAX_FILES;
  force dut.media_ready=1;force dut.mount_ready=1;force dut.mount_done=1;force dut.mounted=1;
  // Keep the real synchronous index RAM and index_valid latency.
  force dut.open_ready=1;force dut.bbusy=0;
  force dut.bdone=1;force dut.zsource=1;force dut.zdone=1;force dut.zoverflow=0;force dut.wrote=1;
  force dut.ferror=0;force dut.berror=0;
  repeat(5) @(negedge clk);rst=0;commit_load(0);
  next_key();commit_load(1);next_key();commit_load(2);next_key();commit_load(3);next_key();commit_load(4);
  force dut.cursor=27;next_key();release dut.cursor;commit_load(28);check(asset==31,"actual ID31");
  next_key();commit_load(29);check(asset==32,"actual ID31 to ID32");
  next_key();commit_load(30);next_key();commit_load(31);
  force dut.cursor=MAX_FILES-2;next_key();release dut.cursor;commit_load(MAX_FILES-1);
  next_key();commit_load(0);
  audio_before=atoggle;
  force dut.failed=1;
  @(negedge clk);force dut.zoom_press=1;@(negedge clk);force dut.zoom_press=0;
  @(negedge clk);release dut.zoom_press;release dut.failed;
  commit_load(0);check(atoggle==audio_before,"same asset zoom keeps audio position");
  force dut.media_ready=0;force dut.init_error=1;next_key();
  check(reinit_seen,"next request retries failed card init without display reset");
  $display("LIST_BOUNDARY_IDS_PASS actual_ids=31->32 max_files=%0d checks=%0d",MAX_FILES,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"list watchdog state=%0d",dut.state);end
endmodule
