//======================================================================
// 极简 SDRAM 行为模型（只给 frame_read_write 做仿真用）
//   * App_wr_en 上升沿写一个字
//   * App_rd_en 后 1 拍返回数据并拉高 Sdr_rd_en（真控制器约 10 拍内返回）
//   * Sdr_init_done 上电若干拍后拉高
// 真机用的是 sdram.v + 加密的 sdr_* 控制器，这里用行为模型替代，
// 好处是纯 RTL、可看内部、跑得快。
//======================================================================
`timescale 1ns/1ps
module sdram_model #(
  parameter MEM_WORDS = 8192          // 够放测试帧即可（真机 2M 字）
)(
  input  wire        Clk,
  input  wire        Clk_sft,
  input  wire        Rst,
  output reg         Sdr_init_done,
  output reg         Sdr_init_ref_vld,
  input  wire        App_wr_en,
  input  wire [20:0] App_wr_addr,
  input  wire [3:0]  App_wr_dm,
  input  wire [31:0] App_wr_din,
  input  wire        App_rd_en,
  input  wire [20:0] App_rd_addr,
  output reg         Sdr_rd_en,
  output reg  [31:0] Sdr_rd_dout
);
  reg [31:0] mem [0:MEM_WORDS-1];
  integer i;

  initial begin
    for (i = 0; i < MEM_WORDS; i = i + 1) mem[i] = 32'h0000_0000;
    Sdr_init_done    = 1'b0;
    Sdr_init_ref_vld = 1'b0;
    Sdr_rd_en        = 1'b0;
    Sdr_rd_dout      = 32'h0;
  end

  // 上电后 32 拍给出 init_done，并回一个自刷新有效脉冲
  reg [7:0] init_cnt = 8'd0;
  always @(posedge Clk or posedge Rst) begin
    if (Rst) begin
      init_cnt         <= 8'd0;
      Sdr_init_done    <= 1'b0;
      Sdr_init_ref_vld <= 1'b0;
    end else begin
      if (init_cnt < 8'd32) begin
        init_cnt      <= init_cnt + 8'd1;
        Sdr_init_done <= 1'b0;
      end else begin
        Sdr_init_done    <= 1'b1;
        Sdr_init_ref_vld <= (init_cnt == 8'd33);
        init_cnt         <= init_cnt + 8'd1;
      end
    end
  end

  // 写
  always @(posedge Clk)
    if (App_wr_en && !App_wr_dm[0]) mem[App_wr_addr[12:0]] <= App_wr_din;

  // 读（1 拍后返回）
  always @(posedge Clk or posedge Rst) begin
    if (Rst) begin
      Sdr_rd_en   <= 1'b0;
      Sdr_rd_dout <= 32'h0;
    end else begin
      Sdr_rd_en   <= App_rd_en;
      Sdr_rd_dout <= App_rd_en ? mem[App_rd_addr[12:0]] : Sdr_rd_dout;
    end
  end

  // 调试：想数一数读写次数可以看这两个计数
  integer wr_cnt = 0, rd_cnt = 0;
  always @(posedge Clk) begin
    if (App_wr_en) wr_cnt <= wr_cnt + 1;
    if (App_rd_en) rd_cnt <= rd_cnt + 1;
  end
endmodule
