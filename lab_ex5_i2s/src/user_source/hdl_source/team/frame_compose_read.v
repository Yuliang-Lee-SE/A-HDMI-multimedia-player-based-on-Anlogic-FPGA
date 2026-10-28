`timescale 1ns/1ps

// Streams one complete frame or a pre-composed A/B transition frame through one
// sequential FIFO. Supported effects are horizontal slide, horizontal blinds,
// and a true per-pixel A/B crossfade.
module frame_compose_read #(
    parameter ADDR_BITS  = 21,
    parameter BURST_BITS = 9,
    parameter BURST_SIZE = 256,
    parameter FIFO_DEPTH = 512,
    parameter H_ACTIVE   = 640,
    parameter V_ACTIVE   = 480,
    parameter BLINDS     = 8
)(
    input                   rst,
    input                   mem_clk,
    input                   Sdr_init_done,
    input                   Sdr_init_ref_vld,
    input                   Sdr_busy,
    input                   Sdr_rd_en,
    input [31:0]            Sdr_rd_dout,
    input                   App_wr_busy,
    output                  O_rd_busy,

    output                  App_rd_en,
    output [ADDR_BITS-1:0]  App_rd_addr,

    input                   read_req,
    output reg              read_req_ack,
    output                  read_finish,
    input                   read_slide,
    input                   read_blinds,
    input                   read_fade,
    input [ADDR_BITS-1:0]   read_base_a,
    input [ADDR_BITS-1:0]   read_base_b,
    input [ADDR_BITS-1:0]   read_len,
    input [8:0]             read_progress,

    output reg              fifo_aclr,
    input [BURST_BITS-1:0]  wrusedw,
    output                  fifo_we,
    output [31:0]           fifo_data
);

localparam [2:0] S_IDLE      = 3'd0;
localparam [2:0] S_ACK       = 3'd1;
localparam [2:0] S_CHECK     = 3'd2;
localparam [2:0] S_BURST     = 3'd3;
localparam [2:0] S_BURST_END = 3'd4;
localparam [2:0] S_END       = 3'd5;
localparam integer BLADE_HEIGHT = V_ACTIVE / BLINDS;
localparam integer FADE_BLOCK = 16;

reg [2:0] state;
reg read_req_d0, read_req_d1, read_req_d2;
reg [ADDR_BITS-1:0] read_len_d0, read_len_d1, read_len_latch;
reg [ADDR_BITS-1:0] read_cnt;
reg [17:0] issue_count;
reg [3:0] rd_delay;
reg app_rd_arm;
reg app_rd_en_q;
reg slide_latch;
reg blinds_latch;
reg fade_latch;
reg [ADDR_BITS-1:0] a_addr, b_addr;
reg [11:0] slide_width_q, b_line_step;
reg [11:0] addr_x;
reg [5:0] blade_y, blinds_start_q, blinds_end_q;
reg [8:0] fade_alpha_q, fade_inv_q;
reg fade_send_phase, fade_resp_phase;
reg [3:0] fade_send_pos, fade_resp_pos;
reg [23:0] fade_a_block [0:FADE_BLOCK-1];
reg [16:0] mul_a_r, mul_a_g, mul_a_b;
reg [16:0] mul_b_r, mul_b_g, mul_b_b;
reg fade_product_valid, blend_stage2_we;
reg [31:0] blended_pixel;
reg fifo_room_ready;

wire [8:0] room_limit = FIFO_DEPTH - BURST_SIZE;
wire [18:0] issue_limit = fade_latch ? (BURST_SIZE*2) : BURST_SIZE;
wire burst_finish =
    (state == S_BURST) &&
    (issue_count >= issue_limit) &&
    (rd_delay == 4'd10);
wire [17:0] slide_width_calc = H_ACTIVE * read_progress;
wire [11:0] slide_width = slide_width_calc[17:8];
wire [15:0] blinds_reveal_calc = BLADE_HEIGHT * read_progress;
wire [5:0] blinds_reveal = blinds_reveal_calc[13:8];
wire [5:0] blinds_start = (BLADE_HEIGHT - blinds_reveal) >> 1;
wire [5:0] blinds_end = blinds_start + blinds_reveal;
wire slide_use_b =
    slide_latch && !blinds_latch &&
    (addr_x >= (H_ACTIVE - slide_width_q));
wire blinds_use_b =
    blinds_latch &&
    (blade_y >= blinds_start_q) && (blade_y < blinds_end_q);
wire use_b = slide_use_b || blinds_use_b;
wire [23:0] fade_a_rgb = fade_a_block[fade_resp_pos];

assign App_rd_en = app_rd_en_q;
assign App_rd_addr = fade_latch ?
                     (fade_send_phase ? b_addr : a_addr) :
                     (use_b ? b_addr : a_addr);
assign O_rd_busy = (state == S_BURST);
assign read_finish = (state == S_END);
assign fifo_we = fade_latch ?
                 blend_stage2_we :
                 (Sdr_rd_en && (state == S_BURST));
assign fifo_data = fade_latch ? blended_pixel : Sdr_rd_dout;

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
        blinds_latch   <= 1'b0;
        fade_latch     <= 1'b0;
        a_addr         <= {ADDR_BITS{1'b0}};
        b_addr         <= {ADDR_BITS{1'b0}};
        slide_width_q  <= 12'd0;
        b_line_step    <= H_ACTIVE + 1;
        addr_x         <= 12'd0;
        blade_y        <= 6'd0;
        blinds_start_q <= BLADE_HEIGHT >> 1;
        blinds_end_q   <= BLADE_HEIGHT >> 1;
        fade_alpha_q   <= 9'd0;
        fade_inv_q     <= 9'd256;
        fade_send_phase <= 1'b0;
        fade_resp_phase <= 1'b0;
        fade_send_pos  <= 4'd0;
        fade_resp_pos  <= 4'd0;
        mul_a_r        <= 17'd0;
        mul_a_g        <= 17'd0;
        mul_a_b        <= 17'd0;
        mul_b_r        <= 17'd0;
        mul_b_g        <= 17'd0;
        mul_b_b        <= 17'd0;
        fade_product_valid <= 1'b0;
        blend_stage2_we    <= 1'b0;
        blended_pixel      <= 32'd0;
        fifo_room_ready    <= 1'b0;
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
                blinds_latch   <= read_slide && read_blinds;
                fade_latch     <= read_slide && read_fade;
                slide_width_q  <= slide_width;
                b_line_step    <= H_ACTIVE + 1 - slide_width;
                a_addr         <= read_base_a +
                                  ((read_slide && !read_blinds && !read_fade) ?
                                   slide_width : 12'd0);
                b_addr         <= read_base_b;
                blinds_start_q <= blinds_start;
                blinds_end_q   <= blinds_end;
                fade_alpha_q   <= read_progress;
                fade_inv_q     <= 9'd256 - read_progress;
                fade_send_phase <= 1'b0;
                fade_resp_phase <= 1'b0;
                fade_send_pos   <= 4'd0;
                fade_resp_pos   <= 4'd0;
                read_cnt       <= {ADDR_BITS{1'b0}};
                addr_x         <= 12'd0;
                blade_y        <= 6'd0;
                fade_product_valid <= 1'b0;
                blend_stage2_we    <= 1'b0;

                if (!read_req_d2) begin
                    read_req_ack <= 1'b0;
                    fifo_aclr    <= 1'b0;
                    state        <= S_CHECK;
                end
            end

            S_CHECK: begin
                if (read_req_d2) begin
                    state <= S_ACK;
                end else if (fifo_room_ready) begin
                    app_rd_arm  <= 1'b1;
                    issue_count <= 18'd0;
                    rd_delay    <= 4'd0;
                    fade_send_phase <= 1'b0;
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

        fifo_room_ready <=
            (wrusedw < room_limit) &&
            !App_wr_busy && !Sdr_busy && !Sdr_init_ref_vld;

        if (Sdr_rd_en && fade_latch) begin
            if (!fade_resp_phase) begin
                fade_a_block[fade_resp_pos] <= Sdr_rd_dout[31:8];
                fade_product_valid <= 1'b0;
            end else begin
                mul_a_r <= {10'd0,fade_a_rgb[23:16]} *
                           {9'd0,fade_inv_q};
                mul_a_g <= {10'd0,fade_a_rgb[15:8]}  *
                           {9'd0,fade_inv_q};
                mul_a_b <= {10'd0,fade_a_rgb[7:0]}   *
                           {9'd0,fade_inv_q};
                mul_b_r <= {10'd0,Sdr_rd_dout[31:24]} *
                           {9'd0,fade_alpha_q};
                mul_b_g <= {10'd0,Sdr_rd_dout[23:16]} *
                           {9'd0,fade_alpha_q};
                mul_b_b <= {10'd0,Sdr_rd_dout[15:8]}  *
                           {9'd0,fade_alpha_q};
                fade_product_valid <= 1'b1;
            end
            if (fade_resp_pos == FADE_BLOCK-1) begin
                fade_resp_pos   <= 4'd0;
                fade_resp_phase <= ~fade_resp_phase;
            end else begin
                fade_resp_pos <= fade_resp_pos + 4'd1;
            end
        end else begin
            fade_product_valid <= 1'b0;
        end

        if (fade_product_valid) begin
            blended_pixel[31:24] <= (mul_a_r + mul_b_r + 17'd128) >> 8;
            blended_pixel[23:16] <= (mul_a_g + mul_b_g + 17'd128) >> 8;
            blended_pixel[15:8]  <= (mul_a_b + mul_b_b + 17'd128) >> 8;
            blended_pixel[7:0]   <= 8'd0;
            blend_stage2_we <= 1'b1;
        end else begin
            blend_stage2_we <= 1'b0;
        end

        // Registered address issue follows main's proven frame_fifo_read burst
        // shape. Coordinates advance only for requests actually sent.
        app_rd_en_q <= app_rd_arm &&
                       ((issue_count + app_rd_en_q) < issue_limit) &&
                       (state == S_BURST);

        if (app_rd_en_q) begin
            if (fade_latch) begin
                if (!fade_send_phase) begin
                    a_addr <= a_addr + 1'b1;
                end else begin
                    b_addr <= b_addr + 1'b1;
                end
                if (fade_send_pos == FADE_BLOCK-1) begin
                    fade_send_pos   <= 4'd0;
                    fade_send_phase <= ~fade_send_phase;
                end else begin
                    fade_send_pos <= fade_send_pos + 4'd1;
                end
            end else begin
                a_addr <= a_addr + 1'b1;
                if (addr_x == H_ACTIVE - 1) begin
                    addr_x <= 12'd0;
                    if (blinds_latch) begin
                        blade_y <= (blade_y == BLADE_HEIGHT - 1) ? 6'd0 : blade_y + 6'd1;
                        b_addr  <= b_addr + 1'b1;
                    end else if (slide_latch) begin
                        b_addr <= b_addr + b_line_step;
                    end
                end else begin
                    addr_x <= addr_x + 12'd1;
                    if (blinds_latch || use_b)
                        b_addr <= b_addr + 1'b1;
                end
            end
        end
    end
end

endmodule
