`timescale 1ns/1ps

// Physical-key mapping at the top level:
// KEY4 (C1) short: AUTO/PLAY, long: enter/leave picture menu
// KEY4 short in menu: next parameter
// KEY3 (B1): increment parameter in menu
// KEY2 (B2): decrement parameter in menu
module picture_adjust_controller #(
    parameter integer CLK_FREQ_HZ   = 25_000_000,
    parameter integer DEBOUNCE_MS   = 20,
    parameter integer LONG_PRESS_MS = 800,
    parameter integer AUTO_KEY_MS   = 30
)(
    input             clk,
    input             rst,
    input             key4,
    input             key3,
    input             key2,
    output reg        adjust_mode,
    output reg [1:0]  parameter_index,
    output reg signed [7:0] brightness,
    output reg [7:0]  contrast,
    output reg [3:0]  sharpness,
    output reg        auto_key_o,
    output reg [4:0]  rotation_period_s,
    output reg        rotation_period_toggle
);

localparam integer DEBOUNCE_TICKS =
    (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
localparam integer LONG_PRESS_TICKS =
    (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;
localparam integer AUTO_KEY_TICKS =
    (CLK_FREQ_HZ / 1000) * AUTO_KEY_MS;

reg [1:0]  k4_sync;
reg        k4_stable;
reg [23:0] k4_debounce_count;
reg [26:0] k4_hold_count;
reg        k4_long_fired;
reg [26:0] auto_key_count;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        k4_sync           <= 2'b11;
        k4_stable         <= 1'b1;
        k4_debounce_count <= 24'd0;
        k4_hold_count     <= 27'd0;
        k4_long_fired     <= 1'b0;
        auto_key_count    <= 27'd0;
        auto_key_o        <= 1'b1;
        adjust_mode       <= 1'b0;
        parameter_index   <= 2'd0;
    end else begin
        k4_sync <= {k4_sync[0], key4};

        if (auto_key_count != 27'd0) begin
            auto_key_count <= auto_key_count - 27'd1;
            auto_key_o     <= 1'b0;
        end else begin
            auto_key_o <= 1'b1;
        end

        if (k4_sync[1] == k4_stable) begin
            k4_debounce_count <= 24'd0;
        end else if (k4_debounce_count >= DEBOUNCE_TICKS - 1) begin
            k4_debounce_count <= 24'd0;
            k4_stable         <= k4_sync[1];
            if (k4_sync[1] == 1'b0) begin
                k4_hold_count <= 27'd0;
                k4_long_fired <= 1'b0;
            end else if (!k4_long_fired) begin
                if (adjust_mode) begin
                    if (parameter_index == 2'd3)
                        parameter_index <= 2'd0;
                    else
                        parameter_index <= parameter_index + 2'd1;
                end else begin
                    // The existing SD-domain AUTO key debounce is 20 ms.
                    auto_key_count <= AUTO_KEY_TICKS;
                    auto_key_o     <= 1'b0;
                end
            end
        end else begin
            k4_debounce_count <= k4_debounce_count + 24'd1;
        end

        if (!k4_stable && !k4_long_fired) begin
            if (k4_hold_count >= LONG_PRESS_TICKS - 1) begin
                k4_long_fired <= 1'b1;
                if (adjust_mode)
                    adjust_mode <= 1'b0;
                else begin
                    adjust_mode     <= 1'b1;
                    parameter_index <= 2'd0;
                end
            end else begin
                k4_hold_count <= k4_hold_count + 27'd1;
            end
        end
    end
end

reg [1:0]  k3_sync;
reg        k3_stable;
reg [23:0] k3_debounce_count;
reg        k3_increment;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        k3_sync           <= 2'b11;
        k3_stable         <= 1'b1;
        k3_debounce_count <= 24'd0;
        k3_increment      <= 1'b0;
    end else begin
        k3_increment <= 1'b0;
        k3_sync <= {k3_sync[0], key3};
        if (k3_sync[1] == k3_stable) begin
            k3_debounce_count <= 24'd0;
        end else if (k3_debounce_count >= DEBOUNCE_TICKS - 1) begin
            k3_debounce_count <= 24'd0;
            k3_stable         <= k3_sync[1];
            if (!k3_sync[1] && adjust_mode)
                k3_increment <= 1'b1;
        end else begin
            k3_debounce_count <= k3_debounce_count + 24'd1;
        end
    end
end

reg [1:0]  k2_sync;
reg        k2_stable;
reg [23:0] k2_debounce_count;
reg        k2_decrement;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        k2_sync           <= 2'b11;
        k2_stable         <= 1'b1;
        k2_debounce_count <= 24'd0;
        k2_decrement      <= 1'b0;
    end else begin
        k2_decrement <= 1'b0;
        k2_sync <= {k2_sync[0], key2};
        if (k2_sync[1] == k2_stable) begin
            k2_debounce_count <= 24'd0;
        end else if (k2_debounce_count >= DEBOUNCE_TICKS - 1) begin
            k2_debounce_count <= 24'd0;
            k2_stable         <= k2_sync[1];
            if (!k2_sync[1] && adjust_mode)
                k2_decrement <= 1'b1;
        end else begin
            k2_debounce_count <= k2_debounce_count + 24'd1;
        end
    end
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        brightness <= 8'sd0;
        contrast   <= 8'd100;
        sharpness  <= 4'd0;
        rotation_period_s <= 5'd3;
        rotation_period_toggle <= 1'b0;
    end else if (k3_increment) begin
        case (parameter_index)
            2'd0: if (brightness < 8'sd64)
                      brightness <= brightness + 8'sd8;
            2'd1: if (contrast < 8'd150)
                      contrast <= contrast + 8'd10;
            2'd2: if (sharpness < 4'd8)
                      sharpness <= sharpness + 4'd1;
            default: if (rotation_period_s < 5'd30) begin
                         rotation_period_s <= rotation_period_s + 5'd1;
                         rotation_period_toggle <= ~rotation_period_toggle;
                     end
        endcase
    end else if (k2_decrement) begin
        case (parameter_index)
            2'd0: if (brightness > -8'sd64)
                      brightness <= brightness - 8'sd8;
            2'd1: if (contrast > 8'd50)
                      contrast <= contrast - 8'd10;
            2'd2: if (sharpness > 4'd0)
                      sharpness <= sharpness - 4'd1;
            default: if (rotation_period_s > 5'd1) begin
                         rotation_period_s <= rotation_period_s - 5'd1;
                         rotation_period_toggle <= ~rotation_period_toggle;
                     end
        endcase
    end
end

endmodule
