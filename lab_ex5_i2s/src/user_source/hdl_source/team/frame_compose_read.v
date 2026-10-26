`timescale 1ns/1ps

// Streams either one complete frame or a pre-composed horizontal slide frame
// through one sequential FIFO. Normal frames read A contiguously. Slide frames
// read the visible A tail followed by the visible B head for every output row,
// so the display path never needs two independent FIFOs.
module frame_compose_read #(
    parameter ADDR_BITS  = 21,
    parameter BURST_BITS = 9,
    parameter BURST_SIZE = 256,
    parameter FIFO_DEPTH = 512,
    parameter H_ACTIVE   = 640
)(
    input                   rst,
    input                   mem_clk,
    input                   Sdr_init_done,
    input                   Sdr_init_ref_vld,
    input                   Sdr_busy,
    input                   Sdr_rd_en,
    input                   App_wr_busy,
    output                  O_rd_busy,

    output                  App_rd_en,
    output [ADDR_BITS-1:0]  App_rd_addr,

    input                   read_req,
    output reg              read_req_ack,
    output                  read_finish,
    input                   read_slide,
    input [ADDR_BITS-1:0]   read_base_a,
    input [ADDR_BITS-1:0]   read_base_b,
    input [ADDR_BITS-1:0]   read_len,
    input [8:0]             read_progress,

    output reg              fifo_aclr,
    input [BURST_BITS-1:0]  wrusedw
);

localparam [2:0] S_IDLE      = 3'd0;
localparam [2:0] S_ACK       = 3'd1;
localparam [2:0] S_CHECK     = 3'd2;
localparam [2:0] S_BURST     = 3'd3;
localparam [2:0] S_BURST_END = 3'd4;
localparam [2:0] S_END       = 3'd5;

reg [2:0] state;
reg read_req_d0, read_req_d1, read_req_d2;
reg [ADDR_BITS-1:0] read_len_d0, read_len_d1, read_len_latch;
reg [ADDR_BITS-1:0] read_cnt;
reg [17:0] issue_count;
reg [3:0] rd_delay;
reg app_rd_arm;
reg app_rd_en_q;
reg slide_latch;
reg [ADDR_BITS-1:0] a_addr, b_addr;
reg [11:0] slide_width_q, b_line_step;
reg [11:0] addr_x;

wire [8:0] room_limit = FIFO_DEPTH - BURST_SIZE;
wire burst_finish =
    (state == S_BURST) &&
    (issue_count >= BURST_SIZE) &&
    (rd_delay == 4'd10);
wire [17:0] slide_width_calc = H_ACTIVE * read_progress;
wire [11:0] slide_width = slide_width_calc[17:8];
wire use_b = slide_latch && (addr_x >= (H_ACTIVE - slide_width_q));

assign App_rd_en = app_rd_en_q;
assign App_rd_addr = use_b ? b_addr : a_addr;
assign O_rd_busy = (state == S_BURST);
assign read_finish = (state == S_END);

// Request, base addresses and progress are held in the video domain across
// the whole frame. Capture them after the three-stage request synchronizer.
always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        read_req_d0 <= 1'b0;
        read_req_d1 <= 1'b0;
        read_req_d2 <= 1'b0;
        read_len_d0 <= {ADDR_BITS{1'b0}};
        read_len_d1 <= {ADDR_BITS{1'b0}};
    end else begin
        read_req_d0 <= read_req;
        read_req_d1 <= read_req_d0;
        read_req_d2 <= read_req_d1;
        read_len_d0 <= read_len;
        read_len_d1 <= read_len_d0;
    end
end

always @(posedge mem_clk or posedge rst) begin
    if (rst) begin
        state          <= S_IDLE;
        read_req_ack   <= 1'b0;
        fifo_aclr      <= 1'b0;
        read_len_latch <= {ADDR_BITS{1'b0}};
        read_cnt       <= {ADDR_BITS{1'b0}};
        app_rd_arm     <= 1'b0;
        app_rd_en_q    <= 1'b0;
        issue_count    <= 18'd0;
        rd_delay       <= 4'd0;
        slide_latch    <= 1'b0;
        a_addr         <= {ADDR_BITS{1'b0}};
        b_addr         <= {ADDR_BITS{1'b0}};
        slide_width_q  <= 12'd0;
        b_line_step    <= H_ACTIVE + 1;
        addr_x         <= 12'd0;
    end else begin
        case (state)
            S_IDLE: begin
                read_req_ack <= 1'b0;
                app_rd_en_q  <= 1'b0;
                if (read_req_d2 && Sdr_init_done)
                    state <= S_ACK;
            end

            S_ACK: begin
                read_req_ack   <= 1'b1;
                fifo_aclr      <= 1'b1;
                read_len_latch <= read_len_d1;
                slide_latch    <= read_slide;
                slide_width_q  <= slide_width;
                b_line_step    <= H_ACTIVE + 1 - slide_width;
                a_addr         <= read_base_a +
                                  (read_slide ? slide_width : 12'd0);
                b_addr         <= read_base_b;
                read_cnt       <= {ADDR_BITS{1'b0}};
                addr_x         <= 12'd0;

                if (!read_req_d2) begin
                    read_req_ack <= 1'b0;
                    fifo_aclr    <= 1'b0;
                    state        <= S_CHECK;
                end
            end

            S_CHECK: begin
                if (read_req_d2) begin
                    state <= S_ACK;
                end else if ((wrusedw < room_limit) &&
                             !App_wr_busy && !Sdr_busy &&
                             !Sdr_init_ref_vld) begin
                    app_rd_arm  <= 1'b1;
                    issue_count <= 18'd0;
                    rd_delay    <= 4'd0;
                    state       <= S_BURST;
                end
            end

            S_BURST: begin
                if (app_rd_en_q)
                    issue_count <= issue_count + 18'd1;

                if (app_rd_en_q)
                    rd_delay <= 4'd0;
                else if (issue_count >= BURST_SIZE && rd_delay < 4'd10)
                    rd_delay <= rd_delay + 4'd1;

                if (burst_finish) begin
                    app_rd_arm <= 1'b0;
                    app_rd_en_q <= 1'b0;
                    read_cnt <= read_cnt + BURST_SIZE;
                    state <= S_BURST_END;
                end
            end

            S_BURST_END: begin
                if (read_req_d2)
                    state <= S_ACK;
                else if (read_cnt < read_len_latch)
                    state <= S_CHECK;
                else
                    state <= S_END;
            end

            S_END: begin
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase

        // Registered address issue follows main's proven frame_fifo_read burst
        // shape. Coordinates advance only for requests actually sent.
        app_rd_en_q <= app_rd_arm &&
                       ((issue_count + app_rd_en_q) < BURST_SIZE) &&
                       (state == S_BURST);

        if (app_rd_en_q) begin
            a_addr <= a_addr + 1'b1;
            if (addr_x == H_ACTIVE - 1) begin
                addr_x <= 12'd0;
                if (slide_latch)
                    b_addr <= b_addr + b_line_step;
            end else begin
                addr_x <= addr_x + 12'd1;
                if (use_b)
                    b_addr <= b_addr + 1'b1;
            end
        end
    end
end

endmodule
