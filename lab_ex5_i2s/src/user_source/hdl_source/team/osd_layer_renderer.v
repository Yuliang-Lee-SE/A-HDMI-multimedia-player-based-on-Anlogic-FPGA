`timescale 1ns/1ps
// Four registered stages; replaces status(1)+caption(3), so total latency
// before waveform/HDMI is unchanged. Configuration is video-clock local.
module osd_layer_renderer #(parameter DEFAULT_STEP=2,
 parameter SCROLL_HEAD_FRAMES=45,parameter SCROLL_TAIL_FRAMES=45)(
 input clk,input rst,input enable,input auto_mode,input [6:0] item_index,
 input [1:0] caption_index,input caption_enable,
 input hs_in,input vs_in,input de_in,input [23:0] rgb_in,
 output reg hs_out,output reg vs_out,output reg de_out,output reg [23:0] rgb_out,
 input cfg_valid,output cfg_ready,input cfg_show,input [9:0] cfg_x,input [9:0] cfg_y,
 input [2:0] cfg_alpha,input cfg_shadow,input cfg_pause,input [3:0] cfg_step);
reg [9:0] x,y;
reg de_prev,vs_prev;
wire frame_tick=vs_in && !vs_prev && !de_in;
reg pending;
reg p_show,p_shadow,p_pause;
reg [9:0] p_x,p_y;
reg [2:0] p_alpha;
reg [3:0] p_step;
reg show,shadow,pause;
reg [9:0] origin_x,origin_y;
reg [2:0] alpha;
reg [3:0] step;
assign cfg_ready=!pending;
wire commit=frame_tick && pending;
wire scroll_pause=commit ? (p_pause || !p_show) : (pause || !show);
wire [3:0] scroll_step=commit ? p_step : step;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  pending<=0;p_show<=1;p_shadow<=1;p_pause<=0;p_x<=24;p_y<=380;p_alpha<=3;p_step<=DEFAULT_STEP;
  show<=1;shadow<=1;pause<=0;origin_x<=24;origin_y<=380;alpha<=3;step<=DEFAULT_STEP;
 end else begin
  if(cfg_valid && cfg_ready) begin
   pending<=1;p_show<=cfg_show;p_shadow<=cfg_shadow;p_pause<=cfg_pause;
   p_x<=(cfg_x>48) ? 10'd48 : cfg_x;
   p_y<=(cfg_y<96) ? 10'd96 : (cfg_y>404) ? 10'd404 : cfg_y;
   p_alpha<=(cfg_alpha>4) ? 3'd4 : cfg_alpha;
   p_step<=(cfg_step<1) ? 4'd1 : (cfg_step>8) ? 4'd8 : cfg_step;
  end
  if(commit) begin
   pending<=0;show<=p_show;shadow<=p_shadow;pause<=p_pause;
   origin_x<=p_x;origin_y<=p_y;alpha<=p_alpha;step<=p_step;
  end
 end
end
always @(posedge clk or posedge rst) begin
 if(rst) begin x<=0;y<=0;de_prev<=0;vs_prev<=0;end
 else begin
  de_prev<=de_in;vs_prev<=vs_in;
  if(frame_tick)begin x<=0;y<=0;end
  else if(de_in)begin if(x==639)x<=0;else x<=x+1'b1;end
  else begin x<=0;if(de_prev && y<479)y<=y+1'b1;end
 end
end
wire [10:0] rx={1'b0,x}-{1'b0,origin_x};
wire [10:0] ry={1'b0,y}-{1'b0,origin_y};
wire panel=rx<592 && ry<76;
wire border=panel && (rx<2 || rx>=590 || ry<2 || ry>=74);
wire title=rx>=16 && rx<272 && ry>=30 && ry<46;
wire desc=rx>=16 && rx<576 && ry>=54 && ry<70;
 wire status_area=rx>=16 && rx<100 && ry>=8 && ry<22;
wire [10:0] dx=rx-16;
wire [10:0] dy=title ? ry-30 : ry-54;
wire [6:0] length;
wire [10:0] scroll_offset;
wire [10:0] sx=dx+scroll_offset;
wire [10:0] width={length,4'b0};
osd_text_lengths lengths(.item_index(caption_index),.description_length(length));
osd_layer_scroll #(.HEAD_FRAMES(SCROLL_HEAD_FRAMES),.TAIL_FRAMES(SCROLL_TAIL_FRAMES)) scroll(.clk(clk),.rst(rst),.frame_tick(frame_tick),.enable(enable && caption_enable),
 .pause(scroll_pause),.step_frames(scroll_step),.item_index(caption_index),.length(length),.offset(scroll_offset));
wire [6:0] address=title ? {3'b0,dx[7:4]} : ((sx<width) ? 7'd32+{1'b0,sx[9:4]} : 7'd32);
wire [7:0] text_id;
wire [15:0] glyph;
reg [3:0] row1,col1,col2;
osd_resources resources(.clk(clk),.text_addr({caption_index,address}),.text_id(text_id),
 .glyph_addr({text_id,row1}),.glyph_row(glyph));
wire [10:0] stx=rx-16,sty=ry-8;
wire [2:0] stchar=stx/12,stcol=(stx/2)%6,strow=sty/2;
wire [6:0] ordinal=item_index+7'd1;
reg [4:0] code;
always @* begin
 case(stchar)
  0:code=auto_mode ? 2 : 0;
  1:code=auto_mode ? 4 : 1;
  2:code=auto_mode ? 5 : 2;
  3:code=auto_mode ? 6 : 3;
  4:code=15;
  5:code=16+ordinal/10;
  6:code=16+ordinal%10;
  default:code=15;
 endcase
end
wire [4:0] status_bits=status_row(code,strow);
wire status_pixel=status_area && stcol<5 && status_bits[4-stcol];
// Extended sums avoid overflow; truncate only after the final /4.
function [7:0] blend;
 input [7:0] base,ink;input [2:0] a;
 reg [9:0] b,p,s;
 begin
  b={2'b0,base};p={2'b0,ink};
  case(a)
   0:s=b<<2;
   1:s=(b<<1)+b+p;
   2:s=(b+p)<<1;
   3:s=b+(p<<1)+p;
   default:s=p<<2;
  endcase
  blend=s[9:2];
 end
endfunction
 function [4:0] status_row;
     input [4:0] glyph;
    input [2:0] row;
    begin
        case (glyph)
            4'd0: begin // P
                case (row)
                    0: status_row = 5'b11110;
                    1: status_row = 5'b10001;
                    2: status_row = 5'b10001;
                    3: status_row = 5'b11110;
                    4: status_row = 5'b10000;
                    5: status_row = 5'b10000;
                    6: status_row = 5'b10000;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd1: begin // L
                case (row)
                    0,1,2,3,4,5: status_row = 5'b10000;
                    6: status_row = 5'b11111;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd2: begin // A
                case (row)
                    0: status_row = 5'b01110;
                    1: status_row = 5'b10001;
                    2: status_row = 5'b10001;
                    3: status_row = 5'b11111;
                    4: status_row = 5'b10001;
                    5: status_row = 5'b10001;
                    6: status_row = 5'b10001;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd3: begin // Y
                case (row)
                    0: status_row = 5'b10001;
                    1: status_row = 5'b01010;
                    2,3,4,5,6: status_row = 5'b00100;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd4: begin // U
                case (row)
                    0,1,2,3,4,5: status_row = 5'b10001;
                    6: status_row = 5'b01110;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd5: begin // T
                case (row)
                    0: status_row = 5'b11111;
                    1,2,3,4,5,6: status_row = 5'b00100;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd6: begin // O
                case (row)
                    0,6: status_row = 5'b01110;
                    1,2,3,4,5: status_row = 5'b10001;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd8: begin // 1
                case (row)
                    0: status_row = 5'b00100;
                    1: status_row = 5'b01100;
                    2,3,4,5: status_row = 5'b00100;
                    6: status_row = 5'b01110;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd9: begin // 2
                case (row)
                    0: status_row = 5'b01110;
                    1: status_row = 5'b10001;
                    2: status_row = 5'b00001;
                    3: status_row = 5'b00010;
                    4: status_row = 5'b00100;
                    5: status_row = 5'b01000;
                    6: status_row = 5'b11111;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd10: begin // 3
                case (row)
                    0,6: status_row = 5'b11110;
                    1,2,4,5: status_row = 5'b00001;
                    3: status_row = 5'b01110;
                    default: status_row = 5'b00000;
                endcase
            end
            4'd11: begin // 4
                case (row)
                    0,1,2: status_row = 5'b10010;
                    3: status_row = 5'b11111;
                    4,5,6: status_row = 5'b00010;
                    default: status_row = 5'b00000;
                endcase
            end
            5'd16: status_row = (35'b01110100011001110101110011000101110 >> ((6-row)*5));
            5'd17: status_row = (35'b00100011000010000100001000010001110 >> ((6-row)*5));
            5'd18: status_row = (35'b01110100010000100010001000100011111 >> ((6-row)*5));
            5'd19: status_row = (35'b11110000010000101110000010000111110 >> ((6-row)*5));
            5'd20: status_row = (35'b10010100101001011111000100001000010 >> ((6-row)*5));
            5'd21: status_row = (35'b11111100001000011110000010000111110 >> ((6-row)*5));
            5'd22: status_row = (35'b01110100001000011110100011000101110 >> ((6-row)*5));
            5'd23: status_row = (35'b11111000010001000100010000100001000 >> ((6-row)*5));
            5'd24: status_row = (35'b01110100011000101110100011000101110 >> ((6-row)*5));
            5'd25: status_row = (35'b01110100011000101111000010000101110 >> ((6-row)*5));
            default: status_row = 5'b00000;
        endcase
    end
endfunction
reg [23:0] rgb1,rgb2,rgb3;
reg [2:0] sync1,sync2,sync3;
reg title1,title2,area1,area2,status1,status2,panel1,panel2,border1,border2;
reg clip1,clip2,clip3,visible1,visible2,shadow1,shadow2,shadow3;
reg [2:0] alpha1,alpha2;
reg [9:0] x1,x2,x3,y1,y2,y3;
reg mask3;
reg [23:0] ink3;
// Two row banks avoid cross-port read/write collisions on the FPGA RAM.
// First-row/first-column gating suppresses unread history without RAM reset.
reg line_mask[0:2047];
wire [10:0] mask_write_addr={y2[0],x2};
wire [10:0] mask_read_addr={~y2[0],x2};
reg old_line,old_line_prev;
wire mask_now=visible2 && (status2 || (area2 && glyph[15-col2]));
always @(posedge clk or posedge rst) begin
 if(rst) begin
  rgb1<=0;rgb2<=0;rgb3<=0;sync1<=0;sync2<=0;sync3<=0;
  row1<=0;col1<=0;col2<=0;title1<=0;title2<=0;area1<=0;area2<=0;
  status1<=0;status2<=0;panel1<=0;panel2<=0;border1<=0;border2<=0;
  clip1<=0;clip2<=0;clip3<=0;visible1<=0;visible2<=0;
  shadow1<=0;shadow2<=0;shadow3<=0;alpha1<=0;alpha2<=0;
  x1<=0;x2<=0;x3<=0;y1<=0;y2<=0;y3<=0;
  mask3<=0;ink3<=0;old_line_prev<=0;
  hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
 end else begin
  rgb1<=rgb_in;rgb2<=rgb1;
  sync1<={hs_in,vs_in,de_in};sync2<=sync1;sync3<=sync2;
  row1<=dy[3:0];col1<=title ? dx[3:0] : sx[3:0];col2<=col1;
  title1<=title;title2<=title1;area1<=caption_enable && (title || (desc && sx<width));area2<=area1;
  status1<=status_pixel;status2<=status1;
  panel1<=panel;panel2<=panel1;border1<=border;border2<=border1;
  clip1<=(caption_enable && (title || desc)) || status_area;clip2<=clip1;clip3<=clip2;
  visible1<=enable && show;visible2<=visible1;
  shadow1<=shadow;shadow2<=shadow1;shadow3<=shadow2 && visible2;
  alpha1<=alpha;alpha2<=alpha1;
  x1<=x;x2<=x1;x3<=x2;y1<=y;y2<=y1;y3<=y2;
  mask3<=sync2[0] && mask_now;
  ink3<=status2 ? 24'hffff00 : (title2 ? 24'hffffff : 24'hd0e0ff);
  if(visible2 && border2) rgb3<=24'hffffff;
  else if(visible2 && panel2) rgb3<={blend(rgb2[23:16],8'h10,alpha2),blend(rgb2[15:8],8'h20,alpha2),blend(rgb2[7:0],8'h40,alpha2)};
  else rgb3<=rgb2;
  old_line_prev<=old_line;
  {hs_out,vs_out,de_out}<=sync3;
  if(!sync3[0])rgb_out<=0;
  else if(mask3)rgb_out<=ink3;
  else if(shadow3 && clip3 && x3>0 && y3>0 && old_line_prev)rgb_out<=0;
  else rgb_out<=rgb3;
 end
end
// Read the preceding row while writing the current row, at distinct addresses.
// Never reset or initialize this RAM; visible rows seed it before use.
always @(posedge clk) if(!rst && sync2[0])begin
 old_line<=line_mask[mask_read_addr];line_mask[mask_write_addr]<=mask_now;
end
endmodule

module osd_layer_scroll #(
 parameter STEP_FRAMES=2, parameter HEAD_FRAMES=45, parameter TAIL_FRAMES=45,
 parameter WINDOW_PIXELS=560, parameter GAP_PIXELS=32
)(input clk,input rst,input frame_tick,input enable,input pause,
 input [3:0] step_frames,input [1:0] item_index,input [6:0] length,output reg [10:0] offset);
reg [1:0] seen_item;
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
   end else if(step_frames<=1 || step_count+1>=step_frames) begin
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

