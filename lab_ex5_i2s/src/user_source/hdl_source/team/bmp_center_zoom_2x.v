`timescale 1ns/1ps
// Load-time center zoom. Input is the unpausable BMP pixel pulse stream.
// Output is a complete, same-size frame in file row order (flip downstream).
// On overflow the frame is invalid; the controller must NOT commit it.
module bmp_center_zoom_2x #(
    parameter integer WIDTH = 640,
    parameter integer HEIGHT = 480,
    parameter integer PACE_ZOOM_OUTPUT = 1,
    parameter integer ENABLE_HALF = 0
)(
    input clk,
    input rst,
    input frame_start,
    input zoom_enable,
    input half_enable,
    output source_permit,
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
reg half_latched;
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
wire half_valid, half_last, half_frame_last, half_overflow, half_permit;
wire [23:0] half_rgb;
assign source_permit = !half_latched || half_permit;
bmp_half_canvas #(.WIDTH(WIDTH), .HEIGHT(HEIGHT)) half_canvas (
 .clk(clk), .rst(local_reset), .active(half_latched && enabled),
 .in_valid(in_valid && source_active && half_latched && enabled), .in_rgb(in_rgb),
 .out_valid(half_valid), .out_ready(out_ready && enabled && half_latched && zoom_output_allowed),
 .out_rgb(half_rgb), .out_last(half_last), .out_frame_last(half_frame_last),
 .source_permit(half_permit), .overflow(half_overflow)
);
assign out_valid = enabled && (half_latched ? (half_valid && zoom_output_allowed) : zoom_latched ? (scale_valid && zoom_output_allowed) : pass_valid);
assign out_rgb = half_latched ? half_rgb : zoom_latched ? scale_rgb : pass_rgb;
assign out_last = half_latched ? half_last : zoom_latched ? scale_last : pass_last;
assign out_frame_last = half_latched ? half_frame_last : zoom_latched ? scale_frame_last : pass_frame_last;

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
        zoom_output_gap <= PACE_ZOOM_OUTPUT && (zoom_latched || half_latched) && out_valid && out_ready;
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
        zoom_latched <= 0;
        half_latched <= 0;
        source_active <= 0;
        x <= 0; y <= 0;
        pass_valid <= 0; pass_rgb <= 0;
        pass_last <= 0; pass_frame_last <= 0;
        source_done <= 0; output_done <= 0; overflow <= 0;
    end else if (frame_start) begin
        zoom_latched <= zoom_enable;
        half_latched <= ENABLE_HALF && half_enable;
        source_active <= 1;
        x <= 0; y <= 0;
        pass_valid <= 0;
        source_done <= 0; output_done <= 0; overflow <= 0;
    end else begin
        if (pass_valid && out_ready && enabled && !zoom_latched && !half_latched)
            pass_valid <= 0;
        if (out_valid && out_ready && out_frame_last)
            output_done <= 1;
        if (half_latched && half_overflow) overflow <= 1;
        if (in_valid && source_active) begin
            if (x == WIDTH-1) begin
                x <= 0;
                if (y == HEIGHT-1) begin
                    source_active <= 0;
                    source_done <= 1;
                end else y <= y+1'b1;
            end else x <= x+1'b1;
            if (!overflow) begin
                if (half_latched) begin
                    if (half_overflow) overflow <= 1;
                end else if (zoom_latched) begin
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

// Half-size nearest-neighbour canvas. Two reset-free BRAM lines.
// Bottom-up odd source rows become even displayed rows after vertical flip.
// The parser waits for source_permit AFTER releasing the FIFO request ACK.
module bmp_half_canvas #(parameter WIDTH=640, HEIGHT=480)(
 input clk, rst, active, in_valid, input [23:0] in_rgb,
 output reg out_valid, input out_ready, output [23:0] out_rgb,
 output reg out_last, out_frame_last, output reg source_permit, overflow
);
function integer bits_for;
 input integer n; integer v;
 begin v=n-1; bits_for=0; while(v>0) begin bits_for=bits_for+1; v=v>>1; end
 if(bits_for<1) bits_for=1; end
endfunction
localparam CW=WIDTH/2, X0=WIDTH/4, Y0=HEIGHT/4;
localparam AW=bits_for(CW);
(* ram_style="bram" *) reg [23:0] line0[0:CW-1];
(* ram_style="bram" *) reg [23:0] line1[0:CW-1];
reg [23:0] q0,q1;
reg [1:0] full;
reg wb,rb,output_bank,output_image,issued_all;
reg [15:0] ix,iy,ox,oy,output_y;
wire image_row=oy>=Y0 && oy<Y0+HEIGHT/2;
wire image_pixel=image_row && ox>=X0 && ox<X0+CW;
// Do not prefetch a new image row until the previous row releases its bank.
wire row_release=out_valid && out_ready && out_last &&
                 output_y>=Y0 && output_y<Y0+HEIGHT/2;
wire issue=active && !issued_all && (!out_valid || out_ready) &&
           (!image_row || (full[rb] && !row_release));
wire capture=active && in_valid && iy[0] && !ix[0] && !full[wb];
assign out_rgb=output_image ? (output_bank ? q1:q0) : 24'd0;
wire [AW-1:0] wa=ix[AW:1];
wire [AW-1:0] ra=ox-X0;
always @(posedge clk)
 if(capture && !wb) line0[wa]<=in_rgb;
always @(posedge clk)
 if(capture && wb) line1[wa]<=in_rgb;
always @(posedge clk)
 if(issue && image_pixel && !rb) q0<=line0[ra];
always @(posedge clk)
 if(issue && image_pixel && rb) q1<=line1[ra];
always @(posedge clk or posedge rst) begin
 if(rst) begin
  full<=0; wb<=0; rb<=0; ix<=0; iy<=0; ox<=0; oy<=0; output_y<=0;
  out_valid<=0; out_last<=0; out_frame_last<=0; output_bank<=0;
  output_image<=0; source_permit<=0; overflow<=0; issued_all<=0;
 end else if(active) begin
  if(in_valid) begin
   if(!source_permit) overflow<=1;
   if(iy[0] && !ix[0] && full[wb]) overflow<=1;
   if(ix==WIDTH-1) begin
    ix<=0; iy<=iy+1'b1;
    if(iy[0]) begin full[wb]<=1; wb<=!wb; end
   end else ix<=ix+1'b1;
  end
  if(out_valid && out_ready && out_last) begin
   if(output_y==Y0-1) source_permit<=1;
   if(output_y>=Y0 && output_y<Y0+HEIGHT/2) begin full[rb]<=0; rb<=!rb; end
  end
  if(!out_valid || out_ready) begin
   out_valid<=issue;
   if(issue) begin
    output_image<=image_pixel; output_bank<=rb; output_y<=oy;
    out_last<=ox==WIDTH-1;
    out_frame_last<=ox==WIDTH-1 && oy==HEIGHT-1;
    if(ox==WIDTH-1) begin
     ox<=0; oy<=oy+1'b1;
     if(oy==HEIGHT-1) issued_all<=1;
    end else ox<=ox+1'b1;
   end
  end
 end
end
endmodule
