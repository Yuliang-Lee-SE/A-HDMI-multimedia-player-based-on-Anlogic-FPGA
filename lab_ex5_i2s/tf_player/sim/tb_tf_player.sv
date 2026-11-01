`timescale 1ns/1ps
module tb_tf_player;
 parameter SMOKE_ONLY=0;
 reg clk=0;always #5 clk=~clk;reg vclk=0;always #20 vclk=~vclk;
 reg rst=1;wire cs,sclk,mosi,miso,wr_req,wr_en,abort_req;
 wire [31:0] wr_data;wire [1:0] wr_bank,disp_bank,track;
 wire display_valid,commit,auto_mode,track_toggle,audio_enabled;wire [13:0] asset;
 wire [6:0] ordinal;wire [3:0] status;reg ack=0,abort_done=0,finish=0;
 wire commit_ack;wire [1:0] vbank;wire [20:0] vitem;wire vvalid,read_req;
 reg frame_req=0,mem_ack=0;integer vcount=0,reads;
 reg [3:0] fault=0;wire [31:0] last_arg;integer pixels=0,cycle=0,finish_delay=0,commits=0;
 reg last_req=0,last_commit=0,last_track=0;reg [23:0] banks[0:614399];
 reg [31:0] prefix_checksum=0;integer failures=0;
    tf_file_player #(.DEBOUNCE_MS(1)) dut(.clk(clk),.rst(rst),.key_next(1'b0),.key_auto(1'b1),.key_zoom(1'b1),
 .rotation_period_s(5'd3),.rotation_period_toggle(1'b0),
 .write_ready(!abort_req),.write_req_ack(ack),.write_finish_toggle(finish),.write_abort_done(abort_done),
 .write_req(wr_req),.write_en(wr_en),.write_data(wr_data),.write_abort(abort_req),
 .write_buf_idx(wr_bank),.disp_buf_idx(disp_bank),.display_valid(display_valid),
 .display_commit_toggle(commit),.display_commit_ack(commit_ack),.display_asset(asset),.display_ordinal(ordinal),
 .osd_auto_mode(auto_mode),.audio_track_idx(track),.audio_track_toggle(track_toggle),.audio_enabled(audio_enabled),
 .state_code(status),.SD_nCS(cs),.SD_DCLK(sclk),.SD_MOSI(mosi),.SD_MISO(miso));
 sd_card_model card(cs,sclk,mosi,miso,1'b1,1'b0,fault,reads,last_arg);
 osd_display_commit #(.ITEM_W(21)) bridge(.clk(vclk),.rst(rst),.src_toggle(commit),.src_bank(disp_bank),
 .src_item({ordinal,asset}),.src_valid(display_valid),.frame_read_req(frame_req),.mem_read_ack(mem_ack),
 .read_req(read_req),.ack_toggle(commit_ack),.bank(vbank),.item(vitem),.valid(vvalid));
 task check(input bit ok,input string why);begin if(!ok) begin
  $display("FAIL %s state=%0d asset=%0d load=%0d pixels=%0d",why,dut.state,asset,dut.load_id,pixels);$fatal(1);end end endtask
 function automatic [23:0] gold(input integer x,input integer y,input integer id);
 reg [7:0] r,g,b;begin b=x+id;g=y*3+id;r=x^y^id;gold={r,g,b};end endfunction
 integer x,y;reg [23:0] expected;
 always @(posedge vclk) if(rst) begin vcount<=0;frame_req<=0;mem_ack<=0;end else begin
  vcount<=vcount+1;frame_req<=vcount%10000==0;mem_ack<=read_req;
 end
 always @(posedge clk) begin
  cycle<=cycle+1;if(cycle>450000000) $fatal(1,"watchdog state=%0d card=%0d fs=%0d bmp=%0d",dut.state,dut.card.state,dut.fs.state,dut.bmp.state);
  ack<=wr_req;abort_done<=abort_req;last_req<=wr_req;
  if(wr_req && !last_req) begin pixels=0;finish_delay=0;end
  if(abort_req && !abort_done) begin failures=failures+1;finish_delay=0;end
  if(wr_en) begin
   check(!vvalid || wr_bank!=vbank,"writing visible bank");check(pixels<307200,"output length");
   x=pixels%640;y=pixels/640;expected=0;
   if(dut.zoom_loading==0) expected=gold(x,y,dut.load_id);
   else if(dut.zoom_loading==1) expected=gold(160+x/2,120+y/2,dut.load_id);
   else if(x>=160 && x<480 && y>=120 && y<360) expected=gold((x-160)*2,(y-120)*2+1,dut.load_id);
   check(wr_data[31:8]===expected,"SPI player pixels");banks[wr_bank*307200+pixels]=wr_data[31:8];pixels=pixels+1;
   if(pixels==307200) finish_delay=20;
  end
  if(finish_delay>0) begin finish_delay=finish_delay-1;if(finish_delay==0) finish<=!finish;end
  if(commit!=last_commit) begin
   check(pixels==307200,"commit pixel count");
   check(dut.wrote && dut.bmp_ok && dut.zsource && dut.zdone,"all completion gates");
   commits=commits+1;$display("PLAYER COMMIT %0d asset=%0d ordinal=%0d zoom=%0d",commits,asset,ordinal,dut.zoom_loading);
  end
  if(track_toggle!=last_track) begin
   check(commit_ack==commit,"audio before video ack");
   check(audio_enabled==(asset>=1 && asset<=4),"explicit mute map");
   if(audio_enabled) check(track==asset-1,"explicit track map");
  end
  last_commit<=commit;last_track<=track_toggle;
 end
 task next_key;begin @(negedge clk);force dut.next_press=1;@(negedge clk);force dut.next_press=0;@(negedge clk);release dut.next_press;end endtask
 task zoom_key;begin @(negedge clk);force dut.zoom_press=1;@(negedge clk);force dut.zoom_press=0;@(negedge clk);release dut.zoom_press;end endtask
 task wait_idle;begin wait(dut.state==2 && display_valid);repeat(10) @(negedge clk);end endtask
 integer j;reg [31:0] checksum;reg [20:0] old_meta;reg [1:0] old_bank;
 initial begin
  repeat(10) @(negedge clk);rst=0;
  if(SMOKE_ONLY) begin
   wait(commits==1);wait_idle();check(asset==1 && ordinal==1 && audio_enabled && track==0,"final source smoke");
   $display("TF_PLAYER_SMOKE_PASS commits=%0d pixels=%0d",commits,pixels);$finish;
  end
  wait(dut.state==5 && pixels>1000);zoom_key();next_key();
  wait(commits==1);check(asset==1 && ordinal==1,"first list item");
  wait(commits==2);check(asset==1 && ordinal==1,"busy zoom reopens same file");
  wait(dut.load_id==2 && pixels>1000 && dut.state==5);fault=1;
  old_meta=vitem;old_bank=vbank;checksum=0;
  for(j=0;j<307200;j=j+1) checksum=checksum+banks[old_bank*307200+j];
  wait(failures==1);fault=0;wait_idle();
  check(commits==2 && vitem==old_meta && vbank==old_bank,"failure holds image metadata");
  check(audio_enabled && track==0,"failure holds audio");prefix_checksum=0;
  for(j=0;j<307200;j=j+1) prefix_checksum=prefix_checksum+banks[old_bank*307200+j];
  check(checksum==prefix_checksum,"old canvas retained");
  force dut.cursor=2;next_key();release dut.cursor;wait(commits==3);wait_idle();
  check(asset==4 && ordinal==4 && audio_enabled && track==3,"fourth mapping");
  next_key();wait(commits==4);wait_idle();check(asset==5 && ordinal==5 && !audio_enabled,"four to five mute");
  zoom_key();wait(commits==5);wait_idle();check(asset==5 && ordinal==5 && dut.zoom_loading==2,"half reload");
  $display("TF_PLAYER_PASS commits=%0d failures=%0d",commits,failures);$finish;
 end
endmodule
