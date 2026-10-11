
module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ       = 100_000_000,
    parameter integer ENABLE_ZOOM      = 0,
    parameter integer ENABLE_DISPLAY_COMMIT = 0,
    parameter integer FRAME_WIDTH      = 640,
    parameter integer FRAME_HEIGHT     = 480,
    parameter [31:0]  SCAN_START_SECTOR = 32'd0,
    parameter [31:0]  SCAN_MAX_SECTOR   = 32'd131071,
    parameter [2:0]   SCAN_TARGET_COUNT = 3'd4,
    parameter integer AUTO_INTERVAL_MS  = 3000,   // 自动轮播间隔（原来硬编码 1s）
    parameter integer DEBOUNCE_MS       = 20,     // 按键消抖时间
    // SD 卡 SPI 分频：默认值 = 官方例程，只有仿真会调小
    parameter integer SPI_LOW_SPEED_DIV  = 248,
    parameter integer SPI_HIGH_SPEED_DIV = 0
)(
    input                       clk,
    input                       rst,
    input                       key_next,
    input                       key_auto,
    input                       key_zoom,
    input                       write_ready,
    output [3:0]                state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg                  display_valid,
    output                      osd_auto_mode,
    output [1:0]                osd_item_index,
    output reg                  display_commit_toggle,
    input                       display_commit_ack,

    // 音画联动：把"当前显示第几张图"送给音频播放器（audio_mclk 域自己同步）
    output reg [1:0]            audio_track_idx,
    output reg                  audio_track_toggle,

    input                       write_finish_toggle,
    output reg [1:0]            write_buf_idx,
    output reg [1:0]            disp_buf_idx,

    output                      write_req,
    input                       write_req_ack,
    output                      write_en,
    output [31:0]               write_data,
    output                      SD_nCS,
    output                      SD_DCLK,
    output                      SD_MOSI,
    input                       SD_MISO
);

wire key_next_press;
wire key_auto_press;
wire key_zoom_press;
wire [3:0] bmp_state_code;
wire zoom_source_done, zoom_output_done, zoom_overflow;
reg [1:0] zoom_requested, zoom_loading, zoom_displayed;
wire zoom_source_permit;
reg zoom_write_request_seen, zoom_write_armed;
wire zoom_write_allowed = zoom_loading != 2 || zoom_write_armed;
reg write_done_seen, source_started_seen, load_error;
reg commit_wait;
reg [2:0] commit_ack_sync;

wire             sd_sec_read;
wire [31:0]      sd_sec_read_addr;
wire [7:0]       sd_sec_read_data;
wire             sd_sec_read_data_valid;
wire             sd_sec_read_end;
wire             bmp_data_wr_en;
wire [23:0]      bmp_data;
wire             sd_init_done;
wire             bmp_ready;
wire             scan_done;
wire             scan_found_valid;
wire [31:0]      scan_found_sector;
wire [2:0]       scan_found_total;

reg              scan_start_pulse;
reg              load_start_pulse;
reg [31:0]       load_sector;
reg              scan_kicked;
reg              first_image_committed;
reg              auto_play_en;
reg [31:0]       auto_cnt;
reg [2:0]        img_found_count;
reg [1:0]        img_idx;              // 当前真正显示中的图片编号
reg [1:0]        load_idx;             // 当前正在写入的图片编号
reg [1:0]        pending_buf_idx;      // 当前正在写入的目标缓冲区
reg [31:0]       img_sector0;
reg [31:0]       img_sector1;
reg [31:0]       img_sector2;
reg [31:0]       img_sector3;
reg [1:0]        next_req_pending;      // 最多记 3 次连按，加载期间不再丢按键
reg              load_busy;
reg              source_done_seen;
wire load_complete = load_busy && !load_error && !zoom_overflow &&
    source_done_seen && zoom_source_done && zoom_output_done && write_done_seen;

// Source reading, processed output and SDRAM write completion are distinct.

// 同步 mem_clk 域的 write_finish_toggle
reg [2:0]        wrfin_tgl_sync;
wire             write_finish_pulse;

// 同步sd与卡侧握手
reg [1:0]        wr_ack_sync;

wire auto_tick;
wire [1:0] next_from_current;

// 轮播间隔 = AUTO_INTERVAL_MS 毫秒（100MHz 下 3000ms -> 300,000,000 拍，32bit 足够）
localparam [31:0] AUTO_TICKS = (CLK_FREQ_HZ / 1000) * AUTO_INTERVAL_MS;

// 状态码：缩放链路出错时显示 f（角色 B）
assign state_code = load_error ? 4'hf : bmp_state_code;

// 缩放开关（角色 B）：ENABLE_ZOOM=1 时像素流先过 bmp_center_zoom_2x 再写帧缓存，
// =0 时旁路（等价原直通路径）。两个分支里的 write_en/write_data 互斥，不会重复驱动。
generate if (ENABLE_ZOOM) begin : g_zoom
    wire pixel_valid;
    wire [23:0] pixel_rgb;
    bmp_center_zoom_2x #(.WIDTH(FRAME_WIDTH), .HEIGHT(FRAME_HEIGHT), .ENABLE_HALF(1)) zoom (
        .clk(clk), .rst(rst || !sd_init_done), .frame_start(load_start_pulse),
        .zoom_enable(zoom_loading == 2'd1),
        .half_enable(zoom_loading == 2'd2), .source_permit(zoom_source_permit), .in_valid(bmp_data_wr_en), .in_rgb(bmp_data),
        .out_valid(pixel_valid), .out_ready(write_ready && !load_error && zoom_write_allowed),
        .out_rgb(pixel_rgb), .out_last(), .out_frame_last(),
        .source_done(zoom_source_done), .output_done(zoom_output_done),
        .overflow(zoom_overflow)
    );
    assign write_en = pixel_valid && write_ready && !load_error && zoom_write_allowed;
    assign write_data = {pixel_rgb, 8'b0};
end else begin : g_original
    assign write_en = bmp_data_wr_en;
    assign write_data = {bmp_data, 8'b0};
    assign zoom_source_done = 1'b1;
    assign zoom_output_done = 1'b1;
    assign zoom_overflow = 1'b0;
    assign zoom_source_permit = 1'b1;
end endgenerate
assign osd_auto_mode  = auto_play_en;
assign osd_item_index = img_idx;
assign auto_tick  = (auto_cnt == (AUTO_TICKS - 1));
assign next_from_current = next_index_limited(img_idx, img_found_count);
assign write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (DEBOUNCE_MS)
) u_key_next (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_next),
    .press_pulse(key_next_press)
);

key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (DEBOUNCE_MS)
) u_key_auto (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_auto),
    .press_pulse(key_auto_press)
);

// 角色 B：KEY3（B1）缩放切换键，消抖参数跟随 DEBOUNCE_MS，保持三处一致
key_press_debounce #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (DEBOUNCE_MS)
) u_key_zoom (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key_zoom),
    .press_pulse(key_zoom_press)
);

// Half canvas emits padding before source pixels. Wait for this load's
// request to be seen and withdrawn before accepting any output into the FIFO.
// write_ready then supplies the existing reset-release / full protection.
always @(posedge clk or posedge rst) begin
    if(rst) begin zoom_write_request_seen<=0; zoom_write_armed<=0; end
    else if(!sd_init_done || load_start_pulse) begin
        zoom_write_request_seen<=0; zoom_write_armed<=0;
    end else if(load_busy) begin
        if(write_req) zoom_write_request_seen<=1;
        if(zoom_write_request_seen && !write_req) zoom_write_armed<=1;
    end
end

function [1:0] next_index_limited;
    input [1:0] cur;
    input [2:0] count;
    begin
        case (count)
            3'd0: next_index_limited = 2'd0;
            3'd1: next_index_limited = 2'd0;
            3'd2: next_index_limited = (cur == 2'd1) ? 2'd0 : (cur + 2'd1);
            3'd3: next_index_limited = (cur == 2'd2) ? 2'd0 : (cur + 2'd1);
            default: next_index_limited = (cur == 2'd3) ? 2'd0 : (cur + 2'd1);
        endcase
    end
endfunction

function [31:0] sector_lut;
    input [1:0] idx;
    begin
        case (idx)
            2'd0: sector_lut = img_sector0;
            2'd1: sector_lut = img_sector1;
            2'd2: sector_lut = img_sector2;
            2'd3: sector_lut = img_sector3;
            default: sector_lut = img_sector0;
        endcase
    end
endfunction

function [1:0] next_buf_lut;
    input [1:0] cur_disp_buf;
    input       valid_now;
    begin
        if (!valid_now)
            next_buf_lut = 2'd0;                 // 首图固定写 buffer0
        else if (cur_disp_buf == 2'd0)
            next_buf_lut = 2'd1;
        else
            next_buf_lut = 2'd0;
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync        <= 3'b000;
        scan_start_pulse      <= 1'b0;
        load_start_pulse      <= 1'b0;
        load_sector           <= 32'd0;
        scan_kicked           <= 1'b0;
        first_image_committed <= 1'b0;
        auto_play_en          <= 1'b0;
        auto_cnt              <= 32'd0;
        img_found_count       <= 3'd0;
        img_idx               <= 2'd0;
        load_idx              <= 2'd0;
        pending_buf_idx       <= 2'd0;
        write_buf_idx         <= 2'd0;
        disp_buf_idx          <= 2'd0;
        img_sector0           <= 32'd0;
        img_sector1           <= 32'd0;
        img_sector2           <= 32'd0;
        img_sector3           <= 32'd0;
        next_req_pending      <= 2'd0;
        load_busy             <= 1'b0;
        source_done_seen      <= 1'b0;
        display_valid         <= 1'b0;
        wr_ack_sync           <= 2'b00;
        audio_track_idx       <= 2'd0;
        audio_track_toggle    <= 1'b0;
        zoom_requested        <= 1'b0;
        zoom_loading          <= 1'b0;
        zoom_displayed        <= 1'b0;
        write_done_seen       <= 1'b0;
        source_started_seen   <= 1'b0;
        load_error            <= 1'b0;
        display_commit_toggle <= 1'b0;
        commit_wait           <= 1'b0;
        commit_ack_sync       <= 3'b000;
    end else begin
        commit_ack_sync <= {commit_ack_sync[1:0],display_commit_ack};
        if (ENABLE_DISPLAY_COMMIT && commit_wait &&
            commit_ack_sync[2] == display_commit_toggle) begin
            commit_wait <= 1'b0;
            audio_track_idx <= img_idx;
            audio_track_toggle <= ~audio_track_toggle;
        end
        wrfin_tgl_sync   <= {wrfin_tgl_sync[1:0], write_finish_toggle};
        wr_ack_sync      <= {wr_ack_sync[0], write_req_ack};
        scan_start_pulse <= 1'b0;
        load_start_pulse <= 1'b0;

        if (!sd_init_done) begin
            scan_kicked           <= 1'b0;
            first_image_committed <= 1'b0;
            auto_play_en          <= 1'b0;
            auto_cnt              <= 32'd0;
            img_found_count       <= 3'd0;
            img_idx               <= 2'd0;
            load_idx              <= 2'd0;
            pending_buf_idx       <= 2'd0;
            write_buf_idx         <= 2'd0;
            disp_buf_idx          <= 2'd0;
            img_sector0           <= 32'd0;
            img_sector1           <= 32'd0;
            img_sector2           <= 32'd0;
            img_sector3           <= 32'd0;
            next_req_pending      <= 2'd0;
            load_busy             <= 1'b0;
            source_done_seen      <= 1'b0;
            display_valid         <= 1'b0;
            zoom_requested        <= 1'b0;
            zoom_loading          <= 1'b0;
            zoom_displayed        <= 1'b0;
            write_done_seen       <= 1'b0;
            source_started_seen   <= 1'b0;
            load_error            <= 1'b0;
        end else begin
            // 扫描阶段缓存前 4 张图的起始 sector
            if (scan_found_valid) begin
                case (img_found_count)
                    3'd0: img_sector0 <= scan_found_sector;
                    3'd1: img_sector1 <= scan_found_sector;
                    3'd2: img_sector2 <= scan_found_sector;
                    3'd3: img_sector3 <= scan_found_sector;
                    default: ;
                endcase

                if (img_found_count < 3'd4)
                    img_found_count <= img_found_count + 3'd1;
            end

            // 记住 bmp_read 已经把源图送完 FIFO，但还不能切显示，得等整帧写完
            if (load_start_pulse) begin
                source_started_seen <= 1'b0;
                source_done_seen <= 1'b0;
                write_done_seen <= 1'b0;
            end else if (load_busy) begin
                if (!bmp_ready) source_started_seen <= 1'b1;
                if (write_finish_pulse) write_done_seen <= 1'b1;
            end
            if (load_busy && !load_start_pulse && source_started_seen && bmp_ready)
                source_done_seen <= 1'b1;

            if (load_busy && (zoom_overflow ||
                (source_done_seen && !zoom_source_done)))
                load_error <= 1'b1;

            // Commit only after all three completion conditions have been latched.
            if (load_complete) begin
                if (ENABLE_DISPLAY_COMMIT) begin
                    display_commit_toggle <= ~display_commit_toggle;
                    commit_wait <= 1'b1;
                end
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
                disp_buf_idx          <= pending_buf_idx;
                img_idx               <= load_idx;
                display_valid         <= 1'b1;
                first_image_committed <= 1'b1;
                // 音画联动：图像提交的那一拍同步换音频段
                if (!ENABLE_DISPLAY_COMMIT) begin
                    audio_track_idx       <= load_idx;
                    audio_track_toggle    <= ~audio_track_toggle;
                end
                zoom_displayed        <= zoom_loading;
            end

            // 上电后自动发起一次“扫描前 4 张 BMP”
            if (!scan_kicked && bmp_ready) begin
                scan_start_pulse      <= 1'b1;
                scan_kicked           <= 1'b1;
                first_image_committed <= 1'b0;
                auto_play_en          <= 1'b0;
                auto_cnt              <= 32'd0;
                img_found_count       <= 3'd0;
                img_idx               <= 2'd0;
                load_idx              <= 2'd0;
                pending_buf_idx       <= 2'd0;
                write_buf_idx         <= 2'd0;
                disp_buf_idx          <= 2'd0;
                next_req_pending      <= 2'd0;
                display_valid         <= 1'b0;
                load_busy             <= 1'b0;
                source_done_seen      <= 1'b0;
            end else begin
                // 按键计数：最多记 3 次“下一张”，加载期间连按不再丢
                if (key_next_press && scan_done && (img_found_count > 3'd0)) begin
                    if (next_req_pending != 2'd3)
                        next_req_pending <= next_req_pending + 2'd1;
                end

                if (ENABLE_ZOOM && key_zoom_press && scan_done && !load_error)
                    zoom_requested <= (zoom_requested == 2'd2) ? 2'd0 : zoom_requested + 2'd1;

                // 自动播放开/关
                if (key_auto_press && scan_done && (img_found_count > 3'd1)) begin
                    auto_play_en <= ~auto_play_en;
                    auto_cnt     <= 32'd0;
                end

                // 自动播放间隔计数（AUTO_INTERVAL_MS，默认 3s）：只有当前没有写图任务时才计时
                if (scan_done && auto_play_en && display_valid && !load_busy && !commit_wait && first_image_committed && (img_found_count > 3'd1)) begin
                    if (auto_tick)
                        auto_cnt <= 32'd0;
                    else
                        auto_cnt <= auto_cnt + 32'd1;
                end else begin
                    auto_cnt <= 32'd0;
                end

                // 首图自动加载到 buffer0
                if (scan_done && !load_error && !first_image_committed && bmp_ready && !load_busy && !commit_wait && (img_found_count != 3'd0)) begin
                    load_idx         <= 2'd0;
                    load_sector      <= img_sector0;
                    pending_buf_idx  <= 2'd0;
                    write_buf_idx    <= 2'd0;
                    load_start_pulse <= 1'b1;
                    zoom_loading     <= zoom_requested;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= 2'd0;
                    auto_cnt         <= 32'd0;
                end
                // Reload the current file into the other buffer when zoom changes.
                // A second press while busy is handled after the current load commits.
                else if (ENABLE_ZOOM && scan_done && !load_error && bmp_ready &&
                         display_valid && !load_busy && !commit_wait && zoom_requested != zoom_displayed) begin
                    load_idx         <= img_idx;
                    load_sector      <= sector_lut(img_idx);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    zoom_loading     <= zoom_requested;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
                // 缩放重载优先于手动切图（角色 B）；下面这条是手动下一张（角色 C，
                // 2bit 连按计数：加载期间连按最多记 3 次，用一次减一）。
                else if (scan_done && !load_error && bmp_ready && display_valid && !load_busy && !commit_wait && (next_req_pending != 2'd0) && (img_found_count != 3'd0)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    zoom_loading     <= zoom_requested;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    next_req_pending <= next_req_pending - 2'd1;
                    auto_cnt         <= 32'd0;
                end
                // 自动播放下一张：同样写到“非当前显示”的另一块 buffer
                else if (scan_done && !load_error && bmp_ready && display_valid && !load_busy && !commit_wait && auto_play_en && auto_tick && (img_found_count > 3'd1)) begin
                    load_idx         <= next_from_current;
                    load_sector      <= sector_lut(next_from_current);
                    pending_buf_idx  <= next_buf_lut(disp_buf_idx, display_valid);
                    write_buf_idx    <= next_buf_lut(disp_buf_idx, display_valid);
                    load_start_pulse <= 1'b1;
                    zoom_loading     <= zoom_requested;
                    load_busy        <= 1'b1;
                    source_done_seen <= 1'b0;
                    auto_cnt         <= 32'd0;
                end
            end
        end
    end
end

bmp_read #(.USE_PIXEL_START_PERMIT(1)) bmp_read_m0(
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (bmp_ready),

    .scan_start             (scan_start_pulse),
    .scan_start_sector      (SCAN_START_SECTOR),
    .scan_max_sector        (SCAN_MAX_SECTOR),
    .scan_target_count      (SCAN_TARGET_COUNT),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),

    .load_start             (load_start_pulse),
    .load_sector            (load_sector),

    .sd_init_done           (sd_init_done),
    .state_code             (bmp_state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (wr_ack_sync[1]),
    .pixel_start_permit     (zoom_source_permit),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
);

sd_card_top #(
    .SPI_LOW_SPEED_DIV  (SPI_LOW_SPEED_DIV),
    .SPI_HIGH_SPEED_DIV (SPI_HIGH_SPEED_DIV)
) sd_card_top_m0(
    .clk                    (clk),
    .rst                    (rst),
    .SD_nCS                 (SD_nCS),
    .SD_DCLK                (SD_DCLK),
    .SD_MOSI                (SD_MOSI),
    .SD_MISO                (SD_MISO),
    .sd_init_done           (sd_init_done),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .sd_sec_write           (1'b0),
    .sd_sec_write_addr      (32'd0),
    .sd_sec_write_data      (),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
);

endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
