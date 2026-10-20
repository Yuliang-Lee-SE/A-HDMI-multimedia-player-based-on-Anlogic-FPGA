`timescale 1ns/1ps
module tb_osd_layers_pipeline;
reg clk=0;always #5 clk=~clk;
reg rst=1,hs=0,vs=0,de=0,av=0;reg [23:0] rgb=0,sample=0;
reg cv=0,shadow=0;reg [2:0] alpha=4;
wire ready,ph,pv,pd,sh,sv,sd,ch,ccv,cd,ah,asv,ad,bh,bv,bd;
wire [23:0] pr,sr,cr,ar,br;
osd_layer_renderer layers(clk,rst,1'b1,1'b0,2'd0,hs,vs,de,rgb,ph,pv,pd,pr,
 cv,ready,1'b1,10'd24,10'd380,alpha,shadow,1'b0,4'd2);
osd_overlay #(.TEXT_Y_REL(8)) status(clk,rst,1'b1,1'b0,2'd0,hs,vs,de,rgb,sh,sv,sd,sr);
osd_text_renderer captions(clk,rst,1'b1,2'd0,sh,sv,sd,sr,ch,ccv,cd,cr,1'b0);
waveform_overlay actual(clk,rst,1'b1,av,sample,ph,pv,pd,pr,ah,asv,ad,ar);
waveform_overlay baseline(clk,rst,1'b1,av,sample,ch,ccv,cd,cr,bh,bv,bd,br);
wire dh,dv,dd,eh,ev,ed;wire [23:0] dr,er;
// Deliberate overlap in a test-only instance proves waveform priority.
waveform_overlay #(.WAV_Y(400)) overlap(clk,rst,1'b1,av,sample,ph,pv,pd,pr,dh,dv,dd,dr);
waveform_overlay #(.WAV_Y(400)) probe(clk,rst,1'b1,av,sample,ph,pv,pd,24'haabbcc,eh,ev,ed,er);
integer errors=0,completed=0,checked=0,overlap_checked=0,px=0,py=0,x,y,i,f;
reg prior_de=0;
always @(posedge clk) begin
 #1;
 if(!rst) begin
  if({ah,asv,ad}!=={bh,bv,bd})begin errors=errors+1;if(errors<5)$display("[FAIL] P3 total latency changed");end
  if(ad) begin
   if(f==0 || !(px>=24 && px<616 && py>=380 && py<456))begin
    if(ar!==br)begin errors=errors+1;if(errors<5)$display("[FAIL] P3 pipeline x=%0d y=%0d",px,py);end
    checked=checked+1;
   end
   if(er!=24'haabbcc && py>=400 && py<472)begin
    overlap_checked=overlap_checked+1;
    if(dr!==er)begin errors=errors+1;if(errors<5)$display("[FAIL] waveform priority");end
   end
   if(px==639)px=0;else px=px+1;
  end else if(prior_de)py=py+1;
  prior_de=ad;
 end
end
task tick;
input ih,iv,id;input [23:0] data;
begin @(negedge clk);hs=ih;vs=iv;de=id;rgb=data;end
endtask
initial begin
 repeat(4)@(negedge clk);rst=0;av=1;
 for(i=0;i<1600;i=i+1)begin @(negedge clk);sample=(i%32)<<16;end
 av=0;repeat(10)@(negedge clk);
 for(f=0;f<2;f=f+1)begin
  px=0;py=0;alpha=f==0 ? 4 : 3;shadow=f!=0;cv=1;
  tick(0,0,0,0);cv=0;tick(0,1,0,0);repeat(8)tick(0,0,0,0);
  for(y=0;y<480;y=y+1)begin
   for(x=0;x<640;x=x+1)tick(0,0,1,{x[7:0],y[7:0],8'h5a});
   repeat(8)tick(1,0,0,0);
  end
  repeat(12)tick(0,0,0,0);
 end
 if(overlap_checked==0)errors=errors+1;
 completed=1;$display("OSD P3 PIPELINE COMPLETE checked=%0d overlap=%0d errors=%0d",checked,overlap_checked,errors);$finish;
end
initial begin #20000000;errors=errors+1;$display("[FAIL] pipeline timeout");$finish;end
endmodule
