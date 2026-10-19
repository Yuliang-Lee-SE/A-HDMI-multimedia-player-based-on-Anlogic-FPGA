`timescale 1ns/1ps
// Three registered stages: text lookup, glyph-row lookup, pixel composition.
// ID 0 is space; padded text means empty/short strings need no variable logic.
module osd_text_renderer #(
 parameter STABLE_ID=0, parameter SCROLL_ENABLE=1, parameter SCROLL_STEP_FRAMES=2,
 parameter SCROLL_HEAD_FRAMES=45, parameter SCROLL_TAIL_FRAMES=45
)(input clk, input rst, input enable, input [13:0] item_index,
 input hs_in, input vs_in, input de_in, input [23:0] rgb_in,
 output reg hs_out, output reg vs_out, output reg de_out, output reg [23:0] rgb_out,
 input scroll_pause);
reg [9:0] x,y;
reg de_prev,vs_prev;
wire title = x>=40 && x<296 && y>=410 && y<426;
wire desc = x>=40 && x<600 && y>=434 && y<450;
wire [9:0] dx=x-10'd40;
wire [6:0] description_length;
wire [10:0] scroll_offset;
wire [10:0] source_x={1'b0,dx}+scroll_offset;
wire [10:0] text_width={description_length,4'b0000};
wire area = enable && de_in && (title || (desc && source_x<text_width));
wire [1:0] resource_index=STABLE_ID ?
 (item_index==1 ? 0:item_index==2 ? 1:item_index==3 ? 2:item_index==4 ? 3:0):item_index[1:0];
osd_text_lengths lengths(.item_index(resource_index),.description_length(description_length));
osd_scroll_ctrl #(.ITEM_W(14),.STEP_FRAMES(SCROLL_STEP_FRAMES),.HEAD_FRAMES(SCROLL_HEAD_FRAMES),
 .TAIL_FRAMES(SCROLL_TAIL_FRAMES)) scroll(
 .clk(clk),.rst(rst),.frame_tick(vs_in && !vs_prev && !de_in),
 .enable(enable && SCROLL_ENABLE),.pause(scroll_pause),.item_index(item_index),
 .length(description_length),.offset(scroll_offset));
wire [9:0] dy=title ? y-10'd410 : y-10'd434;
// Clamp addresses in the trailing gap; never wrap into another exhibit.
wire [6:0] offset=title ? {3'b000,dx[7:4]} :
 ((source_x<text_width) ? 7'd32+{1'b0,source_x[9:4]} : 7'd32);
wire [7:0] text_id;
wire [15:0] glyph_row;
reg [3:0] row1,col1,col2;
reg area1,area2,title1,title2;
reg [23:0] rgb1,rgb2;
reg [2:0] sync1,sync2;
// The generator emits 16*power-of-two(glyph count) rows; the upper unused
// address bits are pruned by synthesis. IDs are generated and range checked.
osd_resources resources(.clk(clk),.text_addr({resource_index,offset}),.text_id(text_id),
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
  row1<=dy[3:0];col1<=title ? dx[3:0] : source_x[3:0];col2<=col1;
  area1<=area;area2<=area1;title1<=title;title2<=title1;
  rgb1<=rgb_in;rgb2<=rgb1;sync1<={hs_in,vs_in,de_in};sync2<=sync1;
  {hs_out,vs_out,de_out}<=sync2;
  if(!sync2[0]) rgb_out<=0;
  else if(area2 && glyph_row[15-col2]) rgb_out<=title2 ? 24'hffffff : 24'hd0e0ff;
  else rgb_out<=rgb2;
 end
end
endmodule

// Same video clock and committed exhibit ID as the renderer. All visible
// state advances only at the end of VS in blanking. Same-ID bank reloads
// (zoom) and failed loads leave the trajectory intact.
module osd_scroll_ctrl #(
 parameter ITEM_W=2, parameter STEP_FRAMES=2, parameter HEAD_FRAMES=45, parameter TAIL_FRAMES=45,
 parameter WINDOW_PIXELS=560, parameter GAP_PIXELS=32
)(input clk,input rst,input frame_tick,input enable,input pause,
 input [ITEM_W-1:0] item_index,input [6:0] length,output reg [10:0] offset);
reg [ITEM_W-1:0] seen_item;
reg active;
reg [15:0] step_count,hold_count;
reg [1:0] phase;
localparam HEAD=0, MOVE=1, TAIL=2;
wire [10:0] width={length,4'b0000};
wire [10:0] tail_offset=width-WINDOW_PIXELS;
wire [10:0] cycle_end=width+GAP_PIXELS;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  offset<=0;seen_item<=0;active<=0;step_count<=0;hold_count<=0;phase<=HEAD;
 end else if(frame_tick) begin
  if(!enable || !active || item_index!=seen_item || width<=WINDOW_PIXELS) begin
   offset<=0;seen_item<=item_index;active<=enable;
   step_count<=0;hold_count<=0;phase<=HEAD;
  end else if(!pause) begin
   if(phase==HEAD || phase==TAIL) begin
    if((phase==HEAD && (HEAD_FRAMES==0 || hold_count+1>=HEAD_FRAMES)) ||
       (phase==TAIL && (TAIL_FRAMES==0 || hold_count+1>=TAIL_FRAMES))) begin
     phase<=MOVE;hold_count<=0;step_count<=0;
    end else hold_count<=hold_count+1'b1;
   end else if(STEP_FRAMES<=1 || step_count+1>=STEP_FRAMES) begin
    step_count<=0;
    if(offset+1>=cycle_end) begin offset<=0;phase<=HEAD;hold_count<=0;end
    else begin
     offset<=offset+1'b1;
     if(offset+1==tail_offset) begin phase<=TAIL;hold_count<=0;end
    end
   end else step_count<=step_count+1'b1;
  end
 end
end
endmodule
