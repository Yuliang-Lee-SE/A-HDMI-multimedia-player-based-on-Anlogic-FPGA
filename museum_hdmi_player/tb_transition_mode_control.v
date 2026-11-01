`timescale 1ns/1ps

module tb_transition_mode_control;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg key = 1'b1;
    wire [1:0] mode;
    wire setting_active;
    wire mode_change_toggle;
    wire next_press;

    integer errors = 0;
    integer next_press_count = 0;

    transition_mode_control #(
        .CLK_FREQ_HZ (1000),
        .DEBOUNCE_MS (2),
        .LONG_MS     (10)
    ) dut (
        .clk                (clk),
        .rst                (rst),
        .key                (key),
        .mode               (mode),
        .setting_active     (setting_active),
        .mode_change_toggle (mode_change_toggle),
        .next_press         (next_press)
    );

    always @(posedge clk) begin
        if (!rst && next_press)
            next_press_count <= next_press_count + 1;
    end

    task check;
        input condition;
        input [8*80-1:0] message;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s", message);
            end
        end
    endtask

    task short_press;
        begin
            @(negedge clk);
            key = 1'b0;
            repeat (4) @(negedge clk);
            key = 1'b1;
            repeat (6) @(negedge clk);
        end
    endtask

    task long_press;
        begin
            @(negedge clk);
            key = 1'b0;
            repeat (16) @(negedge clk);
            key = 1'b1;
            repeat (6) @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;
        repeat (3) @(negedge clk);
        check(mode == 2'd0, "default mode must be hard cut");
        check(!setting_active, "configuration mode must start inactive");

        short_press;
        check(next_press_count == 1, "short press outside setup advances image");
        check(mode == 2'd0, "short press outside setup must not change mode");

        long_press;
        check(setting_active, "long press must enter configuration mode");
        check(next_press_count == 1, "long press must not advance image");

        short_press;
        check(mode == 2'd1, "first setup press selects slide");
        check(next_press_count == 1, "setup press must not advance image");

        short_press;
        check(mode == 2'd2, "second setup press selects blinds");
        short_press;
        check(mode == 2'd3, "third setup press selects crossfade");
        short_press;
        check(mode == 2'd0, "fourth setup press wraps to hard cut");

        long_press;
        check(!setting_active, "second long press must exit configuration mode");
        check(next_press_count == 1, "exit long press must not advance image");

        short_press;
        check(next_press_count == 2, "short press after exit advances image");
        check(mode == 2'd0, "mode remains selected after exit");

        if (errors == 0)
            $display("TRANSITION_MODE_CONTROL_PASS");
        else
            $display("TRANSITION_MODE_CONTROL_FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("[FAIL] timeout");
        $finish;
    end
endmodule
