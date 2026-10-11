
module tb_half_canvas;
reg clk=0; always #5 clk=~clk;
reg rst=1,start=0,valid=0,ready=0,half=0,zoom=0;
reg [23:0] rgb;
wire ov,ol,ofl,sd,od,err,permit;
wire [23:0] data;
integer errors=0,completed=0,count=0,cycles=0,mode=0;
integer sx,sy,i,black_count,image_count;
reg stalled=0; reg [23:0] held; reg hl,hf;
reg [23:0] expected;
bmp_center_zoom_2x #(.ENABLE_HALF(1)) dut(
 .clk(clk),.rst(rst),.frame_start(start),.zoom_enable(zoom),.half_enable(half),
 .source_permit(permit),.in_valid(valid),.in_rgb(rgb),.out_valid(ov),
 .out_ready(ready),.out_rgb(data),.out_last(ol),.out_frame_last(ofl),
 .source_done(sd),.output_done(od),.overflow(err));
always @(negedge clk) begin cycles=cycles+1; ready=cycles%11>2; end
always @(posedge clk) if(!rst && !start) begin
 if(stalled && (!ov || data!==held || ol!==hl || ofl!==hf)) begin
  errors=errors+1; $display("[FAIL] output changed while stalled");
 end
 stalled=ov && !ready; held=data; hl=ol; hf=ofl;
 if(ov && ready) begin
  sx=count%640; sy=count/640;
  if(mode==1) begin sx=160+sx/2; sy=120+sy/2; end
  if(mode==2) begin sx=2*(sx-160); sy=2*(sy-120)+1; end
  expected=24'h112200+sy*640+sx;
  if(mode==2 && (count%640<160 || count%640>=480 || count/640<120 || count/640>=360)) begin
   expected=0; black_count=black_count+1;
  end else image_count=image_count+1;
  if(data!==expected || ol!==(count%640==639) || ofl!==(count==307199)) begin
   if(errors<8) $display("[FAIL] mode=%0d pixel=%0d data=%h expected=%h",mode,count,data,expected);
   errors=errors+1;
  end
  count=count+1;
 end
end
task frame;
input integer m;
begin
 @(negedge clk); mode=m; half=m==2; zoom=m==1; start=1;
 count=0; black_count=0; image_count=0; stalled=0;
 @(negedge clk); start=0;
 wait(permit);
 for(i=0;i<307200;i=i+1) begin
  @(negedge clk); valid=1; rgb=24'h112200+i;
  @(negedge clk); valid=0;
  repeat(6) @(negedge clk);
 end
 wait(od); repeat(4) @(negedge clk);
 if(!sd || err || count!=307200 || (m==2 && (black_count!=230400 || image_count!=76800))) errors=errors+1;
 $display("[FRAME] mode=%0d count=%0d black=%0d image=%0d overflow=%b",m,count,black_count,image_count,err);
end
endtask
initial begin
 repeat(4) @(negedge clk); rst=0;
 frame(0); frame(1); frame(2); frame(0); frame(2);
 completed=1;
 if(errors==0) $display("[TEST PASS] full-size three-mode canvas and stalls");
 else $display("[TEST FAIL] errors=%0d",errors);
 $finish;
end
initial begin #200000000; errors=errors+1; $display("[FAIL] timeout"); $finish; end
endmodule
