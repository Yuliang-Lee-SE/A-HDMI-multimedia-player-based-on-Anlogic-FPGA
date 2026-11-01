`timescale 1ns/1ps
module tb_wav_pcm_loader;
reg clk=0,rst=1,start=0,data_valid=0,file_done=0,file_error=0;
reg [7:0] data=0;
wire data_ready,ram_we,done,error,busy;
wire [14:0] ram_addr;
wire [15:0] ram_data;
wire [15:0] sample_count;
reg [15:0] captured[0:15];
integer writes=0;
integer i;

always #5 clk=~clk;

wav_pcm_loader #(.RAM_DEPTH(24576)) dut(
 .clk(clk),.rst(rst),.start(start),.data_valid(data_valid),.data_ready(data_ready),
 .data(data),.file_done(file_done),.file_error(file_error),
 .ram_we(ram_we),.ram_addr(ram_addr),.ram_data(ram_data),
 .done(done),.error(error),.sample_count(sample_count),.busy(busy));

always @(posedge clk) if(ram_we) begin
 captured[writes]<=ram_data;
 writes<=writes+1;
end

task send_byte(input [7:0] value);
begin
 data=value;data_valid=1;
 while(!data_ready) @(posedge clk);
 @(posedge clk);
 data_valid=0;
 #1;
end
endtask

task begin_wav;
begin
 start=1;@(posedge clk);start=0;
 send_byte("R");send_byte("I");send_byte("F");send_byte("F");
 send_byte(8'd36);send_byte(0);send_byte(0);send_byte(0);
 send_byte("W");send_byte("A");send_byte("V");send_byte("E");
 send_byte("f");send_byte("m");send_byte("t");send_byte(" ");
 send_byte(16);send_byte(0);send_byte(1);send_byte(0);
 send_byte(1);send_byte(0);
 send_byte(8'd64);send_byte(8'd31);send_byte(0);send_byte(0);
 send_byte(8'd128);send_byte(8'd62);send_byte(0);send_byte(0);
 send_byte(2);send_byte(0);send_byte(16);send_byte(0);
 send_byte("d");send_byte("a");send_byte("t");send_byte("a");
 send_byte(16);send_byte(0);send_byte(0);send_byte(0);
end
endtask

initial begin
 repeat(3) @(posedge clk);
 rst=0;
 repeat(2) @(posedge clk);
 begin_wav();
 send_byte(8'h34);send_byte(8'h12);
 send_byte(8'hFE);send_byte(8'hFF);
 send_byte(8'h00);send_byte(8'h80);
 send_byte(8'hFF);send_byte(8'h7F);
 send_byte(8'h01);send_byte(8'h00);
 send_byte(8'h02);send_byte(8'h00);
 send_byte(8'h03);send_byte(8'h00);
 send_byte(8'h04);send_byte(8'h00);
 @(posedge clk);
 if(writes!=8) $fatal(1,"FAIL write count %0d",writes);
 if(captured[0]!=16'h1234 || captured[1]!=16'hFFFE ||
    captured[2]!=16'h8000 || captured[3]!=16'h7FFF)
  $fatal(1,"FAIL PCM little-endian samples");
 file_done=1;@(posedge clk);#1;
 if(!done || error || sample_count!=8) $fatal(1,"FAIL completion");
 if(busy) $fatal(1,"FAIL busy after completion");
 file_done=0;
 $display("=== S6 WAV PCM loader PASS ===");
 $finish;
end

initial begin
 #200000;
 $fatal(1,"FAIL timeout");
end
endmodule
