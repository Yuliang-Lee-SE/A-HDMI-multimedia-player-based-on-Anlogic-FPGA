//======================================================================
// S1: bmp_read 单独仿真（不需要器件库、不需要 SD 卡硬件模型）
//     假卡：扇区 3 放一张合法的小 BMP，扇区 0/1/2 放垃圾
//     验证点：扫描命中扇区号、命中张数、写请求握手、3 字节拼像素的顺序
//======================================================================
`timescale 1ns/1ps
module tb_bmp_read;

  reg clk = 1'b0;
  always #5 clk = ~clk;                       // 100MHz，与 sd_card_clk 一致

  //---------------- DUT 端口 ----------------
  reg         rst               = 1'b1;
  wire        ready;
  reg         scan_start        = 1'b0;
  reg  [31:0] scan_start_sector = 32'd0;
  reg  [31:0] scan_max_sector   = 32'd15;
  reg  [2:0]  scan_target_count = 3'd1;
  wire        scan_done;
  wire        scan_found_valid;
  wire [31:0] scan_found_sector;
  wire [2:0]  scan_found_total;
  reg         load_start        = 1'b0;
  reg  [31:0] load_sector       = 32'd0;
  reg         sd_init_done      = 1'b1;
  wire [3:0]  state_code;
  reg  [15:0] bmp_width         = 16'd640;
  reg  [15:0] bmp_height        = 16'd480;
  wire        write_req;
  reg         write_req_ack     = 1'b0;
  wire        sd_sec_read;
  wire [31:0] sd_sec_read_addr;
  reg  [7:0]  sd_sec_read_data;
  reg         sd_sec_read_data_valid = 1'b0;
  reg         sd_sec_read_end        = 1'b0;
  wire        bmp_data_wr_en;
  wire [23:0] bmp_data;

  bmp_read u_dut (
    .clk                    (clk),
    .rst                    (rst),
    .ready                  (ready),
    .scan_start             (scan_start),
    .scan_start_sector      (scan_start_sector),
    .scan_max_sector        (scan_max_sector),
    .scan_target_count      (scan_target_count),
    .scan_done              (scan_done),
    .scan_found_valid       (scan_found_valid),
    .scan_found_sector      (scan_found_sector),
    .scan_found_total       (scan_found_total),
    .load_start             (load_start),
    .load_sector            (load_sector),
    .sd_init_done           (sd_init_done),
    .state_code             (state_code),
    .bmp_width              (bmp_width),
    .bmp_height             (bmp_height),
    .write_req              (write_req),
    .write_req_ack          (write_req_ack),
    .sd_sec_read            (sd_sec_read),
    .sd_sec_read_addr       (sd_sec_read_addr),
    .sd_sec_read_data       (sd_sec_read_data),
    .sd_sec_read_data_valid (sd_sec_read_data_valid),
    .sd_sec_read_end        (sd_sec_read_end),
    .bmp_data_wr_en         (bmp_data_wr_en),
    .bmp_data               (bmp_data)
  );

  //---------------- 假 SD 卡（扇区级）----------------
  reg [7:0] card_mem [0:8191];                // 16 个扇区
  integer   i;
  initial begin
    for (i = 0; i < 8192; i = i + 1) card_mem[i] = 8'h5A;      // 默认垃圾
    // 扇区 3 = 一张“小 BMP”：file_len=60，pixel_offset=54，640x480/24bit/不压缩
    for (i = 0; i < 64; i = i + 1) card_mem[3*512 + i] = 8'h00;  // 文件头先全部清零
    card_mem[3*512 +  0] = "B";
    card_mem[3*512 +  1] = "M";
    card_mem[3*512 +  2] = 8'd60;                                // file_len 低字节 = 60
    card_mem[3*512 + 10] = 8'd54;                                // pixel_offset = 54
    card_mem[3*512 + 18] = 8'h80;                                // width  = 640
    card_mem[3*512 + 19] = 8'h02;
    card_mem[3*512 + 22] = 8'hE0;                                // height = 480
    card_mem[3*512 + 23] = 8'h01;
    card_mem[3*512 + 28] = 8'd24;                                // bit_count = 24
    card_mem[3*512 + 54] = 8'h11; card_mem[3*512 + 55] = 8'h22;  // 像素 0 = 33_22_11
    card_mem[3*512 + 56] = 8'h33;
    card_mem[3*512 + 57] = 8'h44; card_mem[3*512 + 58] = 8'h55;  // 像素 1 = 66_55_44
    card_mem[3*512 + 59] = 8'h66;
  end

  reg        card_busy = 1'b0;
  reg [31:0] card_addr;
  reg [9:0]  card_cnt;
  reg        rd_d = 1'b0;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      card_busy            <= 1'b0;
      sd_sec_read_data_valid <= 1'b0;
      sd_sec_read_end      <= 1'b0;
      card_cnt             <= 10'd0;
      rd_d                 <= 1'b0;
    end else begin
      rd_d                   <= sd_sec_read;
      sd_sec_read_data_valid <= 1'b0;
      sd_sec_read_end        <= 1'b0;
      if (!card_busy && sd_sec_read && !rd_d) begin        // 上升沿开始一次扇区读
        card_busy <= 1'b1;
        card_addr <= sd_sec_read_addr;
        card_cnt  <= 10'd0;
      end else if (card_busy) begin
        if (card_cnt < 10'd512) begin
          sd_sec_read_data       <= card_mem[(card_addr[7:0]*512) + card_cnt];
          sd_sec_read_data_valid <= 1'b1;
          card_cnt               <= card_cnt + 10'd1;
        end else begin
          card_busy        <= 1'b0;
          sd_sec_read_end  <= 1'b1;                        // 512 字节送完，回一个 end
        end
      end
    end
  end

  //---------------- 握手与结果收集 ----------------
  always @(posedge clk) write_req_ack <= write_req;            // 1 拍应答

  reg [31:0] got_sector = 32'd0;
  reg [2:0]  got_total  = 3'd0;
  integer    npx        = 0;
  reg [23:0] px [0:7];
  always @(posedge clk) begin
    if (scan_found_valid) begin got_sector <= scan_found_sector; got_total <= scan_found_total; end
    if (bmp_data_wr_en)   begin px[npx] <= bmp_data; npx <= npx + 1; end
  end

  integer errors = 0;
  integer tmo;
  integer n_sec = 0;                                    // 调试：收到多少次扇区结束
  always @(posedge clk) if (sd_sec_read_end) begin
    n_sec <= n_sec + 1;
    $display("   [dbg] t=%0t 第 %0d 个扇区读完，addr=%0d header_0=%h header_1=%h width=%0d height=%0d bitcnt=%0d comp=%0d filelen=%0d",
             $time, n_sec+1, sd_sec_read_addr, u_dut.header_0, u_dut.header_1,
             u_dut.width[15:0], u_dut.height[15:0], u_dut.bit_count, u_dut.compression, u_dut.file_len);
  end
  always @(posedge clk) if (scan_found_valid)
    $display("   [dbg] t=%0t scan_found_valid: sector=%0d total=%0d", $time, scan_found_sector, scan_found_total);

  initial begin
    $display("=== S1: bmp_read 子系统仿真 ===");
    repeat (10) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);
    wait (ready);
    @(posedge clk);

    //---- 阶段 1：扫描 ----
    scan_start = 1'b1; @(posedge clk); scan_start = 1'b0;
    tmo = 0;
    while (!scan_done && tmo < 500000) begin @(posedge clk); tmo = tmo + 1; end
    @(posedge clk);            // 多等一拍，让非阻塞赋值生效后再比较（否则读到的是旧值）
    if (!scan_done) begin $display("✗ FAIL: 扫描超时，scan_done 未拉高"); errors = errors + 1; end
    else begin
      if (got_sector == 32'd3) $display("✓ 扫描命中扇区 = %0d", got_sector);
      else begin $display("✗ FAIL: 命中扇区 = %0d，期望 3", got_sector); errors = errors + 1; end
      if (got_total == 3'd1)   $display("✓ 命中张数 = %0d", got_total);
      else begin $display("✗ FAIL: 命中张数 = %0d，期望 1", got_total); errors = errors + 1; end
    end

    //---- 阶段 2：按扇区加载 ----
    load_sector = 32'd3;
    load_start  = 1'b1; @(posedge clk); load_start = 1'b0;
    tmo = 0;
    while (npx < 2 && tmo < 500000) begin @(posedge clk); tmo = tmo + 1; end
    if (npx < 2) begin $display("✗ FAIL: 只收到 %0d 个像素", npx); errors = errors + 1; end
    else begin
      if (px[0] === 24'h33_22_11) $display("✓ 像素 0 = %h（3 字节按 [7:0]->[15:8]->[23:16] 拼接）", px[0]);
      else begin $display("✗ FAIL: 像素 0 = %h，期望 332211", px[0]); errors = errors + 1; end
      if (px[1] === 24'h66_55_44) $display("✓ 像素 1 = %h", px[1]);
      else begin $display("✗ FAIL: 像素 1 = %h，期望 665544", px[1]); errors = errors + 1; end
      if (npx == 2) $display("✓ 一共输出 %0d 个像素（= file_len 60 - 54 偏移，/3）", npx);
      else begin $display("✗ FAIL: 输出 %0d 个像素，期望 2", npx); errors = errors + 1; end
    end

    //---- 阶段 3：回到 IDLE ----
    tmo = 0;
    while (state_code != 4'd1 && tmo < 10000) begin @(posedge clk); tmo = tmo + 1; end
    if (state_code == 4'd1) $display("✓ 整帧读完后 state_code 回到 1 (IDLE)");
    else begin $display("✗ FAIL: state_code = %0d，期望 1", state_code); errors = errors + 1; end

    if (errors == 0) $display("=== S1 全部通过 ===");
    else             $display("=== S1 失败 %0d 项 ===", errors);
    $finish;
  end

  initial begin
    #20_000_000;                       // 20ms 看门狗
    $display("✗ FAIL: 仿真超时（20ms）"); $finish;
  end
endmodule
