`timescale 1ns/1ps
module tb_bmp_center_zoom_2x;
parameter W=8, H=8;
reg clk=0;
always #5 clk=~clk;
reg rst=1, frame_start=0, zoom_enable=0, in_valid=0;
reg [23:0] in_rgb=0;
reg out_ready=0;
wire out_valid, out_last, out_frame_last, source_done, output_done, overflow;
wire [23:0] out_rgb;
integer errors=0, received=0, cycles=0;
reg checking=0, expected_zoom=0, force_stall=0;
integer completed=0;
reg [23:0] held_rgb;
reg held_last, held_frame_last, held=0;
integer sx, sy;
reg [23:0] expected;
bmp_center_zoom_2x #(.WIDTH(W),.HEIGHT(H)) dut (
    .clk(clk),.rst(rst),.frame_start(frame_start),.zoom_enable(zoom_enable),
    .in_valid(in_valid),.in_rgb(in_rgb),.out_valid(out_valid),.out_ready(out_ready),
    .out_rgb(out_rgb),.out_last(out_last),.out_frame_last(out_frame_last),
    .source_done(source_done),.output_done(output_done),.overflow(overflow)
);
always @(negedge clk) begin
    cycles=cycles+1;
    out_ready=!force_stall && (cycles%7 != 0 && cycles%7 != 1);
end
always @(posedge clk) begin
    if (rst || frame_start || !checking) held=0;
    else begin
        if (held && (!out_valid || out_rgb !== held_rgb ||
                     out_last !== held_last || out_frame_last !== held_frame_last)) begin
            $display("[FAIL] Output changed during back-pressure"); errors=errors+1;
        end
        held=out_valid && !out_ready;
        held_rgb=out_rgb; held_last=out_last; held_frame_last=out_frame_last;
        if (out_valid && out_ready) begin
            sx=expected_zoom ? (W-W/2)/2+(received%W)/2 : received%W;
            sy=expected_zoom ? (H-H/2)/2+(received/W)/2 : received/W;
            expected=sy*W+sx+24'h112200;
            if (received>=W*H || out_rgb !== expected ||
                out_last !== (received%W == W-1) ||
                out_frame_last !== (received == W*H-1)) begin
                if (errors<10) $display("[FAIL] pixel %0d got %h expected %h",received,out_rgb,expected);
                errors=errors+1;
            end
            received=received+1;
        end
    end
end
task start_frame;
input mode;
begin
    @(negedge clk); frame_start=1; zoom_enable=mode; in_valid=0;
    @(negedge clk); frame_start=0; received=0; expected_zoom=mode;
end
endtask
task send_frame;
integer i;
begin
    for(i=0;i<W*H;i=i+1) begin
        @(negedge clk); in_valid=1; in_rgb=24'h112200+i;
        @(negedge clk); in_valid=0;
        repeat(6) @(negedge clk);
        // External selection changes mid-frame must not change latched mode.
        if(i==W*H/2) zoom_enable=!zoom_enable;
    end
end
endtask
task good_frame;
input mode;
begin
    start_frame(mode); checking=1;
    send_frame;
    wait(output_done); repeat(3) @(negedge clk);
    if (!source_done || overflow || received!=W*H) begin
        $display("[FAIL] Incomplete frame mode=%0d count=%0d overflow=%b",mode,received,overflow);
        errors=errors+1;
    end else $display("[PASS] %0dx%0d mode=%0d pixels=%0d, border/last/handshake correct",W,H,mode,received);
    checking=0;
end
endtask
initial begin
    repeat(4) @(negedge clk); rst=0;
    good_frame(0); good_frame(1); good_frame(0);
    if(W==8 && H==8) begin
        force_stall=1; start_frame(1); send_frame;
        if(!overflow || output_done) begin errors=errors+1; $display("[FAIL] Missing zoom overflow protection"); end
        else $display("[PASS] Unpausable input overflow detected; frame not marked complete");
        // Start discards the damaged frame and resets line-bank ownership.
        force_stall=0; good_frame(1);
        force_stall=1; start_frame(0); send_frame;
        if(!overflow || output_done) begin errors=errors+1; $display("[FAIL] Missing pass-through overflow protection"); end
        else $display("[PASS] Pass-through overflow detected");
        @(negedge clk); rst=1;
        repeat(3) @(negedge clk); rst=0; force_stall=0;
        good_frame(0);
    end
    completed=1;
    if(errors==0) $display("[TEST PASS] BMP center zoom and 1x/2x/1x frame switching are correct.");
    else $display("[TEST FAIL] errors=%0d",errors);
    $finish;
end
initial begin
    #200000000;
    errors=errors+1;
    $display("[TEST FAIL] Simulation timeout"); $finish;
end
endmodule
