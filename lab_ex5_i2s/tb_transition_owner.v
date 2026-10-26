`timescale 1ns/1ps

module tb_transition_owner;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg frame_request = 1'b0;
    reg committed_valid = 1'b0;
    reg [1:0] committed_bank = 2'd0;
    reg [20:0] committed_item = 21'd0;
    reg commit_ack_toggle = 1'b0;

    wire [1:0] source_bank_a;
    wire [1:0] source_bank_b;
    wire read_dual;
    wire transition_active;
    wire [8:0] transition_progress;
    wire display_valid;
    wire [20:0] display_item;
    wire release_toggle;
    wire transition_busy;

    integer errors = 0;

    transition_frame_owner #(.TRANSITION_FRAMES(4)) dut (
        .clk                 (clk),
        .rst                 (rst),
        .frame_request       (frame_request),
        .committed_valid     (committed_valid),
        .committed_bank      (committed_bank),
        .committed_item      (committed_item),
        .source_commit_toggle(commit_ack_toggle),
        .source_bank_a       (source_bank_a),
        .source_bank_b       (source_bank_b),
        .read_dual           (read_dual),
        .transition_active   (transition_active),
        .transition_progress (transition_progress),
        .display_valid       (display_valid),
        .display_item        (display_item),
        .release_toggle      (release_toggle),
        .transition_busy     (transition_busy)
    );

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

    task frame;
        begin
            @(negedge clk);
            frame_request = 1'b1;
            @(negedge clk);
            frame_request = 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst = 1'b0;

        // First complete frame: hard cut and release bank 0.
        committed_valid = 1'b1;
        committed_bank = 2'd0;
        committed_item = {7'd1,14'd1};
        frame;
        commit_ack_toggle = 1'b1;
        repeat (5) @(negedge clk);
        check(display_valid, "first frame must become visible");
        check(display_item == {7'd1,14'd1}, "first frame metadata");
        check(!transition_active && !read_dual, "first frame must hard cut");
        check(source_bank_a == 0 && source_bank_b == 0, "first source bank");
        check(release_toggle == commit_ack_toggle, "first bank release");

        // Same asset, new bank: scale reload is a VS hard cut.
        committed_bank = 2'd1;
        frame;
        commit_ack_toggle = 1'b0;
        repeat (5) @(negedge clk);
        check(!transition_active, "scale reload must not slide");
        check(source_bank_a == 1 && !read_dual, "scale hard-cut source");
        check(release_toggle == commit_ack_toggle, "scale bank release");

        // Different asset: the first frame is a single-read warmup so both
        // line-buffer halves are armed before the dual-read slide starts.
        committed_bank = 2'd0;
        committed_item = {7'd2,14'd2};
        frame;
        check(transition_active && !read_dual, "image switch must start warmup");
        check(source_bank_a == 1 && source_bank_b == 0, "slide old/new banks");
        check(display_item == {7'd1,14'd1}, "old metadata during slide");
        commit_ack_toggle = 1'b1;
        repeat (2) @(negedge clk);
        check(release_toggle != commit_ack_toggle, "slide holds writer ack");

        frame;
        check(transition_active && read_dual, "warmup must enable dual read");
        repeat (3) frame;
        repeat (5) @(negedge clk);
        check(!transition_active && !read_dual, "slide must finish");
        check(source_bank_a == 0 && source_bank_b == 0, "new active bank");
        check(display_item == {7'd2,14'd2}, "new metadata after slide");
        check(release_toggle == commit_ack_toggle, "release after slide");

        if (errors == 0)
            $display("TRANSITION_OWNER_PASS");
        else
            $display("TRANSITION_OWNER_FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        #100000;
        $display("[FAIL] timeout");
        $finish;
    end
endmodule
