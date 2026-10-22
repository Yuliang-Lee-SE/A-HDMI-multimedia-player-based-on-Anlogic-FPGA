`timescale 1ns/1ps
module tb_osd_layers_video;
reg video_clk=0,mem_clk=0;
always #20 video_clk=~video_clk;
always #4 mem_clk=~mem_clk;
reg rst=1,toggle=0;reg [1:0] src_bank=0,src_item=0;
wire req,ack,forward,hs,vs,de,valid,commit_ack;
wire [1:0] bank,item;
wire [20:0] address;wire app_en;
wire [9:0] dummy;
integer errors=0,completed=0,frames=0,commits=0;
video_timing_data timing(.video_clk(video_clk),.rst(rst),.read_req(req),.read_req_ack(ack),.hs(hs),.vs(vs),.de(de));
osd_display_commit bridge(video_clk,rst,toggle,src_bank,src_item,1'b1,req,ack,forward,commit_ack,bank,item,valid);
frame_fifo_read #(.BURST_SIZE(256)) reader(
 .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(1'b0),.App_wr_busy(1'b0),.O_rd_busy(),.App_rd_en(app_en),.App_rd_addr(address),
 .read_req(forward),.read_req_ack(ack),.read_finish(),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_addr_index(bank),.read_len(21'd307200),.fifo_aclr(),.wrusedw(9'd0));
wire caption_hs,caption_vs,caption_de;wire [23:0] caption_rgb;
osd_layer_renderer #(.DEFAULT_STEP(1),.SCROLL_HEAD_FRAMES(0),.SCROLL_TAIL_FRAMES(0)) captions(
 video_clk,rst,valid,1'b0,item,item[1:0],1'b1,hs,vs,de,24'h123456,caption_hs,caption_vs,caption_de,caption_rgb,
 1'b0,,1'b1,10'd24,10'd380,3'd3,1'b1,1'b0,4'd1);
reg prev_req=0,prev_de=0,prev_ack=0;
reg [1:0] old_bank=0,old_item=0;
reg old_valid=0;
reg [20:0] locked_base=0;
always @(posedge mem_clk) begin
 if(!rst && reader.state==1) begin
  #1;locked_base=reader.App_rd_addr_r;
 end
end
always @(posedge video_clk) begin
 if(!rst) begin
  if(req && !prev_req) frames=frames+1;
  prev_req=req;
  #1;
  if({bank,item,valid}!={old_bank,old_item,old_valid}) begin
   commits=commits+1;
   if(de || !req) begin errors=errors+1;$display("[FAIL] Real video commit outside blanking/read boundary");end
  end
  if(commit_ack!=prev_ack) begin
   if(locked_base!=(bank==0 ? 0 : 307200)) begin
    errors=errors+1;$display("[FAIL] Ack before real memory bank latch");
   end
   prev_ack=commit_ack;
  end
  old_bank=bank;old_item=item;old_valid=valid;
 end
end
task publish;
input [1:0] b,id;
begin
 @(negedge video_clk);src_bank=b;src_item=id;toggle=~toggle;
 wait(commit_ack==toggle);repeat(8)@(negedge video_clk);
 if(bank!=b || item!=id || !valid)begin errors=errors+1;$display("[FAIL] Atomic payload mismatch");end
end
endtask
initial begin
 repeat(5)@(negedge video_clk);rst=0;
 publish(0,0);
 @(posedge vs);repeat(5)@(negedge video_clk);
 if(captions.scroll_offset!=0)begin errors=errors+1;$display("[FAIL] First item scroll did not start at zero");end
 wait(de);publish(1,1);
 // A simultaneous two-bit ID change must not expose intermediate IDs.
 wait(de);publish(0,2);
 @(posedge vs);repeat(5)@(negedge video_clk);
 if(captions.scroll_offset!=0 || captions.scroll.seen_item!=2)begin errors=errors+1;$display("[FAIL] Committed new ID did not reset scroll");end
 // Same exhibit, different bank (zoom reload).
 wait(de);publish(1,2);
 @(posedge vs);repeat(5)@(negedge video_clk);
 if(captions.scroll.phase!=1)begin errors=errors+1;$display("[FAIL] Same-ID zoom restarted head pause");end
 @(posedge vs);repeat(5)@(negedge video_clk);
 if(captions.scroll_offset!=1)begin errors=errors+1;$display("[FAIL] Same-ID trajectory did not continue");end
 completed=1;$display("OSD P3 REAL VIDEO COMMIT COMPLETE frames=%0d commits=%0d errors=%0d",frames,commits,errors);$finish;
end
initial begin #200000000;errors=errors+1;$display("[FAIL] Video commit timeout");$finish;end
endmodule
