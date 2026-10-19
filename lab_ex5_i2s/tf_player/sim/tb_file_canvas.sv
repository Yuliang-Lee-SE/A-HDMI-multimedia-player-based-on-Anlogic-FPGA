`timescale 1ns/1ps
module tb_file_canvas;
 parameter MAX_FILES=32;
 reg clk=0;always #5 clk=~clk;
 reg rst=1,mount=0,open=0,start=0;reg [13:0] id=1;
 reg [31:0] media=66581;reg [5:0] slot=0;wire [13:0] index_id;wire [31:0] size;
 wire mounted,mdone,mready,oready,ivalid,valid,ready,fdone,err;
 wire [7:0] fdata,ecode;wire [$clog2(MAX_FILES+1)-1:0] count;
 wire req;wire [31:0] lba,reqtag;reg [31:0] tag=0;reg rv=0,rd=0,re=0;
 reg [7:0] data=0;wire cancel;wire [31:0] ctag;
 reg sending=0;integer at=0,delay=0,fd,seek,n,requests=0,fail_at=0;
 reg [7:0] sector[0:511];string image;
 wire wr_req,frame,bv,bd,be,bb;wire [23:0] pixel;reg ack=0,armed=0;
 reg [1:0] zoom=0;wire zv,zs,zd,zo,permit;wire [23:0] rgb;
 integer pixels=0,source_pixels=0,mode=0,mutate=0,byte_pos=0,passes=0;
 reg bout=0,berr=0;reg wready=1;integer cycle=0;
 wire [7:0] parsed_data=(mutate!=0 && byte_pos==mutate) ? fdata^8'h80:fdata;
 fat32_ro #(.MAX_FILES(MAX_FILES),.MAX_CHAIN(2048),.IO_TIMEOUT(100000),.STALL_TIMEOUT(1000000)) fs(
 .clk(clk),.rst(rst),.mount_valid(mount),.mount_ready(mready),.media_sectors(media),.mounted(mounted),.mount_done(mdone),
 .file_count(count),.index_slot(slot[$clog2(MAX_FILES)-1:0]),.index_valid(ivalid),.index_id(index_id),.index_size(size),
 .open_valid(open),.open_ready(oready),.open_id(id),.data_valid(valid),.data_ready(ready),.data(fdata),.file_done(fdone),
 .error_valid(err),.error_code(ecode),.req_valid(req),.req_ready(!sending),.req_lba(lba),.req_tag(reqtag),
 .rsp_tag(tag),.rsp_valid(rv),.rsp_data(data),.rsp_done(rd),.rsp_error(re),.cancel_valid(cancel),.cancel_tag(ctag));
 bmp_file_stream #(.WAIT_CYCLES(1000000)) bmp(.clk(clk),.rst(rst),.start(start),.file_size(size),
 .data_valid(valid),.data_ready(ready),.data(parsed_data),.file_done(fdone),.file_error(err),
 .write_req(wr_req),.write_req_ack(ack),.write_ready(wready && armed),.source_permit(permit),
 .frame_start(frame),.pixel_valid(bv),.pixel(pixel),.done(bd),.error(be),.busy(bb));
 bmp_center_zoom_2x #(.ENABLE_HALF(1)) scaler(.clk(clk),.rst(rst || start),.frame_start(frame),
 .zoom_enable(zoom==1),.half_enable(zoom==2),.source_permit(permit),.in_valid(bv && wready && armed),.in_rgb(pixel),
 .out_valid(zv),.out_ready(wready && armed),.out_rgb(rgb),.out_last(),.out_frame_last(),.source_done(zs),.output_done(zd),.overflow(zo));
 function automatic [23:0] gold(input integer x,input integer y);
 reg [7:0] r,g,b;begin b=x+id;g=y*3+id;r=x^y^id;gold={r,g,b};end endfunction
 integer x,y,sx,sy;reg [23:0] expected;
 task check(input bit ok,input string text);begin if(!ok) begin $display("FAIL %s pixels=%0d state=%0d zoom=%0d",text,pixels,bmp.state,zoom);$fatal(1);end end endtask
 always @(posedge clk) begin
  cycle<=cycle+1;if(cycle>180000000) $fatal(1,"watchdog");
  wready<=cycle%29!=0; // bounded FIFO backpressure; no memory-model claim
  ack<=wr_req;
  if(start) begin armed<=0;bout<=0;berr<=0;pixels=0;byte_pos=0;source_pixels=0;end
  if(ack && !wr_req) armed<=1;
  if(valid && ready) byte_pos=byte_pos+1;
  if(bd) bout<=1;if(be) berr<=1;
  if(bv && wready && armed) source_pixels=source_pixels+1;
  if(zv && wready && armed) begin
   x=pixels%640;y=pixels/640;expected=0;
   if(zoom==0) expected=gold(x,y);
   else if(zoom==1) expected=gold(160+x/2,120+y/2);
   else if(x>=160 && x<480 && y>=120 && y<360) expected=gold((x-160)*2,(y-120)*2+1);
   check(rgb===expected,"canvas pixel");pixels=pixels+1;
  end
  if(zo) $fatal(1,"zoom overflow");
  rv<=0;rd<=0;re<=0;
  if(req && !sending) begin
   requests=requests+1;tag<=reqtag;at<=0;delay<=0;sending<=1;
   if(fail_at!=0 && requests==fail_at) begin re<=1;sending<=0;end
   else begin seek=$fseek(fd,lba*512,0);n=$fread(sector,fd);check(n==512,"image read");end
  end else if(sending) begin
   if(delay==0) begin
    rv<=1;data<=sector[at];delay<=7;
    if(at==511) begin rd<=1;sending<=0;end else at<=at+1;
   end else delay<=delay-1;
  end
 end
 task load(input integer z,input integer asset,input integer corruption,input bit expect_error);
 begin
  wait(oready);@(negedge clk);zoom=z;id=asset;slot=(asset==9999 ? MAX_FILES-1:asset-1);mutate=corruption;
  @(negedge clk);open=1;start=1;@(negedge clk);open=0;start=0;
  wait(bout || berr);if(expect_error) check(berr && !bout,"reject invalid file");
  else begin wait(zd);check(bout && !berr && pixels==307200 && source_pixels==307200 && zs,"complete frame");end
  passes=passes+1;$display("CANVAS case=%0d asset=%0d zoom=%0d checked=%0d error=%0d",passes,asset,z,pixels,berr);
  repeat(10) @(negedge clk);
 end endtask
 initial begin
  if(!$value$plusargs("IMAGE=%s",image)) $fatal(1,"IMAGE required");
  n=$value$plusargs("MEDIA=%d",media);fd=$fopen(image,"rb");check(fd!=0,"open image");
  repeat(5) @(negedge clk);rst=0;mount=1;@(negedge clk);mount=0;wait(mdone || err);
  check(mdone && count==MAX_FILES,"full count");slot=MAX_FILES-1;#1;wait(ivalid);#1;check(index_id==9999,"wide ID sorted");
  load(0,1,0,0);load(1,4,0,0);load(2,5,0,0);load(0,9999,0,0);
  load(0,1,28,1); // valid FAT but invalid bits-per-pixel header
  fail_at=requests+8;load(0,1,0,1);fail_at=0;load(0,1,0,0);
  $display("FILE_CANVAS_PASS cases=%0d max_files=%0d",passes,MAX_FILES);$finish;
 end
endmodule
