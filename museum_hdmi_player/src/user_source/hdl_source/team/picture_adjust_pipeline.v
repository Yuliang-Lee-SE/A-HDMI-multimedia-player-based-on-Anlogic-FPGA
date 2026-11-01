`timescale 1ns/1ps

// One-pixel-stream picture processor. Contrast is relative to 50% gray and
// sharpness uses a causal three-tap high-pass response. RGB and timing are
// both delayed by one pixel clock.
module picture_adjust_pipeline (
    input             clk,
    input             rst,
    input      [23:0] rgb_in,
    input             hs_in,
    input             vs_in,
    input             de_in,
    input signed [7:0] brightness_i,
    input      [7:0]  contrast_i,
    input      [3:0]  sharpness_i,
    output reg [23:0] rgb_out,
    output reg        hs_out,
    output reg        vs_out,
    output reg        de_out
);

function [7:0] apply_tone;
    input [7:0] pixel;
    input signed [7:0] offset;
    input [7:0] gain_q7;
    reg signed [10:0] centered;
    reg signed [15:0] contrast_wide;
    reg signed [20:0] product;
    reg signed [20:0] summed;
    begin
        centered = $signed({1'b0, pixel}) - 11'sd128;
        contrast_wide = $signed({8'd0, gain_q7});
        product  = centered * contrast_wide;
        summed   = (product >>> 7) + 21'sd128 +
                   $signed({{13{offset[7]}}, offset});
        if (summed < 0)
            apply_tone = 8'd0;
        else if (summed > 21'sd255)
            apply_tone = 8'hFF;
        else
            apply_tone = summed[7:0];
    end
endfunction

function [7:0] apply_sharp;
    input [7:0] current;
    input [7:0] previous;
    input [7:0] older;
    input [3:0] amount;
    reg signed [10:0] high_pass;
    reg signed [15:0] amount_wide;
    reg signed [14:0] blended;
    begin
        high_pass = ($signed({1'b0, current}) <<< 1) -
                    $signed({1'b0, previous}) -
                    $signed({1'b0, older});
        amount_wide = $signed({12'd0, amount});
        blended   = $signed({1'b0, current}) +
                    ((high_pass * amount_wide) >>> 3);
        if (blended < 0)
            apply_sharp = 8'd0;
        else if (blended > 15'sd255)
            apply_sharp = 8'hFF;
        else
            apply_sharp = blended[7:0];
    end
endfunction

// Map the displayed 50..150 percent range to an exact Q7 gain around neutral
// 128. This keeps the default 100 percent setting bit-exact.
function [7:0] contrast_to_gain;
    input [7:0] displayed_contrast;
    begin
        case (displayed_contrast)
            8'd50:  contrast_to_gain = 8'd64;
            8'd60:  contrast_to_gain = 8'd77;
            8'd70:  contrast_to_gain = 8'd90;
            8'd80:  contrast_to_gain = 8'd102;
            8'd90:  contrast_to_gain = 8'd115;
            8'd100: contrast_to_gain = 8'd128;
            8'd110: contrast_to_gain = 8'd141;
            8'd120: contrast_to_gain = 8'd154;
            8'd130: contrast_to_gain = 8'd166;
            8'd140: contrast_to_gain = 8'd179;
            8'd150: contrast_to_gain = 8'd192;
            default: contrast_to_gain = 8'd128;
        endcase
    end
endfunction

wire [7:0] gain_q7 = contrast_to_gain(contrast_i);

wire [23:0] tone_rgb = {
    apply_tone(rgb_in[23:16], brightness_i, gain_q7),
    apply_tone(rgb_in[15:8],  brightness_i, gain_q7),
    apply_tone(rgb_in[7:0],   brightness_i, gain_q7)
};

reg [23:0] tone_previous_1;
reg [23:0] tone_previous_2;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        rgb_out         <= 24'd0;
        hs_out          <= 1'b0;
        vs_out          <= 1'b0;
        de_out          <= 1'b0;
        tone_previous_1 <= 24'd0;
        tone_previous_2 <= 24'd0;
    end else begin
        hs_out <= hs_in;
        vs_out <= vs_in;
        de_out <= de_in;

        if (!de_in)
            rgb_out <= 24'd0;
        else
            rgb_out <= {
                apply_sharp(tone_rgb[23:16], tone_previous_1[23:16],
                            tone_previous_2[23:16], sharpness_i),
                apply_sharp(tone_rgb[15:8], tone_previous_1[15:8],
                            tone_previous_2[15:8], sharpness_i),
                apply_sharp(tone_rgb[7:0], tone_previous_1[7:0],
                            tone_previous_2[7:0], sharpness_i)
            };

        if (de_in) begin
            tone_previous_1 <= tone_rgb;
            tone_previous_2 <= tone_previous_1;
        end else begin
            tone_previous_1 <= 24'd0;
            tone_previous_2 <= 24'd0;
        end
    end
end

endmodule
