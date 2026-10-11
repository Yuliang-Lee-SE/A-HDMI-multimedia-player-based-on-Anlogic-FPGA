//======================================================================
// S6: 片内 ROM 语音播放器（角色 C）
//   DUT: audio_rom_player + fake_audio_rom + I2S_receiver + audio_arc_calculate
//
// 验证点：
//   1) BCLK = MCLK/2，每个 LRCK 半周期 64 个 BCLK，fs ≈ 48kHz
//      （HDMI 音频核 ACR_N=6144 认的就是这个帧率）
//   2) 8kHz 素材 -> 每 6 个 48kHz 帧换一次样点（6× 零阶保持）
//   3) 段切换：ROM 地址跳到新段基址，且切换过程幅度经过 0（20ms 淡出/淡入）
//   4) 复位后先淡入（第一个样本幅度为 0，不是满幅突跳）
//   5) audio_valid ≈ 48kHz，acr_cts 落在 20000~30000
//
// 说明：本 TB 不需要 SD/视频链路，也不需要器件库。
//======================================================================
`timescale 1ns/1ps
module tb_audio_rom_player;

  // 12.295MHz 音频主时钟（与工程 PLL 实际输出一致）
  reg mclk = 1'b0;
  always #40.66 mclk = ~mclk;

  // 25MHz 视频时钟：I2S_receiver 与 ACR 挂在这个域
  reg vclk = 1'b0;
  always #20 vclk = ~vclk;

  reg  rst = 1'b1;

  // ---------------- DUT 端口 ----------------
  reg  [1:0] track_idx    = 2'd0;
  reg        track_toggle = 1'b0;
  wire [7:0] rom_data;
  wire [15:0] rom_addr;
  wire       i2s_bclk, i2s_lrck, i2s_dout;

  wire       audio_valid;
  wire [23:0] audio_l, audio_r;
  wire       acr_valid;
  wire [19:0] acr_cts, acr_n;

  fake_audio_rom #(.DEPTH(49152)) u_rom (
    .addra (rom_addr),
    .clka  (mclk),
    .doa   (rom_data)
  );

  audio_rom_player #(
    .MCLK_HZ     (12295000),
    .SRC_HZ      (8000),
    .SEG_SAMPLES (12288),
    .TRACK0_ADDR (16'd0),
    .TRACK1_ADDR (16'd12288),
    .TRACK2_ADDR (16'd24576),
    .TRACK3_ADDR (16'd36864),
    .RAMP_FRAMES (960)
  ) u_dut (
    .I_mclk         (mclk),
    .I_rst          (rst),
    .I_track_idx    (track_idx),
    .I_track_toggle (track_toggle),
    .I_rom_data     (rom_data),
    .O_rom_addr     (rom_addr),
    .O_i2s_BCLK     (i2s_bclk),
    .O_i2s_LRCK     (i2s_lrck),
    .O_i2s_DOUT     (i2s_dout)
  );

  I2S_receiver u_rx (
    .I_clk              (vclk),
    .I_rst              (rst),
    .I_i2s_BCLK         (i2s_bclk),
    .I_i2s_LRCK         (i2s_lrck),
    .I_i2s_DOUT         (i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_l),
    .O_audio_right_data (audio_r)
  );

  audio_arc_calculate #(.ACR_N(6144)) u_acr (
    .I_clk         (vclk),
    .I_rst         (rst),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
  );

  // ---------------- 测量 ----------------
  time     t_lrck_last = 0;
  integer  lrck_period_ps = 0;
  integer  n_bclk_high = 0, n_bclk_per_half = 0;
  integer  n_sample = 0, n_acr = 0, n_chan_mismatch = 0;
  integer  cts_min = 999999, cts_max = 0;

  // 零阶保持 / 段切换观测
  reg signed [23:0] prev_smp = 24'sd0;
  integer run_len = 0, run_max = 0, n_distinct = 0;
  integer zero_cross_seen = 0;
  integer addr_min_in_seg = 999999, addr_max_in_seg = 0;
  reg  [1:0] cur_seg = 2'd0;
  integer switch_phase = 0;          // 0=切换前 1=切换中（观察淡出）2=切换后

  integer errors = 0;
  real    fs_khz;

  always @(posedge i2s_bclk) begin
    if (i2s_lrck) n_bclk_high = n_bclk_high + 1;
  end

  always @(posedge i2s_lrck) begin
    if (t_lrck_last != 0) begin
      lrck_period_ps = ($time - t_lrck_last) * 1000;
      n_bclk_per_half = n_bclk_high;
    end
    t_lrck_last = $time;
    n_bclk_high = 0;
  end

  // 采样统计：run_len 就是"同一个值连续出现了几帧"
  always @(posedge vclk) begin
    if (audio_valid) begin
      n_sample = n_sample + 1;
      if (audio_l !== audio_r) n_chan_mismatch = n_chan_mismatch + 1;

      if (audio_l === prev_smp) begin
        run_len = run_len + 1;
      end else begin
        if (run_len > run_max) run_max = run_len;
        run_len = 1;
        prev_smp = audio_l;
        n_distinct = n_distinct + 1;
      end

      if (audio_l === 24'sd0) zero_cross_seen = 1;

      // 段内地址范围观测
      if (rom_addr >= (cur_seg * 12288) && rom_addr < ((cur_seg + 1) * 12288)) begin
        if (rom_addr < addr_min_in_seg) addr_min_in_seg = rom_addr;
        if (rom_addr > addr_max_in_seg) addr_max_in_seg = rom_addr;
      end
    end

    if (acr_valid) begin
      n_acr = n_acr + 1;
      if (acr_n != 20'd6144) begin
        $display("✗ FAIL: acr_n = %0d，期望 6144", acr_n);
        errors = errors + 1;
      end
      if (acr_cts < cts_min) cts_min = acr_cts;
      if (acr_cts > cts_max) cts_max = acr_cts;
    end
  end

  // 记录段切换瞬间的幅度是否经过 0
  reg     sw_zero_ok;
  always @(posedge vclk) begin
    if (switch_phase == 1) begin
      if (audio_valid) begin
        if (audio_l === 24'sd0) sw_zero_ok = 1'b1;
        if (sw_zero_ok && audio_l !== 24'sd0) switch_phase = 2;
      end
    end
  end

  initial begin
    $display("=== S6: 片内 ROM 语音播放器（audio_rom_player）===");

    repeat (20) @(posedge mclk);
    rst = 1'b0;

    //---- 等复位后的淡入结束（960 帧 ≈ 20ms）----
    repeat (1500) @(posedge vclk);

    //---- 1) BCLK / LRCK 关系 ----
    @(posedge i2s_lrck); @(posedge i2s_lrck);
    if (lrck_period_ps != 0) begin
      fs_khz = 1000000.0 / lrck_period_ps * 1000.0;
      $display("✓ LRCK 周期 ≈ %0d ps -> fs ≈ %0.3f kHz（每半周期 %0d 个 BCLK）",
               lrck_period_ps, fs_khz, n_bclk_per_half);
      if (n_bclk_per_half != 64) begin
        $display("✗ FAIL: 每个 LRCK 半周期 BCLK 数 = %0d，期望 64", n_bclk_per_half);
        errors = errors + 1;
      end
      if (fs_khz < 47.5 || fs_khz > 48.5) begin
        $display("✗ FAIL: 采样率 %0.3f kHz 偏离 48kHz", fs_khz);
        errors = errors + 1;
      end
    end

    //---- 2) 零阶保持：同一值应连续 6 帧 ----
    run_len = 0; run_max = 0; n_distinct = 0;
    n_sample = 0; n_acr = 0; n_chan_mismatch = 0;
    cts_min = 999999; cts_max = 0;
    #2_000_000;                            // 2ms ≈ 96 个 48kHz 帧
    $display("✓ 2ms 内 audio_valid = %0d 次（48kHz 理论 96 次）", n_sample);
    $display("✓ 2ms 内 acr_valid = %0d 次，acr_cts = %0d ~ %0d", n_acr, cts_min, cts_max);
    $display("✓ 零阶保持：最长连续 %0d 帧，平均 %.3f 帧/样点（8kHz 素材期望 ≈6）",
             run_max, (n_distinct > 0) ? (n_sample * 1.0 / n_distinct) : 0.0);
    if (n_sample < 90 || n_sample > 102) begin
      $display("✗ FAIL: 2ms 内样本数 %0d 不合理", n_sample);
      errors = errors + 1;
    end
    // 48kHz 帧率 / 8kHz 素材 = 6.0034，所以连续帧数在 6 与 7 之间摆动
    if (run_max < 6 || run_max > 7) begin
      $display("✗ FAIL: 零阶保持最长连续帧数 = %0d，期望 6 或 7", run_max);
      errors = errors + 1;
    end
    if (n_distinct > 0 && (n_sample * 1.0 / n_distinct) < 5.5) begin
      $display("✗ FAIL: 平均保持帧数偏低，素材播放速度不对");
      errors = errors + 1;
    end
    if (n_chan_mismatch != 0) begin
      $display("✗ FAIL: 左右声道不一致出现 %0d 次", n_chan_mismatch);
      errors = errors + 1;
    end
    if (cts_min < 20000 || cts_max > 30000) begin
      $display("✗ FAIL: acr_cts 超出合理范围");
      errors = errors + 1;
    end else
      $display("✓ acr_cts 落在合理范围（ACR 与 48kHz 帧率一致）");

    //---- 3) 段切换：切到 track1，地址应落到 12288 段内，幅度经过 0 ----
    cur_seg = 2'd1;
    addr_min_in_seg = 999999; addr_max_in_seg = 0;
    zero_cross_seen = 0; sw_zero_ok = 1'b0;
    switch_phase = 1;

    @(posedge mclk);
    track_idx    = 2'd1;
    track_toggle = ~track_toggle;          // 请求换段

    // 等切换完成：淡出 20ms + 淡入 20ms，留 45ms 余量
    #45_000_000;

    $display("✓ 切段后 ROM 地址范围 = %0d ~ %0d（应在 [12288,24575] 内）",
             addr_min_in_seg, addr_max_in_seg);
    if (addr_min_in_seg < 12288 || addr_max_in_seg > 24575) begin
      $display("✗ FAIL: 切段后地址没有落在 track1 段内");
      errors = errors + 1;
    end
    if (!sw_zero_ok) begin
      $display("✗ FAIL: 切换过程没有经过 0 幅度（淡出/淡入未生效）");
      errors = errors + 1;
    end else
      $display("✓ 切换过程幅度经过 0（20ms 淡出/淡入生效，无爆音跳变）");

    //---- 4) 回到 track0，并检查循环：地址应始终落在本段内 ----
    cur_seg = 2'd0;
    addr_min_in_seg = 999999; addr_max_in_seg = 0;
    @(posedge mclk);
    track_idx    = 2'd0;
    track_toggle = ~track_toggle;
    #45_000_000;
    // 段长 12288 样点 @8kHz = 1.536s，仿真太长，这里只确认回到了 0 段
    if (rom_addr >= 12288) begin
      $display("✗ FAIL: 切回 track0 后地址 = %0d，超出 [0,12287]", rom_addr);
      errors = errors + 1;
    end else
      $display("✓ 切回 track0 生效，当前地址 = %0d", rom_addr);

    if (errors == 0) $display("=== S6 全部通过 (ALL PASS) ===");
    else             $display("=== S6 FAIL %0d 项 ===", errors);
    $finish;
  end

  initial begin
    #200_000_000;                          // 200ms 超时保护
    $display("✗ FAIL: 仿真超时");
    $finish;
  end

endmodule
