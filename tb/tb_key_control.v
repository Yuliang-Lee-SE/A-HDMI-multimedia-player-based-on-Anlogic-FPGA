//======================================================================
// S7: 按键 / 切图 / 自动轮播 / 音画联动（角色 C）
//   DUT: sd_card_bmp（含 key_press_debounce + 切图轮播状态机）
//        假 SD 卡 fake_sd_card_multi + 假的"帧写完成"模型
//
// 验证点：
//   1) 上电后能扫到 2 张图并提交首图（display_valid）
//   2) audio_track_idx 与 osd_item_index 始终一致（换段随换图）
//   3) 自动轮播间隔 ≈ AUTO_INTERVAL_MS
//   4) 加载期间连按 3 次"下一张"，3 次都不会丢（不再只记 1 次）
//
// 仿真加速说明（真机参数不受影响）：
//   - SPI_LOW_SPEED_DIV 调到 0（真机 248），否则一个扇区就要 20ms
//   - DEBOUNCE_MS 调到 1ms（真机 20ms），否则按一次键要等 20ms
//   - AUTO_INTERVAL_MS 调到 20ms（真机 3000ms）
//   这三处只是把时间轴等比缩小，验证的是同一套逻辑与计数公式。
//
// BMP：沿用 S1 的最小合法头（file_len=60、640×480、24bit、pixel_offset=54）
//======================================================================
`timescale 1ns/1ps
module tb_key_control;

  localparam integer CLK_HZ    = 100_000_000;
  localparam integer AUTO_MS   = 20;          // 真机 3000ms
  localparam integer DB_MS     = 1;           // 真机 20ms
  localparam integer IDLE_LIM  = 100_000;     // 帧写完成模型的空闲判据：1ms

  reg clk = 1'b0;
  always #5 clk = ~clk;                       // 100MHz

  reg rst  = 1'b1;
  reg key1 = 1'b1;                            // 按下 = 0
  reg key2 = 1'b1;

  wire [3:0]  state_code;
  wire        display_valid;
  wire        osd_auto_mode;
  wire [1:0]  osd_item_index;
  wire [1:0]  audio_track_idx;
  wire        audio_track_toggle;
  wire        write_req, write_en;
  wire [31:0] write_data;
  wire [1:0]  write_buf_idx, disp_buf_idx;
  wire        SD_nCS, SD_DCLK, SD_MOSI, SD_MISO;

  reg         write_req_ack      = 1'b0;
  reg         write_finish_toggle = 1'b0;

  sd_card_bmp #(
    .CLK_FREQ_HZ        (CLK_HZ),
    .SCAN_START_SECTOR  (32'd0),
    .SCAN_MAX_SECTOR    (32'd20),
    .SCAN_TARGET_COUNT  (3'd2),
    .AUTO_INTERVAL_MS   (AUTO_MS),
    .DEBOUNCE_MS        (DB_MS),
    .SPI_LOW_SPEED_DIV  (0),
    .SPI_HIGH_SPEED_DIV (0)
  ) dut (
    .clk                (clk),
    .rst                (rst),
    .key_next           (key1),
    .key_auto           (key2),
    .state_code         (state_code),
    .bmp_width          (16'd640),
    .bmp_height         (16'd480),
    .display_valid      (display_valid),
    .osd_auto_mode      (osd_auto_mode),
    .osd_item_index     (osd_item_index),
    .audio_track_idx    (audio_track_idx),
    .audio_track_toggle (audio_track_toggle),
    .write_finish_toggle(write_finish_toggle),
    .write_buf_idx      (write_buf_idx),
    .disp_buf_idx       (disp_buf_idx),
    .write_req          (write_req),
    .write_req_ack      (write_req_ack),
    .write_en           (write_en),
    .write_data         (write_data),
    .SD_nCS             (SD_nCS),
    .SD_DCLK            (SD_DCLK),
    .SD_MOSI            (SD_MOSI),
    .SD_MISO            (SD_MISO)
  );

  fake_sd_card_multi #(.CARDSEC(64)) u_card (
    .nCS  (SD_nCS),
    .DCLK (SD_DCLK),
    .MOSI (SD_MOSI),
    .MISO (SD_MISO)
  );

  //------------------------------------------------------------------
  // 假的"帧缓存写口"：1 拍应答；像素流停止 1ms 后回一个 write_finish_toggle
  // （不做像素计数，这样不用关心 BMP 到底有多少像素）
  //------------------------------------------------------------------
  reg [31:0] px_cnt  = 32'd0;
  reg [31:0] idle_cnt = 32'd0;
  reg        fin_done = 1'b0;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      write_req_ack       <= 1'b0;
      write_finish_toggle <= 1'b0;
      px_cnt              <= 32'd0;
      idle_cnt            <= 32'd0;
      fin_done            <= 1'b0;
    end else begin
      write_req_ack <= write_req;                 // B 类握手：1 拍应答

      if (write_en) begin
        px_cnt   <= px_cnt + 32'd1;
        idle_cnt <= 32'd0;
        fin_done <= 1'b0;
      end else if ((px_cnt != 32'd0) && (idle_cnt < IDLE_LIM)) begin
        idle_cnt <= idle_cnt + 32'd1;
      end else if ((px_cnt != 32'd0) && !fin_done) begin
        fin_done            <= 1'b1;
        write_finish_toggle <= ~write_finish_toggle;
      end
    end
  end

  //------------------------------------------------------------------
  // 观测：提交次数、提交时刻、音画索引一致性
  //------------------------------------------------------------------
  integer  n_commit = 0;
  integer  n_mismatch = 0;
  reg      tgl_d = 1'b0;
  time     t_commit [0:63];

  always @(posedge clk) begin
    if (audio_track_toggle !== tgl_d) begin
      tgl_d = audio_track_toggle;
      if (n_commit < 64) t_commit[n_commit] = $time;
      n_commit = n_commit + 1;
    end
    if (display_valid && (audio_track_idx !== osd_item_index))
      n_mismatch = n_mismatch + 1;
  end

  //------------------------------------------------------------------
  // 假 SD 卡内容：扇区 2 和扇区 4 各放一张最小合法 BMP
  //------------------------------------------------------------------
  task put_bmp;
    input integer sec;
    input [7:0]  px0, px1, px2, px3, px4, px5;
    integer i;
    begin
      for (i = 0; i < 64; i = i + 1) u_card.mem[sec*512 + i] = 8'h00;
      u_card.mem[sec*512 +  0] = "B";
      u_card.mem[sec*512 +  1] = "M";
      u_card.mem[sec*512 +  2] = 8'd60;          // file_len = 60
      u_card.mem[sec*512 + 10] = 8'd54;          // pixel_offset = 54
      u_card.mem[sec*512 + 18] = 8'h80;          // width  = 640
      u_card.mem[sec*512 + 19] = 8'h02;
      u_card.mem[sec*512 + 22] = 8'hE0;          // height = 480
      u_card.mem[sec*512 + 23] = 8'h01;
      u_card.mem[sec*512 + 28] = 8'd24;          // bit_count = 24
      u_card.mem[sec*512 + 54] = px0;
      u_card.mem[sec*512 + 55] = px1;
      u_card.mem[sec*512 + 56] = px2;
      u_card.mem[sec*512 + 57] = px3;
      u_card.mem[sec*512 + 58] = px4;
      u_card.mem[sec*512 + 59] = px5;
    end
  endtask

  initial begin
    #1;                                          // 等模型自己填完垃圾值
    put_bmp(2, 8'h11, 8'h22, 8'h33, 8'h44, 8'h55, 8'h66);   // 图 1
    put_bmp(4, 8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF);   // 图 2
  end

  //------------------------------------------------------------------
  // 按键任务：按下 ms 毫秒后松开，再空 ms 毫秒
  //------------------------------------------------------------------
  task press_key1;
    input integer ms;
    begin
      key1 = 1'b0; repeat (ms * 100000) @(posedge clk);
      key1 = 1'b1; repeat (ms * 100000) @(posedge clk);
    end
  endtask

  task press_key2;
    input integer ms;
    begin
      key2 = 1'b0; repeat (ms * 100000) @(posedge clk);
      key2 = 1'b1; repeat (ms * 100000) @(posedge clk);
    end
  endtask

  integer errors = 0;
  integer guard;
  integer n_base;
  integer i;
  time    dt;
  real    dt_ms;

  initial begin
    $display("=== S7: 按键 / 切图 / 自动轮播 / 音画联动 ===");

    repeat (20) @(posedge clk);
    rst = 1'b0;

    //---- 阶段 0：等首图提交 ----
    guard = 0;
    while (!display_valid && (guard < 40_000_000)) begin
      @(posedge clk);
      guard = guard + 1;
    end
    if (!display_valid) begin
      $display("✗ FAIL: 等不到首图提交（scan/load 链路没跑通）");
      $finish;
    end
    $display("✓ 上电后首图已提交（display_valid=1），state_code=%0d", state_code);

    // 空跑一会儿，确认平时不丢一致性
    #10_000_000;
    if (n_mismatch != 0) begin
      $display("✗ FAIL: audio_track_idx 与 osd_item_index 有 %0d 次不一致", n_mismatch);
      errors = errors + 1;
    end else
      $display("✓ audio_track_idx 与 osd_item_index 始终一致");

    //---- 阶段 1：自动轮播间隔 ----
    n_base = n_commit;
    press_key2(2);                                   // 开自动播放
    if (!osd_auto_mode) begin
      $display("✗ FAIL: 按 key2 后 osd_auto_mode 没有置 1");
      errors = errors + 1;
    end

    guard = 0;
    while ((n_commit < n_base + 3) && (guard < 20_000_000)) begin
      @(posedge clk);
      guard = guard + 1;
    end
    if (n_commit < n_base + 3) begin
      $display("✗ FAIL: 自动轮播没有连续切 3 张（只切了 %0d 张）", n_commit - n_base);
      errors = errors + 1;
    end else begin
      for (i = n_base; i < n_base + 2; i = i + 1) begin
        dt    = t_commit[i+1] - t_commit[i];
        dt_ms = dt / 1000000.0;
        $display("✓ 自动轮播第 %0d 次间隔 = %.3f ms（设定 %0d ms）", i + 1, dt_ms, AUTO_MS);
        if (dt_ms < AUTO_MS || dt_ms > (AUTO_MS + 8)) begin
          $display("✗ FAIL: 轮播间隔 %.3f ms 超出 [%0d, %0d] ms", dt_ms, AUTO_MS, AUTO_MS + 8);
          errors = errors + 1;
        end
      end
    end

    press_key2(2);                                   // 关自动播放
    if (osd_auto_mode) begin
      $display("✗ FAIL: 再按 key2 没有关掉自动播放");
      errors = errors + 1;
    end else
      $display("✓ key2 可以开/关自动播放");

    #30_000_000;                                     // 等手上的加载收尾

    //---- 阶段 2：加载期间连按 3 次"下一张" ----
    n_base = n_commit;
    press_key1(2); press_key1(2); press_key1(2);
    #30_000_000;
    $display("✓ 连按 3 次 key1 -> 实际切图 %0d 次（期望 3 次，一次都不丢）", n_commit - n_base);
    if ((n_commit - n_base) != 3) begin
      $display("✗ FAIL: 连按 3 次只切了 %0d 次", n_commit - n_base);
      errors = errors + 1;
    end

    if (n_mismatch != 0) begin
      $display("✗ FAIL: 全程 audio_track_idx / osd_item_index 不一致 %0d 次", n_mismatch);
      errors = errors + 1;
    end

    if (errors == 0) $display("=== S7 全部通过 (ALL PASS) ===");
    else             $display("=== S7 FAIL %0d 项 ===", errors);
    $finish;
  end

  initial begin
    #400_000_000;                                    // 400ms 超时保护
    $display("✗ FAIL: 仿真超时");
    $finish;
  end

endmodule
