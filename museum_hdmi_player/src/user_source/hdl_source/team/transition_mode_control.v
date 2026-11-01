`timescale 1ns/1ps

// KEY1 is shared between image advance and transition-mode configuration.
// A long press toggles configuration mode. While configuring, short presses
// cycle 0=hard cut, 1=slide, 2=blinds, 3=crossfade and do not advance images.
// Power-on defaults to mode 0 (hard cut).
module transition_mode_control #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS     = 1200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       key,
    output reg  [1:0] mode,
    output reg        setting_active,
    output reg        mode_change_toggle,
    output wire       next_press
);

wire short_pulse;
wire long_pulse;

key_short_long #(
    .CLK_FREQ_HZ (CLK_FREQ_HZ),
    .DEBOUNCE_MS (DEBOUNCE_MS),
    .LONG_MS     (LONG_MS)
) classify (
    .clk        (clk),
    .rst        (rst),
    .button_in  (key),
    .short_pulse(short_pulse),
    .long_pulse (long_pulse)
);

assign next_press = short_pulse && !setting_active;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        mode           <= 2'd0;
        setting_active <= 1'b0;
        mode_change_toggle <= 1'b0;
    end else begin
        if (long_pulse)
            setting_active <= ~setting_active;
        else if (short_pulse && setting_active) begin
            mode <= (mode == 2'd3) ? 2'd0 : mode + 2'd1;
            mode_change_toggle <= ~mode_change_toggle;
        end
    end
end

endmodule
