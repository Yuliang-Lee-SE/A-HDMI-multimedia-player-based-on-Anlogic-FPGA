`timescale 1ns/1ps
// 8 kHz signed-16 PCM player read from the narration RAM, driving the proven
// 48 kHz 64-bit-slot I2S transmit path.
module audio_pcm_player #(
    parameter integer ENABLE_MUTE = 0,
    parameter integer MCLK_HZ     = 12295000,
    parameter integer SRC_HZ      = 8000,
    parameter integer RAMP_FRAMES = 960
)(
    input  wire        I_mclk,
    input  wire        I_rst,
    input  wire [4:0]  I_track_idx,
    input  wire        I_enabled,
    input  wire        I_pcm_ready,
    input  wire [15:0] I_pcm_len,
    input  wire [2:0]  I_vol_level,
    input  wire        I_track_toggle,
    input  wire [15:0] I_pcm_data,
    output wire [14:0] O_pcm_addr,
    output reg         O_i2s_BCLK,
    output reg         O_i2s_LRCK,
    output reg         O_i2s_DOUT
);
    localparam integer GAIN_STEP = (255 * 256) / RAMP_FRAMES;
    localparam integer GAIN_FULL = 255 * 256;
    localparam integer SRC_INC   = SRC_HZ * 256;
    localparam [23:0] SRC_INC24  = SRC_INC;
    localparam [15:0] GAIN_FULL16 = GAIN_FULL;

    localparam [1:0] ST_FADE_IN = 2'd0;
    localparam [1:0] ST_IDLE    = 2'd1;
    localparam [1:0] ST_FADE_OUT= 2'd2;

    reg [4:0] idx_meta, idx_sync;
    reg [15:0] len_meta, len_sync;
    reg ready_meta, ready_sync;
    reg enabled_meta, enabled_sync, enabled_lat;
    reg [2:0] vol_meta, vol_sync;
    reg [2:0] tgl_sync;
    wire tgl_pulse = tgl_sync[2] ^ tgl_sync[1];

    reg [5:0] bit_cnt;
    reg [63:0] shift_reg;
    reg [23:0] sample_word, sample_next;
    reg [23:0] src_acc;
    reg [14:0] src_pos;
    reg [15:0] pcm_d;
    reg [15:0] gain_acc;
    reg [1:0] fade_state;
    reg sw_req;
    reg signed [23:0] lp1, lp2;

    wire [23:0] src_sum = src_acc + SRC_INC24;
    wire src_tick = (src_sum >= MCLK_HZ);
    wire [23:0] src_acc_next = src_tick ? (src_sum-MCLK_HZ) : src_sum;
    wire pos_last = ({1'b0,src_pos}+16'd1 >= len_sync);
    wire [14:0] pos_next = src_tick ?
                           (pos_last ? 15'd0 : src_pos+15'd1) : src_pos;
    wire signed [32:0] pcm_product =
        $signed(pcm_d) * $signed({1'b0,gain_acc});
    wire signed [23:0] faded = pcm_product >>> 8;

    assign O_pcm_addr = src_pos;

    reg signed [23:0] vol_out;
    always @(*) begin
        case (vol_sync)
            3'd0: vol_out = 24'sd0;
            3'd1: vol_out = faded >>> 2;
            3'd2: vol_out = faded >>> 1;
            3'd3: vol_out = (faded >>> 1) + (faded >>> 2);
            default: vol_out = faded;
        endcase
    end

    wire signed [23:0] source_out =
        ((ENABLE_MUTE && !enabled_lat) || !ready_sync) ? 24'sd0 : vol_out;
    wire signed [24:0] lp1_delta = source_out - lp1;
    wire signed [23:0] lp1_next = lp1 + (lp1_delta-(lp1_delta>>>2));
    wire signed [24:0] lp2_delta = lp1_next - lp2;
    wire signed [23:0] lp2_next = lp2 + (lp2_delta-(lp2_delta>>>2));

    wire [15:0] gain_dn =
        (gain_acc>GAIN_STEP) ? (gain_acc-GAIN_STEP) : 16'd0;
    wire [16:0] gain_up_sum = gain_acc+GAIN_STEP;
    wire [15:0] gain_up =
        (gain_up_sum>=GAIN_FULL) ? GAIN_FULL16 : gain_up_sum[15:0];

    always @(posedge I_mclk or posedge I_rst) begin
        if (I_rst) begin
            O_i2s_BCLK<=0; O_i2s_LRCK<=0; O_i2s_DOUT<=0; bit_cnt<=0;
            shift_reg<=0; sample_word<=0; sample_next<=0;
            idx_meta<=0; idx_sync<=0;
            len_meta<=0; len_sync<=0; ready_meta<=0; ready_sync<=0;
            enabled_meta<=0; enabled_sync<=0; enabled_lat<=0;
            vol_meta<=4; vol_sync<=4; tgl_sync<=0;
            src_acc<=0; src_pos<=0; pcm_d<=0; gain_acc<=0;
            fade_state<=ST_FADE_IN; sw_req<=0;
            lp1<=0; lp2<=0;
        end else begin
            idx_meta<=I_track_idx; idx_sync<=idx_meta;
            len_meta<=I_pcm_len; len_sync<=len_meta;
            ready_meta<=I_pcm_ready; ready_sync<=ready_meta;
            enabled_meta<=I_enabled; enabled_sync<=enabled_meta;
            vol_meta<=I_vol_level; vol_sync<=vol_meta;
            tgl_sync<={tgl_sync[1:0],I_track_toggle};
            pcm_d<=I_pcm_data;
            if(tgl_pulse) sw_req<=1;

            O_i2s_BCLK<=~O_i2s_BCLK;
            if(O_i2s_BCLK==1'b1) begin
                O_i2s_DOUT<=shift_reg[63];
                shift_reg<={shift_reg[62:0],1'b0};
                if(bit_cnt==6'd63) begin
                    bit_cnt<=0;
                    if(O_i2s_LRCK==0) begin
                        O_i2s_LRCK<=1;
                        shift_reg<={sample_word,40'd0};
                    end else begin
                        O_i2s_LRCK<=0;
                        if(fade_state==ST_IDLE) begin
                            if(sw_req) begin
                                fade_state<=ST_FADE_OUT;
                                gain_acc<=gain_dn;
                                sw_req<=0;
                            end
                        end else if(fade_state==ST_FADE_OUT) begin
                            if(gain_acc<=GAIN_STEP) begin
                                gain_acc<=0;
                                fade_state<=ST_FADE_IN;
                                enabled_lat<=enabled_sync;
                                src_pos<=0;
                                src_acc<=0;
                            end else gain_acc<=gain_dn;
                        end else begin
                            if(gain_up>=GAIN_FULL16) begin
                                gain_acc<=GAIN_FULL16;
                                fade_state<=ST_IDLE;
                            end else gain_acc<=gain_up;
                        end

                        if(fade_state!=ST_FADE_OUT) begin
                            src_acc<=src_acc_next;
                            src_pos<=pos_next;
                        end
                        lp1<=lp1_next;
                        lp2<=lp2_next;
                        sample_next<=lp2_next;
                        sample_word<=sample_next;
                        shift_reg<={lp2_next,40'd0};
                    end
                end else bit_cnt<=bit_cnt+1;
            end
        end
    end
endmodule
