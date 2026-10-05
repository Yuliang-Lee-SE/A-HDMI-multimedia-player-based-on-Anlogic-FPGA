//======================================================================
// S2: sd_card_top（SD 卡 SPI 协议栈）子系统仿真
//     DUT: sd_card_top -> sd_card_sec_read_write + sd_card_cmd + spi_master
//     卡  : fake_sd_card（SPI 从机模型）
//     验证点：CMD0/8/55/41/16 初始化流程走通、sd_init_done 拉高、
//             CMD17 读一个扇区时 512 字节数据与卡内数据一致、end 脉冲
//     注意：TB 把 SPI_LOW_SPEED_DIV 从 248 改小，否则初始化的
//           11 字节 0xFF 会在仿真里花掉大量时间（真机不需要改）
//======================================================================
`timescale 1ns/1ps
module tb_sd_card;

  reg clk = 1'b0;
  always #5 clk = ~clk;                      // 100MHz

  reg rst = 1'b1;

  wire SD_nCS, SD_DCLK, SD_MOSI;
  wire SD_MISO;                              // 由卡模型驱动（不能是 reg）

  wire        sd_init_done;
  reg         sd_sec_read       = 1'b0;
  reg  [31:0] sd_sec_read_addr  = 32'd0;
  wire [7:0]  sd_sec_read_data;
  wire        sd_sec_read_data_valid;
  wire        sd_sec_read_end;

  sd_card_top #(
    .SPI_LOW_SPEED_DIV  (16'd4),            // 真机用 248；仿真改小
    .SPI_HIGH_SPEED_DIV (16'd0)
  ) u_dut (
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
    .sd_sec_write_data      (8'd0),
    .sd_sec_write_data_req  (),
    .sd_sec_write_end       ()
  );

  fake_sd_card u_card (
    .nCS  (SD_nCS),
    .DCLK (SD_DCLK),
    .MOSI (SD_MOSI),
    .MISO (SD_MISO)
  );

  // 预填卡内扇区：字节 i 的值 = i[7:0]（方便比对）
  integer i;
  initial begin
    for (i = 0; i < 512; i = i + 1) u_card.sector_mem[i] = i[7:0];
  end

  // 收集读回的 512 字节
  integer   nbyte = 0;
  reg [7:0] rx [0:511];
  always @(posedge clk) begin
    if (sd_sec_read_data_valid) begin
      if (nbyte < 512) rx[nbyte] <= sd_sec_read_data;
      nbyte <= nbyte + 1;
    end
  end

  integer errors = 0;
  // ---- 临时调试：每 5000 个时钟打印一次关键内部状态 ----
  integer dbgcnt = 0;
  always @(posedge clk) begin
    dbgcnt = dbgcnt + 1;
    if (dbgcnt % 20000 == 0)
      $display("   [dbg] t=%0t sec_state=%0d cmd=%h cmd_req=%b err=%b | card_st=%0d cmdcnt=%0d cmd=%0d MISOb=%b | nCS=%b",
               $time, u_dut.sd_card_sec_read_write_m0.state,
               u_dut.sd_card_sec_read_write_m0.cmd,
               u_dut.sd_card_sec_read_write_m0.cmd_req,
               u_dut.sd_card_sec_read_write_m0.cmd_req_error,
               u_card.st, u_card.cmdcnt, u_card.cmd, SD_MISO, SD_nCS);
  end
  integer tmo;
  integer nend = 0;
  always @(posedge clk) if (sd_sec_read_end) nend <= nend + 1;

  initial begin
    $display("=== S2: sd_card_top 子系统仿真 ===");
    repeat (10) @(posedge clk);
    rst = 1'b0;

    //---- 阶段 1：等初始化完成（CMD0/8/55/41/16）----
    tmo = 0;
    while (!sd_init_done && tmo < 5000000) begin @(posedge clk); tmo = tmo + 1; end
    if (sd_init_done) $display("✓ SD 卡初始化完成（sd_init_done=1），用了 %0d 个时钟", tmo);
    else begin $display("✗ FAIL: 初始化超时，sd_init_done 仍为 0"); errors = errors + 1; end
    @(posedge clk);      // 让非阻塞赋值生效

    //---- 阶段 2：读扇区 ----
    sd_sec_read_addr = 32'd0;
    sd_sec_read      = 1'b1;
    tmo = 0;
    while (!sd_sec_read_end && tmo < 5000000) begin @(posedge clk); tmo = tmo + 1; end
    @(posedge clk);
    sd_sec_read = 1'b0;

    if (sd_sec_read_end | (nend > 0)) $display("✓ 收到 sd_sec_read_end（%0d 次），读了 %0d 个字节", nend, nbyte);
    else begin $display("✗ FAIL: 没等到 sd_sec_read_end"); errors = errors + 1; end

    if (nbyte == 512) $display("✓ 数据字节数 = 512");
    else begin $display("✗ FAIL: 数据字节数 = %0d，期望 512", nbyte); errors = errors + 1; end

    // 抽查若干字节
    if (rx[0] === 8'h00 && rx[1] === 8'h01 && rx[255] === 8'hFF && rx[511] === 8'hFF)
      $display("✓ 抽查通过：rx[0]=%h rx[1]=%h rx[255]=%h rx[511]=%h", rx[0], rx[1], rx[255], rx[511]);
    else begin
      $display("✗ FAIL: 抽查失败 rx[0]=%h rx[1]=%h rx[255]=%h rx[511]=%h", rx[0], rx[1], rx[255], rx[511]);
      errors = errors + 1;
    end

    if (errors == 0) $display("=== S2 全部通过 ===");
    else             $display("=== S2 失败 %0d 项 ===", errors);
    $finish;
  end

  initial begin
    #50_000_000;                                  // 50ms 看门狗
    $display("✗ FAIL: 仿真超时");
    $finish;
  end
endmodule
