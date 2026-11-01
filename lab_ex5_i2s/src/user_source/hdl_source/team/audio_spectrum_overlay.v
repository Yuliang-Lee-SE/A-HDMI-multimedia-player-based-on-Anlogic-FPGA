`timescale 1ns/1ps
// 32-point audio spectrum overlay.
//
// The transform evaluates the 16 positive-frequency bins of a real 32-point
// DFT with one time-shared multiplier. For a 32-point input this is the same
// frequency result as a radix-2 FFT, but the sequential structure is smaller
// and avoids the read-after-write hazards of an inferred dual-port RAM.
module audio_spectrum_overlay #(
    parameter integer H_ACTIVE = 640,
    parameter integer V_ACTIVE = 480,
    parameter integer SPEC_X   = 472,
    parameter integer SPEC_Y   = 16,
    parameter integer SPEC_W   = 144,
    parameter integer SPEC_H   = 72,
    parameter integer BASE_Y   = 76
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        audio_valid,
    input  wire [23:0] audio_sample,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    output reg         hs_out,
    output reg         vs_out,
    output reg         de_out,
    output reg  [23:0] rgb_out
);
    localparam [2:0] S_CAPTURE = 3'd0;
    localparam [2:0] S_MUL_RE   = 3'd1;
    localparam [2:0] S_ACC_RE   = 3'd2;
    localparam [2:0] S_ACC_IM   = 3'd3;
    localparam integer BAR_AREA_H = 48;

    reg signed [15:0] sample_buf [0:31];
    reg [7:0] spec_bar [0:15];
    reg [8:0] sample_count;
    reg [4:0] capture_idx;
    reg [4:0] point_idx;
    reg [4:0] phase_index;
    reg [3:0] bin_idx;
    reg [2:0] state;
    reg signed [15:0] mul_a, mul_b;
    reg signed [22:0] acc_re, acc_im;
    integer spec_init_i;

    wire signed [15:0] sample_q = $signed(audio_sample[23:8]);
    wire signed [15:0] selected_sample = sample_buf[point_idx];
    wire signed [31:0] product = mul_a * mul_b;

    function signed [15:0] cos_q15;
        input [3:0] index;
        begin
            case (index)
                4'd0:  cos_q15=16'sd32767;
                4'd1:  cos_q15=16'sd32138;
                4'd2:  cos_q15=16'sd30274;
                4'd3:  cos_q15=16'sd27246;
                4'd4:  cos_q15=16'sd23170;
                4'd5:  cos_q15=16'sd18205;
                4'd6:  cos_q15=16'sd12540;
                4'd7:  cos_q15=16'sd6393;
                4'd8:  cos_q15=16'sd0;
                4'd9:  cos_q15=-16'sd6393;
                4'd10: cos_q15=-16'sd12540;
                4'd11: cos_q15=-16'sd18205;
                4'd12: cos_q15=-16'sd23170;
                4'd13: cos_q15=-16'sd27246;
                4'd14: cos_q15=-16'sd30274;
                default:cos_q15=-16'sd32138;
            endcase
        end
    endfunction

    function signed [15:0] sin_q15;
        input [3:0] index;
        begin
            case (index)
                4'd0:  sin_q15=16'sd0;
                4'd1:  sin_q15=16'sd6393;
                4'd2:  sin_q15=16'sd12540;
                4'd3:  sin_q15=16'sd18205;
                4'd4:  sin_q15=16'sd23170;
                4'd5:  sin_q15=16'sd27246;
                4'd6:  sin_q15=16'sd30274;
                4'd7:  sin_q15=16'sd32138;
                4'd8:  sin_q15=16'sd32767;
                4'd9:  sin_q15=16'sd32138;
                4'd10: sin_q15=16'sd30274;
                4'd11: sin_q15=16'sd27246;
                4'd12: sin_q15=16'sd23170;
                4'd13: sin_q15=16'sd18205;
                4'd14: sin_q15=16'sd12540;
                default:sin_q15=16'sd6393;
            endcase
        end
    endfunction

    function signed [15:0] cos32_q15;
        input [4:0] index;
        begin
            cos32_q15 = index[4] ? -cos_q15(index[3:0]) :
                                   cos_q15(index[3:0]);
        end
    endfunction

    function signed [15:0] sin32_q15;
        input [4:0] index;
        begin
            sin32_q15 = index[4] ? -sin_q15(index[3:0]) :
                                   sin_q15(index[3:0]);
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sample_count <= 9'd0;
            capture_idx  <= 5'd0;
            point_idx    <= 5'd0;
            phase_index  <= 5'd0;
            bin_idx      <= 4'd0;
            state        <= S_CAPTURE;
            mul_a        <= 16'sd0;
            mul_b        <= 16'sd0;
            acc_re       <= 23'sd0;
            acc_im       <= 23'sd0;
            for (spec_init_i=0; spec_init_i<16; spec_init_i=spec_init_i+1)
                spec_bar[spec_init_i] <= 8'd0;
        end else begin
            case (state)
                S_CAPTURE: begin
                    if (audio_valid) begin
                        if (sample_count[3:0]==4'd0) begin
                            sample_buf[capture_idx] <= sample_q;
                            capture_idx <= capture_idx + 5'd1;
                        end
                        if (sample_count==9'd511) begin
                            sample_count <= 9'd0;
                            capture_idx  <= 5'd0;
                            point_idx    <= 5'd0;
                            phase_index  <= 5'd0;
                            bin_idx      <= 4'd0;
                            acc_re       <= 23'sd0;
                            acc_im       <= 23'sd0;
                            state        <= S_MUL_RE;
                        end else begin
                            sample_count <= sample_count + 9'd1;
                        end
                    end
                end

                S_MUL_RE: begin
                    mul_a <= selected_sample;
                    mul_b <= cos32_q15(phase_index);
                    state <= S_ACC_RE;
                end

                S_ACC_RE: begin
                    acc_re <= acc_re + (product >>> 15);
                    mul_a <= selected_sample;
                    mul_b <= sin32_q15(phase_index);
                    state <= S_ACC_IM;
                end

                S_ACC_IM: begin
                    begin : finish_bin
                        reg signed [23:0] imag_now;
                        reg [23:0] abs_re;
                        reg [23:0] abs_im;
                        reg [23:0] magnitude;
                        reg [7:0] target;
                        imag_now = acc_im - (product >>> 15);
                        abs_re = acc_re[22] ? (24'sd0-acc_re) : acc_re;
                        abs_im = imag_now[23] ? (24'sd0-imag_now) : imag_now;
                        magnitude = (abs_re + abs_im) >>> 5;
                        target = (magnitude>=24'd32768) ? 8'd255 :
                                 magnitude[14:7];
                        if (point_idx==5'd31) begin
                            if (target>=spec_bar[bin_idx])
                                spec_bar[bin_idx] <= target;
                            else if (spec_bar[bin_idx]>=8'd4)
                                spec_bar[bin_idx] <= spec_bar[bin_idx]-8'd4;
                            else
                                spec_bar[bin_idx] <= 8'd0;
                        end
                    end

                    acc_im <= acc_im - (product >>> 15);
                    if (point_idx==5'd31) begin
                        point_idx   <= 5'd0;
                        phase_index <= 5'd0;
                        acc_re      <= 23'sd0;
                        acc_im      <= 23'sd0;
                        if (bin_idx==4'd15) begin
                            bin_idx <= 4'd0;
                            state <= S_CAPTURE;
                        end else begin
                            bin_idx <= bin_idx + 4'd1;
                            state <= S_MUL_RE;
                        end
                    end else begin
                        point_idx <= point_idx + 5'd1;
                        phase_index <= phase_index + {1'b0,bin_idx};
                        state <= S_MUL_RE;
                    end
                end

                default: state <= S_CAPTURE;
            endcase
        end
    end

    reg [11:0] x, y;
    reg de_prev, vs_prev;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x<=12'd0; y<=12'd0; de_prev<=1'b0; vs_prev<=1'b0;
        end else begin
            de_prev<=de_in; vs_prev<=vs_in;
            if (vs_in&&!vs_prev) begin
                x<=12'd0; y<=12'd0;
            end else if (de_in) begin
                x <= (x==H_ACTIVE-1) ? 12'd0 : x+12'd1;
            end else begin
                x<=12'd0;
                if (de_prev&&(y<V_ACTIVE-1)) y<=y+12'd1;
            end
        end
    end

    wire in_panel = (x>=SPEC_X)&&(x<SPEC_X+SPEC_W)&&
                    (y>=SPEC_Y)&&(y<SPEC_Y+SPEC_H);
    wire on_border = in_panel &&
                     ((x<SPEC_X+2)||(x>=SPEC_X+SPEC_W-2)||
                      (y<SPEC_Y+2)||(y>=SPEC_Y+SPEC_H-2));
    wire [11:0] local_x = x-(SPEC_X+8);
    wire in_bar_region = in_panel&&(local_x<128)&&
                         (y<BASE_Y)&&(y>=BASE_Y-BAR_AREA_H);
    wire [4:0] column = local_x[6:2];
    wire [3:0] bar_index = column[4] ? (4'd15-column[3:0]) : column[3:0];
    wire [6:0] bar_height = spec_bar[bar_index][7:1];
    wire on_bar = in_bar_region&&(local_x[1:0]<2'd3)&&
                  (y>=(BASE_Y-bar_height));
    wire on_axis = in_panel&&(y==BASE_Y);
    wire on_grid = in_bar_region &&
                   (((y==BASE_Y-12)||(y==BASE_Y-24)||
                     (y==BASE_Y-36)||(y==BASE_Y-48)) ||
                    (local_x[3:0]==4'd0));
    wire [7:0] bar_level = BASE_Y-y;
    wire [23:0] bar_color = (bar_level<8'd15)?24'h8C6E3D:
                            (bar_level<8'd29)?24'hB08A52:
                            (bar_level<8'd39)?24'hD2AC68:24'hE3C48A;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            hs_out<=1'b0; vs_out<=1'b0; de_out<=1'b0; rgb_out<=24'd0;
        end else begin
            hs_out<=hs_in; vs_out<=vs_in; de_out<=de_in;
            if (!de_in) rgb_out<=24'd0;
            else if (!enable) rgb_out<=rgb_in;
            else if (on_border) rgb_out<=24'h8F7958;
            else if (on_bar) rgb_out<=bar_color;
            else if (on_axis) rgb_out<=24'h6B5A43;
            else if (on_grid) rgb_out<=24'h2A261F;
            else if (in_panel) rgb_out<=24'h0C1014;
            else rgb_out<=rgb_in;
        end
    end
endmodule
