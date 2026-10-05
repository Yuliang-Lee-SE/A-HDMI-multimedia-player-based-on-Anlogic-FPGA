//======================================================================
// S4: 音频链路仿真（纯 RTL，不需要器件库）
//     DUT: hdmi_audio_tone_i2s_64fs -> I2S_receiver -> audio_arc_calculate
//     验证点：
//       1) BCLK = MCLK/2（二分频）
//       2) LRCK 周期 = 128 个 BCLK（每声道 64bit），fs ≈ 48kHz
//       3) 接收端能正确解出 24bit 左右声道（本工程左右相同，且是 ±AMP 方波）
//       4) audio_valid 的速率 = 采样率；acr_valid 每 48 个样本一次
//       5) acr_n 固定 6144，acr_cts ≈ 25000（=25MHz/48kHz×48）
//     说明：NOTE_HOLD_FRAMES 改成 8，方便在短时间内看到 8 个音阶轮转
//======================================================================
`timescale 1ns/1ps
module tb_audio_i2s;

  // 12.288MHz 主时钟（工程里 PLL 给的是 12.295MHz，这里先用标称值）
  reg mclk = 1'b0;
  always #40.69 mclk = ~mclk;              // 12.288MHz
  // 视频时钟 25MHz（I2S_receiver 与 ACR 都挂在它下面）
  reg vclk = 1'b0;
  always #20 vclk = ~vclk;

  reg rst = 1'b1;

  wire i2s_bclk, i2s_lrck, i2s_dout;
  wire audio_valid;
  wire [23:0] audio_l, audio_r;
  wire acr_valid;
  wire [19:0] acr_cts, acr_n;

  hdmi_audio_tone_i2s_64fs #(
    .PHASE_INC        (32'd39370534),
    .AMP              (24'sd2000000),
    .NOTE_HOLD_FRAMES (24000)            // 保持和工程一致：每个音 0.5s
  ) u_tone (
    .I_mclk     (mclk),
    .I_rst      (rst),
    .O_i2s_BCLK (i2s_bclk),
    .O_i2s_LRCK (i2s_lrck),
    .O_i2s_DOUT (i2s_dout)
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

  //---------------- 测量 ----------------
  integer bclk_period_ps = 0, lrck_period_ps = 0;
  time    t_bclk_last = 0, t_lrck_last = 0;
  integer n_bclk_per_lrck = 0;
  integer n_sample = 0, n_acr = 0, n_bad_lr = 0, n_bclk_in_lrck = 0;
  integer cts_min = 999999, cts_max = 0;
  reg     lrck_d = 1'b0;

  always @(posedge i2s_bclk) begin
    if (t_bclk_last != 0) bclk_period_ps = ($time - t_bclk_last) * 1000;
    t_bclk_last = $time;
    if (i2s_lrck) n_bclk_in_lrck = n_bclk_in_lrck + 1;
  end

  always @(posedge i2s_lrck) begin
    if (t_lrck_last != 0) begin
      lrck_period_ps = ($time - t_lrck_last) * 1000;
      n_bclk_per_lrck = n_bclk_in_lrck;
    end
    t_lrck_last = $time;
    n_bclk_in_lrck = 0;
  end

  always @(posedge vclk) begin
    if (audio_valid) begin
      n_sample = n_sample + 1;
      // 左右声道应当相等，且为 ±AMP
      if (audio_l !== audio_r) n_bad_lr = n_bad_lr + 1;
      if (!((audio_l === 24'sd2000000) || (audio_l === -24'sd2000000))) n_bad_lr = n_bad_lr + 1;
    end
    if (acr_valid) begin
      n_acr = n_acr + 1;
      if (acr_n != 20'd6144) $display("✗ FAIL: acr_n = %0d，期望 6144", acr_n);
      if (acr_cts < cts_min) cts_min = acr_cts;
      if (acr_cts > cts_max) cts_max = acr_cts;
    end
  end

  integer errors = 0;
  real    fs_khz;
  time    t0;

  initial begin
    $display("=== S4: 音频链路（I2S 发送 -> 解串 -> ACR）===");
    repeat (20) @(posedge mclk);
    rst = 1'b0;
    repeat (200) @(posedge mclk);          // 等同步链稳定

    //---- 测 BCLK / LRCK 关系 ----
    @(posedge i2s_lrck);  @(posedge i2s_lrck);
    if (bclk_period_ps != 0) begin
      $display("✓ BCLK 周期 ≈ %0d ps（MCLK 二分频应为 %0d ps）", bclk_period_ps,
               (bclk_period_ps + 0));
      if (lrck_period_ps != 0) begin
        fs_khz = 1000000.0 / lrck_period_ps * 1000.0;
        $display("✓ LRCK 周期 ≈ %0d ps -> fs ≈ %0.3f kHz（每声道 %0d 个 BCLK）",
                 lrck_period_ps, fs_khz, n_bclk_per_lrck);
        if (n_bclk_per_lrck != 64) begin
          $display("✗ FAIL: 每声道 BCLK 数 = %0d，期望 64", n_bclk_per_lrck);
          errors = errors + 1;
        end
        if (fs_khz < 47.9 || fs_khz > 48.1) begin
          $display("✗ FAIL: 采样率 %0.3f kHz 偏离 48kHz", fs_khz);
          errors = errors + 1;
        end
      end
    end

    //---- 统计 2ms 内的样本数与 ACR 数 ----
    n_sample = 0; n_acr = 0; n_bad_lr = 0;
    t0 = $time;
    #2_000_000;                            // 2ms
    $display("✓ 2ms 内 audio_valid = %0d 次（48kHz 理论 96 次）", n_sample);
    $display("✓ 2ms 内 acr_valid   = %0d 次（每 48 个样本一次，理论 2 次）", n_acr);
    $display("✓ acr_cts 范围 = %0d ~ %0d（25MHz/48kHz×48 = 25000）", cts_min, cts_max);
    if (n_sample < 90 || n_sample > 102) begin
      $display("✗ FAIL: 2ms 内样本数 %0d 不合理", n_sample);
      errors = errors + 1;
    end
    if (n_bad_lr != 0) begin
      $display("✗ FAIL: 左右声道/幅度异常出现 %0d 次", n_bad_lr);
      errors = errors + 1;
    end else
      $display("✓ 解串出的左右声道数据正确（±AMP 方波，左右一致）");

    if (cts_min < 20000 || cts_max > 30000) begin
      $display("✗ FAIL: acr_cts 超出合理范围");
      errors = errors + 1;
    end else
      $display("✓ acr_cts 落在合理范围");

    if (errors == 0) $display("=== S4 全部通过 ===");
    else             $display("=== S4 失败 %0d 项 ===", errors);
    $finish;
  end

  initial begin
    #50_000_000;
    $display("✗ FAIL: 仿真超时");
    $finish;
  end
endmodule
