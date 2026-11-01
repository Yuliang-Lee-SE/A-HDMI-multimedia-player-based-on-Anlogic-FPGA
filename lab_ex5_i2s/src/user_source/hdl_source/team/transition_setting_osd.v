`timescale 1ns/1ps
// On-screen transition selector. KEY2 long press enters/leaves this menu;
// KEY2 short press cycles CUT -> SLIDE -> BLINDS -> FADE.
module transition_setting_osd (
    input  wire       clk,
    input  wire       rst,
    input  wire       enable,
    input  wire [1:0] mode,
    input  wire       hs_in,
    input  wire       vs_in,
    input  wire       de_in,
    input  wire [23:0] rgb_in,
    output reg        hs_out,
    output reg        vs_out,
    output reg        de_out,
    output reg [23:0] rgb_out
);
localparam integer PANEL_X = 246;
localparam integer PANEL_Y = 132;
localparam integer PANEL_W = 310;
localparam integer PANEL_H = 196;
localparam integer SCALE   = 2;
localparam integer CELL_W  = 6 * SCALE;

reg [11:0] x, y;
reg de_prev, vs_prev;
wire frame_tick = vs_in && !vs_prev && !de_in;
wire in_panel = x >= PANEL_X && x < PANEL_X + PANEL_W &&
                y >= PANEL_Y && y < PANEL_Y + PANEL_H;
wire [11:0] lx = x - PANEL_X;
wire [11:0] ly = y - PANEL_Y;
wire [11:0] tx = lx - 12'd18;
wire title_line = ly >= 12 && ly < 26;
wire row0_line  = ly >= 40 && ly < 54;
wire row1_line  = ly >= 66 && ly < 80;
wire row2_line  = ly >= 92 && ly < 106;
wire row3_line  = ly >= 118 && ly < 132;
wire foot0_line = ly >= 150 && ly < 164;
wire foot1_line = ly >= 168 && ly < 182;
wire in_line = in_panel && lx >= 18 &&
               (title_line || row0_line || row1_line || row2_line ||
                row3_line || foot0_line || foot1_line);
wire [3:0] cell_index = tx / CELL_W;
wire [2:0] char_column = (tx / SCALE) % 6;
wire [11:0] line_offset =
    title_line ? ly-12 : row0_line ? ly-40 : row1_line ? ly-66 :
    row2_line ? ly-92 : row3_line ? ly-118 : foot0_line ? ly-150 : ly-168;
wire [2:0] char_row = line_offset / SCALE;

reg [7:0] character;
always @(*) begin
    character = 8'h20;
    if(title_line) begin
        case(cell_index)
            0:character="T";1:character="R";2:character="A";3:character="N";
            4:character="S";5:character="I";6:character="T";7:character="I";
            8:character="O";9:character="N";default:character=8'h20;
        endcase
    end else if(row0_line) begin
        if(cell_index==0 && mode==0) character=">";
        else if(cell_index>=2) case(cell_index-2)
            0:character="C";1:character="U";2:character="T";default:character=8'h20;
        endcase
    end else if(row1_line) begin
        if(cell_index==0 && mode==1) character=">";
        else if(cell_index>=2) case(cell_index-2)
            0:character="S";1:character="L";2:character="I";3:character="D";
            4:character="E";default:character=8'h20;
        endcase
    end else if(row2_line) begin
        if(cell_index==0 && mode==2) character=">";
        else if(cell_index>=2) case(cell_index-2)
            0:character="B";1:character="L";2:character="I";3:character="N";
            4:character="D";5:character="S";default:character=8'h20;
        endcase
    end else if(row3_line) begin
        if(cell_index==0 && mode==3) character=">";
        else if(cell_index>=2) case(cell_index-2)
            0:character="F";1:character="A";2:character="D";3:character="E";
            default:character=8'h20;
        endcase
    end else if(foot0_line) begin
        case(cell_index)
            0:character="K";1:character="E";2:character="Y";3:character="2";
            5:character="N";6:character="E";7:character="X";8:character="T";
            default:character=8'h20;
        endcase
    end else if(foot1_line) begin
        case(cell_index)
            0:character="H";1:character="O";2:character="L";3:character="D";
            5:character="E";6:character="X";7:character="I";8:character="T";
            default:character=8'h20;
        endcase
    end
end

wire [34:0] font = font_bits(character);
wire [4:0] font_row = glyph_row(font,char_row);
wire text_pixel = enable && in_line && char_column<5 &&
                  font_row[4-char_column];
wire active_row = enable &&
                  ((mode==0 && row0_line) || (mode==1 && row1_line) ||
                   (mode==2 && row2_line) || (mode==3 && row3_line));
wire divider = enable && in_panel && lx>=18 && lx<292 &&
               ((ly>=32 && ly<34) || (ly>=142 && ly<144));
wire [23:0] text_color = active_row ? 24'hE3C48A : 24'hF3E9D2;

always @(posedge clk or posedge rst) begin
    if(rst) begin
        x<=0;y<=0;de_prev<=0;vs_prev<=0;
    end else begin
        de_prev<=de_in;vs_prev<=vs_in;
        if(frame_tick) begin x<=0;y<=0;end
        else if(de_in) begin if(x==639)x<=0;else x<=x+1;end
        else begin x<=0;if(de_prev&&y<479)y<=y+1;end
    end
end

always @(posedge clk or posedge rst) begin
    if(rst) begin
        hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
    end else begin
        hs_out<=hs_in;vs_out<=vs_in;de_out<=de_in;
        if(!de_in) rgb_out<=0;
        else if(!enable) rgb_out<=rgb_in;
        else if(text_pixel) rgb_out<=text_color;
        else if(divider) rgb_out<=24'h8F7958;
        else if(in_panel) rgb_out<=24'h101614;
        else rgb_out<=rgb_in;
    end
end

function [34:0] font_bits;
    input [7:0] c;
    begin
        case(c)
            8'h20:font_bits={35{1'b0}};
            8'h2D:font_bits={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
            8'h32:font_bits={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
            8'h3E:font_bits={5'b10000,5'b01000,5'b00100,5'b00010,5'b00100,5'b01000,5'b10000};
            8'h41:font_bits={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            8'h42:font_bits={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
            8'h43:font_bits={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
            8'h44:font_bits={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
            8'h45:font_bits={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
            8'h46:font_bits={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
            8'h48:font_bits={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            8'h49:font_bits={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b11111};
            8'h4B:font_bits={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
            8'h4C:font_bits={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
            8'h4E:font_bits={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
            8'h4F:font_bits={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            8'h52:font_bits={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
            8'h53:font_bits={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
            8'h54:font_bits={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
            8'h55:font_bits={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            8'h58:font_bits={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
            8'h59:font_bits={5'b10001,5'b10001,5'b01010,5'b00100,5'b00100,5'b00100,5'b00100};
            default:font_bits={35{1'b0}};
        endcase
    end
endfunction

function [4:0] glyph_row;
    input [34:0] glyph;
    input [2:0] row;
    begin
        case(row)
            0:glyph_row=glyph[34:30];
            1:glyph_row=glyph[29:25];
            2:glyph_row=glyph[24:20];
            3:glyph_row=glyph[19:15];
            4:glyph_row=glyph[14:10];
            5:glyph_row=glyph[9:5];
            6:glyph_row=glyph[4:0];
            default:glyph_row=5'd0;
        endcase
    end
endfunction
endmodule
