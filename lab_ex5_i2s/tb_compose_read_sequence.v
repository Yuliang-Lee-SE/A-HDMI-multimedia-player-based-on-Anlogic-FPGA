`timescale 1ns/1ps

module tb_compose_read_sequence;
    localparam integer WORDS = 1024;
    localparam [20:0] READ_LEN = 21'd1024;
    localparam [8:0] PROGRESS = 9'd128;

    reg mclk = 1'b0;
    reg vclk = 1'b0;
    always #4 mclk = ~mclk;
    always #20 vclk = ~vclk;

    reg rst = 1'b1;
    reg frame_req = 1'b0;
    reg slide = 1'b0;
    reg [8:0] progress = 9'd0;
    reg [20:0] base_a = 21'd0;
    reg [20:0] base_b = 21'd2048;

    wire frame_ack;
    wire frame_finish;
    wire App_rd_en;
    wire [20:0] App_rd_addr;
    wire Sdr_rd_en;
    wire [31:0] Sdr_rd_dout;
    wire Sdr_init_done;
    wire Sdr_init_ref_vld;
    wire Sdr_busy;
    wire read_en_a;
    wire [31:0] read_data_a;
    wire read_empty_a;

    reg sample = 1'b0;
    assign read_en_a = sample && !read_empty_a;
    reg read_en_q = 1'b0;
    integer count = 0;
    integer finish_count = 0;
    integer errors = 0;
    integer run_slide = 0;

    frame_read_write_dual #(
        .FRAME_WIDTH  (640),
        .FRAME_HEIGHT (480)
    ) storage (
        .rst                (rst),
        .write_abort        (1'b0),
        .write_abort_done   (),
        .mem_clk            (mclk),
        .Sdr_init_done      (Sdr_init_done),
        .Sdr_init_ref_vld   (Sdr_init_ref_vld),
        .Sdr_busy           (Sdr_busy),
        .App_rd_en          (App_rd_en),
        .App_rd_addr        (App_rd_addr),
        .Sdr_rd_en          (Sdr_rd_en),
        .Sdr_rd_dout        (Sdr_rd_dout),
        .read_clk           (vclk),
        .read_req           (frame_req),
        .read_dual          (slide),
        .read_req_ack       (frame_ack),
        .read_finish        (frame_finish),
        .read_addr_a        (base_a),
        .read_addr_b        (base_b),
        .read_len           (READ_LEN),
        .read_progress      (progress),
        .read_en_a          (read_en_a),
        .read_en_b          (1'b0),
        .read_data_a        (read_data_a),
        .read_data_b        (),
        .read_empty_a       (read_empty_a),
        .read_empty_b       (),
        .App_wr_en          (),
        .App_wr_addr        (),
        .App_wr_din         (),
        .App_wr_dm          (),
        .write_clk          (vclk),
        .write_req          (1'b0),
        .write_req_ack      (),
        .write_finish       (),
        .write_addr_0       (21'd0),
        .write_addr_1       (21'd307200),
        .write_addr_2       (21'd0),
        .write_addr_3       (21'd0),
        .write_addr_index   (2'd0),
        .write_len          (21'd307200),
        .write_en           (1'b0),
        .write_data         (32'd0),
        .write_ready        ()
    );

    sdram_model #(
        .MEM_WORDS    (4096),
        .READ_LATENCY (10)
    ) memory (
        .Clk              (mclk),
        .Clk_sft          (mclk),
        .Rst              (rst),
        .Sdr_init_done    (Sdr_init_done),
        .Sdr_init_ref_vld (Sdr_init_ref_vld),
        .Sdr_busy         (Sdr_busy),
        .App_wr_en        (1'b0),
        .App_wr_addr      (21'd0),
        .App_wr_dm        (4'd0),
        .App_wr_din       (32'd0),
        .App_rd_en        (App_rd_en),
        .App_rd_addr      (App_rd_addr),
        .Sdr_rd_en        (Sdr_rd_en),
        .Sdr_rd_dout      (Sdr_rd_dout)
    );

    always @(posedge mclk) begin
        if (!rst && frame_finish)
            finish_count <= finish_count + 1;
    end

    function [31:0] expected_word;
        input integer index;
        integer x;
        integer y;
        begin
            x = index % 640;
            y = index / 640;
            if (run_slide && x >= 320)
                expected_word = 32'h00800000 + y*640 + (x-320);
            else if (run_slide)
                expected_word = y*640 + x + 320;
            else
                expected_word = index;
        end
    endfunction

    // FIFO data is valid one video clock after read_en.
    always @(posedge vclk) begin
        read_en_q <= read_en_a;
        if (read_en_q) begin
            if (read_data_a !== expected_word(count)) begin
                errors = errors + 1;
                if (errors < 8)
                    $display("[FAIL] index=%0d slide=%0b got=%h expected=%h",
                             count,run_slide,read_data_a,expected_word(count));
            end
            count = count + 1;
        end
    end

    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1)
            memory.mem[i] = i;
        for (i = 0; i < 2048; i = i + 1)
            memory.mem[2048+i] = 32'h00800000 + i;
    end

    task run_frame;
        input use_slide;
        integer timeout;
        integer finish_base;
        begin
            run_slide = use_slide;
            sample = 1'b1;
            finish_base = finish_count;
            @(negedge vclk);
            slide = use_slide;
            progress = use_slide ? PROGRESS : 9'd0;
            frame_req = 1'b1;
            timeout = 0;
            while (!frame_ack && timeout < 100000) begin
                @(negedge vclk);
                timeout = timeout + 1;
            end
            if (timeout >= 100000) begin
                errors = errors + 1;
                $display("[FAIL] request timeout slide=%0b state=%0d",
                         use_slide,storage.frame_compose_read_m0.state);
            end
            @(negedge vclk);
            frame_req = 1'b0;

            timeout = 0;
            while ((count < WORDS) && timeout < 100000) begin
                @(negedge vclk);
                timeout = timeout + 1;
            end
            if (timeout >= 100000) begin
                errors = errors + 1;
                $display("[FAIL] drain timeout slide=%0b count=%0d state=%0d used=%0d",
                         use_slide,count,
                         storage.frame_compose_read_m0.state,
                         storage.rdusedw_a);
            end

            timeout = 0;
            while ((finish_count == finish_base) && timeout < 10000) begin
                @(negedge vclk);
                timeout = timeout + 1;
            end
            if (finish_count == finish_base) begin
                errors = errors + 1;
                $display("[FAIL] frame finish timeout slide=%0b state=%0d",
                         use_slide,storage.frame_compose_read_m0.state);
            end

            repeat (4) @(negedge vclk);
            sample = 1'b0;
            @(negedge vclk);
        end
    endtask

    initial begin
        repeat (8) @(negedge vclk);
        rst = 1'b0;
        wait (Sdr_init_done);

        run_frame(1'b0);
        count = 0;
        run_frame(1'b1);
        count = 0;
        run_frame(1'b0);

        if (errors == 0)
            $display("COMPOSE_READ_SEQUENCE_PASS frames=3 words=%0d",WORDS);
        else
            $display("COMPOSE_READ_SEQUENCE_FAIL errors=%0d",errors);
        $finish;
    end

    initial begin
        #10000000;
        $display("[FAIL] global timeout");
        $finish;
    end
endmodule
