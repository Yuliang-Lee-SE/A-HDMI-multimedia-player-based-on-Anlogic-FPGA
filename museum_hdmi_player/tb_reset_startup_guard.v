`timescale 1ns/1ps

module tb_reset_startup_guard;
reg clk = 0;
always #5 clk = ~clk;

reg raw_rst_n = 1'b0;
wire reset_n;
integer errors = 0;

reset_startup_guard #(
    .CLK_HZ(1000),
    .STARTUP_HOLD_MS(5),
    .LOCKOUT_MS(20)
) dut (
    .clk(clk),
    .raw_rst_n(raw_rst_n),
    .reset_n(reset_n)
);

task press_reset;
begin
    raw_rst_n = 1'b0;
    repeat (10) @(posedge clk);
    raw_rst_n = 1'b1;
    repeat (10) @(posedge clk);
end
endtask

task check_high;
input [255:0] message;
begin
    if (reset_n !== 1'b1) begin
        errors = errors + 1;
        $display("[FAIL] %0s", message);
    end
end
endtask

initial begin
    repeat (5) @(posedge clk);
    if (reset_n !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] reset must be held after power-on");
    end

    raw_rst_n = 1'b1;
    wait (reset_n === 1'b1);
    $display("[PASS] startup hold released");

    press_reset;
    check_high("button press inside lockout must be ignored");

    wait (dut.state == 2'd3);
    press_reset;
    if (reset_n !== 1'b0) begin
        errors = errors + 1;
        $display("[FAIL] reset after lockout must be accepted");
    end else begin
        $display("[PASS] reset after lockout accepted");
    end

    raw_rst_n = 1'b1;
    wait (reset_n === 1'b1);
    press_reset;
    check_high("post-reset lockout must start again");

    if (errors == 0) $display("RESET_STARTUP_GUARD_PASS");
    else $display("RESET_STARTUP_GUARD_FAIL errors=%0d", errors);
    $finish;
end

initial begin
    #100000;
    $display("RESET_STARTUP_GUARD_FAIL timeout");
    $finish;
end
endmodule
