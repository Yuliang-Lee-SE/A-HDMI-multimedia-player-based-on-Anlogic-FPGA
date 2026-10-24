`timescale 1ns/1ps
//======================================================================
// audio_rom_player.v                                   角色 C
//
// 功能：片内 ROM 语音播放器 + I2S 发送（替换 hdmi_audio_tone_i2s_64fs 的测试音源）
//
// 为什么不直接改 hdmi_audio_tone_i2s_64fs：
//   该模块与 I2S_receiver / audio_arc_calculate 构成一条已上板验证的链路：
//     audio_mclk(12.295MHz) -> I2S(BCLK=MCLK/2, LRCK=MCLK/256=48kHz, 每声道 64bit)
//       -> I2S_receiver(video_clk 域三拍同步) -> audio_valid(48kHz)
//       -> audio_arc_calculate(ACR_N=6144) -> HDMI 核
//   ACR 的 CTS 是数 audio_valid 的速率算出来的，所以音频源必须始终保持
//   "每声道 64bit、LRCK=48kHz" 的帧率。本模块完整保留这套 I2S 时序，
//   只把样本来源从内部方波换成 ROM。
//
// 采样率：素材 8kHz，每 6 个 48kHz 帧取一次新样点（零阶保持）。
//   推进节拍用分数累加器按实际 MCLK 计算，得到精确的 8.000kHz：
//       acc += SRC_HZ*256 ;  acc >= MCLK_HZ 时推进并 acc -= MCLK_HZ
//   （*256 是为了避开除法，MCLK_HZ 直接取 PLL 实际频率）
//
// 切段：I_track_toggle 翻转表示"换素材"，播放器先 20ms 淡出、切段、
//   再 20ms 淡入，避免切换爆音。淡入淡出用 8bit×8bit 乘法（≤1 个 DSP）。
//
// 复位：高有效（rst_all），异步复位、同步释放，与接口约束文档 1.2 一致。
//======================================================================
module audio_rom_player #(
    parameter integer ENABLE_MUTE=0,
    parameter integer MCLK_HZ     = 12295000,  // PLL_HDMI_AUDIO C2 实际输出（文档 2.1 节）
    parameter integer SRC_HZ      = 8000,      // 素材采样率
    parameter integer SEG_SAMPLES = 12288,     // 每段样点数 = 1.536s @ 8kHz
    parameter [15:0]  TRACK0_ADDR = 16'd0,
    parameter [15:0]  TRACK1_ADDR = 16'd12288,
    parameter [15:0]  TRACK2_ADDR = 16'd24576,
    parameter [15:0]  TRACK3_ADDR = 16'd36864,
    parameter integer RAMP_FRAMES = 960,       // 20ms @ 48kHz
    parameter integer LOOP_EN     = 1          // 1=播完循环，0=播完停在末样点
)(
    input  wire        I_mclk,          // 12.295MHz 音频主时钟
    input  wire        I_rst,           // 高有效
    input  wire [1:0]  I_track_idx,     // 来自 sd_card_clk 域，稳定电平
    input wire I_enabled,
    input  wire [2:0]  I_vol_level,     // 0=静音,1=25%,2=50%,3=75%,4=100%（sd_card_clk 域）
    input  wire        I_track_toggle,  // 来自 sd_card_clk 域，换段时翻转
    input  wire [7:0]  I_rom_data,      // ROM 读数据（有符号 8bit PCM）
    output wire [15:0] O_rom_addr,      // ROM 读地址
    output reg         O_i2s_BCLK,      // = MCLK/2 = 6.144MHz
    output reg         O_i2s_LRCK,      // = MCLK/256 = 48kHz
    output reg         O_i2s_DOUT
);

    //------------------------------------------------------------------
    // 常数
    //------------------------------------------------------------------
    localparam integer GAIN_STEP  = (255 * 256) / RAMP_FRAMES;  // 20ms 走完 255 级
    localparam integer GAIN_FULL  = 255 * 256;                  // 65280
    localparam integer SRC_INC    = SRC_HZ * 256;               // 分数累加器步进
    localparam integer POS_W      = 14;                         // 12288 -> 14bit
    localparam [23:0] SRC_INC24   = SRC_INC;      // 显式收窄，避免工具对参数位选处理不一致
    localparam [15:0] GAIN_FULL16 = GAIN_FULL;

    localparam [1:0] ST_FADE_IN = 2'd0;
    localparam [1:0] ST_IDLE    = 2'd1;
    localparam [1:0] ST_FADE_OUT= 2'd2;

    //------------------------------------------------------------------
    // 跨域同步：索引打两拍，toggle 打三拍取边沿
    //------------------------------------------------------------------
    reg [1:0] S_idx_meta,S_idx_sync;
    reg enabled_meta,enabled_sync,enabled_lat;
    reg [2:0] vol_meta, vol_sync;      // 音量档位（准静态，打两拍）
    reg  [2:0] S_tgl_sync;
    wire       S_tgl_pulse = S_tgl_sync[2] ^ S_tgl_sync[1];

    //------------------------------------------------------------------
    // I2S 发送状态
    //------------------------------------------------------------------
    reg  [5:0]  S_bit_cnt;
    reg  [63:0] S_shift_reg;
    reg  [23:0] S_sample_word;
    reg  [23:0] S_sample_next;

    //------------------------------------------------------------------
    // 音频源状态
    //------------------------------------------------------------------
    reg  [23:0] S_src_acc;        // 8kHz 推进累加器
    reg  [POS_W-1:0] S_pos;       // 段内样点位置
    reg  [1:0]  S_track_lat;      // 当前段号
    reg  [15:0] S_track_base;     // 当前段起始地址

    reg  [15:0] S_gain_acc;       // 8.8 定点增益，[15:8] 为实际增益
    reg  [1:0]  S_fade_state;
    reg         S_sw_req;         // 换段请求（toggle 边沿置位，切完清零）

    reg  [7:0]  S_rom_d;          // ROM 数据延迟一拍，保证地址与数据对齐

    wire [7:0]  S_gain = S_gain_acc[15:8];

    // 源推进（分数累加器）
    wire [23:0] S_src_sum  = S_src_acc + SRC_INC24;
    wire        S_src_tick = (S_src_sum >= MCLK_HZ);
    wire [23:0] S_src_acc_next = S_src_tick ? (S_src_sum - MCLK_HZ) : S_src_sum;

    wire        S_pos_last = (S_pos == SEG_SAMPLES - 1);
    wire [POS_W-1:0] S_pos_next = S_src_tick
                                ? (S_pos_last ? (LOOP_EN ? {POS_W{1'b0}} : S_pos)
                                              : (S_pos + 1'b1))
                                : S_pos;

    // 增益斜坡
    wire [15:0] S_gain_dn = (S_gain_acc > GAIN_STEP) ? (S_gain_acc - GAIN_STEP) : 16'd0;
    wire [16:0] S_gain_up_sum = S_gain_acc + GAIN_STEP;
    wire [15:0] S_gain_up = (S_gain_up_sum >= GAIN_FULL) ? GAIN_FULL16
                                                         : S_gain_up_sum[15:0];

    // 8bit 有符号样本 × 8bit 增益 -> 24bit 样本（左移 8 位对齐到 24bit 满量程）
    wire signed [7:0]  S_s8  = S_rom_d;
    wire signed [15:0] S_mul = S_s8 * $signed({1'b0, S_gain});
    wire signed [23:0] S_mul_ext = {{8{S_mul[15]}}, S_mul};
    // 淡入淡出后的 24bit 样本
    wire signed [23:0] S_fade = S_mul_ext <<< 8;
    // 音量：只用移位和一次加法（75%），不增加乘法器
    reg  signed [23:0] S_vol;
    always @(*) begin
        case (vol_sync)
            3'd0:    S_vol = 24'sd0;                              // 静音
            3'd1:    S_vol = S_fade >>> 2;                        // 25%
            3'd2:    S_vol = S_fade >>> 1;                        // 50%
            3'd3:    S_vol = (S_fade >>> 1) + (S_fade >>> 2);     // 75%
            default: S_vol = S_fade;                              // 100%
        endcase
    end
    wire signed [23:0] S_out = (ENABLE_MUTE && !enabled_lat) ? 24'sd0 : S_vol;

    assign O_rom_addr = S_track_base + {{(16-POS_W){1'b0}}, S_pos};

    //------------------------------------------------------------------
    // 主时序：I2S 时序与 hdmi_audio_tone_i2s_64fs 完全一致
    //------------------------------------------------------------------
    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            O_i2s_BCLK    <= 1'b0;
            O_i2s_LRCK    <= 1'b0;
            O_i2s_DOUT    <= 1'b0;
            S_bit_cnt     <= 6'd0;
            S_shift_reg   <= 64'd0;
            S_sample_word <= 24'sd0;
            S_sample_next <= 24'sd0;

            S_idx_sync    <= 2'd0;S_idx_meta<=0;enabled_meta<=0;enabled_sync<=0;enabled_lat<=0;
            vol_meta <= 3'd4; vol_sync <= 3'd4;
            S_tgl_sync    <= 3'b000;
            S_rom_d       <= 8'd0;

            S_src_acc     <= 24'd0;
            S_pos         <= {POS_W{1'b0}};
            S_track_lat   <= 2'd0;
            S_track_base  <= TRACK0_ADDR;

            S_gain_acc    <= 16'd0;      // 复位后从 0 淡入，避免上电爆音
            S_fade_state  <= ST_FADE_IN;
            S_sw_req      <= 1'b0;
        end else begin
            // 跨域同步链
            S_idx_meta<=I_track_idx;S_idx_sync<=S_idx_meta;
            enabled_meta<=I_enabled;enabled_sync<=enabled_meta;
            vol_meta<=I_vol_level;vol_sync<=vol_meta;
            S_tgl_sync <= {S_tgl_sync[1:0], I_track_toggle};
            S_rom_d    <= I_rom_data;

            if (S_tgl_pulse)
                S_sw_req <= 1'b1;

            // I2S 位时钟：每个 MCLK 翻转一次 => BCLK = MCLK/2
            O_i2s_BCLK <= ~O_i2s_BCLK;

            if (O_i2s_BCLK == 1'b1) begin
                O_i2s_DOUT  <= S_shift_reg[63];
                S_shift_reg <= {S_shift_reg[62:0], 1'b0};

                if (S_bit_cnt == 6'd63) begin
                    S_bit_cnt <= 6'd0;

                    if (O_i2s_LRCK == 1'b0) begin
                        // 左声道发完 -> 右声道复用同一采样
                        O_i2s_LRCK  <= 1'b1;
                        S_shift_reg <= {S_sample_word[23:0], 40'd0};
                    end else begin
                        // 右声道发完 -> 一个完整帧结束，推进音频源
                        O_i2s_LRCK <= 1'b0;

                        // ---- 增益状态机（每帧一步）----
                        if (S_fade_state == ST_IDLE) begin
                            if (S_sw_req) begin
                                S_fade_state <= ST_FADE_OUT;
                                S_gain_acc   <= S_gain_dn;
                                S_sw_req     <= 1'b0;
                            end
                        end else if (S_fade_state == ST_FADE_OUT) begin
                            if (S_gain_acc <= GAIN_STEP) begin
                                // 已淡到 0：切换段、回到段首、开始淡入
                                S_gain_acc   <= 16'd0;
                                S_fade_state <= ST_FADE_IN;
                                S_pos        <= {POS_W{1'b0}};
                                S_src_acc    <= 24'd0;
                                S_track_lat  <= S_idx_sync;enabled_lat<=enabled_sync;
                                case (S_idx_sync)
                                    2'd0: S_track_base <= TRACK0_ADDR;
                                    2'd1: S_track_base <= TRACK1_ADDR;
                                    2'd2: S_track_base <= TRACK2_ADDR;
                                    default: S_track_base <= TRACK3_ADDR;
                                endcase
                            end else
                                S_gain_acc <= S_gain_dn;
                        end else begin // ST_FADE_IN
                            if (S_gain_up >= GAIN_FULL16) begin
                                S_gain_acc   <= GAIN_FULL16;
                                S_fade_state <= ST_IDLE;
                            end else
                                S_gain_acc <= S_gain_up;
                        end

                        // ---- 音频源推进（淡出期间保持当前样点）----
                        if (S_fade_state != ST_FADE_OUT) begin
                            S_src_acc <= S_src_acc_next;
                            S_pos     <= S_pos_next;
                        end

                        // ---- 下一个 24bit 采样 ----
                        S_sample_next <= S_out;
                        S_sample_word <= S_sample_next;
                        S_shift_reg   <= {S_out[23:0], 40'd0};
                    end
                end else
                    S_bit_cnt <= S_bit_cnt + 6'd1;
            end
        end
    end

endmodule
