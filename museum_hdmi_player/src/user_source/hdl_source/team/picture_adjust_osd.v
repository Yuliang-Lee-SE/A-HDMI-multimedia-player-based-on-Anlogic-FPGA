`timescale 1ns/1ps

// Right-side picture menu. The panel shows all three values so the currently
// selected parameter is clear without cycling through separate pages.
module picture_adjust_osd (
    input             clk,
    input             rst,
    input             enable,
    input             transition_enable,
    input      [1:0]  transition_mode,
    input      [1:0]  parameter_index,
    input signed [7:0] brightness,
    input      [7:0]  contrast,
    input      [3:0]  sharpness,
    input      [4:0]  rotation_period_s,
    input             hs_in,
    input             vs_in,
    input             de_in,
    input      [23:0] rgb_in,
    output reg        hs_out,
    output reg        vs_out,
    output reg        de_out,
    output reg [23:0] rgb_out
);

localparam integer PANEL_X      = 456;
localparam integer PANEL_Y      = 112;
localparam integer PANEL_WIDTH  = 172;
localparam integer PANEL_HEIGHT = 198;
localparam integer TEXT_SCALE   = 2;
localparam integer CELL_WIDTH   = 6 * TEXT_SCALE;

reg [11:0] x;
reg [11:0] y;
reg        de_prev;
reg        vs_prev;

wire frame_tick = vs_in && !vs_prev && !de_in;
 wire menu_enable = transition_enable || enable;
 wire [1:0] selected_parameter = transition_enable ? transition_mode : parameter_index;
 wire in_panel = menu_enable && (x >= PANEL_X) && (x < PANEL_X + PANEL_WIDTH) &&
                (y >= PANEL_Y) && (y < PANEL_Y + PANEL_HEIGHT);
wire in_border = in_panel &&
                 ((x < PANEL_X + 2) ||
                  (x >= PANEL_X + PANEL_WIDTH - 2) ||
                  (y < PANEL_Y + 2) ||
                  (y >= PANEL_Y + PANEL_HEIGHT - 2));

wire [11:0] local_x = x - PANEL_X;
wire [11:0] local_y = y - PANEL_Y;
wire [11:0] text_x  = local_x - 12'd16;

wire title_line   = local_y >= 12  && local_y < 26;
wire row0_line    = local_y >= 38  && local_y < 52;
wire row1_line    = local_y >= 64  && local_y < 78;
wire row2_line    = local_y >= 90  && local_y < 104;
wire row3_line    = local_y >= 116 && local_y < 130;
wire footer1_line = local_y >= 146 && local_y < 160;
wire footer2_line = local_y >= 164 && local_y < 178;
wire in_text_line = in_panel && local_x >= 16 &&
                    (title_line || row0_line || row1_line || row2_line || row3_line ||
                     footer1_line || footer2_line);

wire [3:0] cell_index = text_x / CELL_WIDTH;
wire [2:0] char_column = (text_x / TEXT_SCALE) % 6;
wire [11:0] line_offset =
    title_line   ? local_y - 12 :
    row0_line    ? local_y - 38 :
    row1_line    ? local_y - 64 :
    row2_line    ? local_y - 90 :
    row3_line    ? local_y - 116 :
    footer1_line ? local_y - 146 : local_y - 164;
wire [2:0] char_row = line_offset / TEXT_SCALE;

reg [7:0] char_code;
always @(*) begin
    char_code = 8'h20;
    if (transition_enable && title_line) begin
        if (cell_index >= 2 && cell_index <= 6)
            char_code = transition_title_char(cell_index - 2);
    end else if (transition_enable && (row0_line || row1_line || row2_line || row3_line)) begin
        if (cell_index == 0 && selected_parameter ==
            (row0_line ? 2'd0 : row1_line ? 2'd1 : row2_line ? 2'd2 : 2'd3))
            char_code = ">";
        else if (cell_index >= 2)
            char_code = transition_word_char(
                row0_line ? 2'd0 : row1_line ? 2'd1 : row2_line ? 2'd2 : 2'd3,
                cell_index - 2);
    end else if (transition_enable && footer1_line) begin
        char_code = transition_footer_char(4'd0, cell_index);
    end else if (transition_enable && footer2_line) begin
        char_code = transition_footer_char(4'd1, cell_index);
    end else if (title_line) begin
        if (cell_index >= 2 && cell_index <= 8)
            char_code = title_char(cell_index - 2);
    end else if (row0_line) begin
        if (cell_index == 0 && parameter_index == 2'd0)
            char_code = ">";
        else if (cell_index >= 2 && cell_index <= 9)
            char_code = label_char(2'd0, cell_index - 2);
        else if (cell_index >= 10 && cell_index <= 12)
            char_code = value_char(2'd0, cell_index - 10,
                                   brightness, contrast, sharpness, rotation_period_s);
    end else if (row1_line) begin
        if (cell_index == 0 && parameter_index == 2'd1)
            char_code = ">";
        else if (cell_index >= 2 && cell_index <= 9)
            char_code = label_char(2'd1, cell_index - 2);
        else if (cell_index >= 10 && cell_index <= 12)
            char_code = value_char(2'd1, cell_index - 10,
                                   brightness, contrast, sharpness, rotation_period_s);
    end else if (row2_line) begin
        if (cell_index == 0 && parameter_index == 2'd2)
            char_code = ">";
        else if (cell_index >= 2 && cell_index <= 9)
            char_code = label_char(2'd2, cell_index - 2);
        else if (cell_index >= 10 && cell_index <= 12)
            char_code = value_char(2'd2, cell_index - 10,
                                   brightness, contrast, sharpness, rotation_period_s);
    end else if (row3_line) begin
        if (cell_index == 0 && parameter_index == 2'd3)
            char_code = ">";
        else if (cell_index >= 2 && cell_index <= 9)
            char_code = label_char(2'd3, cell_index - 2);
        else if (cell_index >= 10 && cell_index <= 12)
            char_code = value_char(2'd3, cell_index - 10,
                                   brightness, contrast, sharpness, rotation_period_s);
    end else if (footer1_line) begin
        char_code = footer1_char(cell_index);
    end else if (footer2_line) begin
        char_code = footer2_char(cell_index);
    end
end

wire [34:0] font = font_bits(char_code);
wire [4:0] font_row = glyph_row_bits(font, char_row);
 wire text_pixel = menu_enable && in_text_line && char_column < 5 &&
                  font_row[4-char_column];
 wire active_row = menu_enable &&
                  ((selected_parameter == 2'd0 && row0_line) ||
                   (selected_parameter == 2'd1 && row1_line) ||
                   (selected_parameter == 2'd2 && row2_line) ||
                   (selected_parameter == 2'd3 && row3_line));
 wire [23:0] text_color = active_row ? 24'hE3C48A : 24'hF3E9D2;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        x       <= 12'd0;
        y       <= 12'd0;
        de_prev <= 1'b0;
        vs_prev <= 1'b0;
    end else begin
        de_prev <= de_in;
        vs_prev <= vs_in;
        if (frame_tick) begin
            x <= 12'd0;
            y <= 12'd0;
        end else if (de_in) begin
            if (x == 12'd639)
                x <= 12'd0;
            else
                x <= x + 12'd1;
        end else begin
            x <= 12'd0;
            if (de_prev && y < 12'd479)
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
        else if (!menu_enable)
            rgb_out <= rgb_in;
        else if (text_pixel)
            rgb_out <= text_color;
        else if (in_border)
            rgb_out <= 24'h8F7958;
        else if (in_panel)
            rgb_out <= 24'h101614;
        else
            rgb_out <= rgb_in;
    end
end

function [7:0] title_char;
    input [3:0] col;
    begin
        case (col)
            4'd0: title_char = "P";
            4'd1: title_char = "I";
            4'd2: title_char = "C";
            4'd3: title_char = "T";
            4'd4: title_char = "U";
            4'd5: title_char = "R";
            4'd6: title_char = "E";
            default: title_char = 8'h20;
        endcase
    end
endfunction

function [7:0] label_char;
    input [1:0] param_sel;
    input [3:0] col;
    begin
        label_char = 8'h20;
        case (param_sel)
            2'd0: case (col)
                4'd0: label_char = "B";
                4'd1: label_char = "R";
                4'd2: label_char = "I";
                4'd3: label_char = "G";
                4'd4: label_char = "H";
                4'd5: label_char = "T";
            endcase
            2'd1: case (col)
                4'd0: label_char = "C";
                4'd1: label_char = "O";
                4'd2: label_char = "N";
                4'd3: label_char = "T";
                4'd4: label_char = "R";
                4'd5: label_char = "A";
                4'd6: label_char = "S";
                4'd7: label_char = "T";
            endcase
            2'd2: case (col)
                4'd0: label_char = "S";
                4'd1: label_char = "H";
                4'd2: label_char = "A";
                4'd3: label_char = "R";
                4'd4: label_char = "P";
            endcase
            default: case (col)
                4'd0: label_char = "R";
                4'd1: label_char = "O";
                4'd2: label_char = "T";
                4'd3: label_char = "A";
                4'd4: label_char = "T";
                4'd5: label_char = "E";
            endcase
        endcase
    end
endfunction

function [7:0] footer1_char;
    input [3:0] col;
    begin
        case (col)
            4'd0: footer1_char = "K";
            4'd1: footer1_char = "4";
            4'd2: footer1_char = 8'h20;
            4'd3: footer1_char = "N";
            4'd4: footer1_char = "E";
            4'd5: footer1_char = "X";
            4'd6: footer1_char = "T";
            default: footer1_char = 8'h20;
        endcase
    end
endfunction

function [7:0] footer2_char;
    input [3:0] col;
    begin
        case (col)
            4'd0: footer2_char = "K";
            4'd1: footer2_char = "3";
            4'd2: footer2_char = "+";
            4'd3: footer2_char = 8'h20;
            4'd4: footer2_char = 8'h20;
            4'd5: footer2_char = "K";
            4'd6: footer2_char = "2";
            4'd7: footer2_char = "-";
            default: footer2_char = 8'h20;
        endcase
    end
endfunction

function [7:0] digit_char;
    input [3:0] digit;
    begin
        if (digit > 4'd9)
            digit_char = 8'h20;
        else
            digit_char = 8'h30 + {4'd0, digit};
    end
endfunction

function [7:0] value_char;
    input [1:0] param_sel;
    input [3:0] slot;
    input signed [7:0] bright;
    input [7:0] contr;
    input [3:0] sharp;
    input [4:0] rotation;
    reg [7:0] magnitude;
    reg [3:0] digit;
    begin
        value_char = 8'h20;
        case (param_sel)
            2'd0: begin
                magnitude = bright[7] ? (8'd0 - bright) : bright;
                case (slot)
                    4'd0: value_char = bright[7] ? "-" : 8'h20;
                    4'd1: if (magnitude >= 8'd10)
                              value_char = digit_char(magnitude / 8'd10);
                    4'd2: value_char = digit_char(magnitude % 8'd10);
                endcase
            end
            2'd1: begin
                case (slot)
                    4'd0: value_char = digit_char(contr / 8'd100);
                    4'd1: begin
                        digit = (contr / 8'd10) % 4'd10;
                        value_char = digit_char(digit);
                    end
                    4'd2: begin
                        digit = contr % 8'd10;
                        value_char = digit_char(digit);
                    end
                endcase
            end
            2'd2: begin
                if (slot == 4'd2)
                    value_char = digit_char(sharp);
            end
            default: begin
                case (slot)
                    4'd1: if (rotation >= 5'd10)
                              value_char = digit_char(rotation / 5'd10);
                    4'd2: value_char = digit_char(rotation -
                                                  (rotation / 5'd10) * 5'd10);
                endcase
            end
        endcase
    end
endfunction

function [7:0] transition_title_char;
    input [3:0] col;
    begin
        case(col)
            0:transition_title_char="T";
            1:transition_title_char="R";
            2:transition_title_char="A";
            3:transition_title_char="N";
            4:transition_title_char="S";
            default:transition_title_char=8'h20;
        endcase
    end
endfunction

function [7:0] transition_word_char;
    input [1:0] mode_index;
    input [3:0] col;
    begin
        transition_word_char=8'h20;
        case(mode_index)
            2'd0:case(col)0:transition_word_char="C";1:transition_word_char="U";2:transition_word_char="T";endcase
            2'd1:case(col)0:transition_word_char="S";1:transition_word_char="L";2:transition_word_char="I";3:transition_word_char="D";4:transition_word_char="E";endcase
            2'd2:case(col)0:transition_word_char="B";1:transition_word_char="L";2:transition_word_char="I";3:transition_word_char="N";4:transition_word_char="D";5:transition_word_char="S";endcase
            default:case(col)0:transition_word_char="F";1:transition_word_char="A";2:transition_word_char="D";3:transition_word_char="E";endcase
        endcase
    end
endfunction

function [7:0] transition_footer_char;
    input [3:0] line;
    input [3:0] col;
    begin
        transition_footer_char=8'h20;
        if(line==0)case(col)
            0:transition_footer_char="K";1:transition_footer_char="E";2:transition_footer_char="Y";3:transition_footer_char="2";
            5:transition_footer_char="N";6:transition_footer_char="E";7:transition_footer_char="X";8:transition_footer_char="T";
        endcase
        else case(col)
            0:transition_footer_char="H";1:transition_footer_char="O";2:transition_footer_char="L";3:transition_footer_char="D";
            5:transition_footer_char="E";6:transition_footer_char="X";7:transition_footer_char="I";8:transition_footer_char="T";
        endcase
    end
endfunction

function [34:0] font_bits;
    input [7:0] character;
    begin
        case (character)
            8'h20: font_bits = {35{1'b0}};
            8'h2B: font_bits = {5'b00000,5'b00000,5'b00100,
                                5'b01110,5'b00100,5'b00000,5'b00000};
            8'h2D: font_bits = {5'b00000,5'b00000,5'b00000,
                                5'b01110,5'b00000,5'b00000,5'b00000};
            8'h30: font_bits = {5'b01110,5'b10011,5'b10101,
                                5'b10101,5'b11001,5'b10001,5'b01110};
            8'h31: font_bits = {5'b00100,5'b01100,5'b00100,
                                5'b00100,5'b00100,5'b00100,5'b01110};
            8'h32: font_bits = {5'b01110,5'b10001,5'b00001,
                                5'b00010,5'b00100,5'b01000,5'b11111};
            8'h33: font_bits = {5'b11110,5'b00001,5'b00001,
                                5'b01110,5'b00001,5'b00001,5'b11110};
            8'h34: font_bits = {5'b00010,5'b00110,5'b01010,
                                5'b10010,5'b11111,5'b00010,5'b00010};
            8'h35: font_bits = {5'b11111,5'b10000,5'b10000,
                                5'b11110,5'b00001,5'b00001,5'b11110};
            8'h36: font_bits = {5'b01110,5'b10000,5'b10000,
                                5'b11110,5'b10001,5'b10001,5'b01110};
            8'h37: font_bits = {5'b11111,5'b00001,5'b00010,
                                5'b00100,5'b01000,5'b01000,5'b01000};
            8'h38: font_bits = {5'b01110,5'b10001,5'b10001,
                                5'b01110,5'b10001,5'b10001,5'b01110};
            8'h39: font_bits = {5'b01110,5'b10001,5'b10001,
                                5'b01111,5'b00001,5'b00001,5'b01110};
            8'h3E: font_bits = {5'b10000,5'b01000,5'b00100,
                                5'b00010,5'b00100,5'b01000,5'b10000};
            8'h41: font_bits = {5'b01110,5'b10001,5'b10001,
                                5'b11111,5'b10001,5'b10001,5'b10001};
            8'h42: font_bits = {5'b11110,5'b10001,5'b10001,
                                5'b11110,5'b10001,5'b10001,5'b11110};
            8'h43: font_bits = {5'b01111,5'b10000,5'b10000,
                                5'b10000,5'b10000,5'b10000,5'b01111};
            8'h44: font_bits = {5'b11110,5'b10001,5'b10001,
                                 5'b10001,5'b10001,5'b10001,5'b11110};
            8'h45: font_bits = {5'b11111,5'b10000,5'b10000,
                                5'b11110,5'b10000,5'b10000,5'b11111};
            8'h46: font_bits = {5'b11111,5'b10000,5'b10000,
                                 5'b11110,5'b10000,5'b10000,5'b10000};
            8'h47: font_bits = {5'b01110,5'b10001,5'b10000,
                                5'b10111,5'b10001,5'b10001,5'b01110};
            8'h48: font_bits = {5'b10001,5'b10001,5'b10001,
                                5'b11111,5'b10001,5'b10001,5'b10001};
            8'h49: font_bits = {5'b11111,5'b00100,5'b00100,
                                5'b00100,5'b00100,5'b00100,5'b11111};
            8'h4B: font_bits = {5'b10001,5'b10010,5'b10100,
                                5'b11000,5'b10100,5'b10010,5'b10001};
            8'h4C: font_bits = {5'b10000,5'b10000,5'b10000,
                                 5'b10000,5'b10000,5'b10000,5'b11111};
            8'h4E: font_bits = {5'b10001,5'b11001,5'b10101,
                                5'b10011,5'b10001,5'b10001,5'b10001};
            8'h4F: font_bits = {5'b01110,5'b10001,5'b10001,
                                5'b10001,5'b10001,5'b10001,5'b01110};
            8'h50: font_bits = {5'b11110,5'b10001,5'b10001,
                                5'b11110,5'b10000,5'b10000,5'b10000};
            8'h52: font_bits = {5'b11110,5'b10001,5'b10001,
                                5'b11110,5'b10100,5'b10010,5'b10001};
            8'h53: font_bits = {5'b01111,5'b10000,5'b10000,
                                5'b01110,5'b00001,5'b00001,5'b11110};
            8'h54: font_bits = {5'b11111,5'b00100,5'b00100,
                                5'b00100,5'b00100,5'b00100,5'b00100};
            8'h55: font_bits = {5'b10001,5'b10001,5'b10001,
                                5'b10001,5'b10001,5'b10001,5'b01110};
            8'h58: font_bits = {5'b10001,5'b10001,5'b01010,
                                5'b00100,5'b01010,5'b10001,5'b10001};
            8'h59: font_bits = {5'b10001,5'b10001,5'b01010,
                                 5'b00100,5'b00100,5'b00100,5'b00100};
            default: font_bits = {35{1'b0}};
        endcase
    end
endfunction

function [4:0] glyph_row_bits;
    input [34:0] glyph;
    input [2:0] row;
    begin
        case (row)
            3'd0: glyph_row_bits = glyph[34:30];
            3'd1: glyph_row_bits = glyph[29:25];
            3'd2: glyph_row_bits = glyph[24:20];
            3'd3: glyph_row_bits = glyph[19:15];
            3'd4: glyph_row_bits = glyph[14:10];
            3'd5: glyph_row_bits = glyph[9:5];
            3'd6: glyph_row_bits = glyph[4:0];
            default: glyph_row_bits = 5'd0;
        endcase
    end
endfunction

endmodule
