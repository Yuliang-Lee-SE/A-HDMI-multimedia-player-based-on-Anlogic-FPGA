`timescale 1ns/1ps
// Audio integration smoke test:
//   audio_pcm_player -> I2S_receiver -> audio_arc_calculate.
module tb_audio_i2s;
  localparam integer MCLK_HZ = 12_288_000;

  reg mclk = 1'b0;
  always #40.69 mclk = ~mclk;

  reg vclk = 1'b0;
  always #20 vclk = ~vclk;

  reg rst = 1'b1;
  reg [4:0] track_idx = 5'd0;
  reg track_toggle = 1'b0;
  reg enabled = 1'b1;
  reg pcm_ready = 1'b1;
  reg [15:0] pcm_len = 16'd16;
  reg [2:0] vol_level = 3'd4;
  wire [14:0] pcm_addr;
  wire [15:0] pcm_data = pcm_addr[3] ? 16'sh4000 : -16'sh4000;
  wire i2s_bclk, i2s_lrck, i2s_dout;
  wire audio_valid;
  wire [23:0] audio_l, audio_r;
  wire acr_valid;
  wire [19:0] acr_cts, acr_n;

  audio_pcm_player #(
    .ENABLE_MUTE (0),
    .MCLK_HZ     (MCLK_HZ),
    .SRC_HZ      (8000),
    .RAMP_FRAMES (16)
  ) dut_player (
    .I_mclk         (mclk),
    .I_rst          (rst),
    .I_track_idx    (track_idx),
    .I_enabled      (enabled),
    .I_pcm_ready    (pcm_ready),
    .I_pcm_len      (pcm_len),
    .I_vol_level    (vol_level),
    .I_track_toggle (track_toggle),
    .I_pcm_data     (pcm_data),
    .O_pcm_addr     (pcm_addr),
    .O_i2s_BCLK     (i2s_bclk),
    .O_i2s_LRCK     (i2s_lrck),
    .O_i2s_DOUT     (i2s_dout)
  );

  I2S_receiver dut_rx (
    .I_clk              (vclk),
    .I_rst              (rst),
    .I_i2s_BCLK         (i2s_bclk),
    .I_i2s_LRCK         (i2s_lrck),
    .I_i2s_DOUT         (i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_l),
    .O_audio_right_data (audio_r)
  );

  audio_arc_calculate #(.ACR_N(6144)) dut_acr (
    .I_clk         (vclk),
    .I_rst         (rst),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
  );

  integer bclk_period_ps = 0;
  integer lrck_period_ps = 0;
  time t_bclk_last = 0;
  time t_lrck_last = 0;
  integer bclk_in_lrck = 0;
  integer bclk_per_lrck = 0;
  integer samples = 0;
  integer nonzero_samples = 0;
  integer acr_packets = 0;
  integer bad_channels = 0;
  integer bad_acr_n = 0;
  integer cts_min = 999999;
  integer cts_max = 0;

  always @(posedge i2s_bclk) begin
    if (t_bclk_last != 0)
      bclk_period_ps = ($time - t_bclk_last) * 1000;
    t_bclk_last = $time;
    if (i2s_lrck)
      bclk_in_lrck = bclk_in_lrck + 1;
  end

  always @(posedge i2s_lrck) begin
    if (t_lrck_last != 0) begin
      lrck_period_ps = ($time - t_lrck_last) * 1000;
      bclk_per_lrck = bclk_in_lrck;
    end
    t_lrck_last = $time;
    bclk_in_lrck = 0;
  end

  always @(posedge vclk) begin
    if (audio_valid) begin
      samples = samples + 1;
      if (audio_l != audio_r)
        bad_channels = bad_channels + 1;
      if (audio_l != 24'sd0)
        nonzero_samples = nonzero_samples + 1;
    end
    if (acr_valid) begin
      acr_packets = acr_packets + 1;
      if (acr_n != 20'd6144)
        bad_acr_n = bad_acr_n + 1;
      if (acr_cts < cts_min)
        cts_min = acr_cts;
      if (acr_cts > cts_max)
        cts_max = acr_cts;
    end
  end

  integer errors = 0;
  real fs_khz;

  initial begin
    $display("=== S4: WAV PCM -> I2S -> receiver -> ACR ===");
    repeat (20) @(posedge mclk);
    rst = 1'b0;
    repeat (300) @(posedge mclk);

    @(posedge i2s_lrck);
    @(posedge i2s_lrck);
    if (bclk_period_ps == 0 || lrck_period_ps == 0) begin
      $display("? FAIL: I2S clocks did not start");
      errors = errors + 1;
    end else begin
      fs_khz = 1_000_000.0 / lrck_period_ps * 1000.0;
      $display("? BCLK period=%0d ps, LRCK period=%0d ps, fs=%0.3f kHz",
               bclk_period_ps, lrck_period_ps, fs_khz);
      if (bclk_per_lrck != 64) begin
        $display("? FAIL: BCLK count per channel=%0d, expected 64", bclk_per_lrck);
        errors = errors + 1;
      end
      if (fs_khz < 47.9 || fs_khz > 48.1) begin
        $display("? FAIL: LRCK rate %.3f kHz is outside 48 kHz +/-0.1 kHz", fs_khz);
        errors = errors + 1;
      end
    end

    samples = 0;
    nonzero_samples = 0;
    acr_packets = 0;
    bad_channels = 0;
    bad_acr_n = 0;
    cts_min = 999999;
    cts_max = 0;
    #2_000_000;

    $display("? audio_valid=%0d packets in 2 ms (expected about 96)", samples);
    $display("? nonzero samples=%0d, acr packets=%0d", nonzero_samples, acr_packets);
    $display("? acr_cts range=%0d..%0d", cts_min, cts_max);

    if (samples < 90 || samples > 102) begin
      $display("? FAIL: audio sample rate is out of range");
      errors = errors + 1;
    end
    if (nonzero_samples == 0) begin
      $display("? FAIL: PCM player produced only silence");
      errors = errors + 1;
    end
    if (bad_channels != 0) begin
      $display("? FAIL: left/right channels differ %0d times", bad_channels);
      errors = errors + 1;
    end
    if (bad_acr_n != 0) begin
      $display("? FAIL: ACR_N was not 6144");
      errors = errors + 1;
    end
    if (acr_packets == 0 || cts_min < 20000 || cts_max > 30000) begin
      $display("? FAIL: ACR timing values are invalid");
      errors = errors + 1;
    end

    if (errors == 0)
      $display("=== S4 PASS ===");
    else
      $display("=== S4 FAIL: %0d error(s) ===", errors);
    $finish;
  end

  initial begin
    #50_000_000;
    $display("? FAIL: audio integration test timed out");
    $finish;
  end
endmodule
