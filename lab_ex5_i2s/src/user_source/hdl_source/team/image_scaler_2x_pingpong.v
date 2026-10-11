`timescale 1ns/1ps
// Single-clock 2x scaler with two alternating line buffers.
// The consumer must honor out_valid; switching buffers costs one clock.
// Input consists of complete SRC_WIDTH x SRC_HEIGHT frames in raster order.
module image_scaler_2x_pingpong #(
    parameter integer SRC_WIDTH = 320,
    parameter integer SRC_HEIGHT = 240
)(
    input clk,
    input rst,
    input in_valid,
    output in_ready,
    input [23:0] in_rgb,
    output reg out_valid,
    input out_ready,
    output [23:0] out_rgb,
    output reg out_last,
    output reg out_frame_last
);
function integer bits_for;
    input integer count;
    integer value;
    begin
        value = count-1;
        bits_for = 0;
        while (value>0) begin
            bits_for = bits_for+1;
            value = value>>1;
        end
        if (bits_for<1) bits_for = 1;
    end
endfunction
localparam ADDR_WIDTH = bits_for(SRC_WIDTH);
localparam ROW_WIDTH = bits_for(SRC_HEIGHT);

// Anlogic TD directive and reset-free synchronous RAM read template.
(* ram_style = "bram" *) reg [23:0] line0 [0:SRC_WIDTH-1];
(* ram_style = "bram" *) reg [23:0] line1 [0:SRC_WIDTH-1];
reg [23:0] line0_q;
reg [23:0] line1_q;
reg output_bank;
reg [1:0] bank_full;
reg write_bank;
reg read_bank;
reg [ADDR_WIDTH-1:0] fill_index;
reg [ADDR_WIDTH:0] emit_index;
reg [ROW_WIDTH-1:0] source_row;
reg repeat_row;
reg all_issued;

assign in_ready = !rst && !bank_full[write_bank];
wire issue_read;
assign issue_read = !rst && (!out_valid || out_ready) &&
                    bank_full[read_bank] && !all_issued;
assign out_rgb = output_bank ? line1_q : line0_q;

// No memory reset: only valid/ownership state is reset.
always @(posedge clk)
    if (in_valid && in_ready && !write_bank)
        line0[fill_index] <= in_rgb;
always @(posedge clk)
    if (in_valid && in_ready && write_bank)
        line1[fill_index] <= in_rgb;

// RAM output registers must have no asynchronous reset for BRAM inference.
always @(posedge clk)
    if (issue_read && !read_bank)
        line0_q <= line0[emit_index[ADDR_WIDTH:1]];
always @(posedge clk)
    if (issue_read && read_bank)
        line1_q <= line1[emit_index[ADDR_WIDTH:1]];

always @(posedge clk or posedge rst) begin
    if (rst) begin
        bank_full <= 0;
        write_bank <= 0;
        read_bank <= 0;
        fill_index <= 0;
        emit_index <= 0;
        source_row <= 0;
        repeat_row <= 0;
        all_issued <= 0;
        out_valid <= 0;
        output_bank <= 0;
        out_last <= 0;
        out_frame_last <= 0;
    end else begin
        if (in_valid && in_ready) begin
            if (fill_index == SRC_WIDTH-1) begin
                fill_index <= 0;
                bank_full[write_bank] <= 1;
                write_bank <= !write_bank;
            end else
                fill_index <= fill_index + 1;
        end

        if (!out_valid || out_ready) begin
            if (bank_full[read_bank] && !all_issued) begin
                out_valid <= 1;
                output_bank <= read_bank;
                out_last <= (emit_index == 2*SRC_WIDTH-1);
                out_frame_last <= (source_row == SRC_HEIGHT-1 &&
                                   repeat_row && emit_index == 2*SRC_WIDTH-1);
                if (emit_index == 2*SRC_WIDTH-1) begin
                    if (!repeat_row) begin
                        repeat_row <= 1;
                        emit_index <= 0;
                    end else
                        all_issued <= 1;
                end else
                    emit_index <= emit_index + 1;
            end else begin
                out_valid <= 0;
                out_last <= 0;
                out_frame_last <= 0;
            end
        end

        if (out_valid && out_ready && all_issued) begin
            bank_full[read_bank] <= 0;
            read_bank <= !read_bank;
            emit_index <= 0;
            repeat_row <= 0;
            all_issued <= 0;
            if (source_row == SRC_HEIGHT-1)
                source_row <= 0;
            else
                source_row <= source_row + 1;
        end
    end
end
endmodule
