`timescale 1ns/1ps

// Exercises the actual video timing -> commit bridge -> dual SDRAM reader ->
// owner -> source ACK path without requiring an SD/FAT image.
module tb_top_commit_readback;
    reg vclk = 1'b0;
    reg mclk = 1'b0;
    reg sclk = 1'b0;
    always #20 vclk = ~vclk;
    always #4  mclk = ~mclk;
    always #5  sclk = ~sclk;

    reg rst = 1'b1;
    wire video_req, video_ack, hs, vs, de;
    reg src_toggle = 1'b0;
    reg src_valid = 1'b0;
    reg [1:0] src_bank = 2'd0;
    reg [20:0] src_item = 21'd0;

    wire bridge_req;
    wire [1:0] committed_bank;
    wire [20:0] committed_item;
    wire committed_valid;
    wire [1:0] source_bank_a, source_bank_b;
    wire source_dual, transition_blinds, transition_fade, transition_active;
    wire [8:0] progress;
    wire display_valid;
    wire [20:0] display_item;
    wire owner_release_toggle;
    wire bridge_ack;

    (* async_reg = "true" *) reg [2:0] release_sync;
    always @(posedge sclk or posedge rst) begin
        if (rst) release_sync <= 3'b000;
        else release_sync <= {release_sync[1:0],owner_release_toggle};
    end
    wire commit_ack = bridge_ack;

    video_timing_data timing (
        .video_clk(vclk), .rst(rst), .read_req(video_req),
        .read_req_ack(video_ack), .hs(hs), .vs(vs), .de(de)
    );

    osd_display_commit #(.ITEM_W(21)) bridge (
        .clk(vclk), .rst(rst), .src_toggle(src_toggle),
        .src_bank(src_bank), .src_item(src_item), .src_valid(src_valid),
        .frame_read_req(video_req), .mem_read_ack(video_ack),
        .read_req(bridge_req), .ack_toggle(bridge_ack),
        .bank(committed_bank), .item(committed_item), .valid(committed_valid)
    );

    transition_frame_owner #(.TRANSITION_FRAMES(4)) owner (
        .clk(vclk), .rst(rst), .frame_request(bridge_req),
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
        .transition_progress(progress),
        .display_valid(display_valid),
        .display_item(display_item),
        .release_toggle(owner_release_toggle),
        .transition_busy()
    );

    wire App_rd_en, App_rd_busy, Sdr_rd_en, Sdr_init_done, Sdr_init_ref_vld, Sdr_busy;
    wire [20:0] App_rd_addr;
    wire [31:0] Sdr_rd_dout;
    wire [31:0] data_a, data_b;
    wire empty_a, empty_b;
    wire request_ack;

    frame_read_write_dual #(.FRAME_WIDTH(640),.FRAME_HEIGHT(480)) storage (
        .rst(rst), .write_abort(1'b0), .write_abort_done(),
        .mem_clk(mclk), .Sdr_init_done(Sdr_init_done),
        .Sdr_init_ref_vld(Sdr_init_ref_vld), .Sdr_busy(Sdr_busy),
        .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout),
        .read_clk(vclk), .read_req(bridge_req), .read_dual(source_dual),
        .read_req_ack(request_ack), .read_finish(),
        .read_addr_a(source_bank_a ? 21'd307200 : 21'd0),
        .read_addr_b(source_bank_b ? 21'd307200 : 21'd0),
        .read_len(21'd307200),
        .read_progress(9'd0),
        .read_blinds(1'b0),
        .read_fade(1'b0),
        .read_en_a(!empty_a), .read_en_b(1'b0),
        .read_data_a(data_a), .read_data_b(data_b),
        .read_empty_a(empty_a), .read_empty_b(empty_b),
        .App_wr_en(), .App_wr_addr(), .App_wr_din(), .App_wr_dm(),
        .write_clk(sclk), .write_req(1'b0), .write_req_ack(),
        .write_finish(), .write_addr_0(21'd0), .write_addr_1(21'd307200),
        .write_addr_2(21'd0), .write_addr_3(21'd0),
        .write_addr_index(2'd0), .write_len(21'd307200),
        .write_en(1'b0), .write_data(32'd0), .write_ready()
    );

    sdram_model #(.MEM_WORDS(1048576),.READ_LATENCY(10)) mem_model (
        .Clk(mclk), .Clk_sft(mclk), .Rst(rst),
        .Sdr_init_done(Sdr_init_done), .Sdr_init_ref_vld(Sdr_init_ref_vld),
        .Sdr_busy(Sdr_busy),
        .App_wr_en(1'b0), .App_wr_addr(21'd0), .App_wr_dm(4'd0),
        .App_wr_din(32'd0), .App_rd_en(App_rd_en), .App_rd_addr(App_rd_addr),
        .Sdr_rd_en(Sdr_rd_en), .Sdr_rd_dout(Sdr_rd_dout)
    );
    assign video_ack = request_ack;

    integer errors = 0;
    integer timeout;
    integer frame_req_count = 0;
    always @(posedge video_req) if (!rst) frame_req_count = frame_req_count + 1;
    initial begin
        repeat (8) @(negedge vclk);
        rst = 1'b0;
        repeat (100) @(negedge vclk);

        @(negedge sclk);
        src_bank = 2'd0;
        src_item = {7'd1,14'd1};
        src_valid = 1'b1;
        src_toggle = 1'b1;

        timeout = 0;
        while ((commit_ack !== src_toggle) && timeout < 1000000) begin
            @(negedge vclk);
            timeout = timeout + 1;
        end
        if (timeout >= 1000000) begin
            errors = errors + 1;
            $display("[FAIL] source ACK timeout bridge_req=%b video_req=%b ack=%b valid=%b owner=%b sync=%b",
                     bridge_req,video_req,commit_ack,display_valid,
                     owner_release_toggle,owner.source_toggle_sync[2]);
        end
        if (!display_valid || display_item != {7'd1,14'd1}) begin
            errors = errors + 1;
            $display("[FAIL] committed display state");
        end
        repeat (1500000) @(negedge vclk);
        if (frame_req_count < 3) begin
            errors = errors + 1;
            $display("[FAIL] recurring frame requests=%0d video_req=%b bridge_req=%b ack=%b state=%0d",
                     frame_req_count,video_req,bridge_req,video_ack,
                     storage.frame_compose_read_m0.state);
        end

        if (errors == 0)
            $display("TOP_COMMIT_READBACK_PASS frame_requests=%0d",frame_req_count);
        else
            $display("TOP_COMMIT_READBACK_FAIL errors=%0d",errors);
        $finish;
    end
endmodule
