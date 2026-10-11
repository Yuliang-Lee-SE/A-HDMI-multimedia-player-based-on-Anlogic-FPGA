//======================================================================
// 多扇区 SD 卡 SPI 从机模型（供 S7 使用）
//
// 与 fake_sd_card.v 的区别：那个模型只有一个 512B 扇区数组，
// 不管主机请求哪个扇区都回同一份数据；本模型按 CMD17 的参数返回
// 对应扇区，所以可以做"扫描多张图 + 逐张加载"的整链路仿真。
//
//   CMD0 -> R1=01   CMD8 -> R1=01 + R7(00 00 01 AA)
//   CMD55 -> R1=01  CMD41 -> R1=00（模拟已初始化好的卡）
//   CMD16 -> R1=00  CMD17 -> R1=00 + 数据令牌 FE + 512B + 2B CRC
//
// SPI mode 3（CPOL=1/CPHA=1），时序与 fake_sd_card.v 完全一致
// （已在 S2 验证过）：上升沿采样 MOSI，下降沿更新 MISO。
//
// 注意：mem 由 testbench 通过层次引用直接写入（u_card.mem[...]），
//       模型自己只在 0 时刻填 0x5A 垃圾值。
//======================================================================
`timescale 1ns/1ps
module fake_sd_card_multi #(
  parameter integer CARDSEC = 64          // 模拟 64 个扇区 = 32KB
)(
  input  wire nCS,
  input  wire DCLK,
  input  wire MOSI,
  output reg  MISO
);
  localparam ST_CMD   = 3'd0;
  localparam ST_R1    = 3'd1;
  localparam ST_R7    = 3'd2;
  localparam ST_TOKEN = 3'd3;
  localparam ST_DATA  = 3'd4;
  localparam ST_CRC   = 3'd5;

  reg [7:0] mem [0:CARDSEC*512-1];

  reg [7:0] rx_shift;
  reg [2:0] bitc;
  reg [2:0] cmdcnt;
  reg [5:0] cmd;
  reg [31:0] arg;
  reg [15:0] sec_sel;
  reg [2:0] st;
  reg [9:0] dcnt;
  reg [1:0] ccnt;
  reg [1:0] r7cnt;
  reg [7:0] tx;

  wire [7:0] rx_next = {rx_shift[6:0], MOSI};
  wire [31:0] sec_base = {16'd0, sec_sel} * 512;

  integer k;
  initial begin
    rx_shift = 8'hFF; bitc = 3'd0; cmdcnt = 3'd0; cmd = 6'd0; arg = 32'd0;
    sec_sel = 16'd0; st = ST_CMD; dcnt = 10'd0; ccnt = 2'd0; r7cnt = 2'd0;
    tx = 8'hFF; MISO = 1'b1;
    for (k = 0; k < CARDSEC * 512; k = k + 1) mem[k] = 8'h5A;   // 垃圾：不含 "BM"
  end

  //========== 采样 MOSI + 字节级状态机（DCLK 上升沿）==========
  always @(posedge DCLK) begin
    rx_shift <= rx_next;
    if (nCS) begin
      bitc   <= 3'd0;
      cmdcnt <= 3'd0;
      st     <= ST_CMD;
      dcnt   <= 10'd0;
      ccnt   <= 2'd0;
      r7cnt  <= 2'd0;
    end else if (bitc == 3'd7) begin
      bitc <= 3'd0;
      case (st)
        ST_CMD: begin
          if (cmdcnt == 3'd0)      cmd        <= rx_next[5:0];
          else if (cmdcnt == 3'd1) arg[31:24] <= rx_next;
          else if (cmdcnt == 3'd2) arg[23:16] <= rx_next;
          else if (cmdcnt == 3'd3) arg[15:8]  <= rx_next;
          else if (cmdcnt == 3'd4) arg[7:0]   <= rx_next;
          if (cmdcnt == 3'd5) begin
            cmdcnt <= 3'd0;
            st     <= ST_R1;
            case (cmd)
              6'd0 : tx <= 8'h01;
              6'd8 : tx <= 8'h01;
              6'd55: tx <= 8'h01;
              6'd41: tx <= 8'h00;
              6'd16: tx <= 8'h00;
              6'd17: begin tx <= 8'h00; sec_sel <= arg[15:0]; end
              default: tx <= 8'h00;
            endcase
          end else begin
            cmdcnt <= cmdcnt + 3'd1;
            tx     <= 8'hFF;
          end
        end
        ST_R1: begin
          if (cmd == 6'd8)       begin st <= ST_R7;    r7cnt <= 2'd0; tx <= 8'h00; end
          else if (cmd == 6'd17) begin st <= ST_TOKEN; dcnt  <= 10'd0; tx <= 8'hFE; end
          else                   begin st <= ST_CMD;   tx <= 8'hFF; end
        end
        ST_R7: begin
          case (r7cnt)
            2'd0: tx <= 8'h00;
            2'd1: tx <= 8'h01;
            2'd2: tx <= 8'hAA;
            default: tx <= 8'hFF;
          endcase
          if (r7cnt == 2'd2) begin st <= ST_CMD; r7cnt <= 2'd0; end
          else r7cnt <= r7cnt + 2'd1;
        end
        ST_TOKEN: begin st <= ST_DATA; dcnt <= 10'd0; tx <= mem[sec_base]; end
        ST_DATA: begin
          if (dcnt == 10'd511) begin st <= ST_CRC; ccnt <= 2'd0; tx <= 8'hFF; end
          else begin dcnt <= dcnt + 10'd1; tx <= mem[sec_base + dcnt + 10'd1]; end
        end
        ST_CRC: begin
          tx <= 8'hFF;
          if (ccnt == 2'd1) begin st <= ST_CMD; ccnt <= 2'd0; end
          else ccnt <= ccnt + 2'd1;
        end
        default: st <= ST_CMD;
      endcase
    end else
      bitc <= bitc + 3'd1;
  end

  //========== 输出移位（DCLK 下降沿，保证上升沿时数据已稳定）==========
  always @(negedge DCLK) begin
    if (nCS) begin
      tx   <= 8'hFF;
      MISO <= 1'b1;
    end else begin
      MISO <= tx[7];
      tx   <= {tx[6:0], 1'b1};
    end
  end
endmodule
