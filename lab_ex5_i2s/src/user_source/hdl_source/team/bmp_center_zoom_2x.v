`timescale 1ns/1ps
// Load-time center zoom. Input is the unpausable BMP pixel pulse stream.
// Output is a complete, same-size frame in file row order (flip downstream).
// On overflow the frame is invalid; the controller must NOT commit it.
module bmp_center_zoom_2x #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter integer PACE_ZOOM_OUTPUT = 1
)(
    input clk,
    input rst,
    input frame_start,
    input zoom_enable,
    input in_valid,
    input [23:0] in_rgb,
    output out_valid,
    input out_ready,
    output [23:0] out_rgb,
    output out_last,
    output out_frame_last,
    output reg source_done,
    output reg output_done,
    output reg overflow
);
localparam CW = WIDTH/2;
localparam CH = HEIGHT/2;
localparam X0 = (WIDTH-CW)/2;
localparam Y0 = (HEIGHT-CH)/2;
reg zoom_latched;
reg source_active;
reg [15:0] x, y;
reg pass_valid;
reg [23:0] pass_rgb;
reg pass_last, pass_frame_last;
reg zoom_output_gap;
wire crop = x >= X0 && x < X0+CW && y >= Y0 && y < Y0+CH;
wire scale_in_ready, scale_valid, scale_last, scale_frame_last;
wire [23:0] scale_rgb;
wire local_reset = rst || frame_start;
wire enabled = !local_reset && !overflow && !output_done;
// A completed zoom transfer inserts one idle source clock before the next.
// Once valid is presented it stays presented while the consumer is stalled.
// Do not use this as a per-word SDRAM busy/ack substitute: the original FIFO
// and burst scheduler remain responsible for the memory interface.
wire zoom_output_allowed = !PACE_ZOOM_OUTPUT || !zoom_output_gap;
assign out_valid = enabled && (zoom_latched ? (scale_valid && zoom_output_allowed) : pass_valid);
assign out_rgb = zoom_latched ? scale_rgb : pass_rgb;
assign out_last = zoom_latched ? scale_last : pass_last;
assign out_frame_last = zoom_latched ? scale_frame_last : pass_frame_last;

image_scaler_2x_pingpong #(.SRC_WIDTH(CW), .SRC_HEIGHT(CH)) scaler (
    .clk(clk), .rst(local_reset),
    .in_valid(in_valid && source_active && crop && zoom_latched && enabled),
    .in_ready(scale_in_ready), .in_rgb(in_rgb),
    .out_valid(scale_valid), .out_ready(out_ready && enabled && zoom_latched && zoom_output_allowed),
    .out_rgb(scale_rgb), .out_last(scale_last),
    .out_frame_last(scale_frame_last)
);

always @(posedge clk or posedge rst) begin
    if (rst)
        zoom_output_gap <= 1'b0;
    else if (frame_start)
        zoom_output_gap <= 1'b0;
    else
        zoom_output_gap <= PACE_ZOOM_OUTPUT && zoom_latched && out_valid && out_ready;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        zoom_latched <= 0;
        source_active <= 0;
        x <= 0; y <= 0;
        pass_valid <= 0; pass_rgb <= 0;
        pass_last <= 0; pass_frame_last <= 0;
        source_done <= 0; output_done <= 0; overflow <= 0;
    end else if (frame_start) begin
        zoom_latched <= zoom_enable;
        source_active <= 1;
        x <= 0; y <= 0;
        pass_valid <= 0;
        source_done <= 0; output_done <= 0; overflow <= 0;
    end else begin
        if (pass_valid && out_ready && enabled && !zoom_latched)
            pass_valid <= 0;
        if (out_valid && out_ready && out_frame_last)
            output_done <= 1;
        if (in_valid && source_active) begin
            if (x == WIDTH-1) begin
                x <= 0;
                if (y == HEIGHT-1) begin
                    source_active <= 0;
                    source_done <= 1;
                end else y <= y+1'b1;
            end else x <= x+1'b1;
            if (!overflow) begin
                if (zoom_latched) begin
                    if (crop && !scale_in_ready) overflow <= 1;
                end else if (pass_valid && !out_ready) begin
                    overflow <= 1;
                end else begin
                    pass_valid <= 1;
                    pass_rgb <= in_rgb;
                    pass_last <= x == WIDTH-1;
                    pass_frame_last <= x == WIDTH-1 && y == HEIGHT-1;
                end
            end
        end
    end
end
endmodule
