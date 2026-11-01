// Strict BITMAPINFOHEADER, 640x480 RGB24 BI_RGB bottom-up.
// Consumes a complete file once; no physical sector addresses or seek.
module bmp_file_stream #(
 parameter integer WIDTH=640,HEIGHT=480,WAIT_CYCLES=50000000
)(input clk,rst,input start,input [31:0] file_size,
 input data_valid,output wire data_ready,input [7:0] data,
 input file_done,file_error,
 output reg write_req,input write_req_ack,input write_ready,source_permit,
 output reg frame_start,output reg pixel_valid,output reg [23:0] pixel,
 output reg done,error,output wire busy);
 localparam IDLE=0,HEADER=1,CHECK=2,ACK=3,PRIME=4,BODY=5,DRAIN=6,END=7,CHECK_RESULT=8,CHECK2=9;
 localparam integer ROW_BYTES=((WIDTH*3+3)/4)*4;
 localparam integer IMAGE_BYTES=ROW_BYTES*HEIGHT;
 reg [3:0] state;reg [7:0] header[0:53];
 reg [31:0] size,pos,offset,wait_count,pixels,row_pos;
 reg [1:0] channel;reg [7:0] blue,green;reg bad,file_seen;
 reg [3:0] header_bad;
 reg [32:0] image_end;
 `define B16(a) {header[(a)+1],header[(a)]}
 `define B32(a) {header[(a)+3],header[(a)+2],header[(a)+1],header[(a)]}
 assign busy=state!=IDLE;
 // Once malformed, drain the remaining file rather than inventing file-layer cancel.
 assign data_ready=(state==HEADER || state==BODY || state==DRAIN) && !pixel_valid;
 task automatic fail;
 begin bad<=1;write_req<=0;pixel_valid<=0;state<=DRAIN;end endtask
 always @(posedge clk) begin
  if(rst) begin state<=IDLE;write_req<=0;frame_start<=0;pixel_valid<=0;
   done<=0;error<=0;pixel<=0;pos<=0;bad<=0;file_seen<=0;wait_count<=0;end
  else begin
   frame_start<=0;done<=0;error<=0;
   // Count freely in states where the value is irrelevant. Every timed
   // state still starts at zero and progress resets it, avoiding a global
   // enable path from FIFO readiness to all counter registers.
   wait_count<=wait_count+1;
   if(pixel_valid && write_ready) pixel_valid<=0;
   if(file_done) file_seen<=1;
   if(file_error && state!=IDLE) begin error<=1;state<=IDLE;write_req<=0;pixel_valid<=0;end
   else case(state)
    IDLE: if(start) begin
     size<=file_size;pos<=0;pixels<=0;channel<=0;row_pos<=0;bad<=0;file_seen<=0;
     pixel_valid<=0;wait_count<=0;state<=HEADER;
    end
    HEADER: begin
     if(data_valid && data_ready) begin header[pos]<=data;pos<=pos+1;if(pos==53) state<=CHECK;end
     if(file_seen || file_done) begin bad<=1;state<=END;end
    end
    CHECK: begin
     header_bad[0]<=header[0]!=8'h42 || header[1]!=8'h4d || `B32(2)!=size || `B32(6)!=0;
     header_bad[1]<=`B32(14)!=40 || `B32(18)!=WIDTH || `B32(22)!=HEIGHT;
      state<=CHECK2;
     end
     CHECK2: begin
     header_bad[2]<=`B16(26)!=1 || `B16(28)!=24 || `B32(30)!=0;
     header_bad[3]<=(`B32(34)!=0 && `B32(34)!=IMAGE_BYTES) || `B32(46)!=0 || `B32(50)!=0 || `B32(10)<54;
     image_end<={1'b0,`B32(10)}+IMAGE_BYTES;
     state<=CHECK_RESULT;
    end
    CHECK_RESULT: begin
     if(|header_bad || image_end!={1'b0,size}) fail();
     else begin offset<=`B32(10);write_req<=1;state<=ACK;wait_count<=0;end
    end
    ACK: if(write_req_ack) begin write_req<=0;frame_start<=1;state<=PRIME;wait_count<=0;end
      else if(wait_count>=WAIT_CYCLES) fail();else wait_count<=wait_count+1;
    PRIME: if(!frame_start && write_ready && source_permit) begin state<=BODY;wait_count<=0;end
      else if(wait_count>=WAIT_CYCLES) fail();else wait_count<=wait_count+1;
    BODY: begin
     if(pixel_valid && !write_ready) begin
      if(wait_count>=WAIT_CYCLES) fail();else wait_count<=wait_count+1;
     end else wait_count<=0;
     if(data_valid && data_ready) begin
      pos<=pos+1;
      if(pos>=offset && pos<offset+IMAGE_BYTES) begin
       if(row_pos<WIDTH*3) begin
        case(channel)
         0:begin blue<=data;channel<=1;end
         1:begin green<=data;channel<=2;end
         2:begin pixel<={data,green,blue};pixel_valid<=1;pixels<=pixels+1;channel<=0;end
        endcase
       end
       if(row_pos==ROW_BYTES-1) begin row_pos<=0;channel<=0;end else row_pos<=row_pos+1;
      end
     end
     if(file_seen || file_done) state<=END;
    end
    DRAIN: if(file_seen || file_done) state<=END;
    END: if(!pixel_valid || write_ready) begin
     if(!bad && pos==size && pixels==WIDTH*HEIGHT && row_pos==0 && channel==0) done<=1;
     else error<=1;
     state<=IDLE;
    end
    default:fail();
   endcase
  end
 end
 `undef B16
 `undef B32
endmodule
