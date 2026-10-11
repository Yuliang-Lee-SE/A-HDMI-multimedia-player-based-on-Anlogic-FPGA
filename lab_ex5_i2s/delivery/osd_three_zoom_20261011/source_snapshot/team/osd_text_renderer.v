`timescale 1ns/1ps
// Three registered stages: text lookup, glyph-row lookup, pixel composition.
// ID 0 is space; padded text means empty/short strings need no variable logic.
module osd_text_renderer(input clk, input rst, input enable, input [1:0] item_index,
 input hs_in, input vs_in, input de_in, input [23:0] rgb_in,
 output reg hs_out, output reg vs_out, output reg de_out, output reg [23:0] rgb_out);
reg [9:0] x,y;
reg de_prev,vs_prev;
wire title = x>=40 && x<296 && y>=410 && y<426;
wire desc = x>=40 && x<600 && y>=434 && y<450;
wire area = enable && de_in && (title || desc);
wire [9:0] dx=x-10'd40;
wire [9:0] dy=title ? y-10'd410 : y-10'd434;
wire [6:0] offset=title ? {3'b000,dx[7:4]} : 7'd32+{1'b0,dx[9:4]};
wire [7:0] text_id;
wire [15:0] glyph_row;
reg [3:0] row1,col1,col2;
reg area1,area2,title1,title2;
reg [23:0] rgb1,rgb2;
reg [2:0] sync1,sync2;
// The generator emits 16*power-of-two(glyph count) rows; the upper unused
// address bits are pruned by synthesis. IDs are generated and range checked.
osd_resources resources(.clk(clk),.text_addr({item_index,offset}),.text_id(text_id),
 .glyph_addr({text_id,row1}),.glyph_row(glyph_row));
always @(posedge clk or posedge rst) begin
 if(rst) begin x<=0; y<=0; de_prev<=0; vs_prev<=0; end
 else begin
  de_prev<=de_in; vs_prev<=vs_in;
  if(vs_in && !vs_prev) begin x<=0; y<=0; end
  else if(de_in) begin if(x==639) x<=0; else x<=x+1'b1; end
  else begin x<=0; if(de_prev && y<479) y<=y+1'b1; end
 end
end
always @(posedge clk or posedge rst) begin
 if(rst) begin
  row1<=0;col1<=0;col2<=0;area1<=0;area2<=0;title1<=0;title2<=0;
  rgb1<=0;rgb2<=0;sync1<=0;sync2<=0;hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  row1<=dy[3:0];col1<=dx[3:0];col2<=col1;
  area1<=area;area2<=area1;title1<=title;title2<=title1;
  rgb1<=rgb_in;rgb2<=rgb1;sync1<={hs_in,vs_in,de_in};sync2<=sync1;
  {hs_out,vs_out,de_out}<=sync2;
  if(!sync2[0]) rgb_out<=0;
  else if(area2 && glyph_row[15-col2]) rgb_out<=title2 ? 24'hffffff : 24'hd0e0ff;
  else rgb_out<=rgb2;
 end
end
endmodule
