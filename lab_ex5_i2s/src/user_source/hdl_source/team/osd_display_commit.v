`timescale 1ns/1ps
// Bundled-data CDC. Source holds bank/item/valid until ack_toggle returns.
// Commit only at a new video frame read request; forward that request one
// clock later so the selected bank settles before the memory-domain request.
module osd_display_commit #(parameter ITEM_W=2)(input clk,input rst,input src_toggle,
 input [1:0] src_bank,input [ITEM_W-1:0] src_item,input src_valid,
 input frame_read_req,input mem_read_ack,
 output reg read_req,output reg ack_toggle,
 output reg [1:0] bank,output reg [ITEM_W-1:0] item,output reg valid);
reg [2:0] req_sync;
reg [1:0] ack_sync;
reg frame_prev,accepted,await_ack;
reg captured,pending_valid;
reg [1:0] pending_bank;
reg [ITEM_W-1:0] pending_item;
always @(posedge clk or posedge rst) begin
 if(rst) begin
  req_sync<=0;ack_sync<=0;frame_prev<=0;accepted<=0;await_ack<=0;
  captured<=0;pending_valid<=0;pending_bank<=0;pending_item<=0;
  read_req<=0;ack_toggle<=0;bank<=0;item<=0;valid<=0;
 end else begin
  req_sync<={req_sync[1:0],src_toggle};ack_sync<={ack_sync[0],mem_read_ack};
  frame_prev<=frame_read_req;read_req<=frame_read_req;
  if(req_sync[2]!=captured) begin
   pending_bank<=src_bank;pending_item<=src_item;pending_valid<=src_valid;
   captured<=req_sync[2];
  end
  if(frame_read_req && !frame_prev && captured!=accepted) begin
   bank<=pending_bank;item<=pending_item;valid<=pending_valid;
   accepted<=captured;await_ack<=1;
  end
  if(await_ack && ack_sync[1]) begin ack_toggle<=accepted;await_ack<=0;end
 end
end
endmodule
