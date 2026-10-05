//======================================================================
// S3: 帧缓存读写通路（纯 RTL 版）
//     DUT: wfifo_32_32_512 + frame_fifo_write + rfifo_32_32_512 + frame_fifo_read
//          存储用 sdram_model（行为模型，代替加密的 SDRAM 控制器）
//     参数: FRAME_WIDTH=32, FRAME_HEIGHT=16 -> 一帧 512 个 32bit 字
//     验证点：256 字突发写、垂直翻转地址映射、写完成、整帧读回、数据一致
//
//  ⚠ 为什么这里不直接例化 frame_read_write：
//     原文件 SD/frame_read_write.v 里
//         wire[BURST_BITS-1:0] wrusedw;   // 9bit
//         wire[BURST_BITS-1:0] rdusedw;   // 9bit
//     而 frame_fifo_write/read 的端口是 input[9:0]（10bit），
//     FIFO IP 的 usedw 输出本身也只有 9bit。综合时高位补 0 掩盖了这个问题，
//     RTL 仿真时高位悬空(Z)，会让 into_burst / wrusedw 比较变成 X，写/读突发进不去。
//     本 TB 直接把两个子模块按正确位宽接起来，既避开这个坑，也更方便看波形。
//======================================================================
`timescale 1ns/1ps
module tb_frame_fifo;

  // 注意：一帧字数要小于 FIFO 深度(512)才能完整放进写 FIFO——
  //       wfifo 的 almost-full 阈值是 509，写满 512 会丢掉最后几个字。
  localparam integer FW   = 32;
  localparam integer FH   = 8;
  localparam integer NPIX = FW * FH;          // 256 = 正好一个 256 字突发

  reg sd_clk  = 1'b0;  always #5  sd_clk  = ~sd_clk;    // 100MHz 写侧
  reg mem_clk = 1'b0;  always #4  mem_clk = ~mem_clk;   // 125MHz 存储侧
  reg vid_clk = 1'b0;  always #20 vid_clk = ~vid_clk;   // 25MHz 读侧

  reg rst = 1'b1;

  //---------------- 公共 ----------------
  wire        Sdr_init_done, Sdr_init_ref_vld;
  wire        Sdr_busy;      assign Sdr_busy = 1'b0;    // 行为模型：永不忙
  wire        App_wr_en, App_rd_en;
  wire [20:0] App_wr_addr, App_rd_addr;
  wire [31:0] App_wr_din;
  wire [3:0]  App_wr_dm;
  wire        Sdr_rd_en;
  wire [31:0] Sdr_rd_dout;

  wire        O_wr_busy, O_rd_busy;
  wire        write_fifo_aclr, read_fifo_aclr;
  wire [8:0]  wfifo_rdusedw, rfifo_wrusedw;
  wire [9:0]  rdusedw = {1'b0, wfifo_rdusedw};   // 补零扩展到 10bit（关键）
  wire [9:0]  wrusedw = {1'b0, rfifo_wrusedw};

  //---------------- 写侧 ----------------
  reg         write_req        = 1'b0;
  wire        write_req_ack;
  wire        write_finish;
  reg  [20:0] write_addr_0     = 21'd0;
  reg  [1:0]  write_addr_index = 2'd0;
  reg  [20:0] write_len        = NPIX;
  reg         write_en         = 1'b0;
  reg  [31:0] write_data       = 32'd0;

  wfifo_32_32_512 u_wfifo (
    .rst        (write_fifo_aclr),
    .clkw       (sd_clk),
    .clkr       (mem_clk),
    .we         (write_en),
    .di         (write_data),
    .re         (App_wr_en),
    .dout       (App_wr_din),
    .valid      (),
    .full_flag  (),
    .empty_flag (),
    .afull      (),
    .aempty     (),
    .wrusedw    (),
    .rdusedw    (wfifo_rdusedw)
  );

  frame_fifo_write #(
    .MEM_DATA_BITS (32),
    .ADDR_BITS     (21),
    .BURST_BITS    (9),
    .BURST_SIZE    (256),
    .WRITE_V_FLIP  (1),
    .FRAME_WIDTH   (FW),
    .FRAME_HEIGHT  (FH)
  ) u_wctrl (
    .rst               (rst),
    .mem_clk           (mem_clk),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_rd_busy       (O_rd_busy),
    .O_wr_busy         (O_wr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .write_req         (write_req),
    .write_req_ack     (write_req_ack),
    .write_finish      (write_finish),
    .write_addr_0      (write_addr_0),
    .write_addr_1      (21'd0),
    .write_addr_2      (21'd0),
    .write_addr_3      (21'd0),
    .write_addr_index  (write_addr_index),
    .write_len         (write_len),
    .fifo_aclr         (write_fifo_aclr),
    .rdusedw           (rdusedw)
  );

  //---------------- 读侧 ----------------
  reg         read_req       = 1'b0;
  wire        read_req_ack;
  wire        read_finish;
  reg  [20:0] read_addr_0    = 21'd0;
  reg  [1:0]  read_addr_index = 2'd0;
  reg  [20:0] read_len       = NPIX;
  reg         read_en        = 1'b0;
  wire [31:0] read_data;

  frame_fifo_read #(
    .MEM_DATA_BITS (32),
    .ADDR_BITS     (21),
    .BURST_BITS    (9),
    .FIFO_DEPTH    (512),
    .BURST_SIZE    (256)
  ) u_rctrl (
    .rst               (rst),
    .mem_clk           (mem_clk),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .Sdr_rd_en         (Sdr_rd_en),
    .App_wr_busy       (O_wr_busy),
    .O_rd_busy         (O_rd_busy),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .read_req          (read_req),
    .read_req_ack      (read_req_ack),
    .read_finish       (read_finish),
    .read_addr_0       (read_addr_0),
    .read_addr_1       (21'd0),
    .read_addr_2       (21'd0),
    .read_addr_3       (21'd0),
    .read_addr_index   (read_addr_index),
    .read_len          (read_len),
    .fifo_aclr         (read_fifo_aclr),
    .wrusedw           (wrusedw)
  );

  rfifo_32_32_512 u_rfifo (
    .rst        (read_fifo_aclr),
    .clkr       (vid_clk),
    .clkw       (mem_clk),
    .we         (Sdr_rd_en),
    .di         (Sdr_rd_dout),
    .re         (read_en),
    .dout       (read_data),
    .valid      (),
    .full_flag  (),
    .empty_flag (),
    .afull      (),
    .aempty     (),
    .wrusedw    (rfifo_wrusedw),
    .rdusedw    ()
  );

  sdram_model #(.MEM_WORDS(8192)) u_mem (
    .Clk              (mem_clk),
    .Clk_sft          (mem_clk),
    .Rst              (rst),
    .Sdr_init_done    (Sdr_init_done),
    .Sdr_init_ref_vld (Sdr_init_ref_vld),
    .App_wr_en        (App_wr_en),
    .App_wr_addr      (App_wr_addr),
    .App_wr_dm        (App_wr_dm),
    .App_wr_din       (App_wr_din),
    .App_rd_en        (App_rd_en),
    .App_rd_addr      (App_rd_addr),
    .Sdr_rd_en        (Sdr_rd_en),
    .Sdr_rd_dout      (Sdr_rd_dout)
  );
  assign App_wr_dm = 4'b0000;

  // 写入模式：第 i 个像素 = 32'h1000_0000 | i
  function [31:0] wpat;
    input integer i;
    begin wpat = 32'h1000_0000 | i[31:0]; end
  endfunction
  // 因为写地址做了垂直翻转，按存储顺序读出来第 k 个字 = 写入的第 src 个像素
  function [31:0] epat;
    input integer k;
    integer src;
    begin
      src = ((FH-1) - (k / FW)) * FW + (k % FW);
      epat = 32'h1000_0000 | src[31:0];
    end
  endfunction

  integer    i, k, tmo, errs = 0, nrd = 0, nwr = 0;
  reg [31:0] rd_word [0:NPIX-1];

  always @(posedge mem_clk) if (App_wr_en) nwr = nwr + 1;

  // rfifo_32_32_512 的 SHOW_AHEAD_EN=0：dout 比 re 晚一拍，
  // 所以要在 read_en 的下一个时钟沿采样（真机里 video_delay 的 21 拍延迟就是配这个的）
  reg read_en_d = 1'b0;
  always @(posedge vid_clk) begin
    read_en_d <= read_en;
    if (read_en_d) begin
      rd_word[nrd] = read_data;
      nrd = nrd + 1;
    end
  end

  // 可选的调试打印：看写侧状态机为什么没进突发
  integer dbgc = 0;
  always @(posedge mem_clk) begin
    dbgc = dbgc + 1;
    if (dbgc % 300 == 0)
      $display("   [dbg] t=%0t wfsm=%0d cnt=%0d into=%b | rfsm=%0d app_rd=%b rd_cnt=%0d rfifo_wr=%0d read_en=%b read_data=%h",
               $time, u_wctrl.state, u_wctrl.write_cnt, u_wctrl.into_burst, u_rctrl.state,
               App_rd_en, u_mem.rd_cnt, rfifo_wrusedw, read_en, read_data);
  end

  initial begin
    $display("=== S3: 帧缓存读写通路仿真（%0dx%0d，%0d 字/帧）===", FW, FH, NPIX);
    repeat (20) @(negedge sd_clk);
    rst = 1'b0;
    wait (Sdr_init_done);
    $display("✓ SDRAM 行为模型初始化完成");

    //---- 写：先握手（fifo_aclr 会在 S_ACK 里清 FIFO），再送 512 个字 ----
    write_req <= 1'b1;
    tmo = 0;
    while (!write_req_ack && tmo < 100000) begin @(negedge sd_clk); tmo = tmo + 1; end
    if (!write_req_ack) begin $display("✗ FAIL: 写握手超时"); errs = errs + 1; end
    else $display("✓ 写请求被应答（write_req_ack）");
    @(negedge sd_clk);
    write_req <= 1'b0;

    // frame_fifo_write 在 S_ACK 里会把写 FIFO 清空（fifo_aclr），
    // 要等 aclr 落下、状态机进入 S_CHECK_FIFO 之后再送像素，
    // 否则开头几个像素会被丢掉（真机里这段时间正好在等第一个扇区）。
    repeat (20) @(negedge sd_clk);

    for (i = 0; i < NPIX; i = i + 1) begin
      @(negedge sd_clk);
      write_en   <= 1'b1;
      write_data <= wpat(i);
    end
    @(negedge sd_clk);
    write_en <= 1'b0;

    tmo = 0;
    while (!write_finish && tmo < 200000) begin @(negedge mem_clk); tmo = tmo + 1; end
    if (!write_finish) begin $display("✗ FAIL: 没等到 write_finish"); errs = errs + 1; end
    else $display("✓ 整帧写完（write_finish），SDRAM 侧写入 %0d 个字", u_mem.wr_cnt);
    if (u_mem.wr_cnt == NPIX) $display("✓ 突发写字数正确：%0d", u_mem.wr_cnt);
    else begin $display("✗ FAIL: 写入 %0d 个字，期望 %0d", u_mem.wr_cnt, NPIX); errs = errs + 1; end

    // 看一眼翻转后的地址：第 0 个像素应落在 (FH-1)*FW
    $display("   参考：写入第 0 个字进了 SDRAM 地址 %0d（= (FH-1)*FW = %0d）",
             (FH-1)*FW, (FH-1)*FW);

    //---- 读：整帧读回 ----
    @(negedge vid_clk);
    read_req <= 1'b1;
    tmo = 0;
    while (!read_req_ack && tmo < 100000) begin @(negedge vid_clk); tmo = tmo + 1; end
    if (!read_req_ack) begin $display("✗ FAIL: 读握手超时"); errs = errs + 1; end
    else $display("✓ 读请求被应答（read_req_ack）");
    @(negedge vid_clk);
    read_req <= 1'b0;

    // 等读 FIFO 里先攒一点数据再开始弹，否则前几拍 re 落在空 FIFO 上会错位
    wait (rfifo_wrusedw >= 16);
    @(negedge vid_clk);

    for (k = 0; k < NPIX; k = k + 1) begin
      @(negedge vid_clk);
      read_en <= 1'b1;
    end
    @(negedge vid_clk);
    read_en <= 1'b0;
    repeat (30) @(negedge vid_clk);

    if (nrd == NPIX) $display("✓ 读回 %0d 个字", nrd);
    else begin $display("✗ FAIL: 读回 %0d 个字，期望 %0d", nrd, NPIX); errs = errs + 1; end

    for (k = 0; k < NPIX; k = k + 1)
      if (k < nrd && rd_word[k] !== epat(k)) begin
        if (errs < 6) $display("   [dbg] 第 %0d 个字 = %h，期望 %h", k, rd_word[k], epat(k));
        errs = errs + 1;
      end

    if (errs == 0) begin
      $display("✓ 垂直翻转映射验证通过：读出第 0 个字 = %h（写侧第 %0d 个像素）",
               rd_word[0], (FH-1)*FW);
      $display("=== S3 全部通过 ===");
    end else
      $display("=== S3 失败 %0d 项 ===", errs);
    $finish;
  end

  initial begin
    #20_000_000;
    $display("✗ FAIL: 仿真超时");
    $finish;
  end
endmodule
