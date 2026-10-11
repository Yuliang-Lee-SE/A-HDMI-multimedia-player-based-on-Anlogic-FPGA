`timescale 1ns/1ps
// Controller integration with a synthetic BMP reader and SDRAM completion sink.
// The real parser/FIFO/SDRAM/HDMI are NOT modeled by this test.
module tb_half_bmp_control;
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
reg short_source=0;
sd_card_bmp #(.CLK_FREQ_HZ(1000), .AUTO_INTERVAL_MS(1000), .ENABLE_ZOOM(1),
    .SCAN_MAX_SECTOR(13), .SCAN_TARGET_COUNT(2), .FRAME_WIDTH(8), .FRAME_HEIGHT(8)) dut (
    .clk(clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),
    .key_zoom(key_zoom), .write_ready(write_ready), .state_code(state_code),
    .bmp_width(16'd8), .bmp_height(16'd8), .display_valid(display_valid),
    .osd_auto_mode(auto_mode), .osd_item_index(item),
    .audio_track_idx(audio_idx), .audio_track_toggle(audio_toggle),
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
    wait(!dut.load_busy && display_valid && dut.zoom_displayed==target);
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
    wait(item==1 && !dut.load_busy);
    $display("[PASS] Original next-picture key preserved");
    @(negedge clk); key_auto=0;
    repeat(25) @(negedge clk); key_auto=1;
    wait(auto_mode); wait(item==0 && !dut.load_busy);
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
    press_zoom; wait_mode(1);
    saved_buf=disp_buf;
    force_stall=1; press_zoom; wait(dut.load_busy);
    repeat(500) @(negedge clk);
    if(disp_buf!=saved_buf || dut.load_error || dut.zoom_source_permit || dut.zoom_loading!=2) begin
        errors=errors+1; $display("[FAIL] Half padding stall violated old-frame/source protection");
    end
    force_stall=0; wait_mode(2);
    $display("[PASS] Half padding stall retains old image; release completes");
    press_zoom; wait_mode(0);
    saved_buf=disp_buf;
    force_stall=1; press_zoom;
    wait(dut.load_error);
    repeat(700) @(negedge clk);
    if(disp_buf!=saved_buf || !display_valid || state_code!=4'hf) begin
        errors=errors+1; $display("[FAIL] Damaged frame committed");
    end else $display("[PASS] Overflow keeps old frame and reports F (reset required)");
    rst=1; force_stall=0;
    repeat(4) @(negedge clk); rst=0;
    wait_mode(0); $display("[PASS] Board reset restores normal initial load");
    press_zoom; wait_mode(1);
    saved_buf=disp_buf; short_source=1;
    press_zoom; wait(dut.load_error);
    repeat(200) @(negedge clk);
    if(disp_buf!=saved_buf || !display_valid || state_code!=4'hf) begin
        errors=errors+1; $display("[FAIL] Half short source committed");
    end else $display("[PASS] Half short source rejected; displayed frame retained");
    completed=1;
    if(errors==0) $display("[TEST PASS] Board zoom controller integration is correct.");
    else $display("[TEST FAIL] Controller errors=%0d",errors);
    $finish;
end
initial begin
    #1000000; errors=errors+1;
    $display("[TEST FAIL] Controller timeout: busy=%b error=%b requested=%b loading=%b displayed=%b pixels=%0d source=%b output=%b readydone=%b memdone=%b overflow=%b",dut.load_busy,dut.load_error,dut.zoom_requested,dut.zoom_loading,dut.zoom_displayed,count,dut.zoom_source_done,dut.zoom_output_done,dut.source_done_seen,dut.write_done_seen,dut.zoom_overflow);
    $finish;
end
endmodule

module sd_card_top #(parameter SPI_LOW_SPEED_DIV=248, SPI_HIGH_SPEED_DIV=0)(
 input clk,rst, output SD_nCS,SD_DCLK,SD_MOSI, input SD_MISO,
 output sd_init_done, input sd_sec_read, input [31:0] sd_sec_read_addr,
 output reg [7:0] sd_sec_read_data, output reg sd_sec_read_data_valid,sd_sec_read_end,
 input sd_sec_write, input [31:0] sd_sec_write_addr, input [7:0] sd_sec_write_data,
 output sd_sec_write_data_req,sd_sec_write_end
);
assign sd_init_done=1;
assign {SD_nCS,SD_DCLK,SD_MOSI}=3'b100;
assign {sd_sec_write_data_req,sd_sec_write_end}=0;
reg previous=0,busy=0;
integer pos=0,gap=0,sector=0;
reg [23:0] pixel;
function [7:0] byte_at;
 input integer sec,n;
 reg [23:0] p;
 begin
 byte_at=0;
 if(sec==11 || sec==13) begin
  case(n)
   0:byte_at=8'h42; 1:byte_at=8'h4d; 2:byte_at=tb_half_bmp_control.short_source ? 243 : 246;
   10:byte_at=54; 18:byte_at=8; 22:byte_at=8; 28:byte_at=24;
   default:begin
    if(n>=54 && n<246) begin
     p=24'h112200+(sec==13 ? 256:0)+(n-54)/3;
     case((n-54)%3)
      0:byte_at=p[7:0]; 1:byte_at=p[15:8]; 2:byte_at=p[23:16];
     endcase
    end
   end
  endcase
 end
 end
endfunction
always @(posedge clk) begin
 if(rst) begin previous<=0;busy<=0;pos<=0;gap<=0;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;sd_sec_read_data<=0;end
 else begin
  previous<=sd_sec_read;sd_sec_read_data_valid<=0;sd_sec_read_end<=0;
  if(!busy && sd_sec_read && !previous) begin busy<=1;pos<=0;gap<=0;sector<=sd_sec_read_addr;end
  else if(busy) begin
   if(gap!=0) gap<=gap-1;
   else if(pos<512) begin
    sd_sec_read_data<=byte_at(sector,pos);sd_sec_read_data_valid<=1;pos<=pos+1;gap<=1;
   end else begin busy<=0;sd_sec_read_end<=1;end
  end
 end
end
endmodule
