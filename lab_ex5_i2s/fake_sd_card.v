//======================================================================
// 简易 SD 卡 SPI 从机模型（只实现例程用到的命令）
//   CMD0  -> R1=01
//   CMD8  -> R1=01 + R7(00 00 01 AA)
//   CMD55 -> R1=01
//   CMD41 -> R1=00   （模拟“已初始化好”的卡，让状态机一次通过）
//   CMD16 -> R1=00
//   CMD17 -> R1=00 + 数据令牌 FE + 512B 数据 + 2B CRC
//
// 时序对齐（SPI mode 3，CPOL=1/CPHA=1）：
//   主端在 DCLK 下降沿改变 MOSI，在上升沿采样 MISO；
//   所以本模型：上升沿采样 MOSI（此时数据已稳定），下降沿更新 MISO。
//   一个字节 = 8 个下降沿（输出 8 bit）+ 8 个上升沿（采样 8 bit），
//   字节级状态机放在“第 8 个上升沿”触发，此时刚好收齐 8 bit。
//======================================================================
`timescale 1ns/1ps
module fake_sd_card (
  input  wire nCS,
  input  wire DCLK,
  input  wire MOSI,
  output reg  MISO
);
  localparam ST_CMD   = 3'd0;   // 收 6 字节命令
  localparam ST_R1    = 3'd1;   // 发 R1
  localparam ST_R7    = 3'd2;   // CMD8 的 R7 剩余字节
  localparam ST_TOKEN = 3'd3;   // 发数据令牌 FE
  localparam ST_DATA  = 3'd4;   // 发 512 字节
  localparam ST_CRC   = 3'd5;   // 发 2 字节 CRC

  reg [7:0] sector_mem [0:511];    // 只模拟一个扇区，TB 里可直接预填
  reg [7:0] rx_shift;
  reg [2:0] bitc;
  reg [2:0] cmdcnt;
  reg [5:0] cmd;
  reg [31:0] arg;
  reg [2:0] st;
  reg [9:0] dcnt;
  reg [1:0] ccnt;
  reg [1:0] r7cnt;
  reg [7:0] tx;

  wire [7:0] rx_next = {rx_shift[6:0], MOSI};

  integer k;
  initial begin
    rx_shift = 8'hFF; bitc = 3'd0; cmdcnt = 3'd0; cmd = 6'd0; arg = 32'd0;
    st = ST_CMD; dcnt = 10'd0; ccnt = 2'd0; r7cnt = 2'd0; tx = 8'hFF; MISO = 1'b1;
    for (k = 0; k < 512; k = k + 1) sector_mem[k] = 8'h00;
  end

  //========== 采样 MOSI + 字节级状态机（DCLK 上升沿）==========
  always @(posedge DCLK) begin
    rx_shift <= rx_next;
    if (nCS) begin                       // 片选释放：等下一个命令
      bitc   <= 3'd0;
      cmdcnt <= 3'd0;
      st     <= ST_CMD;
      dcnt   <= 10'd0;
      ccnt   <= 2'd0;
      r7cnt  <= 2'd0;
    end else if (bitc == 3'd7) begin     // 收齐 8 bit
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
            case (cmd)                       // 命令号在前面已锁存
              6'd0 : tx <= 8'h01;
              6'd8 : tx <= 8'h01;
              6'd55: tx <= 8'h01;
              6'd41: tx <= 8'h00;
              6'd16: tx <= 8'h00;
              6'd17: tx <= 8'h00;
              default: tx <= 8'h00;
            endcase
          end else begin
            cmdcnt <= cmdcnt + 3'd1;
            tx     <= 8'hFF;                 // 命令字节期间 MISO 保持高
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
        ST_TOKEN: begin st <= ST_DATA; dcnt <= 10'd0; tx <= sector_mem[0]; end
        ST_DATA: begin
          if (dcnt == 10'd511) begin st <= ST_CRC; ccnt <= 2'd0; tx <= 8'hFF; end
          else begin dcnt <= dcnt + 10'd1; tx <= sector_mem[dcnt + 10'd1]; end
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
