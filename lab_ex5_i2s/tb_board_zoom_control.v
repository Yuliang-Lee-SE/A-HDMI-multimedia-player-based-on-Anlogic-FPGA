`timescale 1ns/1ps
// Controller integration with a synthetic BMP reader and SDRAM completion sink.
// The real parser/FIFO/SDRAM/HDMI are NOT modeled by this test.
module tb_board_zoom_control;
parameter DISPLAY_COMMIT=0;
reg clk=0;
always #5 clk=~clk;
reg rst=1, key_next=1, key_auto=1, key_zoom=1, finish_toggle=0;
reg write_ready=1, force_stall=0;
wire display_valid, write_req, write_en, auto_mode;
wire [1:0] write_buf, disp_buf, item, audio_idx;
wire audio_toggle;
reg previous_audio=0;
wire [31:0] write_data;
wire [3:0] state_code;
integer errors=0, completed=0, count=0, loads=0, cycles=0;
integer sx, sy, base;
reg [23:0] expected;
reg [1:0] saved_buf;
reg [1:0] mode;
reg vclk=0;always #19 vclk=~vclk;
reg vreq=0;
integer vcycle=0;
wire mem_req,commit_req,commit_ack,vvalid;
wire [1:0] vbank,vitem;
reg mem_ack=0;
reg [3:0] mem_req_sync=0;
reg [1:0] bank0=0,bank1=0,locked_bank=0;
reg [1:0] locked_item=0;
integer commits=0;
reg prior_audio_toggle=0;
always @(posedge clk) begin
 if(rst) prior_audio_toggle=0;
 else begin
  #1;
  if(audio_toggle!=prior_audio_toggle) begin
   if(audio_idx!=item || (DISPLAY_COMMIT && commit_ack!=commit_req)) begin
    errors=errors+1;$display("[FAIL] Audio notification before display commit or wrong ID");
   end
   prior_audio_toggle=audio_toggle;
  end
 end
end
osd_display_commit bridge(.clk(vclk),.rst(rst),.src_toggle(commit_req),
 .src_bank(disp_buf),.src_item(item),.src_valid(display_valid),
 .frame_read_req(vreq),.mem_read_ack(mem_ack),.read_req(mem_req),
 .ack_toggle(commit_ack),.bank(vbank),.item(vitem),.valid(vvalid));
always @(negedge vclk) begin
 if(rst) begin vcycle=0;vreq=0;end
 else begin
  vcycle=vcycle+1;
  if(vcycle%400==0) vreq=1;
  else if(mem_ack) vreq=0;
 end
end
// Memory-domain bundled read address selection mirrors frame_fifo_read:
// bank has two synchronizers, request has three, address locks during ack.
always @(posedge clk) begin
 if(rst) begin mem_req_sync<=0;bank0<=0;bank1<=0;mem_ack<=0;locked_bank<=0;locked_item<=0;end
 else begin
  mem_req_sync<={mem_req_sync[2:0],mem_req};bank0<=vbank;bank1<=bank0;
  mem_ack<=mem_req_sync[3];
  if(mem_req_sync[3]) begin locked_bank<=bank1;locked_item<=vitem;end
 end
end
reg [1:0] prior_vbank=0,prior_vitem=0;
reg prior_vvalid=0;
reg prior_vreq=0;
always @(posedge vclk) begin
 if(rst) begin prior_vbank=0;prior_vitem=0;prior_vvalid=0;prior_vreq=0;end
 else begin
  #1;
  if(DISPLAY_COMMIT && (prior_vbank!=vbank || prior_vitem!=vitem || prior_vvalid!=vvalid)) begin
   commits=commits+1;
   if(!vreq || prior_vreq) begin errors=errors+1;$display("[FAIL] Display changed outside frame read boundary");end
  end
  prior_vbank=vbank;prior_vitem=vitem;prior_vvalid=vvalid;prior_vreq=vreq;
  if(DISPLAY_COMMIT && mem_ack && (locked_bank!=vbank || locked_item!=vitem)) begin
   errors=errors+1;$display("[FAIL] Image bank and caption ID mismatch");
  end
 end
end
sd_card_bmp #(.CLK_FREQ_HZ(1000), .AUTO_INTERVAL_MS(1000), .ENABLE_ZOOM(1),
    .ENABLE_DISPLAY_COMMIT(DISPLAY_COMMIT),
    .FRAME_WIDTH(8), .FRAME_HEIGHT(8)) dut (
    .clk(clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),
    .key_zoom(key_zoom), .write_ready(write_ready), .state_code(state_code),
    .bmp_width(16'd8), .bmp_height(16'd8), .display_valid(display_valid),
    .osd_auto_mode(auto_mode), .osd_item_index(item),
    .display_commit_toggle(commit_req),.display_commit_ack(commit_ack),
    .audio_track_idx(audio_idx),.audio_track_toggle(audio_toggle),
    .write_finish_toggle(finish_toggle), .write_buf_idx(write_buf), .disp_buf_idx(disp_buf),
    .write_req(write_req), .write_req_ack(write_req), .write_en(write_en),
    .write_data(write_data), .SD_nCS(), .SD_DCLK(), .SD_MOSI(), .SD_MISO(1'b1)
);
always @(negedge clk) begin
    cycles=cycles+1;
    write_ready=!force_stall && cycles%7!=0 && cycles%7!=1;
end
always @(posedge clk) begin
    if(rst) begin count=0; finish_toggle<=0; previous_audio=0; end
    else begin
        if(audio_toggle!=previous_audio) begin
            if(audio_idx!==item || !display_valid || dut.load_busy) begin
                errors=errors+1; $display("[FAIL] Audio notification outside committed image");
            end
        end
        previous_audio=audio_toggle;
        if(dut.load_start_pulse) begin
            if(DISPLAY_COMMIT && (dut.commit_wait || (vvalid && write_buf==vbank))) begin
                errors=errors+1;$display("[FAIL] Reload before display ack or overwriting active bank");
            end
            loads=loads+1; count=0; mode=dut.zoom_loading;
            $display("[INFO] load=%0d mode=%b sector=%0d buffer=%0d",loads,mode,dut.load_sector,write_buf);
            base=dut.load_idx==0 ? 0 : 256;
            if(display_valid && write_buf==disp_buf) begin
                $display("[FAIL] Loading overwrites displayed buffer"); errors=errors+1;
            end
        end
        if(write_en) begin
            if(mode==2 && (!dut.zoom_write_armed || write_req)) begin
                errors=errors+1; $display("[FAIL] Padding sent before writer request completed");
            end
            sx=mode==1 ? 2+(count%8)/2 : count%8;
            sy=mode==1 ? 2+(count/8)/2 : count/8;
            expected=24'h112200+base+sy*8+sx;
            if(mode==2) begin
                sx=2*((count%8)-2); sy=2*((count/8)-2)+1;
                expected=(count%8>=2 && count%8<6 && count/8>=2 && count/8<6) ?
                         24'h112200+base+sy*8+sx : 0;
            end
            if(!write_ready || count>=64 || write_data !== {expected,8'b0}) begin
                $display("[FAIL] Sink pixel %0d: %h expected %h",count,write_data,{expected,8'b0});
                errors=errors+1;
            end
            count=count+1;
            if(count==64) begin
                finish_toggle<=!finish_toggle;
                if(mode && !dut.zoom_source_done)
                    $display("[PASS] Write completion arrives before source file end");
            end
        end
    end
end
task press_zoom;
begin
    @(negedge clk); key_zoom=0;
    repeat(25) @(negedge clk); key_zoom=1;
    repeat(25) @(negedge clk);
end
endtask
task wait_mode;
input [1:0] target;
begin
    wait(!dut.load_busy && !dut.commit_wait && display_valid && dut.zoom_displayed==target);
    @(negedge clk);
    if(count!=64 || dut.load_error) begin errors=errors+1; $display("[FAIL] Incomplete committed frame"); end
end
endtask
integer saved_loads;
initial begin
    repeat(4) @(negedge clk); rst=0;
    wait_mode(0); $display("[PASS] Initial normal frame committed");
    saved_loads=loads;
    // Bounce shorter than the configured 20 clocks must not switch mode.
    key_zoom=0; repeat(5) @(negedge clk); key_zoom=1;
    repeat(25) @(negedge clk);
    if(loads!=saved_loads) begin errors=errors+1; $display("[FAIL] Bounce triggered reload"); end
    @(negedge clk); key_zoom=0;
    repeat(120) @(negedge clk);
    if(!dut.zoom_requested || loads!=saved_loads+1) begin errors=errors+1; $display("[FAIL] Long hold toggled repeatedly"); end
    key_zoom=1; repeat(25) @(negedge clk);
    wait_mode(1); $display("[PASS] KEY3 debounce/hold and center 2x reload");
    press_zoom; wait_mode(2); $display("[PASS] Half canvas");
    press_zoom; wait_mode(0); $display("[PASS] KEY3 returns to normal");
    press_zoom;
    wait(dut.load_busy);
    press_zoom;
    wait_mode(2);
    if(dut.zoom_requested!=2) begin errors=errors+1; $display("[FAIL] Busy press lost"); end
    $display("[PASS] Second press while loading retained and applied");
    press_zoom; wait_mode(0);
    @(negedge clk); key_next=0;
    repeat(25) @(negedge clk); key_next=1;
    wait(item==1 && !dut.load_busy && !dut.commit_wait);
    $display("[PASS] Original next-picture key preserved");
    @(negedge clk); key_auto=0;
    repeat(25) @(negedge clk); key_auto=1;
    wait(auto_mode); wait(item==0 && !dut.load_busy && !dut.commit_wait);
    @(negedge clk); key_auto=0;
    repeat(25) @(negedge clk); key_auto=1;
    wait(!auto_mode);
    $display("[PASS] Original auto-play key preserved");
    // Three accepted presses while a 2x load is active return the target to 2x.
    saved_loads=loads;
    press_zoom; wait(dut.load_busy);
    press_zoom; press_zoom; press_zoom;
    if(dut.zoom_loading!=1 || dut.zoom_requested!=1) begin
        errors=errors+1; $display("[FAIL] Busy mode was not latched or three-press cycle lost");
    end
    wait_mode(1); repeat(40) @(negedge clk);
    if(loads!=saved_loads+1) begin errors=errors+1; $display("[FAIL] Redundant reload after full busy cycle"); end
    $display("[PASS] Three busy presses preserve latched frame and latest target");
    press_zoom; wait_mode(2);
    press_zoom; wait_mode(0);
    saved_buf=disp_buf;
    force_stall=1; press_zoom;
    wait(dut.load_error);
    repeat(700) @(negedge clk);
    if(disp_buf!=saved_buf || !display_valid || state_code!=4'hf || (DISPLAY_COMMIT && (vbank!=saved_buf || vitem!=item))) begin
        errors=errors+1; $display("[FAIL] Damaged frame committed");
    end else $display("[PASS] Overflow keeps old frame and reports F (reset required)");
    rst=1; force_stall=0;
    repeat(4) @(negedge clk); rst=0;
    wait_mode(0); $display("[PASS] Board reset restores normal initial load");
    completed=1;
    if(errors==0) $display("[TEST PASS] Board zoom controller integration is correct.");
    else $display("[TEST FAIL] Controller errors=%0d",errors);
    $finish;
end
initial begin
    #5000000; errors=errors+1;
    $display("[TEST FAIL] Controller timeout: busy=%b error=%b requested=%b loading=%b displayed=%b pixels=%0d source=%b output=%b readydone=%b memdone=%b overflow=%b",dut.load_busy,dut.load_error,dut.zoom_requested,dut.zoom_loading,dut.zoom_displayed,count,dut.zoom_source_done,dut.zoom_output_done,dut.source_done_seen,dut.write_done_seen,dut.zoom_overflow);
    $finish;
end
endmodule

module bmp_read #(parameter USE_PIXEL_START_PERMIT=0) (
    input clk, rst, scan_start, input [31:0] scan_start_sector, scan_max_sector,
    input [2:0] scan_target_count, output reg scan_done, scan_found_valid,
    output reg [31:0] scan_found_sector, output [2:0] scan_found_total,
    input load_start, input [31:0] load_sector, input sd_init_done,
    output [3:0] state_code, input [15:0] bmp_width, bmp_height,
    output reg write_req, input write_req_ack, pixel_start_permit, output sd_sec_read,
    output [31:0] sd_sec_read_addr, input [7:0] sd_sec_read_data,
    input sd_sec_read_data_valid, sd_sec_read_end,
    output reg bmp_data_wr_en, output reg [23:0] bmp_data, output ready
);
integer scan_step, step, pixel, gap, base;
assign ready=step==0;
assign state_code=step;
assign scan_found_total=2;
assign sd_sec_read=0;
assign sd_sec_read_addr=0;
always @(posedge clk) begin
    if(rst) begin
        scan_step<=0; scan_done<=0; scan_found_valid<=0; scan_found_sector<=0;
        step<=0; pixel<=0; gap<=0; base<=0; write_req<=0;
        bmp_data_wr_en<=0; bmp_data<=0;
    end else begin
        scan_found_valid<=0; bmp_data_wr_en<=0;
        if(scan_start) begin scan_step<=1; scan_done<=0; end
        else if(scan_step==1) begin scan_found_valid<=1; scan_found_sector<=11; scan_step<=2; end
        else if(scan_step==2) begin scan_found_valid<=1; scan_found_sector<=13; scan_step<=3; end
        else if(scan_step==3) begin scan_done<=1; scan_step<=0; end
        if(load_start) begin step<=1; pixel<=0; gap<=0; base<=load_sector==11 ? 0 : 256; write_req<=0; gap<=50; step<=5; end
        else if(step==5) begin
            if(gap==0) begin write_req<=1; step<=1; end else gap<=gap-1;
        end
        else if(step==1 && write_req_ack) begin write_req<=0; step<=4; end
        else if(step==4 && (!USE_PIXEL_START_PERMIT || pixel_start_permit)) step<=2;
        else if(step==2) begin
            if(gap==0) begin
                bmp_data_wr_en<=1; bmp_data<=24'h112200+base+pixel; pixel<=pixel+1; gap<=7;
                if(pixel==63) step<=3;
            end else gap<=gap-1;
        end else if(step==3) step<=0;
    end
end
endmodule

module sd_card_top #(
    parameter SPI_LOW_SPEED_DIV=248,
    parameter SPI_HIGH_SPEED_DIV=0
) (
    input clk, rst, output SD_nCS, SD_DCLK, SD_MOSI, input SD_MISO,
    output sd_init_done, input sd_sec_read, input [31:0] sd_sec_read_addr,
    output [7:0] sd_sec_read_data, output sd_sec_read_data_valid, sd_sec_read_end,
    input sd_sec_write, input [31:0] sd_sec_write_addr,
    input [7:0] sd_sec_write_data, output sd_sec_write_data_req, sd_sec_write_end
);
assign sd_init_done=1;
assign {SD_nCS, SD_DCLK, SD_MOSI}=3'b100;
assign sd_sec_read_data=0;
assign {sd_sec_read_data_valid,sd_sec_read_end,sd_sec_write_data_req,sd_sec_write_end}=0;
endmodule
