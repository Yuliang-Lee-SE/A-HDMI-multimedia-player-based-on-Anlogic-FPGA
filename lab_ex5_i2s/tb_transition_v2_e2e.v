`timescale 1ns/1ps

// Complete-frame integration:
// two ping-pong banks -> 640x480 writer -> composed single-stream reader ->
// video_delay -> frame-boundary slide. The same-asset reload exercises the
// non-display-bank scale replacement without a scratch bank or slide.
module tb_transition_v2_e2e;
    localparam integer W = 640;
    localparam integer H = 480;
    localparam [20:0] NPIX = 21'd307200;
    localparam [20:0] BUF0 = 21'd0;
    localparam [20:0] BUF1 = NPIX;
    localparam [20:0] ITEM1 = {7'd1,14'd1};
    localparam [20:0] ITEM2 = {7'd2,14'd2};

    reg wclk = 1'b0;
    reg mclk = 1'b0;
    reg vclk = 1'b0;
    always #5  wclk = ~wclk;
    always #4  mclk = ~mclk;
    always #20 vclk = ~vclk;

    reg rst = 1'b1;
    reg write_req = 1'b0;
    reg write_abort = 1'b0;
    reg [20:0] write_base = 21'd0;
    reg [1:0] write_bank = 2'd0;
    reg write_en = 1'b0;
    reg [31:0] write_data = 32'd0;
    wire write_req_ack;
    wire write_abort_done;
    wire write_finish;
    wire write_ready;

    wire App_wr_en, App_rd_en, App_rd_busy;
    wire [20:0] App_wr_addr, App_rd_addr;
    wire [31:0] App_wr_din, Sdr_rd_dout;
    wire [3:0] App_wr_dm;
    wire Sdr_rd_en, Sdr_init_done, Sdr_init_ref_vld;
    wire Sdr_busy;

    reg frame_request = 1'b0;
    wire frame_dual;
    wire [20:0] frame_base_a;
    wire [20:0] frame_base_b;
    wire frame_request_ack;
    wire frame_read_finish;
    wire video_read_en;
    wire [31:0] read_data_a;
    wire read_empty_a;

    reg hs = 1'b0;
    reg vs = 1'b0;
    reg de = 1'b0;
    wire mixed_hs, mixed_vs, mixed_de;
    wire [23:0] mixed_rgb;

    reg committed_valid = 1'b0;
    reg [1:0] committed_bank = 2'd0;
    reg [20:0] committed_item = 21'd0;
    reg commit_ack_toggle = 1'b0;
    wire [1:0] source_bank_a, source_bank_b;
    wire source_dual;
    wire transition_blinds;
    wire transition_fade;
    wire transition_active;
    wire [8:0] transition_progress;
    wire shown_valid;
    wire [20:0] shown_item;
    wire release_toggle, transition_busy;

    integer errors = 0;
    integer write_count = 0;
    integer frame_pixels = 0;
    integer frame_mode = 0;
    integer frame_number = 0;
    integer transition_snapshot = 0;
    integer progress_snapshot = 0;
    integer blinds_snapshot = 0;
    integer fade_snapshot = 0;
    reg [23:0] expected_rgb;

    frame_read_write_dual #(
        .WRITE_V_FLIP  (1),
        .FRAME_WIDTH   (W),
        .FRAME_HEIGHT  (H)
    ) storage (
        .rst                (rst),
        .write_abort        (write_abort),
        .write_abort_done   (write_abort_done),
        .mem_clk            (mclk),
        .Sdr_init_done      (Sdr_init_done),
        .Sdr_init_ref_vld   (Sdr_init_ref_vld),
        .Sdr_busy           (Sdr_busy),
        .App_rd_en          (App_rd_en),
        .App_rd_addr        (App_rd_addr),
        .Sdr_rd_en          (Sdr_rd_en),
        .Sdr_rd_dout        (Sdr_rd_dout),
        .read_clk           (vclk),
        .read_req           (frame_request),
        .read_dual          (frame_dual),
        .read_blinds        (transition_blinds),
        .read_fade          (transition_fade),
        .read_progress      (transition_progress),
        .read_req_ack       (frame_request_ack),
        .read_finish        (frame_read_finish),
        .read_addr_a        (frame_base_a),
        .read_addr_b        (frame_base_b),
        .read_len           (NPIX),
        .read_en_a          (video_read_en),
        .read_en_b          (1'b0),
        .read_data_a        (read_data_a),
        .read_data_b        (),
        .read_empty_a       (read_empty_a),
        .read_empty_b       (),
        .App_wr_en          (App_wr_en),
        .App_wr_addr        (App_wr_addr),
        .App_wr_din         (App_wr_din),
        .App_wr_dm          (App_wr_dm),
        .write_clk          (wclk),
        .write_req          (write_req),
        .write_req_ack      (write_req_ack),
        .write_finish       (write_finish),
        .write_addr_0       (BUF0),
        .write_addr_1       (BUF1),
        .write_addr_2       (21'd0),
        .write_addr_3       (21'd0),
        .write_addr_index   (write_bank),
        .write_len          (NPIX),
        .write_en           (write_en),
        .write_data         (write_data),
        .write_ready        (write_ready)
    );

    sdram_model #(.MEM_WORDS(1048576),.READ_LATENCY(10)) memory (
        .Clk              (mclk),
        .Clk_sft          (mclk),
        .Rst              (rst),
        .Sdr_init_done    (Sdr_init_done),
        .Sdr_init_ref_vld (Sdr_init_ref_vld),
        .Sdr_busy         (Sdr_busy),
        .App_wr_en        (App_wr_en),
        .App_wr_addr      (App_wr_addr),
        .App_wr_dm        (App_wr_dm),
        .App_wr_din       (App_wr_din),
        .App_rd_en        (App_rd_en),
        .App_rd_addr      (App_rd_addr),
        .Sdr_rd_en        (Sdr_rd_en),
        .Sdr_rd_dout      (Sdr_rd_dout)
    );

    video_delay frame_display (
        .video_clk (vclk),
        .rst       (rst),
        .read_en   (video_read_en),
        .read_data (read_data_a[31:8]),
        .hs        (hs),
        .vs        (vs),
        .de        (de),
        .hs_r      (mixed_hs),
        .vs_r      (mixed_vs),
        .de_r      (mixed_de),
        .vout_data (mixed_rgb)
    );

    transition_frame_owner #(.TRANSITION_FRAMES(4)) owner (
        .clk                 (vclk),
        .rst                 (rst),
        .frame_request       (frame_request),
        .committed_valid     (committed_valid),
        .committed_bank      (committed_bank),
        .committed_item      (committed_item),
        .source_commit_toggle(commit_ack_toggle),
        .source_bank_a       (source_bank_a),
        .source_bank_b       (source_bank_b),
        .read_dual           (source_dual),
        .transition_blinds   (transition_blinds),
        .transition_fade     (transition_fade),
        .transition_active   (transition_active),
        .transition_progress (transition_progress),
        .display_valid       (shown_valid),
        .display_item        (shown_item),
        .release_toggle      (release_toggle),
        .transition_busy     (transition_busy)
    );

    assign frame_dual = source_dual;
    assign frame_base_a = (source_bank_a == 0) ? BUF0 : BUF1;
    assign frame_base_b = (source_bank_b == 0) ? BUF0 : BUF1;

    function [23:0] file_pixel;
        input integer frame;
        input integer x;
        input integer y;
        begin
            case (frame)
                0: file_pixel = {8'h20+x[7:0],8'h40+y[7:0],x[7:0]^y[7:0]};
                1: file_pixel = {8'hA0+x[7:0],8'h20+y[7:0],x[7:0]+y[7:0]};
                2: file_pixel = {8'hE0+x[7:0],8'h60+y[7:0],x[7:0]^8'h5a};
                3: file_pixel = {8'h40+x[7:0],8'hC0+y[7:0],x[7:0]+y[7:0]};
                4: file_pixel = {8'h10+x[7:0],8'h90+y[7:0],x[7:0]^8'h3c};
                default:
                    file_pixel = {8'hE0+x[7:0],8'h60+y[7:0],x[7:0]^8'h5a};
            endcase
        end
    endfunction

    function [23:0] display_pixel;
        input integer frame;
        input integer x;
        input integer y;
        begin
            display_pixel = file_pixel(frame,x,H-1-y);
        end
    endfunction

    task check;
        input condition;
        input [8*96-1:0] message;
        begin
            if (!condition) begin
                errors = errors + 1;
                if (errors < 12)
                    $display("[FAIL] %0s frame=%0d pixel=%0d",message,frame_number,frame_pixels);
            end
        end
    endtask

    task write_frame;
        input [1:0] bank;
        input integer pattern;
        integer x;
        integer y;
        integer timeout;
        begin
            write_bank = bank;
            @(negedge wclk);
            write_req = 1'b1;
            timeout = 0;
            while (!write_req_ack && timeout < 100000) begin
                @(negedge wclk);
                timeout = timeout + 1;
            end
            check(timeout < 100000,"write request timeout");
            @(negedge wclk);
            write_req = 1'b0;
            repeat (20) @(negedge wclk);

            for (y = 0; y < H; y = y + 1) begin
                if ((y % 80) == 0)
                    $display("write bank=%0d row=%0d t=%0t",bank,y,$time);
                for (x = 0; x < W; x = x + 1) begin
                    @(negedge wclk);
                    while (!write_ready) @(negedge wclk);
                    write_en = 1'b1;
                    write_data = {file_pixel(pattern,x,y),8'b0};
                end
            end
            @(negedge wclk);
            write_en = 1'b0;
            write_data = 32'd0;

            timeout = 0;
            while (!write_finish && timeout < 300000) begin
                @(negedge mclk);
                timeout = timeout + 1;
            end
            check(timeout < 300000,"write finish timeout");
            $display("write complete bank=%0d t=%0t",bank,$time);
            check(memory.wr_cnt == (pattern+1)*NPIX,
                  "complete physical frame written");
        end
    endtask

    task start_frame;
        input valid;
        input [1:0] bank;
        input [20:0] item;
        integer timeout;
        begin
            @(negedge vclk);
            committed_valid = valid;
            committed_bank = bank;
            committed_item = item;
            vs = 1'b1;
            @(negedge vclk);
            vs = 1'b0;
            repeat (3) @(negedge vclk);
            frame_request = 1'b1;
            timeout = 0;
            while (!frame_request_ack && timeout < 100000) begin
                @(negedge vclk);
                timeout = timeout + 1;
            end
            check(timeout < 100000,"frame request timeout");
            @(negedge vclk);
            frame_request = 1'b0;
            commit_ack_toggle = ~commit_ack_toggle;
            repeat (1600) @(negedge vclk);
            $display("preload slide=%b state=%0d app_rd=%b read_we=%b used_a=%0d empty_a=%b ack=%b",
                     frame_dual,storage.frame_compose_read_m0.state,
                     storage.App_rd_en,storage.read_we_a,
                     storage.rdusedw_a,read_empty_a,frame_request_ack);
            transition_snapshot = transition_active;
            progress_snapshot = transition_progress;
            blinds_snapshot = transition_blinds;
            fade_snapshot = transition_fade;
            frame_pixels = 0;
            $display("frame begin number=%0d bank=%0d item=%0h dual=%b t=%0t",
                     frame_number+1,bank,item,frame_dual,$time);
        end
    endtask

    task drive_frame;
        input integer mode;
        integer x;
        integer y;
        begin
            frame_mode = mode;
            $display("display begin frame=%0d t=%0t",frame_number+1,$time);
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    @(negedge vclk);
                    hs = 1'b1;
                    de = 1'b1;
                end
                @(negedge vclk);
                de = 1'b0;
                hs = 1'b0;
                repeat (20) @(negedge vclk);
            end
            repeat (8) @(negedge vclk);
            check(frame_pixels == NPIX,"full-frame pixel count");
            $display("display complete frame=%0d pixels=%0d t=%0t",
                     frame_number+1,frame_pixels,$time);
        end
    endtask

    always @(posedge vclk) begin
        #1;
        if (!rst && mixed_de) begin
            if (transition_snapshot && progress_snapshot > 0) begin
                begin : slide_check
                    integer px;
                    integer py;
                    integer width;
                    integer start;
                    px = frame_pixels % W;
                    py = frame_pixels / W;
                    width = (W*progress_snapshot) >> 8;
                    start = W-width;
                    if (fade_snapshot) begin : fade_check
                        integer fade_a_rgb;
                        integer fade_b_rgb;
                        integer fade_alpha;
                        fade_a_rgb = display_pixel(frame_mode,px,py);
                        fade_b_rgb = display_pixel(4,px,py);
                        fade_alpha = progress_snapshot;
                        expected_rgb[23:16] =
                            (fade_a_rgb[23:16]*(256-fade_alpha) +
                             fade_b_rgb[23:16]*fade_alpha + 128) >> 8;
                        expected_rgb[15:8] =
                            (fade_a_rgb[15:8]*(256-fade_alpha) +
                             fade_b_rgb[15:8]*fade_alpha + 128) >> 8;
                        expected_rgb[7:0] =
                            (fade_a_rgb[7:0]*(256-fade_alpha) +
                             fade_b_rgb[7:0]*fade_alpha + 128) >> 8;
                    end else if (blinds_snapshot) begin : blinds_check
                        integer reveal;
                        integer blind_start;
                        integer blind_end;
                        integer blade_y;
                        reveal = (60*progress_snapshot) >> 8;
                        blind_start = (60-reveal) >> 1;
                        blind_end = blind_start + reveal;
                        blade_y = py % 60;
                        if ((blade_y >= blind_start) && (blade_y < blind_end))
                            expected_rgb = display_pixel(3,px,py);
                        else
                            expected_rgb = display_pixel(frame_mode,px,py);
                    end else if (px >= start)
                        expected_rgb = display_pixel(1,px-start,py);
                    else
                        expected_rgb = display_pixel(frame_mode,px+width,py);
                end
            end else begin
                expected_rgb = display_pixel(frame_mode,frame_pixels % W,frame_pixels / W);
            end
            if (mixed_rgb !== expected_rgb) begin
                errors = errors + 1;
                if (errors < 12)
                    $display("[FAIL] rgb frame=%0d pixel=%0d got=%h expected=%h dual=%b progress=%0d",
                             frame_number,frame_pixels,mixed_rgb,expected_rgb,
                             transition_active,progress_snapshot);
            end
            frame_pixels = frame_pixels + 1;
        end
    end

    initial begin
        repeat (20) @(negedge mclk);
        rst = 1'b0;
        wait (Sdr_init_done);
        $display("storage initialized t=%0t",$time);
        write_frame(0,0);
        write_frame(1,1);

        frame_number = 0;
        start_frame(1'b1,0,ITEM1);
        drive_frame(0);
        check(shown_valid && !transition_active,"initial hard cut");

        frame_number = 1;
        start_frame(1'b1,1,ITEM2);
        drive_frame(0);
        check(transition_active && progress_snapshot == 0,"slide starts old frame");

        frame_number = 2;
        start_frame(1'b1,1,ITEM2);
        drive_frame(0);
        check(progress_snapshot > 0,"slide progress advances at VS");

        frame_number = 3;
        start_frame(1'b1,1,ITEM2);
        drive_frame(0);

        frame_number = 4;
        start_frame(1'b1,1,ITEM2);
        drive_frame(0);

        frame_number = 5;
        start_frame(1'b1,1,ITEM2);
        drive_frame(1);
        check(!transition_active && shown_item == ITEM2,"slide completes on new bank");

        write_frame(0,2);
        frame_number = 6;
        start_frame(1'b1,0,ITEM2);
        drive_frame(2);
        check(!transition_active && shown_item == ITEM2,"same-item reload is hard cut");

        write_frame(1,3);
        frame_number = 7;
        start_frame(1'b1,1,{7'd3,14'd3});
        drive_frame(2);
        check(transition_active && blinds_snapshot,"blinds transition starts");

        frame_number = 8;
        start_frame(1'b1,1,{7'd3,14'd3});
        drive_frame(2);
        check(progress_snapshot > 0,"blinds progress advances");

        frame_number = 9;
        start_frame(1'b1,1,{7'd3,14'd3});
        drive_frame(2);

        frame_number = 10;
        start_frame(1'b1,1,{7'd3,14'd3});
        drive_frame(2);

        frame_number = 11;
        start_frame(1'b1,1,{7'd3,14'd3});
        drive_frame(3);
        check(!transition_active && !transition_blinds,"blinds completes");
        check(shown_item == {7'd3,14'd3},"metadata after blinds");

        write_frame(0,4);
        frame_number = 12;
        start_frame(1'b1,0,{7'd4,14'd4});
        drive_frame(3);
        check(transition_active && fade_snapshot,"fade transition starts");

        frame_number = 13;
        start_frame(1'b1,0,{7'd4,14'd4});
        drive_frame(3);
        check(progress_snapshot > 0,"fade progress advances");

        frame_number = 14;
        start_frame(1'b1,0,{7'd4,14'd4});
        drive_frame(3);

        frame_number = 15;
        start_frame(1'b1,0,{7'd4,14'd4});
        drive_frame(3);

        frame_number = 16;
        start_frame(1'b1,0,{7'd4,14'd4});
        drive_frame(4);
        check(!transition_active && !transition_fade,"fade completes");
        check(shown_item == {7'd4,14'd4},"metadata after fade");

        if (errors == 0)
            $display("TRANSITION_V2_E2E_PASS frames=%0d pixels=%0d",frame_number+1,memory.rd_cnt);
        else
            $display("TRANSITION_V2_E2E_FAIL errors=%0d",errors);
        $finish;
    end

    initial begin
        #500000000;
        $display("[FAIL] global timeout");
        $finish;
    end
endmodule
