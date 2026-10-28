`timescale 1ns/1ps

module tb_commit_release_v2;
    reg vclk = 1'b0;
    reg sclk = 1'b0;
    always #20 vclk = ~vclk;
    always #5  sclk = ~sclk;

    reg rst = 1'b1;
    reg src_toggle = 1'b0;
    reg src_valid = 1'b0;
    reg [1:0] src_bank = 2'd0;
    reg [20:0] src_item = 21'd0;
    reg frame_read_req = 1'b0;
    reg mem_ack = 1'b0;

    wire bridge_read_req, bridge_ack;
    wire [1:0] committed_bank;
    wire [20:0] committed_item;
    wire committed_valid;
    wire [1:0] source_bank_a, source_bank_b;
    wire source_dual, transition_active;
    wire transition_blinds;
    wire transition_fade;
    wire [8:0] transition_progress;
    wire display_valid;
    wire [20:0] display_item;
    wire owner_release_toggle, busy;

    (* async_reg = "true" *) reg [2:0] release_sync;
    always @(posedge sclk or posedge rst) begin
        if (rst) release_sync <= 3'b000;
        else release_sync <= {release_sync[1:0],owner_release_toggle};
    end
    wire commit_ack = release_sync[2];

    osd_display_commit #(.ITEM_W(21)) bridge (
        .clk(vclk), .rst(rst), .src_toggle(src_toggle),
        .src_bank(src_bank), .src_item(src_item), .src_valid(src_valid),
        .frame_read_req(frame_read_req), .mem_read_ack(mem_ack),
        .read_req(bridge_read_req), .ack_toggle(bridge_ack),
        .bank(committed_bank), .item(committed_item), .valid(committed_valid)
    );

    transition_frame_owner #(.TRANSITION_FRAMES(4)) owner (
        .clk(vclk), .rst(rst), .frame_request(bridge_read_req),
        .committed_valid(committed_valid),
        .committed_bank(committed_bank),
        .committed_item(committed_item),
        .source_commit_toggle(src_toggle),
        .source_bank_a(source_bank_a),
        .source_bank_b(source_bank_b),
        .read_dual(source_dual),
        .transition_blinds(transition_blinds),
        .transition_fade(transition_fade),
        .transition_active(transition_active),
        .transition_progress(transition_progress),
        .display_valid(display_valid),
        .display_item(display_item),
        .release_toggle(owner_release_toggle),
        .transition_busy(busy)
    );

    integer errors = 0;
    task check;
        input condition;
        input [8*80-1:0] text;
        begin
            if (!condition) begin
                errors = errors + 1;
                $display("[FAIL] %0s",text);
            end
        end
    endtask

    always @(posedge vclk) begin
        if (!rst) begin
            mem_ack <= bridge_read_req;
            frame_read_req <= (($time / 400) % 10 == 1);
        end else begin
            mem_ack <= 1'b0;
            frame_read_req <= 1'b0;
        end
    end

    task commit_and_wait(input [1:0] bank,input [20:0] item);
        integer timeout;
        begin
            @(negedge vclk);
            src_bank = bank;
            src_item = item;
            src_valid = 1'b1;
            src_toggle = ~src_toggle;
            $display("COMMIT_REQUEST src=%b bank=%0d item=%h t=%0t",
                     src_toggle,bank,item,$time);
            timeout = 0;
            while ((commit_ack !== src_toggle) && timeout < 1000) begin
                @(negedge vclk);
                timeout = timeout + 1;
            end
            if (timeout >= 1000)
                $display("ACK timeout src=%b reqsync=%b owner=%b sync3=%b armed=%b valid=%b item=%h read_req=%b cap=%b acc=%b pend=%b await=%b",
                         src_toggle,bridge.req_sync[2],
                         owner_release_toggle,owner.source_toggle_sync[2],
                         owner.release_armed,display_valid,display_item,bridge_read_req,
                         bridge.captured,bridge.accepted,bridge.pending_item,bridge.await_ack);
            check(timeout < 1000,"commit release timeout");
            repeat (4) @(negedge vclk);
        end
    endtask

    initial begin
        repeat (8) @(negedge vclk);
        rst = 1'b0;
        commit_and_wait(2'd0,{7'd1,14'd1});
        check(display_valid && display_item == {7'd1,14'd1},"initial display");

        commit_and_wait(2'd1,{7'd1,14'd1});
        check(!transition_active,"same item hard cut");

        commit_and_wait(2'd0,{7'd2,14'd2});
        // commit_and_wait waits through the slide and its release.
        check(!transition_active && display_item == {7'd2,14'd2},"slide completion");

        if (errors == 0) $display("COMMIT_RELEASE_V2_PASS");
        else $display("COMMIT_RELEASE_V2_FAIL errors=%0d",errors);
        $finish;
    end
endmodule
