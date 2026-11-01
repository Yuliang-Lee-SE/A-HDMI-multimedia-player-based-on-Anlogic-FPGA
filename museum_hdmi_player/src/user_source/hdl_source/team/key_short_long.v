`timescale 1ns/1ps
// KEY3 short/long press classifier. Input is active-low.
// A short release pulses after debounce; holding for LONG_MS emits one pulse.
module key_short_long #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_MS     = 1200
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,
    output reg  short_pulse,
    output reg  long_pulse
);
    localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer LONG_CYCLES     = (CLK_FREQ_HZ / 1000) * LONG_MS;

    reg        sync0, sync1, stable;
    reg [20:0] db_cnt;
    reg [26:0] hold_cnt;
    reg        long_fired;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync0       <= 1'b1;
            sync1       <= 1'b1;
            stable      <= 1'b1;
            db_cnt      <= 21'd0;
            hold_cnt    <= 27'd0;
            long_fired  <= 1'b0;
            short_pulse <= 1'b0;
            long_pulse  <= 1'b0;
        end else begin
            sync0       <= button_in;
            sync1       <= sync0;
            short_pulse <= 1'b0;
            long_pulse  <= 1'b0;

            if (sync1 == stable)
                db_cnt <= 21'd0;
            else if (db_cnt >= DEBOUNCE_CYCLES - 1) begin
                db_cnt <= 21'd0;
                stable <= sync1;
                if (!stable && sync1 && !long_fired)
                    short_pulse <= 1'b1;
            end else
                db_cnt <= db_cnt + 21'd1;

            if (!stable) begin
                if (!long_fired) begin
                    if (hold_cnt >= LONG_CYCLES - 1) begin
                        long_fired <= 1'b1;
                        long_pulse <= 1'b1;
                    end else
                        hold_cnt <= hold_cnt + 27'd1;
                end
            end else begin
                hold_cnt   <= 27'd0;
                long_fired <= 1'b0;
            end
        end
    end
endmodule
