// File-list scheduler and complete-frame commit. No display reset on card recovery.
module tf_file_player #(
 parameter integer CLK_FREQ_HZ=100000000,MAX_FILES=32,MAX_CHAIN=2048,
 parameter integer DEBOUNCE_MS=20,AUTO_INTERVAL_MS=3000,
 parameter integer VOLUME_LONG_MS=1200,
 parameter integer IO_TIMEOUT=CLK_FREQ_HZ*3,STALL_TIMEOUT=CLK_FREQ_HZ/2,
 parameter integer SLOT_W=$clog2(MAX_FILES),COUNT_W=$clog2(MAX_FILES+1)
)(input clk,rst,input key_next,key_auto,key_zoom,
 input write_ready,write_req_ack,write_finish_toggle,write_abort_done,
 output wire write_req,write_en,output wire [31:0] write_data,
 output reg write_abort,output reg [1:0] write_buf_idx,disp_buf_idx,
 output reg display_valid,display_commit_toggle,input display_commit_ack,
 output reg [13:0] display_asset,output reg [6:0] display_ordinal,
 output wire osd_auto_mode,output reg [1:0] audio_track_idx,
 output reg audio_track_toggle,audio_enabled,output wire audio_vol_long,
 output wire [3:0] state_code,
 output wire [19:0] init_diagnostic,
 output SD_nCS,SD_DCLK,SD_MOSI,input SD_MISO);
 wire media_ready,init_error,block_addressed;wire [31:0] sectors;
 wire req_valid,req_ready,rsp_valid,rsp_done,rsp_error,cancel;
 wire [31:0] lba,req_tag,rsp_tag,cancel_tag;wire [7:0] rsp_data;
 wire mounted,mount_ready,mount_done,open_ready,index_valid;
 wire [COUNT_W-1:0] file_count;wire [13:0] index_id;
 wire [31:0] index_size;wire fvalid,fready,fdone,ferror;wire [7:0] fdata,fcode;
 reg mount_valid,open_valid;reg [13:0] open_id;reg [31:0] load_size;
 reg [SLOT_W-1:0] cursor,load_slot;
 reg [13:0] load_id;
 reg [13:0] audio_asset;
 reg card_reinit;
 reg bmp_start;wire bvalid,bdone,berror,bbusy,bframe;wire [23:0] bpixel;
 wire zvalid,zsource,zdone,zoverflow,permit;wire [23:0] zpixel;
 reg [1:0] zoom_wanted,zoom_loading,zoom_attempted;
 reg [1:0] pending_next;reg auto_mode,need_mount,initial_attempted,armed,request_seen;
 reg [31:0] auto_count,wait_count;
 reg [2:0] ack_sync,finish_sync,abort_sync,commit_sync;reg wrote,bmp_ok,failed;
 wire next_press,auto_press,zoom_press;
 localparam BOOT=0,MOUNT=1,IDLE=2,SELECT=3,OPEN=4,LOAD=5,COMMIT=6,CLEAN=7,CLEAN_RELEASE=8,LOCKED=9,INDEX_WAIT=10;
 reg [3:0] state;wire loading=state==LOAD;
 reg load_timeout,clean_timeout,commit_timeout;
 // Predict the deadline on the incrementing cycle. Progress and state exit
 // clear the prediction, preserving the original exact timeout budgets.
 always @(posedge clk) begin
  if(rst) begin load_timeout<=0;clean_timeout<=0;commit_timeout<=0;end
  else begin
   load_timeout<=state==LOAD && !(fvalid && fready) && wait_count>=CLK_FREQ_HZ*10-1;
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
 bmp_file_stream #(.WAIT_CYCLES(STALL_TIMEOUT)) bmp(.clk(clk),.rst(rst),.start(bmp_start),.file_size(load_size),
 .data_valid(fvalid),.data_ready(fready),.data(fdata),.file_done(fdone),.file_error(ferror),
 .write_req(write_req),.write_req_ack(ack_sync[2]),.write_ready(source_ready),.source_permit(permit),
 .frame_start(bframe),.pixel_valid(bvalid),.pixel(bpixel),.done(bdone),.error(berror),.busy(bbusy));
 bmp_center_zoom_2x #(.ENABLE_HALF(1)) zoom(.clk(clk),.rst(rst || write_abort),.frame_start(bframe),
 .zoom_enable(zoom_loading==1),.half_enable(zoom_loading==2),.source_permit(permit),
 .in_valid(bvalid && source_ready && loading && !failed),.in_rgb(bpixel),
 .out_valid(zvalid),.out_ready(source_ready && loading && !failed),.out_rgb(zpixel),
 .out_last(),.out_frame_last(),.source_done(zsource),.output_done(zdone),.overflow(zoverflow));
 key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) kn(clk,rst,key_next,next_press);
 key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) ka(clk,rst,key_auto,auto_press);
 // KEY3 short press keeps the zoom cycle; a 1.2 s hold becomes volume step.
 key_short_long #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS),
  .LONG_MS(VOLUME_LONG_MS)) kz(.clk(clk),.rst(rst),.button_in(key_zoom),
  .short_pulse(zoom_press),.long_pulse(audio_vol_long));
 // Explicit four-resource mapping. No ID truncation or modulo mapping.
 function automatic mapped(input [13:0] id);begin mapped=(id==1 || id==2 || id==3 || id==4);end endfunction
 function automatic [1:0] track(input [13:0] id);
 begin case(id) 1:track=0;2:track=1;3:track=2;4:track=3;default:track=0;endcase end endfunction
 always @(posedge clk) begin
  if(rst) begin
   state<=BOOT;mount_valid<=0;open_valid<=0;bmp_start<=0;cursor<=0;load_slot<=0;load_id<=0;open_id<=0;load_size<=0;
   need_mount<=1;initial_attempted<=0;display_valid<=0;display_commit_toggle<=0;
   display_asset<=0;display_ordinal<=0;disp_buf_idx<=0;write_buf_idx<=0;
   audio_track_idx<=0;audio_track_toggle<=0;audio_enabled<=0;audio_asset<=0;card_reinit<=0;
   zoom_wanted<=0;zoom_loading<=0;zoom_attempted<=0;pending_next<=0;auto_mode<=0;auto_count<=0;
   ack_sync<=0;finish_sync<=0;abort_sync<=0;commit_sync<=0;wrote<=0;bmp_ok<=0;failed<=0;
   write_abort<=0;armed<=0;request_seen<=0;wait_count<=0;
  end else begin
   ack_sync<={ack_sync[1:0],write_req_ack};finish_sync<={finish_sync[1:0],write_finish_toggle};
   abort_sync<={abort_sync[1:0],write_abort_done};
   commit_sync<={commit_sync[1:0],display_commit_ack};
   mount_valid<=0;open_valid<=0;bmp_start<=0;
   card_reinit<=next_press && init_error && (state==IDLE || state==BOOT);
   if(!media_ready) need_mount<=1;
   if(next_press && pending_next!=3) pending_next<=pending_next+1;
   if(zoom_press) zoom_wanted<=zoom_wanted==2 ? 0:zoom_wanted+1;
   if(auto_press) auto_mode<=!auto_mode;
   if(state==IDLE && auto_mode && display_valid && file_count>1) auto_count<=auto_count+1;else auto_count<=0;
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
      end else if(pending_next!=0 || (auto_mode && auto_count>=(CLK_FREQ_HZ/1000)*AUTO_INTERVAL_MS)) begin
       load_slot<=(cursor+1>=file_count) ? 0:cursor+1;state<=INDEX_WAIT;
       if(pending_next!=0 && !next_press) pending_next<=pending_next-1;
      end
     end
    end
    INDEX_WAIT: state<=SELECT; // synchronous index RAM: slot and data must settle
    SELECT: if(index_valid) begin
     cursor<=load_slot;load_id<=index_id;open_id<=index_id;load_size<=index_size;
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
      disp_buf_idx<=write_buf_idx;display_asset<=load_id;display_ordinal<=load_slot+1;
      display_valid<=1;display_commit_toggle<=!display_commit_toggle;state<=COMMIT;wait_count<=0;
     end else if(fvalid && fready) wait_count<=0;else wait_count<=wait_count+1;
    end
    COMMIT: if(commit_sync[2]==display_commit_toggle) begin
       if(audio_asset!=display_asset) begin
        audio_track_idx<=track(display_asset);audio_enabled<=mapped(display_asset);
        audio_asset<=display_asset;audio_track_toggle<=!audio_track_toggle;
       end
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
