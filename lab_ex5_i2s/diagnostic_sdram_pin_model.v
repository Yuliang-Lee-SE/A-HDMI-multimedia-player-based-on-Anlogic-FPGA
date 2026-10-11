`timescale 1ns/1ps
// Test-only SDR SDRAM command model. NOT vendor silicon model or timing signoff.
// Implements ACTIVE, READ/WRITE, burst4, byte masks, auto-precharge and MRS.
// Storage is addressed by physical row/bank/column, not App_wr_addr.
module sdram_pin_model (
 input clk,input ras_n,input cas_n,input we_n,input [10:0] addr,
 input [1:0] ba,inout [31:0] dq,input [3:0] dm,
 output reg [31:0] protocol_errors
);
reg [31:0] memory [0:2097151];
reg [10:0] rows [0:3];
reg [3:0] open_banks=0;
integer burst_length=4,cas_latency=3;
integer write_left=0,read_left=0,read_wait=0,write_lane=0,read_lane=0,j;
reg [20:0] write_base,read_base;
reg [20:0] pending_read_base;
reg [1:0] write_bank,read_bank;
reg [1:0] pending_read_bank;
reg write_close=0,read_close=0,read_driving=0;
reg pending_read_close=0;
reg [31:0] read_q;
assign dq=read_driving ? read_q : 32'bz;
function [20:0] burst_address;
 input [20:0] start;
 input integer lane;
 begin burst_address={start[20:2],2'b00}+((start[1:0]+lane)&3);end
endfunction
task store_word;
 input [20:0] destination;
 begin
  for(j=0;j<4;j=j+1)
   if(!dm[j]) memory[destination][j*8+:8]=dq[j*8+:8];
 end
endtask
initial protocol_errors=0;
always @(posedge clk) begin
 if(write_left>0) begin
  store_word(burst_address(write_base,write_lane));
  write_left=write_left-1;write_lane=write_lane+1;
  if(write_left==0 && write_close) open_banks[write_bank]=0;
 end
 if(read_driving) begin
  if(read_left>0) begin
   read_q<=memory[burst_address(read_base,read_lane)];
   read_lane=read_lane+1;read_left=read_left-1;
  end else begin
   read_driving<=0;
   if(read_close) open_banks[read_bank]=0;
  end
 end
 if(read_wait>0) begin
  read_wait=read_wait-1;
  if(read_wait==0) begin
   read_base=pending_read_base;read_bank=pending_read_bank;read_close=pending_read_close;
   read_driving<=1;read_q<=memory[read_base];
   read_lane=1;read_left=burst_length-1;
  end
 end
 case({ras_n,cas_n,we_n})
  3'b000:begin burst_length=1<<addr[2:0];cas_latency=addr[6:4];end
  3'b010:begin if(addr[10]) open_banks=0;else open_banks[ba]=0;end
  3'b011:begin rows[ba]=addr;open_banks[ba]=1;end
  3'b100:begin
   if(!open_banks[ba] || write_left!=0) protocol_errors=protocol_errors+1;
   write_base={rows[ba],ba,addr[7:0]};write_bank=ba;write_close=addr[10];
   store_word(write_base);write_left=burst_length-1;write_lane=1;
  end
  3'b101:begin
   // A subsequent READ may arrive while the previous burst is still driving DQ.
   // Keep its CAS-delay metadata separate from the active output burst.
   if(!open_banks[ba] || read_wait!=0) protocol_errors=protocol_errors+1;
   pending_read_base={rows[ba],ba,addr[7:0]};pending_read_bank=ba;pending_read_close=addr[10];
   read_wait=cas_latency;
  end
 endcase
end
endmodule
