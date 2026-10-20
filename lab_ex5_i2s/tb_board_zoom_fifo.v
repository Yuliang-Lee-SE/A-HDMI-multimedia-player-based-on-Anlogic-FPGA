`timescale 1ns/1ps
// Real example FIFO/address scheduler, synthetic source and App write sink.
module tb_board_zoom_fifo;
localparam W=32, H=24, N=W*H;
reg clk=0, mem_clk=0, rst=1, start=0, zoom=0, valid=0, req=0;
always #5 clk=~clk;
always #4 mem_clk=~mem_clk;
reg [23:0] rgb=0;
reg [1:0] bank=0;
reg finished_seen=0;
wire out_valid, ready, source_done, output_done, overflow, ack, finish, wr_en;
wire [23:0] out_rgb;
wire [20:0] address;
wire [31:0] data;
wire [3:0] dm;
integer errors=0, completed=0, count=0, sx, sy, expected_addr, full_checks=0;
reg [23:0] expected;
bmp_center_zoom_2x #(.WIDTH(W),.HEIGHT(H)) scaler (
    .clk(clk),.rst(rst),.frame_start(start),.zoom_enable(zoom),.in_valid(valid),.in_rgb(rgb),
    .out_valid(out_valid),.out_ready(ready),.out_rgb(out_rgb),.out_last(),.out_frame_last(),
    .source_done(source_done),.output_done(output_done),.overflow(overflow)
);
frame_read_write #(.BURST_SIZE(128),.FRAME_WIDTH(W),.FRAME_HEIGHT(H)) store (
    .rst(rst),.mem_clk(mem_clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
    .App_rd_en(),.App_rd_addr(),.Sdr_rd_en(1'b0),.Sdr_rd_dout(32'd0),
    .read_clk(clk),.read_req(1'b0),.read_req_ack(),.read_finish(),
    .read_addr_0(21'd0),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
    .read_addr_index(2'd0),.read_len(21'd768),.read_en(1'b0),.read_data(),
    .App_wr_en(wr_en),.App_wr_addr(address),.App_wr_din(data),.App_wr_dm(dm),
    .write_clk(clk),.write_req(req),.write_req_ack(ack),.write_finish(finish),
    .write_addr_0(21'd0),.write_addr_1(21'd1024),.write_addr_2(21'd0),.write_addr_3(21'd0),
    .write_addr_index(bank),.write_len(21'd768),.write_en(out_valid&&ready),
    .write_data({out_rgb,8'b0}),.write_ready(ready)
);
always @(posedge mem_clk) if(!rst && wr_en) begin
    sx=zoom ? W/4+(count%W)/2 : count%W;
    sy=zoom ? H/4+(count/W)/2 : count/W;
    expected=24'h112200+sy*W+sx;
    expected_addr=bank*1024+(H-1-count/W)*W+count%W;
    if(count>=N || data !== {expected,8'b0} || address!==expected_addr || dm!==0) begin
        if(errors<8) $display("[FAIL] FIFO word=%0d data=%h expected=%h address=%0d expected=%0d",count,data,{expected,8'b0},address,expected_addr);
        errors=errors+1;
    end
    count=count+1;
end
always @(posedge mem_clk)
    if(rst || start) finished_seen<=0;
    else if(finish) finished_seen<=1;
task frame;
input mode;
integer i;
begin
    @(negedge clk); zoom=mode; start=1; req=1; count=0;
    if(mode) force store.App_rd_busy=1'b1;
    @(negedge clk); start=0;
    wait(ack); @(negedge clk); req=0;
    wait(ready);
    fork
        begin
            for(i=0;i<N;i=i+1) begin
                @(negedge clk); valid=1; rgb=24'h112200+i;
                @(negedge clk); valid=0;
                repeat(6) @(negedge clk);
            end
        end
        begin
            if(mode) begin
                wait(store.write_fifo_full);
                repeat(10) @(negedge clk);
                if(ready) begin errors=errors+1; $display("[FAIL] Ready stayed high while real FIFO full"); end
                else begin full_checks=full_checks+1; $display("[PASS] Real FIFO full pauses scaled output"); end
                release store.App_rd_busy;
            end
        end
    join
    wait(finished_seen); repeat(5) @(negedge clk);
    if(count!=N || overflow || !source_done || !output_done) begin
        errors=errors+1; $display("[FAIL] FIFO completion count=%0d overflow=%b",count,overflow);
    end else $display("[PASS] Real async FIFO / vertical address flip mode=%b buffer=%0d words=%0d",mode,bank,count);
end
endtask
initial begin
    repeat(5) @(negedge clk); rst=0;
    repeat(5) @(negedge clk);
    // Exercise sub-cycle asynchronous assertion at different clock phases.
    for(sx=1;sx<5;sx=sx+1) begin
        @(negedge clk); #(sx);
        force store.write_fifo_aclr=1'b1;
        #0.1;
        if(ready!==1'b0) begin errors=errors+1;$display("[FAIL] Reset did not asynchronously block ready");end
        #0.4;release store.write_fifo_aclr;
        wait(!store.write_reset_mem_hold);
        @(posedge clk);#0.1;
        if(ready!==1'b0) begin errors=errors+1;$display("[FAIL] Reset release phase=%0d first clock",sx);end
        @(posedge clk);#0.1;
        if(ready!==1'b0) begin errors=errors+1;$display("[FAIL] Reset release phase=%0d second clock",sx);end
        @(posedge clk);#0.1;
        if(ready!==1'b1) begin errors=errors+1;$display("[FAIL] Ready release did not take three write clocks");end
    end
    $display("[PASS] Async reset assertion and three-clock synchronous release checked");
    frame(0); bank=1; frame(1); bank=0; frame(0);
    if(full_checks!=1) errors=errors+1;
    completed=1;
    if(errors==0) $display("[TEST PASS] Center zoom to original FIFO/address scheduler is correct.");
    else $display("[TEST FAIL] FIFO errors=%0d",errors);
    $finish;
end
initial begin #1000000; errors=errors+1; $display("[TEST FAIL] FIFO timeout count=%0d state=%0d",count,store.frame_fifo_write_m0.state); $finish; end
endmodule
