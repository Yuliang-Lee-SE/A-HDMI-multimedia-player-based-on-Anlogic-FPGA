`timescale 1ns/1ps

// Streaming RGB OSD overlay.
// Counts active pixels from DE and overlays a bordered information panel.
// RGB and timing outputs all have the same one-clock latency.
module osd_overlay #(
    parameter H_ACTIVE     = 640,
    parameter V_ACTIVE     = 480,
    parameter OSD_X        = 24,
    parameter OSD_Y        = 380,
    parameter OSD_WIDTH    = 592,
    parameter OSD_HEIGHT   = 76,
    parameter BORDER_SIZE  = 2,
    parameter BORDER_COLOR = 24'hFFFFFF,
    parameter PANEL_COLOR  = 24'h102040,
    parameter TEXT_ENABLE  = 1,
    parameter TEXT_X_REL   = 16,
    parameter TEXT_Y_REL   = 16,
    parameter TEXT_SCALE   = 2,
    parameter TEXT_COLOR   = 24'hFFFF00
)(
    input             clk,
    input             rst,
    input             enable,
    input             auto_mode,
    input      [1:0]  item_index,
    input             hs_in,
    input             vs_in,
    input             de_in,
    input      [23:0] rgb_in,
    output reg        hs_out,
    output reg        vs_out,
    output reg        de_out,
    output reg [23:0] rgb_out
);

reg [11:0] x;
reg [11:0] y;
reg        de_prev;
reg        vs_prev;

wire in_panel;
wire in_border;
wire in_text_area;
wire [11:0] text_dx;
wire [11:0] text_dy;
wire [2:0]  text_glyph;
wire [2:0]  text_col;
wire [2:0]  text_row;
reg  [3:0]  glyph_code;
wire [4:0]  text_row_bits;
wire        text_pixel;

assign in_panel = (x >= OSD_X) && (x < OSD_X + OSD_WIDTH) &&
                  (y >= OSD_Y) && (y < OSD_Y + OSD_HEIGHT);

assign in_border = in_panel &&
                   ((x < OSD_X + BORDER_SIZE) ||
                    (x >= OSD_X + OSD_WIDTH - BORDER_SIZE) ||
                    (y < OSD_Y + BORDER_SIZE) ||
                    (y >= OSD_Y + OSD_HEIGHT - BORDER_SIZE));

// Dynamic status text: "PLAY 1".."PLAY 4" or "AUTO 1".."AUTO 4".
assign in_text_area = TEXT_ENABLE &&
                      (x >= OSD_X + TEXT_X_REL) &&
                      (x <  OSD_X + TEXT_X_REL + 36 * TEXT_SCALE) &&
                      (y >= OSD_Y + TEXT_Y_REL) &&
                      (y <  OSD_Y + TEXT_Y_REL + 7 * TEXT_SCALE);
assign text_dx    = x - (OSD_X + TEXT_X_REL);
assign text_dy    = y - (OSD_Y + TEXT_Y_REL);
assign text_glyph = text_dx / (6 * TEXT_SCALE);
assign text_col   = (text_dx / TEXT_SCALE) % 6;
assign text_row   = text_dy / TEXT_SCALE;
assign text_row_bits = glyph_row(glyph_code, text_row);
assign text_pixel = in_text_area && (text_glyph < 6) &&
                    (text_col < 5) && text_row_bits[4-text_col];

always @(*) begin
    case (text_glyph)
        0: glyph_code = auto_mode ? 4'd2 : 4'd0; // A or P
        1: glyph_code = auto_mode ? 4'd4 : 4'd1; // U or L
        2: glyph_code = auto_mode ? 4'd5 : 4'd2; // T or A
        3: glyph_code = auto_mode ? 4'd6 : 4'd3; // O or Y
        4: glyph_code = 4'd15;                   // space
        5: glyph_code = 4'd8 + item_index;       // digits 1..4
        default: glyph_code = 4'd15;
    endcase
end

function [4:0] glyph_row;
    input [3:0] glyph;
    input [2:0] row;
    begin
        case (glyph)
            4'd0: begin // P
                case (row)
                    0: glyph_row = 5'b11110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b11110;
                    4: glyph_row = 5'b10000;
                    5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b10000;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd1: begin // L
                case (row)
                    0,1,2,3,4,5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd2: begin // A
                case (row)
                    0: glyph_row = 5'b01110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001;
                    3: glyph_row = 5'b11111;
                    4: glyph_row = 5'b10001;
                    5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd3: begin // Y
                case (row)
                    0: glyph_row = 5'b10001;
                    1: glyph_row = 5'b01010;
                    2,3,4,5,6: glyph_row = 5'b00100;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd4: begin // U
                case (row)
                    0,1,2,3,4,5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd5: begin // T
                case (row)
                    0: glyph_row = 5'b11111;
                    1,2,3,4,5,6: glyph_row = 5'b00100;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd6: begin // O
                case (row)
                    0,6: glyph_row = 5'b01110;
                    1,2,3,4,5: glyph_row = 5'b10001;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd8: begin // 1
                case (row)
                    0: glyph_row = 5'b00100;
                    1: glyph_row = 5'b01100;
                    2,3,4,5: glyph_row = 5'b00100;
                    6: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd9: begin // 2
                case (row)
                    0: glyph_row = 5'b01110;
                    1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b00001;
                    3: glyph_row = 5'b00010;
                    4: glyph_row = 5'b00100;
                    5: glyph_row = 5'b01000;
                    6: glyph_row = 5'b11111;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd10: begin // 3
                case (row)
                    0,6: glyph_row = 5'b11110;
                    1,2,4,5: glyph_row = 5'b00001;
                    3: glyph_row = 5'b01110;
                    default: glyph_row = 5'b00000;
                endcase
            end
            4'd11: begin // 4
                case (row)
                    0,1,2: glyph_row = 5'b10010;
                    3: glyph_row = 5'b11111;
                    4,5,6: glyph_row = 5'b00010;
                    default: glyph_row = 5'b00000;
                endcase
            end
            default: glyph_row = 5'b00000;
        endcase
    end
endfunction

always @(posedge clk or posedge rst) begin
    if (rst) begin
        x       <= 12'd0;
        y       <= 12'd0;
        de_prev <= 1'b0;
        vs_prev <= 1'b0;
    end else begin
        de_prev <= de_in;
        vs_prev <= vs_in;

        // Start of a new frame. The official timing generator uses a VS edge
        // before the first active line.
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
            if (de_prev && (y < V_ACTIVE - 1))
                y <= y + 12'd1;
        end
    end
end

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
        else if (enable && text_pixel)
            rgb_out <= TEXT_COLOR;
        else if (enable && in_border)
            rgb_out <= BORDER_COLOR;
        else if (enable && in_panel)
            rgb_out <= PANEL_COLOR;
        else
            rgb_out <= rgb_in;
    end
end

endmodule
