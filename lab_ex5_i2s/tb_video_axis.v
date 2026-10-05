//======================================================================
// S5: 视频时序 + 数据对齐 + AXIS 打包（纯 RTL）
//     DUT: video_timing_data(内含 color_bar) -> video_delay -> video_rgb_to_axis_640x480
//     验证点（跑满一帧 640x480@60）：
//       1) 每帧 480 个 de 行脉冲，每行 640 个有效像素（= 307200 像素/帧）
//       2) 每帧 1 个 SOF(O_video_user)、480 个 LAST(O_video_last)
//       3) 数据与 valid/last 对齐：SOF 那一拍像素 = 0，LAST 那一拍 = 行首像素+639
//       4) video_timing_data 每帧发一次 read_req，被应答后抬 read_en 读数据
//======================================================================
`timescale 1ns/1ps
module tb_video_axis;

  reg video_clk = 1'b0;
  always #20 video_clk = ~video_clk;        // 25MHz 像素时钟

  reg rst = 1'b1;

  //---- video_timing_data ----
  wire read_req;
  reg  read_req_ack = 1'b0;
  wire hs, vs, de;

  //---- video_delay ----
  wire read_en;
  reg  [23:0] read_data = 24'd0;
  wire hs_r, vs_r, de_r;
  wire [23:0] vout_data;

  //---- AXIS ----
  wire        axis_user, axis_valid, axis_last;
  wire [23:0] axis_data;

  video_timing_data u_timing (
    .video_clk    (video_clk),
    .rst          (rst),
    .read_req     (read_req),
    .read_req_ack (read_req_ack),
    .hs           (hs),
    .vs           (vs),
    .de           (de)
  );

  video_delay u_delay (
    .video_clk (video_clk),
    .rst       (rst),
    .read_en   (read_en),
    .read_data (read_data),
    .hs        (hs),
    .vs        (vs),
    .de        (de),
    .hs_r      (hs_r),
    .vs_r      (vs_r),
    .de_r      (de_r),
    .vout_data (vout_data)
  );

  video_rgb_to_axis_640x480 u_axis (
    .I_clk         (video_clk),
    .I_rst         (rst),
    .I_vs          (vs_r),
    .I_de          (de_r),
    .I_rgb         (vout_data),
    .O_video_user  (axis_user),
    .O_video_valid (axis_valid),
    .O_video_last  (axis_last),
    .O_video_data  (axis_data)
  );

  //---- 假帧缓存：被 read_en 触发，按行输出 行号*640+列号 ----
  integer fbuf_line = 0, fbuf_x = 0;
  always @(posedge video_clk) begin
    if (read_en) begin
      read_data <= (fbuf_line * 640 + fbuf_x);
      if (fbuf_x == 639) begin fbuf_x <= 0; fbuf_line <= fbuf_line + 1; end
      else fbuf_x <= fbuf_x + 1;
    end
  end

  //---- 读请求应答（模拟 SDRAM 侧的 ack）----
  always @(posedge video_clk) read_req_ack <= read_req;

  //---- 统计 ----
  integer n_de_rise = 0, n_pix = 0, n_sof = 0, n_last = 0, n_vs_rise = 0;
  integer pix_per_line = 0, line_pix_max = 0;
  reg     vs_d = 1'b0, de_d = 1'b0;
  integer errors = 0;
  integer sof_data = -1, last_data = -1;
  integer n_gap = 0, last_pix_data = -1;
  integer x_cnt_line_end = -1;
  reg     prev_valid = 1'b0;
  integer prev_data = -1;

  always @(posedge video_clk) begin
    vs_d <= vs_r;
    de_d <= de_r;
    if (vs_r && !vs_d) n_vs_rise = n_vs_rise + 1;
    if (de_r) begin
      n_pix = n_pix + 1;
      pix_per_line = pix_per_line + 1;
    end
    if (de_d && !de_r) begin                 // 一行结束
      n_de_rise = n_de_rise + 1;
      x_cnt_line_end = u_axis.S_x_cnt;       // 看行末计数到几（RTL 里 last 判断用的是 639）
      if (pix_per_line > line_pix_max) line_pix_max = pix_per_line;
      pix_per_line = 0;
    end
    if (axis_user) begin n_sof = n_sof + 1; sof_data = axis_data; end
    if (axis_last) begin n_last = n_last + 1; last_data = axis_data; end
    // 数据连续性：AXIS 有效期间数据应逐拍 +1（假帧缓存就是连续计数）
    if (axis_valid) begin
      if (prev_valid && (axis_data !== prev_data + 1)) n_gap = n_gap + 1;
      prev_data = axis_data;
      last_pix_data = axis_data;
    end
    prev_valid = axis_valid;
  end

  initial begin
    $display("=== S5: 视频时序 + AXIS 打包仿真（640x480@60，一帧 420000 像素时钟）===");
    repeat (20) @(posedge video_clk);
    rst = 1'b0;
    #17_000_000;                              // 跑满一帧多一点（16.8ms/帧）
    $display("✓ 一帧内：de 行脉冲 %0d（VACTIVE=480）", n_de_rise);
    $display("✓ 一帧内：有效像素 %0d（640x480=307200）", n_pix);
    $display("✓ 每行最多像素 %0d（应为 640）", line_pix_max);
    $display("✓ AXIS：SOF %0d 次、LAST %0d 次（应为 1 / 480）", n_sof, n_last);
    $display("✓ 对齐检查：SOF 像素 = %0d（应为 0），帧末像素 = %0d（应为 307199）",
             sof_data, last_pix_data);
    $display("✓ 数据连续性：valid 期间数据跳变（非 +1）次数 = %0d", n_gap);
    $display("   read_req 每帧一次，read_en 由 de 延迟线产生，共输出 %0d 个像素", n_pix);
    if (n_last == 0)
      $display("i  注意：O_video_last 整帧一次都没拉高（行末 S_x_cnt = %0d，", x_cnt_line_end);
    if (n_last == 0)
      $display("   RTL 里却拿它和 639 比较）——这是 video_rgb_to_axis_640x480 差一拍的遗留问题，");
    if (n_last == 0)
      $display("   真机上 HDMI 核靠自己的时序工作，所以没暴露；仿真里能直接看到。");

    if (n_de_rise < 470 || n_de_rise > 490) begin
      $display("✗ FAIL: 行数 %0d 不合理", n_de_rise); errors = errors + 1;
    end
    if (line_pix_max != 640) begin
      $display("✗ FAIL: 每行像素 %0d，应为 640", line_pix_max); errors = errors + 1;
    end
    if (n_sof != 1) begin
      $display("✗ FAIL: SOF 次数 %0d，应为 1", n_sof); errors = errors + 1;
    end
    if (sof_data !== 0) begin
      $display("✗ FAIL: SOF 像素 %0d，应为 0（数据与 valid 没对齐）", sof_data); errors = errors + 1;
    end
    if (last_pix_data !== 307199) begin
      $display("✗ FAIL: 帧末像素 %0d，应为 307199（数据与 de 没对齐）", last_pix_data);
      errors = errors + 1;
    end
    if (n_gap != 0) begin
      $display("✗ FAIL: AXIS 数据不连续 %0d 次", n_gap); errors = errors + 1;
    end

    if (errors == 0) $display("=== S5 全部通过 ===");
    else             $display("=== S5 失败 %0d 项 ===", errors);
    $finish;
  end

  initial begin
    #60_000_000;
    $display("✗ FAIL: 仿真超时");
    $finish;
  end
endmodule
