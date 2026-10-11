`timescale 1ns/1ps
// Controller integration with a synthetic BMP reader and SDRAM completion sink.
// The real parser/FIFO/SDRAM/HDMI are NOT modeled by this test.
module tb_board_zoom_control;
reg clk=0;
always #5 clk=~clk;
reg rst=1, key_next=1, key_auto=1, key_zoom=1, finish_toggle=0;
reg write_ready=1, force_stall=0;
wire display_valid, write_req, write_en, auto_mode;
wire [1:0] write_buf, disp_buf, item;
wire [31:0] write_data;
wire [3:0] state_code;
integer errors=0, completed=0, count=0, loads=0, cycles=0;
integer sx, sy, base;
reg [23:0] expected;
reg [1:0] saved_buf;
reg mode;
sd_card_bmp #(.CLK_FREQ_HZ(1000), .AUTO_INTERVAL_MS(1000), .ENABLE_ZOOM(1),
    .FRAME_WIDTH(8), .FRAME_HEIGHT(8)) dut (
    .clk(clk), .rst(rst), .key_next(key_next), .key_auto(key_auto),
    .key_zoom(key_zoom), .write_ready(write_ready), .state_code(state_code),
    .bmp_width(16'd8), .bmp_height(16'd8), .display_valid(display_valid),
    .osd_auto_mode(auto_mode), .osd_item_index(item),
    .write_finish_toggle(finish_toggle), .write_buf_idx(write_buf), .disp_buf_idx(disp_buf),
    .write_req(write_req), .write_req_ack(write_req), .write_en(write_en),
    .write_data(write_data), .SD_nCS(), .SD_DCLK(), .SD_MOSI(), .SD_MISO(1'b1)
);
always @(negedge clk) begin
    cycles=cycles+1;
    write_ready=!force_stall && cycles%7!=0 && cycles%7!=1;
end
always @(posedge clk) begin
    if(rst) begin count=0; finish_toggle<=0; end
    else begin
        if(dut.load_start_pulse) begin
            loads=loads+1; count=0; mode=dut.zoom_loading;
            $display("[INFO] load=%0d mode=%b sector=%0d buffer=%0d",loads,mode,dut.load_sector,write_buf);
            base=dut.load_idx==0 ? 0 : 256;
            if(display_valid && write_buf==disp_buf) begin
                $display("[FAIL] Loading overwrites displayed buffer"); errors=errors+1;
            end
        end
        if(write_en) begin
            sx=mode ? 2+(count%8)/2 : count%8;
            sy=mode ? 2+(count/8)/2 : count/8;
            expected=24'h112200+base+sy*8+sx;
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
input target;
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
    press_zoom; wait_mode(0); $display("[PASS] KEY3 returns to normal");
    press_zoom;
    wait(dut.load_busy);
    press_zoom;
    wait_mode(0);
    if(dut.zoom_requested) begin errors=errors+1; $display("[FAIL] Busy press lost"); end
    $display("[PASS] Second press while loading retained and applied");
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

module bmp_read (
    input clk, rst, scan_start, input [31:0] scan_start_sector, scan_max_sector,
    input [2:0] scan_target_count, output reg scan_done, scan_found_valid,
    output reg [31:0] scan_found_sector, output [2:0] scan_found_total,
    input load_start, input [31:0] load_sector, input sd_init_done,
    output [3:0] state_code, input [15:0] bmp_width, bmp_height,
    output reg write_req, input write_req_ack, output sd_sec_read,
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
        if(load_start) begin step<=1; pixel<=0; gap<=0; base<=load_sector==11 ? 0 : 256; write_req<=1; end
        else if(step==1 && write_req_ack) begin write_req<=0; step<=2; end
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
