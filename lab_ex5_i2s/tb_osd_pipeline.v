`timescale 1ns/1ps
// Compare unchanged status/waveform pixels against the original composition
// with exactly three extra cycles; preload identical real waveform buffers.
module tb_osd_pipeline;
reg clk=0;always #5 clk=~clk;
reg rst=1,hs=0,vs=0,de=0,av=0;reg [23:0] rgb=0,sample=0;
wire sh,sv,sd;wire [23:0] sr;
wire ch,cv,cd;wire [23:0] cr;
wire ah,asv,ad,bh,bv,bd;wire [23:0] ar,br;
osd_overlay #(.TEXT_Y_REL(8)) status(clk,rst,1'b1,1'b0,2'd0,hs,vs,de,rgb,sh,sv,sd,sr);
osd_text_renderer captions(clk,rst,1'b1,2'd0,sh,sv,sd,sr,ch,cv,cd,cr,1'b0);
waveform_overlay actual(clk,rst,1'b1,av,sample,ch,cv,cd,cr,ah,asv,ad,ar);
waveform_overlay baseline(clk,rst,1'b1,av,sample,sh,sv,sd,sr,bh,bv,bd,br);
reg [26:0] q0=0,q1=0,q2=0;
reg [26:0] expected;
integer errors=0,completed=0,checked=0,px=0,py=0,x,y,i;
reg prior_de=0;
always @(posedge clk) begin
 if(rst) begin q0<=0;q1<=0;q2<=0;end
 else begin q0<={bh,bv,bd,br};q1<=q0;q2<=q1;end
 #1;
 if(!rst) begin
  if({ah,asv,ad}!==q2[26:24]) begin errors=errors+1;if(errors<5)$display("PIPELINE TIMING FAIL");end
  if(ad) begin
   if(!(py>=410 && py<426 && px>=40 && px<296) &&
      !(py>=434 && py<450 && px>=40 && px<600)) begin
    if(ar!==q2[23:0]) begin errors=errors+1;if(errors<5)$display("PIPELINE RGB FAIL x=%0d y=%0d",px,py);end
    checked=checked+1;
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
 repeat(4)@(negedge clk);rst=0;
 av=1;
 for(i=0;i<1600;i=i+1)begin @(negedge clk);sample=(i%32)<<16;end
 av=0;repeat(10)@(negedge clk);
 tick(0,1,0,0);repeat(8)tick(0,0,0,0);
 for(y=0;y<480;y=y+1)begin
  for(x=0;x<640;x=x+1)tick(0,0,1,{x[7:0],y[7:0],8'h5a});
  repeat(8)tick(1,0,0,0);
 end
 repeat(12)tick(0,0,0,0);
 completed=1;$display("OSD STATUS/WAVEFORM PIPELINE COMPLETE checked=%0d errors=%0d",checked,errors);$finish;
end
endmodule
