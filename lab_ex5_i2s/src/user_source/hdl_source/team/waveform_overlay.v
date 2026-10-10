`timescale 1ns/1ps
//======================================================================
// waveform_overlay.v                                   角色 C · 阶段 3
//
// 音频可视化第一步：时域波形叠加层。
//   位置：串在 B 的 osd_overlay 之后（hs/vs/de/rgb 全部 1 拍延迟对齐），
//         只改像素内容，不动别人的模块。
//   数据：直接用 I2S_receiver 输出的 audio_left_data（本来就在 video_clk 域，
//         不需要再做跨时钟域）。
//   逻辑：每 6 个 48kHz 采样取一个包络值（=> 8kHz 列刷新率）写入 256 点环形
//         缓冲，屏幕上一列对应一个缓冲点，画成以中线为中心的竖条。
//         256 列 × 8kHz 就是"最近 32ms 的波形"。
//
// 资源：256×8bit = 2Kb，1 个 9Kb BRAM 块或若干 LUT；无乘法器、无 DSP。
//
// 使用（顶层里怎么接，见 doc/音频通路说明.md）：
//     osd_overlay -> waveform_overlay -> video_rgb_to_axis_640x480
//
// 写法说明（重要）：本文件刻意只用最保守的 Verilog-2001 写法——
//   1) 组合逻辑一律放在 always @(*) 里，包括波形缓冲的读出；
//      （早期版本写成 wire col_mag = buf[col_idx]; 在连续赋值里读存储器，
//        TD 6.2.1 没能正确绑定该模块，把它标成"未使用"自动排除，故改写）
//   2) 数组边界用 localparam 常量，不在边界里写移位表达式；
//   3) 乘法先声明足够宽的中间量（避免按 12 位上下文截断）。
//======================================================================
module waveform_overlay #(
    parameter H_ACTIVE   = 640,
    parameter V_ACTIVE   = 480,
    parameter WAV_X      = 64,      // 波形窗口左上角 x
    parameter WAV_Y      = 16,      // 波形窗口左上角 y
    parameter WAV_W      = 512,     // 窗口宽度（必须 = 缓冲点数 × 2）
    parameter WAV_H      = 72,      // 窗口高度
    parameter BUF_AW     = 8,       // 缓冲地址位宽，深度 = 2^BUF_AW = 256 点
    parameter DECIM      = 6,       // 48kHz -> 8kHz
    parameter BORDER_COLOR = 24'h404040,
    parameter AXIS_COLOR   = 24'h606060,
    parameter WAVE_COLOR   = 24'h00FFFF
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,          // 跟随 display_valid
    input  wire        audio_valid,     // 48kHz 采样有效
    input  wire [23:0] audio_sample,    // audio_left_data
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    output reg         hs_out,
    output reg         vs_out,
    output reg         de_out,
    output reg  [23:0] rgb_out
);

    localparam integer BUF_DEPTH = 256;         // = 2^BUF_AW，与 BUF_AW 保持一致
    localparam integer HALF_H    = WAV_H / 2;   // 36

    //------------------------------------------------------------------
    // 波形缓冲：每次 audio_valid 抽点，每 DECIM 个采样写一次
    //------------------------------------------------------------------
    reg [7:0]  buf [0:BUF_DEPTH-1];
    reg [BUF_AW-1:0] wr_ptr;
    reg [2:0]  dec_cnt;

    // 取绝对值包络：24bit 有符号样本 -> 高 8 位幅度
    wire [7:0] mag;
    assign mag = audio_sample[23] ? (~audio_sample[23:16] + 8'd1)
                                  : audio_sample[23:16];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr  <= {BUF_AW{1'b0}};
            dec_cnt <= 3'd0;
        end else if (audio_valid) begin
            if (dec_cnt == DECIM - 1) begin
                dec_cnt <= 3'd0;
                buf[wr_ptr] <= mag;
                wr_ptr <= wr_ptr + 1'b1;
            end else
                dec_cnt <= dec_cnt + 3'd1;
        end
    end

    //------------------------------------------------------------------
    // 像素坐标（与 osd_overlay 相同的做法）
    //------------------------------------------------------------------
    reg [11:0] x, y;
    reg        de_prev, vs_prev;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x <= 12'd0; y <= 12'd0;
            de_prev <= 1'b0; vs_prev <= 1'b0;
        end else begin
            de_prev <= de_in;
            vs_prev <= vs_in;

            if (vs_in && !vs_prev) begin
                x <= 12'd0;
                y <= 12'd0;
            end else if (de_in) begin
                if (x == H_ACTIVE - 1) x <= 12'd0;
                else                   x <= x + 12'd1;
            end else begin
                x <= 12'd0;
                if (de_prev && (y < V_ACTIVE - 1)) y <= y + 12'd1;
            end
        end
    end

    //------------------------------------------------------------------
    // 画波形：WAV_W = 2 × 256，所以列索引 = (x - WAV_X) >> 1
    //------------------------------------------------------------------
    wire [11:0] dx;
    wire [BUF_AW-1:0] col_idx;
    wire [19:0] mul20;
    wire [11:0] half_h;
    wire [11:0] cy;
    wire in_win, on_border, on_axis, on_wave;
    reg  [7:0] col_mag;

    assign dx      = x - WAV_X;
    assign col_idx = dx[BUF_AW:1];              // /2

    // 组合读缓冲：放在 always @(*) 里，综合成分布式 RAM 的一段读端口
    always @(*) begin
        col_mag = buf[col_idx];
    end

    // 半高 = col_mag/256 × HALF_H；先在 20 位上下文里乘，避免被截断
    assign mul20  = col_mag * HALF_H;
    assign half_h = mul20[19:8];
    assign cy     = WAV_Y + HALF_H;

    assign in_win  = (x >= WAV_X) && (x < (WAV_X + WAV_W)) &&
                     (y >= WAV_Y) && (y < (WAV_Y + WAV_H));
    assign on_border = in_win &&
                       ((x == WAV_X) || (x == (WAV_X + WAV_W - 1)) ||
                        (y == WAV_Y) || (y == (WAV_Y + WAV_H - 1)));
    assign on_axis   = in_win && (y == cy);
    assign on_wave   = in_win && (col_mag != 8'd0) &&
                       (y >= (cy - half_h)) && (y <= (cy + half_h));

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hs_out  <= 1'b0;
            vs_out  <= 1'b0;
            de_out  <= 1'b0;
            rgb_out <= 24'd0;
        end else begin
            hs_out <= hs_in;
            vs_out <= vs_in;
            de_out <= de_in;

            if (!de_in)
                rgb_out <= 24'd0;
            else if (enable && on_wave)
                rgb_out <= WAVE_COLOR;
            else if (enable && on_border)
                rgb_out <= BORDER_COLOR;
            else if (enable && on_axis)
                rgb_out <= AXIS_COLOR;
            else
                rgb_out <= rgb_in;
        end
    end

endmodule
