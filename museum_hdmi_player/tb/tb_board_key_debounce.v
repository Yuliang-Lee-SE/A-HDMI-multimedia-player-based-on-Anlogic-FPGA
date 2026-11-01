`timescale 1ns/1ps

module tb_board_key_debounce;
    reg clk = 1'b0;
    reg rst = 1'b1;
    reg button_in = 1'b1;
    wire press_pulse;
    integer pulse_count = 0;

    always #0.5 clk = ~clk;

    always @(posedge clk)
        if (press_pulse)
            pulse_count = pulse_count + 1;

    board_key_debounce #(
        .CLK_FREQ_HZ (1_000_000),
        .DEBOUNCE_MS (1)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .button_in   (button_in),
        .press_pulse (press_pulse)
    );

    task check;
        input condition;
        input [8*64-1:0] message;
        begin
            if (!condition) begin
                $display("FAIL: %0s", message);
                $fatal(1);
            end
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // A short glitch must be ignored.
        button_in = 1'b0;
        repeat (200) @(posedge clk);
        button_in = 1'b1;
        repeat (1200) @(posedge clk);
        check(pulse_count == 0, "short glitch produced a key pulse");

        // A real press must emit exactly one pulse.
        button_in = 1'b0;
        repeat (1100) @(posedge clk);
        check(pulse_count == 1, "stable press did not emit exactly one pulse");
        button_in = 1'b1;
        repeat (1200) @(posedge clk);
        check(pulse_count == 1, "release emitted an extra pulse");

        // A second press must be accepted.
        button_in = 1'b0;
        repeat (1100) @(posedge clk);
        check(pulse_count == 2, "second stable press was not detected");

        $display("BOARD_KEY_DEBOUNCE_PASS");
        $finish;
    end

    initial begin
        #10_000_000;
        $display("BOARD_KEY_DEBOUNCE_FAIL timeout");
        $finish;
    end
endmodule
