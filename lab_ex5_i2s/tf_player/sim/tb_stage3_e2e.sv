`timescale 1ns/1ps
// Pin-card -> real SPI/FAT/BMP/scaler -> original FIFO -> vendor encrypted
// SDRAM controller -> custom pin model -> original video timing/read FIFO.
// This is simulation evidence, not silicon or an official SDRAM timing model.
module tb_stage3_e2e;
 parameter SELF_REFRESH_OPEN=1;
 parameter FORCED_REFRESH=0;
 parameter TARGET_MODE=-1;
 reg clk=0,mem_clk=0,vclk=0,rst=1;
 always #5 clk=~clk;
 always #4 mem_clk=~mem_clk;
 always #20 vclk=~vclk;
 wire cs,sclk,mosi,miso,wr_req,wr_en,abort_req,ack,abort_done,write_finish,ready;
 wire [31:0] wr_data;
 wire [1:0] wr_bank,disp_bank,track;
 wire display_valid,commit,auto_mode,track_toggle,audio_enabled,commit_ack;
 wire [13:0] asset;wire [6:0] ordinal;wire [3:0] status;
 wire [1:0] vbank;wire [20:0] vitem;wire vvalid,read_req,frame_req,mem_ack;
 wire hs,vs,de,video_read;wire [31:0] read_data;
 reg finish_toggle=0;
 reg [3:0] fault=0;wire [31:0] last_arg;integer reads;
 integer pixels=0,commits=0,failures=0;
 integer track_changes=0,last_completed_id=0,last_completed_zoom=0;
 reg last_req=0,last_commit=0,last_track=0,last_abort=0;
 integer bank_id[0:1],bank_zoom[0:1];
 integer checked_frames[0:2];
 integer underflows=0,checked_pixels=0,old_read_pixels=0,physical_words=0,refreshes=0;
 integer physical_bad=0,physical_post_finish=0;
 reg finished_guard=0;
 wire init_done,refresh_active,sdr_busy,sdram_clk,ras,cas,we;
 wire [1:0] ba;wire [10:0] physical_addr;wire [3:0] physical_dm;
 wire [31:0] dq,core_data,app_data;wire core_valid,app_write,app_read;
 wire [20:0] app_waddr,app_raddr;wire [3:0] app_dm;wire [31:0] protocol_errors;
 reg app_ref_req=0;integer ref_cycles=0;
    tf_file_player #(.DEBOUNCE_MS(1)) dut(.clk(clk),.rst(rst),.key_next(1'b0),.key_auto(1'b1),.key_zoom(1'b1),
  .write_ready(ready),.write_req_ack(ack),.write_finish_toggle(finish_toggle),.write_abort_done(abort_done),
  .write_req(wr_req),.write_en(wr_en),.write_data(wr_data),.write_abort(abort_req),
  .write_buf_idx(wr_bank),.disp_buf_idx(disp_bank),.display_valid(display_valid),
  .display_commit_toggle(commit),.display_commit_ack(commit_ack),.display_asset(asset),.display_ordinal(ordinal),
  .osd_auto_mode(auto_mode),.audio_track_idx(track),.audio_track_toggle(track_toggle),.audio_enabled(audio_enabled),
  .state_code(status),.SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso));
 sd_card_model card(cs,sclk,mosi,miso,1'b1,1'b0,fault,reads,last_arg);
 osd_display_commit #(.ITEM_W(21)) bridge(.clk(vclk),.rst(rst),.src_toggle(commit),.src_bank(disp_bank),
  .src_item({ordinal,asset}),.src_valid(display_valid),.frame_read_req(frame_req),.mem_read_ack(mem_ack),
  .read_req(read_req),.ack_toggle(commit_ack),.bank(vbank),.item(vitem),.valid(vvalid));
 video_timing_data timing(.video_clk(vclk),.rst(rst),.read_req(frame_req),.read_req_ack(mem_ack),.hs(hs),.vs(vs),.de(de));
 video_delay delay_video(.video_clk(vclk),.rst(rst),.read_en(video_read),.read_data(read_data[31:8]),
  .hs(hs),.vs(vs),.de(de),.hs_r(),.vs_r(),.de_r(),.vout_data());
 frame_read_write store(.rst(rst),.mem_clk(mem_clk),.Sdr_init_done(init_done),
  .Sdr_init_ref_vld(refresh_active),.Sdr_busy(sdr_busy),.App_rd_en(app_read),.App_rd_addr(app_raddr),
  .Sdr_rd_en(core_valid),.Sdr_rd_dout(core_data),.read_clk(vclk),.read_req(read_req),.read_req_ack(mem_ack),
  .read_finish(),.read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
  .read_addr_index(vbank),.read_len(21'd307200),.read_en(video_read),.read_data(read_data),
  .App_wr_en(app_write),.App_wr_addr(app_waddr),.App_wr_din(app_data),.App_wr_dm(app_dm),
  .write_clk(clk),.write_req(wr_req),.write_req_ack(ack),.write_finish(write_finish),
  .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
  .write_addr_index(wr_bank),.write_len(21'd307200),.write_en(wr_en),.write_data(wr_data),
  .write_ready(ready),.write_abort(abort_req),.write_abort_done(abort_done));
 sdr_as_ram #(.self_refresh_open(SELF_REFRESH_OPEN)) core(.Sdr_clk(mem_clk),.Sdr_clk_sft(~mem_clk),.Rst(rst),
  .Sdr_init_done(init_done),.Sdr_init_ref_vld(refresh_active),.Sdr_busy(sdr_busy),.App_ref_req(app_ref_req),
  .App_wr_en(app_write),.App_wr_addr(app_waddr),.App_wr_dm(app_dm),.App_wr_din(app_data),
  .App_rd_en(app_read),.App_rd_addr(app_raddr),.Sdr_rd_en(core_valid),.Sdr_rd_dout(core_data),
  .SDRAM_CLK(sdram_clk),.SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(ba),
  .SDR_ADDR(physical_addr),.SDR_DM(physical_dm),.SDR_DQ(dq));
 sdram_pin_model memory(.clk(sdram_clk),.ras_n(ras),.cas_n(cas),.we_n(we),.addr(physical_addr),.ba(ba),
  .dq(dq),.dm(physical_dm),.protocol_errors(protocol_errors));
 task check(input bit ok,input string why);
  if(!ok) begin $display("FAIL %s state=%0d asset=%0d pixels=%0d t=%0t",why,dut.state,asset,pixels,$time);$fatal(1);end
 endtask
 function automatic [23:0] gold(input integer x,y,id);
  reg [7:0] r,g,b;begin b=x+id;g=y*3+id;r=x^y^id;gold={r,g,b};end
 endfunction
 function automatic [23:0] scaled(input integer x,y,id,z);
  begin
   if(z==0) scaled=gold(x,y,id);
   else if(z==1) scaled=gold(160+x/2,120+y/2,id);
   else if(x>=160 && x<480 && y>=120 && y<360) scaled=gold((x-160)*2,(y-120)*2+1,id);
   else scaled=0;
  end
 endfunction
 always @(negedge mem_clk) begin
  if(rst || !init_done) begin ref_cycles=0;app_ref_req=0;end
  else begin ref_cycles=ref_cycles+1;app_ref_req=FORCED_REFRESH && ref_cycles%5000<16;end
 end
 reg previous_finish_drained=0;
 reg previous_abort_done=0,previous_abort_drained=0,abort_guard=0;
 always @(posedge mem_clk) begin
  if(rst) finish_toggle<=0;
  else if(write_finish) begin
   finish_toggle<=!finish_toggle;
   check(previous_finish_drained && !app_write && memory.write_left==0,"write_finish physical tail");
   bank_id[wr_bank]=dut.load_id;bank_zoom[wr_bank]=dut.zoom_loading;
  end
  previous_finish_drained<=store.frame_fifo_write_m0.state==7 && store.frame_fifo_write_m0.controller_drained && !store.frame_fifo_write_m0.abort_sync[2];
  if(core_valid) check(!store.read_buf.full_flag,"video FIFO overflow");
  if(app_write) check(!store.write_buf.empty_flag,"write FIFO underflow");
  if(rst || wr_req) finished_guard=0;
  else if(write_finish) finished_guard=1;
  if(app_write && vvalid) check(app_waddr/307200!=vbank,"App write owns visible bank");
  if(rst || wr_req) abort_guard=0;
  else if(abort_done) abort_guard=1;
  if(abort_done) begin
   if(!previous_abort_done) check(previous_abort_drained,"abort ack without drained controller");
   check(!app_write && memory.write_left==0,"abort ack before physical write tail");
  end
  previous_abort_done<=abort_done;
  previous_abort_drained<=store.frame_fifo_write_m0.controller_drained &&
                          store.frame_fifo_write_m0.state==6 && store.frame_fifo_write_m0.abort_sync[2];
 end
 always @(posedge sdram_clk) begin
  if(!rst) check(protocol_errors==0,"physical SDRAM command protocol");
  if({ras,cas,we}==3'b001) refreshes=refreshes+1;
  if(memory.write_left>0 || {ras,cas,we}==3'b100) begin
   check(!abort_guard,"physical writes after abort ack");
   physical_words=physical_words+1;
   if(^dq===1'bx) physical_bad=physical_bad+1;
   if(finished_guard) physical_post_finish=physical_post_finish+1;
  end
 end
 reg [63:0] previous_fs_control=0,previous_card_control=0;
 always @(posedge clk) begin
  if(!rst) begin
   if(dut.fs.state!==previous_fs_control) check(!$isunknown(dut.fs.state) && $onehot(dut.fs.state),"onehot FAT control");
   if(dut.card.state!==previous_card_control) check(!$isunknown(dut.card.state) && $onehot(dut.card.state),"onehot SD control");
  end
  previous_fs_control<=dut.fs.state;previous_card_control<=dut.card.state;
  last_req<=wr_req;last_abort<=abort_req;
  if(wr_req && !last_req) pixels=0;
  if(abort_req && !last_abort) failures=failures+1;
  if(wr_en) begin
   check(!vvalid || wr_bank!=vbank,"source writing visible bank");
   check(pixels<307200,"source output length");
   check(wr_data[31:8]===scaled(pixels%640,pixels/640,dut.load_id,dut.zoom_loading),"source pixels");
   pixels=pixels+1;
  end
  if(commit!=last_commit) begin
   check(pixels==307200 && dut.wrote && dut.bmp_ok && dut.zsource && dut.zdone,"complete commit gates");
   check(memory.write_left==0 && !app_write,"commit physical drain");
   commits=commits+1;
   $display("E2E COMMIT %0d asset=%0d ordinal=%0d zoom=%0d t=%0t",commits,asset,ordinal,dut.zoom_loading,$time);
  end
  if(track_toggle!=last_track) begin
   track_changes=track_changes+1;
   check(commit_ack==commit,"audio before video/memory ack");
   check(audio_enabled==(asset>=1 && asset<=4),"explicit mute map");
   if(audio_enabled) check(track==asset-1,"explicit track map");
  end
  if(dut.state==6) check(!wr_req && !wr_en,"reuse before commit ack");
  last_commit<=commit;last_track<=track_toggle;
 end
 function automatic [20:0] physical_index(input [20:0] appaddr);
  physical_index={appaddr[20:10],appaddr[3:2],appaddr[9:4],appaddr[1:0]};
 endfunction
 reg [20:0] diag_addr_queue[0:4095];
 integer diag_requests=0,diag_responses=0;
 reg [20:0] diag_response_addr;
 reg [31:0] diag_direct;
 always @(posedge mem_clk) if(!rst) begin
  if(app_read) begin diag_addr_queue[diag_requests%4096]=app_raddr;diag_requests=diag_requests+1;end
  if(core_valid) begin
   diag_response_addr=diag_addr_queue[diag_responses%4096];
   diag_direct=memory.memory[physical_index(diag_response_addr)];
   if(vvalid && diag_response_addr/307200==vbank && core_data!==diag_direct) begin
    $display("CORE_MISMATCH addr=%0d actual=%h direct=%h requests=%0d responses=%0d waddr=%0d wr=%0b readstate=%0d writestate=%0d busy=%0b refresh=%0b t=%0t",diag_response_addr,core_data,diag_direct,diag_requests,diag_responses,app_waddr,app_write,store.frame_fifo_read_m0.state,store.frame_fifo_write_m0.state,sdr_busy,refresh_active,$time);
    $fatal(1,"DIAG core response differs from physical memory");
   end
   diag_responses=diag_responses+1;
  end
 end
 integer vi=0;reg frame_valid=0;reg [1:0] frame_bank=0;integer frame_id=0,frame_zoom=0;
 reg last_frame=0;reg [1:0] prev_bank=0;reg [20:0] prev_item=0;
 always @(posedge vclk) begin
  if(rst) begin vi=0;last_frame=0;frame_valid=0;end
  else begin
   if(frame_req && !last_frame) begin
    if(frame_valid) begin
     check(vi==307200,"video full-frame length");checked_frames[frame_zoom]=checked_frames[frame_zoom]+1;
     last_completed_id=frame_id;last_completed_zoom=frame_zoom;
    end
    vi=0;
    // Bundle is committed on this edge; sample it after the registered bridge.
    #1;frame_valid=vvalid;frame_bank=vbank;frame_id=vitem[13:0];
    if(frame_valid) begin
     frame_zoom=bank_zoom[frame_bank];check(bank_id[frame_bank]==frame_id,"bank metadata at video boundary");
    end
   end
   if(video_read && frame_valid) begin
    check(vbank==frame_bank && vitem[13:0]==frame_id,"bank/item changed within active frame");
    if(store.read_buf.empty_flag) underflows=underflows+1;
    check(!store.read_buf.empty_flag,"video FIFO underflow");
    // Original FIFO uses a registered read port.
    #1;
    if(read_data[31:8]!==scaled(vi%640,479-vi/640,frame_id,frame_zoom)) begin
     $display("MISMATCH vi=%0d x=%0d y=%0d bank=%0d id=%0d zoom=%0d got=%h expected=%h direct=%h",vi,vi%640,vi/640,frame_bank,frame_id,frame_zoom,read_data,scaled(vi%640,479-vi/640,frame_id,frame_zoom),memory.memory[physical_index(frame_bank*307200+vi)]);
     $display("READ status appaddr=%0d state=%0d count=%0d burst=%0d used=%0d core_requests=%0d core_responses=%0d",app_raddr,store.frame_fifo_read_m0.state,store.frame_fifo_read_m0.read_cnt,store.frame_fifo_read_m0.burst_cnt,store.read_buf.rdusedw,diag_requests,diag_responses);
    end
    check(read_data[31:8]===scaled(vi%640,479-vi/640,frame_id,frame_zoom),"physical SDRAM/video pixel");
    vi=vi+1;checked_pixels=checked_pixels+1;
    if(dut.state==5) old_read_pixels=old_read_pixels+1;
   end
   last_frame=frame_req;
  end
 end
 task next_key;begin @(negedge clk);force dut.next_press=1;@(negedge clk);force dut.next_press=0;@(negedge clk);release dut.next_press;end endtask
 task zoom_key;begin @(negedge clk);force dut.zoom_press=1;@(negedge clk);force dut.zoom_press=0;@(negedge clk);release dut.zoom_press;end endtask
 task wait_idle;begin wait(dut.state==2 && display_valid);repeat(10) @(negedge clk);end endtask
 reg [20:0] old_meta;reg [1:0] old_bank;integer old_track_changes=0,mode_key;
 initial begin
  checked_frames[0]=0;checked_frames[1]=0;checked_frames[2]=0;
  bank_id[0]=0;bank_id[1]=0;bank_zoom[0]=0;bank_zoom[1]=0;
  repeat(10) @(negedge clk);rst=0;
  if(TARGET_MODE>=0) begin
   // Three independently runnable full-size cases retain the actual clocks,
   // original SPI byte engine, a real old BMP, a failed prefix and recovery.
   wait(commits==1);wait_idle();wait(checked_frames[0]>0);
   check(asset==1 && ordinal==1 && audio_enabled && track==0,"initial full BMP mapping");
   old_track_changes=track_changes;
   next_key();wait(dut.load_id==2 && pixels>1000 && dut.state==5);
   old_meta=vitem;old_bank=vbank;
   for(mode_key=0;mode_key<TARGET_MODE;mode_key=mode_key+1) zoom_key();
   fault=1;wait(failures==1);fault=0;
   check(vitem==old_meta && vbank==old_bank && track_changes==old_track_changes,"failed prefix retains bank and audio");
   if(TARGET_MODE==0) begin wait_idle();next_key();end
   wait(commits==2);wait_idle();
   check(dut.zoom_loading==TARGET_MODE,"recovered requested scale");
   if(TARGET_MODE!=0) check(asset==1 && ordinal==1 && track_changes==old_track_changes,"same asset scale preserves track");
   else check(asset==3 && ordinal==3 && audio_enabled && track==2,"next image after failed second image");
   wait(last_completed_id==asset && last_completed_zoom==TARGET_MODE);
   check(old_read_pixels>307200 && underflows==0 && protocol_errors==0 && physical_bad==0 && physical_post_finish==0,"end-to-end physical integrity");
   if(FORCED_REFRESH) check(refreshes>100,"refresh stress observed");
   $display("STAGE3_E2E_PASS mode=%0d commits=%0d failures=%0d checked_pixels=%0d old_read_pixels=%0d refresh=%0d",TARGET_MODE,commits,failures,checked_pixels,old_read_pixels,refreshes);
   $finish;
  end
  wait(dut.state==5 && pixels>1000);zoom_key();next_key();
  wait(commits==1);check(asset==1 && ordinal==1,"first item");
  wait(commits==2);check(asset==1 && ordinal==1,"busy same-file zoom");
  wait(dut.load_id==2 && pixels>1000 && dut.state==5);fault=1;old_meta=vitem;old_bank=vbank;
  wait(failures==1);fault=0;wait_idle();
  check(commits==2 && vitem==old_meta && vbank==old_bank,"failed load keeps bank/meta");
  check(audio_enabled && track==0,"failed load keeps audio");
  force dut.cursor=2;next_key();release dut.cursor;wait(commits==3);wait_idle();
  check(asset==4 && ordinal==4 && track==3,"ID4 mapping");
  next_key();wait(commits==4);wait_idle();check(asset==5 && ordinal==5 && !audio_enabled,"ID5 muted");
  zoom_key();wait(commits==5);wait_idle();
  wait(checked_frames[2]>0);
  check(checked_frames[0]>0 && checked_frames[1]>0 && checked_frames[2]>0,"all scales physically read");
  check(old_read_pixels>307200 && underflows==0 && protocol_errors==0 && physical_bad==0 && physical_post_finish==0,"storage integrity counters");
  if(FORCED_REFRESH) check(refreshes>100,"refresh stress observed");
  $display("STAGE3_E2E_PASS commits=%0d failures=%0d checked_pixels=%0d old_read_pixels=%0d frames=%0d/%0d/%0d refresh=%0d",commits,failures,checked_pixels,old_read_pixels,checked_frames[0],checked_frames[1],checked_frames[2],refreshes);
  $finish;
 end
 always #100000000 $display("E2E progress t=%0t state=%0d pixels=%0d commits=%0d checked=%0d",$time,dut.state,pixels,commits,checked_pixels);
 initial begin #(64'd4500000000); $fatal(1,"E2E watchdog state=%0d commits=%0d",dut.state,commits);end
endmodule
