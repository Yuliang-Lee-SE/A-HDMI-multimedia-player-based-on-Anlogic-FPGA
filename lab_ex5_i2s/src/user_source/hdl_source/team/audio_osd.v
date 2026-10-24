`timescale 1ns/1ps
// Right-edge volume bar.
// Timing and RGB use the same one-cycle delay; no BRAM or multiplier is used.
module audio_osd #(
    parameter H_ACTIVE = 640,
    parameter V_ACTIVE = 480,
    parameter BAR_X    = 624,
    parameter BAR_TOP  = 240,
    parameter BAR_W    = 8,
    parameter SEG_H    = 12,
    parameter SEG_GAP  = 4,
    parameter SHOW_FRAMES = 120,
    parameter BAR_ON_COLOR  = 24'h00FF80,
    parameter BAR_OFF_COLOR = 24'h202020
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire [2:0]  vol_level,
    input  wire        vol_toggle,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [23:0] rgb_in,
    output reg         hs_out,
    output reg         vs_out,
    output reg         de_out,
    output reg  [23:0] rgb_out
);
    // The bar uses 16-pixel segment pitch: 12 visible rows and a 4-row gap.
    localparam integer SEG_PITCH = SEG_H + SEG_GAP;
    localparam [7:0]   SHOW_FRAMES8 = SHOW_FRAMES;

    // Multi-bit level and toggle cross from the SD clock to the video clock.
    reg [2:0] lvl_meta, lvl_sync;
    reg [2:0] tgl_sync;
    wire tgl_pulse = tgl_sync[2] ^ tgl_sync[1];

    // A 60 Hz frame counter needs eight bits instead of a 26-bit pixel counter.
    reg [7:0] hold_frames;
    reg       vs_timer_prev;
    wire      vs_timer_rise = vs_in && !vs_timer_prev;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lvl_meta      <= 3'd4;
            lvl_sync      <= 3'd4;
            tgl_sync      <= 3'b000;
            hold_frames   <= 8'd0;
            vs_timer_prev <= 1'b0;
        end else begin
            lvl_meta      <= vol_level;
            lvl_sync      <= lvl_meta;
            tgl_sync      <= {tgl_sync[1:0], vol_toggle};
            vs_timer_prev <= vs_in;

            if (tgl_pulse)
                hold_frames <= SHOW_FRAMES8;
            else if (vs_timer_rise && hold_frames != 8'd0)
                hold_frames <= hold_frames - 8'd1;
        end
    end

    // Reconstruct active-pixel coordinates from HS/VS/DE.
    reg [11:0] x, y;
    reg        de_prev, vs_prev;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            x       <= 12'd0;
            y       <= 12'd0;
            de_prev <= 1'b0;
            vs_prev <= 1'b0;
        end else begin
            de_prev <= de_in;
            vs_prev <= vs_in;
            if (vs_in && !vs_prev) begin
                x <= 12'd0;
                y <= 12'd0;
            end else if (de_in) begin
                if (x == H_ACTIVE - 1)
                    x <= 12'd0;
                else
                    x <= x + 12'd1;
            end else begin
                x <= 12'd0;
                if (de_prev && y < V_ACTIVE - 1)
                    y <= y + 12'd1;
            end
        end
    end

    // Four 8x12 segments. Fill increases from bottom to top.
    wire [11:0] bar_dy = y - BAR_TOP;
    wire in_bar = (x >= BAR_X) && (x < BAR_X + BAR_W) &&
                  (y >= BAR_TOP) && (y < BAR_TOP + 4*SEG_PITCH) &&
                  (bar_dy[3:0] < SEG_H);
    wire [2:0] bar_seg_from_bottom = 3'd3 - {1'b0, bar_dy[5:4]};
    wire bar_fill = lvl_sync > bar_seg_from_bottom;
    wire show_bar = (hold_frames != 8'd0) && (lvl_sync != 3'd0);

    // One-cycle registered output keeps HS/VS/DE and RGB aligned.
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
            else if (enable && show_bar && in_bar)
                rgb_out <= bar_fill ? BAR_ON_COLOR : BAR_OFF_COLOR;
            else
                rgb_out <= rgb_in;
        end
    end
endmodule
