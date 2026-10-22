`timescale 1ns/1ps
module tb_bmp_headers;
 reg clk=0;always #5 clk=~clk;reg rst=1,start=0,dv=0,fdone=0,ferr=0,ack=0,wrdy=1,permit=1;
 reg [7:0] data=0,header[0:53];reg [31:0] size=921654;
 wire ready,req,frame,pvalid,done,error,busy;wire [23:0] pixel;
 integer passes=0,i,j,offsets[0:12];reg saw_error=0,saw_done=0;
 bmp_file_stream #(.WAIT_CYCLES(30)) dut(clk,rst,start,size,dv,ready,data,fdone,ferr,req,ack,wrdy,permit,frame,pvalid,pixel,done,error,busy);
 always @(posedge clk) begin if(error)saw_error<=1;if(done)saw_done<=1;end
 task put32(input integer at,input integer value);begin for(j=0;j<4;j=j+1)header[at+j]=(value>>(j*8))&255;end endtask
 task base;
 begin for(i=0;i<54;i=i+1)header[i]=0;header[0]=8'h42;header[1]=8'h4d;
 put32(2,921654);put32(10,54);put32(14,40);put32(18,640);put32(22,480);header[26]=1;header[28]=24;put32(34,921600);end endtask
 task begin_file;
 begin @(negedge clk);saw_error=0;saw_done=0;start=1;@(negedge clk);start=0;
 for(integer b=0;b<54;b=b+1) begin wait(ready);data=header[b];dv=1;@(negedge clk);dv=0;end
 repeat(3) @(negedge clk);end endtask
 task finish_bad;
 begin fdone=1;@(negedge clk);fdone=0;wait(!busy);repeat(2) @(negedge clk);
 if(!saw_error || saw_done)$fatal(1,"FAIL bad BMP accepted");passes=passes+1;end endtask
 initial begin
  offsets[0]=0;offsets[1]=2;offsets[2]=6;offsets[3]=10;offsets[4]=14;offsets[5]=18;offsets[6]=22;
  offsets[7]=26;offsets[8]=28;offsets[9]=30;offsets[10]=34;offsets[11]=46;offsets[12]=50;
  repeat(5) @(negedge clk);rst=0;
  for(integer n=0;n<13;n=n+1) begin
   base();header[offsets[n]]=header[offsets[n]]^8'h80;begin_file();
   if(req || dut.state!=6)$fatal(1,"FAIL field offset=%0d not rejected before pixels",offsets[n]);finish_bad();
  end
  base();size=54;begin_file();if(req)$fatal(1,"FAIL short directory length");finish_bad();size=921654;
  base();begin_file();if(!req)$fatal(1,"FAIL valid header");ack=1;@(negedge clk);ack=0;
  wait(ready);data=255;dv=1;repeat(15) begin @(negedge clk);while(!ready) @(negedge clk);end
  dv=0;finish_bad(); // legal header, incomplete pixels
  base();begin_file();repeat(40) @(negedge clk);if(req)$fatal(1,"FAIL ACK timeout");finish_bad();
  base();permit=0;begin_file();ack=1;@(negedge clk);ack=0;repeat(40) @(negedge clk);
  if(dut.state!=6)$fatal(1,"FAIL PRIME timeout");finish_bad();permit=1;
  $display("BMP_HEADERS_PASS cases=%0d",passes);$finish;
 end
 initial begin #200000;$fatal(1,"header watchdog state=%0d",dut.state);end
endmodule
