`timescale 1ns/1ps

// Debounced, power-on-aware reset gate for the board refresh/reset button.
// One shared counter serves both the startup hold and post-release lockout.
module reset_startup_guard #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer STARTUP_HOLD_MS = 500,
    parameter integer LOCKOUT_MS = 2000,
    parameter integer COUNTER_W = 27
)(
    input  wire clk,
    input  wire raw_rst_n,
    output wire reset_n
);

localparam [COUNTER_W-1:0] HOLD_TICKS =
    (CLK_HZ / 1000) * STARTUP_HOLD_MS;
localparam [COUNTER_W-1:0] LOCKOUT_TICKS =
    (CLK_HZ / 1000) * LOCKOUT_MS;

localparam [1:0] HOLD = 2'd0;
localparam [1:0] LOCKOUT = 2'd1;
localparam [1:0] WAIT_RELEASE = 2'd2;
localparam [1:0] READY = 2'd3;

(* async_reg = "true" *) reg [1:0] rst_sync = 2'b00;
reg [1:0] state = HOLD;
reg [COUNTER_W-1:0] guard_count = {COUNTER_W{1'b0}};
(* keep = "true" *) reg reset_n_reg = 1'b0;

assign reset_n = reset_n_reg;

always @(posedge clk) begin
    rst_sync <= {rst_sync[0], raw_rst_n};

    case (state)
        HOLD: begin
            reset_n_reg <= 1'b0;
            if (!rst_sync[1]) begin
                guard_count <= {COUNTER_W{1'b0}};
            end else if (guard_count == HOLD_TICKS - 1'b1) begin
                guard_count <= {COUNTER_W{1'b0}};
                reset_n_reg <= 1'b1;
                state <= LOCKOUT;
            end else begin
                guard_count <= guard_count + 1'b1;
            end
        end

        LOCKOUT: begin
            reset_n_reg <= 1'b1;
            if (guard_count == LOCKOUT_TICKS - 1'b1) begin
                guard_count <= {COUNTER_W{1'b0}};
                state <= rst_sync[1] ? READY : WAIT_RELEASE;
            end else begin
                guard_count <= guard_count + 1'b1;
            end
        end

        // A press that overlaps the end of the lockout is ignored completely.
        // Accept the next reset only after the button has returned high.
        WAIT_RELEASE: begin
            reset_n_reg <= 1'b1;
            if (rst_sync[1]) state <= READY;
        end

        READY: begin
            reset_n_reg <= 1'b1;
            if (!rst_sync[1]) begin
                reset_n_reg <= 1'b0;
                guard_count <= {COUNTER_W{1'b0}};
                state <= HOLD;
            end
        end

        default: begin
            reset_n_reg <= 1'b0;
            guard_count <= {COUNTER_W{1'b0}};
            state <= HOLD;
        end
    endcase
end

endmodule
