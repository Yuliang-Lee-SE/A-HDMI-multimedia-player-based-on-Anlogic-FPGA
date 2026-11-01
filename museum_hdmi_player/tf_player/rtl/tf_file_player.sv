// File-list scheduler and complete-frame commit. No display reset on card recovery.
module tf_file_player #(
 parameter integer CLK_FREQ_HZ=100000000,MAX_FILES=64,MAX_CHAIN=2048,
 parameter integer DEBOUNCE_MS=20,AUTO_INTERVAL_MS=3000,
 parameter integer VOLUME_LONG_MS=1200,
 parameter integer IO_TIMEOUT=CLK_FREQ_HZ*3,STALL_TIMEOUT=CLK_FREQ_HZ/2,
 parameter integer SLOT_W=$clog2(MAX_FILES),COUNT_W=$clog2(MAX_FILES+1)
)(input clk,rst,
  input key_next, // One-clock active-high pulse from the board key controller.
  input key_auto,key_zoom,
 input [4:0] rotation_period_s,input rotation_period_toggle,
 input write_ready,write_req_ack,write_finish_toggle,write_abort_done,
 output wire write_req,write_en,output wire [31:0] write_data,
 output reg write_abort,output reg [1:0] write_buf_idx,disp_buf_idx,
 output reg display_valid,display_commit_toggle,input display_commit_ack,
 output reg [13:0] display_asset,output reg [6:0] display_ordinal,
 output wire osd_auto_mode,output reg [4:0] audio_track_idx,
 output reg audio_track_toggle,audio_enabled,output reg [15:0] audio_track_len,
 output reg audio_track_ready,output wire audio_loading,output reg audio_load_error,
 output wire audio_ram_we,output wire [14:0] audio_ram_addr,
 output wire [15:0] audio_ram_data,output wire audio_vol_long,
 output wire [3:0] state_code,
 output wire [19:0] init_diagnostic,
 output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO);
 wire media_ready,init_error,block_addressed;wire [31:0] sectors;
 wire req_valid,req_ready,rsp_valid,rsp_done,rsp_error,cancel;
 wire [31:0] lba,req_tag,rsp_tag,cancel_tag;wire [7:0] rsp_data;
 wire mounted,mount_ready,mount_done,open_ready,index_valid;
 wire [COUNT_W-1:0] file_count;wire [13:0] index_id;
 wire [31:0] index_size;wire fvalid,fdone,ferror;wire [7:0] fdata,fcode;
 wire bmp_fready,wav_fready,fready;
 reg mount_valid,open_valid;reg [13:0] open_id;reg [31:0] load_size;
 reg [SLOT_W-1:0] cursor,load_slot;
 reg [4:0] load_group;
 reg [13:0] load_id,audio_open_id;
 reg index_ready,reuse_group;
 reg [13:0] audio_asset;
 reg audio_start;
 wire [15:0] audio_loaded_len;
 wire wav_done,wav_error,wav_busy;
 reg card_reinit;
 reg bmp_start;wire bvalid,bdone,berror,bbusy,bframe;wire [23:0] bpixel;
 wire zvalid,zsource,zdone,zoverflow,permit;wire [23:0] zpixel;
 reg [1:0] zoom_wanted,zoom_loading,zoom_attempted;
 reg [1:0] pending_next;reg auto_mode,need_mount,initial_attempted,armed,request_seen;
 reg [31:0] wait_count;
 reg [4:0] rotation_period_sd;
 reg [2:0] rotation_toggle_sync;
 reg [8:0] auto_100ms;
 reg [23:0] auto_prescale;
 reg [2:0] ack_sync,finish_sync,abort_sync,commit_sync;reg wrote,bmp_ok,failed;
 wire next_press,auto_press,zoom_press;
 assign next_press=key_next;
  localparam BOOT=0,MOUNT=1,IDLE=2,SELECT=3,OPEN=4,LOAD=5,COMMIT=6,CLEAN=7,CLEAN_RELEASE=8,LOCKED=9,INDEX_WAIT=10,AUDIO_OPEN=11,AUDIO_LOAD=12,SELECT_CHECK=13;
 reg [4:0] state;wire loading=state==LOAD;
 assign fready=((state==AUDIO_OPEN)||(state==AUDIO_LOAD)) ? wav_fready : bmp_fready;
 assign audio_loading=(state==AUDIO_OPEN)||(state==AUDIO_LOAD);
 reg load_timeout,clean_timeout,commit_timeout;
 localparam integer PRESCALE_100MS=CLK_FREQ_HZ/10;
 wire [8:0] auto_limit=({4'd0,rotation_period_sd}<<3)+
                       ({4'd0,rotation_period_sd}<<1)-9'd1;
 wire auto_tick=auto_100ms>=auto_limit;
 // Predict the deadline on the incrementing cycle. Progress and state exit
 // clear the prediction, preserving the original exact timeout budgets.
 always @(posedge clk) begin
  if(rst) begin load_timeout<=0;clean_timeout<=0;commit_timeout<=0;end
  else begin
   load_timeout<=(state==LOAD || state==AUDIO_LOAD) &&
                 !(fvalid && fready) && wait_count>=CLK_FREQ_HZ*10-1;
   clean_timeout<=state==CLEAN && wait_count>=CLK_FREQ_HZ*4-1;
   commit_timeout<=state==COMMIT && wait_count>=CLK_FREQ_HZ*2-1;
  end
 end
 wire source_ready=write_ready && armed && !write_abort;
 assign write_en=loading && zvalid && source_ready && !zoverflow && !failed;
 assign write_data={zpixel,8'b0};assign osd_auto_mode=auto_mode;
 assign state_code=(failed || init_error) ? 4'hf:state;
 sd_spi_reader #(.CLK_HZ(CLK_FREQ_HZ)) card(.clk(clk),.rst(rst),.reinit(card_reinit),
 .SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),
 .media_ready(media_ready),.init_error(init_error),.init_diagnostic(init_diagnostic),.block_addressed(block_addressed),.media_sectors(sectors),
 .req_valid(req_valid),.req_ready(req_ready),.req_lba(lba),.req_tag(req_tag),
 .cancel_valid(cancel),.cancel_tag(cancel_tag),.rsp_tag(rsp_tag),.rsp_valid(rsp_valid),
 .rsp_data(rsp_data),.rsp_done(rsp_done),.rsp_error(rsp_error));
 fat32_ro #(.MAX_FILES(MAX_FILES),.MAX_CHAIN(MAX_CHAIN),.IO_TIMEOUT(IO_TIMEOUT),.STALL_TIMEOUT(STALL_TIMEOUT)) fs(
 .clk(clk),.rst(rst),.mount_valid(mount_valid),.mount_ready(mount_ready),.media_sectors(sectors),
 .mounted(mounted),.mount_done(mount_done),.file_count(file_count),.index_slot(load_slot),
 .index_valid(index_valid),.index_id(index_id),.index_size(index_size),
 .open_valid(open_valid),.open_ready(open_ready),.open_id(open_id),.data_valid(fvalid),
 .data_ready(fready),.data(fdata),.file_done(fdone),.error_valid(ferror),.error_code(fcode),
 .req_valid(req_valid),.req_ready(req_ready),.req_lba(lba),.req_tag(req_tag),
 .rsp_tag(rsp_tag),.rsp_valid(rsp_valid),.rsp_data(rsp_data),.rsp_done(rsp_done),.rsp_error(rsp_error),
 .cancel_valid(cancel),.cancel_tag(cancel_tag));
 wav_pcm_loader #(.RAM_DEPTH(24576)) wav(
  .clk(clk),.rst(rst),.start(audio_start),.data_valid(fvalid),.data_ready(wav_fready),
  .data(fdata),.file_done(fdone),.file_error(ferror),
  .ram_we(audio_ram_we),.ram_addr(audio_ram_addr),.ram_data(audio_ram_data),
  .done(wav_done),.error(wav_error),.sample_count(audio_loaded_len),.busy(wav_busy));
 bmp_file_stream #(.WAIT_CYCLES(STALL_TIMEOUT)) bmp(.clk(clk),.rst(rst),.start(bmp_start),.file_size(load_size),
 .data_valid(fvalid),.data_ready(bmp_fready),.data(fdata),.file_done(fdone),.file_error(ferror),
 .write_req(write_req),.write_req_ack(ack_sync[2]),.write_ready(source_ready),.source_permit(permit),
 .frame_start(bframe),.pixel_valid(bvalid),.pixel(bpixel),.done(bdone),.error(berror),.busy(bbusy));
 bmp_center_zoom_2x #(.ENABLE_HALF(1)) zoom(.clk(clk),.rst(rst || write_abort),.frame_start(bframe),
 .zoom_enable(zoom_loading==1),.half_enable(zoom_loading==2),.source_permit(permit),
 .in_valid(bvalid && source_ready && loading && !failed),.in_rgb(bpixel),
 .out_valid(zvalid),.out_ready(source_ready && loading && !failed),.out_rgb(zpixel),
 .out_last(),.out_frame_last(),.source_done(zsource),.output_done(zdone),.overflow(zoverflow));
 board_key_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) ka(clk,rst,key_auto,auto_press);
 // KEY3 short press keeps the zoom cycle; a 1.2 s hold becomes volume step.
 key_short_long #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS),
  .LONG_MS(VOLUME_LONG_MS)) kz(.clk(clk),.rst(rst),.button_in(key_zoom),
  .short_pulse(zoom_press),.long_pulse(audio_vol_long));
 always @(posedge clk) begin
  if(rst) begin
   state<=BOOT;mount_valid<=0;open_valid<=0;bmp_start<=0;cursor<=0;load_slot<=0;load_id<=0;open_id<=0;load_size<=0;
   load_group<=0;audio_open_id<=0;index_ready<=0;reuse_group<=0;
   need_mount<=1;initial_attempted<=0;display_valid<=0;display_commit_toggle<=0;
   display_asset<=0;display_ordinal<=0;disp_buf_idx<=0;write_buf_idx<=0;
   audio_track_idx<=0;audio_track_toggle<=0;audio_enabled<=0;audio_asset<=0;card_reinit<=0;
   audio_start<=0;audio_load_error<=0;
   audio_track_len<=0;audio_track_ready<=0;
   zoom_wanted<=0;zoom_loading<=0;zoom_attempted<=0;pending_next<=0;auto_mode<=0;
   rotation_period_sd<=5'd3;rotation_toggle_sync<=3'b000;auto_100ms<=9'd0;auto_prescale<=24'd0;
   ack_sync<=0;finish_sync<=0;abort_sync<=0;commit_sync<=0;wrote<=0;bmp_ok<=0;failed<=0;
   write_abort<=0;armed<=0;request_seen<=0;wait_count<=0;
  end else begin
   ack_sync<={ack_sync[1:0],write_req_ack};finish_sync<={finish_sync[1:0],write_finish_toggle};
   abort_sync<={abort_sync[1:0],write_abort_done};
   commit_sync<={commit_sync[1:0],display_commit_ack};
   rotation_toggle_sync<={rotation_toggle_sync[1:0],rotation_period_toggle};
   index_ready<=(state==INDEX_WAIT || state==SELECT) && index_valid;
   if(rotation_toggle_sync[2]!=rotation_toggle_sync[1]) begin
    rotation_period_sd<=rotation_period_s;
    auto_100ms<=9'd0;
    auto_prescale<=24'd0;
   end
   mount_valid<=0;open_valid<=0;bmp_start<=0;audio_start<=0;
   card_reinit<=next_press && init_error && (state==IDLE || state==BOOT);
   if(!media_ready) need_mount<=1;
   if(next_press && pending_next!=3) pending_next<=pending_next+1;
   if(zoom_press) zoom_wanted<=zoom_wanted==2 ? 0:zoom_wanted+1;
   if(auto_press) auto_mode<=!auto_mode;
   if(state==IDLE && auto_mode && display_valid && file_count>1) begin
    if(auto_prescale==PRESCALE_100MS-1) begin
     auto_prescale<=24'd0;
     if(auto_tick) auto_100ms<=9'd0;else auto_100ms<=auto_100ms+9'd1;
    end else auto_prescale<=auto_prescale+24'd1;
   end else begin
    auto_prescale<=24'd0;auto_100ms<=9'd0;
   end
   if(loading) begin
    if(write_req) request_seen<=1;
    if(request_seen && !write_req) armed<=1;
    if(finish_sync[2]!=finish_sync[1]) wrote<=1;
    if(bdone) bmp_ok<=1;
   end
   case(state)
    BOOT: if(media_ready && mount_ready) begin mount_valid<=1;need_mount<=0;state<=MOUNT;end
    MOUNT: if(mount_done) begin state<=IDLE;end
       else if(ferror) begin failed<=1;state<=IDLE;initial_attempted<=1;end
    IDLE: begin
     wait_count<=0;
     if(need_mount && media_ready && mount_ready && !bbusy) begin mount_valid<=1;need_mount<=0;state<=MOUNT;end
     else if(mounted && media_ready && file_count!=0 && !bbusy && open_ready) begin
      if(!initial_attempted) begin load_slot<=0;state<=INDEX_WAIT;initial_attempted<=1;end
      else if(display_valid && zoom_wanted!=zoom_attempted) begin
       load_slot<=display_ordinal-1;state<=INDEX_WAIT;
      end else if(pending_next!=0 || (auto_mode && auto_tick)) begin
       load_slot<=(cursor+1>=file_count) ? 0:cursor+1;state<=INDEX_WAIT;
       if(pending_next!=0 && !next_press) pending_next<=pending_next-1;
      end
     end
    end
    INDEX_WAIT: begin
     load_group<=load_slot/6'd3;
     state<=SELECT;
    end
    SELECT: state<=SELECT_CHECK;
    SELECT_CHECK: if(index_ready) begin
     cursor<=load_slot;load_id<=index_id;open_id<=index_id;load_size<=index_size;
     audio_open_id<=14'd201+load_group;
     reuse_group<=display_valid &&
      ((display_asset==index_id && display_ordinal==load_slot+1) ||
       (audio_track_ready && audio_asset==load_group));
     zoom_loading<=zoom_wanted;zoom_attempted<=zoom_wanted;
     write_buf_idx<=display_valid ? (disp_buf_idx==0 ? 1:0):0;
     failed<=0;wrote<=0;bmp_ok<=0;request_seen<=0;armed<=0;state<=OPEN;
    end else begin failed<=1;state<=IDLE;end
    OPEN: if(open_ready) begin open_valid<=1;bmp_start<=1;state<=LOAD;wait_count<=0;end
    LOAD: begin
     // File completion is included in bdone; a correct prefix cannot commit.
     if(berror || ferror || zoverflow || load_timeout) begin
      failed<=1;write_abort<=1;state<=CLEAN;wait_count<=0;
     end else if(bmp_ok && zsource && zdone && wrote) begin
      if(reuse_group) begin
       // Keep the same BGM playing while advancing through a three-image group.
       disp_buf_idx<=write_buf_idx;display_asset<=load_id;display_ordinal<=load_slot+1;
       display_valid<=1;display_commit_toggle<=!display_commit_toggle;
       state<=COMMIT;wait_count<=0;
      end else begin
       open_id<=audio_open_id;state<=AUDIO_OPEN;wait_count<=0;
      end
     end else if(fvalid && fready) wait_count<=0;else wait_count<=wait_count+1;
    end
    AUDIO_OPEN: begin
     if(ferror) begin
      // A missing or malformed WAV never blocks the matching image.
      disp_buf_idx<=write_buf_idx;display_asset<=load_id;display_ordinal<=load_slot+1;
      display_valid<=1;audio_track_idx<=load_group;audio_track_len<=0;
      audio_track_ready<=0;audio_enabled<=0;audio_load_error<=1;audio_asset<=0;
      display_commit_toggle<=!display_commit_toggle;state<=COMMIT;wait_count<=0;
     end else if(open_ready) begin
      open_valid<=1;audio_start<=1;state<=AUDIO_LOAD;wait_count<=0;
     end
    end
    AUDIO_LOAD: begin
     if(wav_done) begin
      disp_buf_idx<=write_buf_idx;display_asset<=load_id;display_ordinal<=load_slot+1;
      display_valid<=1;audio_track_idx<=load_group;audio_track_len<=wav_error ? 16'd0:audio_loaded_len;
      audio_track_ready<=!wav_error && audio_loaded_len!=0;
      audio_enabled<=!wav_error && audio_loaded_len!=0;
      audio_load_error<=wav_error || audio_loaded_len==0;
      audio_asset<=wav_error ? 14'd0:load_group;
      if(!wav_error && audio_loaded_len!=0) audio_track_toggle<=!audio_track_toggle;
      display_commit_toggle<=!display_commit_toggle;state<=COMMIT;wait_count<=0;
     end else if(load_timeout) begin
      disp_buf_idx<=write_buf_idx;display_asset<=load_id;display_ordinal<=load_slot+1;
      display_valid<=1;audio_track_idx<=load_group;audio_track_len<=0;
      audio_track_ready<=0;audio_enabled<=0;audio_load_error<=1;audio_asset<=0;
      display_commit_toggle<=!display_commit_toggle;state<=COMMIT;wait_count<=0;
     end else if(fvalid && fready) wait_count<=0;else wait_count<=wait_count+1;
    end
    COMMIT: if(commit_sync[2]==display_commit_toggle) begin
       state<=IDLE;
      end else if(commit_timeout) begin failed<=1;state<=LOCKED;end else wait_count<=wait_count+1;
    CLEAN: if(abort_sync[2] && mount_ready && !bbusy) begin write_abort<=0;state<=CLEAN_RELEASE;end
      else if(clean_timeout) begin failed<=1;state<=LOCKED;end else wait_count<=wait_count+1;
    CLEAN_RELEASE: if(!abort_sync[2] && write_ready) state<=IDLE;
    LOCKED: ; // Without a video ack bank ownership is unknown; never reuse it.
    default:state<=LOCKED;
   endcase
  end
 end
endmodule
