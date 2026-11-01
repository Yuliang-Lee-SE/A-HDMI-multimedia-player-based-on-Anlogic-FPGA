`timescale 1ns/1ps

// Owns the two physical ping-pong banks from the video side.
//
// First image and same-item zoom commits are hard cuts at a frame boundary.
// A different committed item keeps the old bank beside the new bank for a
// bounded transition selected by the user: 0=hard cut, 1=slide, 2=blinds,
// 3=crossfade. The selected effect is latched when a transition starts. The
// source-side writer is acknowledged only after both banks are safe to reuse.
module transition_frame_owner #(
    parameter integer TRANSITION_FRAMES = 30
)(
    input             clk,
    input             rst,
    input             frame_request,

    input             committed_valid,
    input      [1:0]  committed_bank,
    input      [20:0] committed_item,
    input             source_commit_toggle,
    input      [1:0]  transition_mode,

    output     [1:0]  source_bank_a,
    output     [1:0]  source_bank_b,
    output            read_dual,
    output wire       transition_blinds,
    output wire       transition_fade,
    output reg        transition_active,
    output reg [8:0]  transition_progress,

    output reg        display_valid,
    output reg [20:0] display_item,

    output reg        release_toggle,
    output wire       transition_busy
);

localparam [8:0] PROGRESS_FULL = 9'd256;
localparam [8:0] PROGRESS_STEP = 9'd256 / TRANSITION_FRAMES;

reg frame_request_prev;
(* async_reg = "true" *) reg [2:0] source_toggle_sync;
reg bundle_seen;
reg [1:0] bundle_bank_seen;
reg [20:0] bundle_item_seen;
reg [1:0] active_bank;
reg [1:0] candidate_bank;
reg [20:0] candidate_item;
reg [5:0] transition_frame;
reg release_armed;
reg transition_warmup;
reg [1:0] transition_effect;

wire frame_tick = frame_request && !frame_request_prev;
wire new_bundle =
    committed_valid &&
    (!bundle_seen ||
     (committed_bank != bundle_bank_seen) ||
     (committed_item != bundle_item_seen));
wire item_change = committed_item != display_item;
wire can_transition =
    display_valid && committed_valid && new_bundle &&
    (committed_bank != active_bank) && item_change;
wire finish_transition =
    transition_active &&
    ((transition_frame + 1'b1) >= TRANSITION_FRAMES);

assign transition_busy = transition_active;
assign source_bank_a = active_bank;
assign source_bank_b = transition_active ? candidate_bank : active_bank;
assign read_dual = transition_active && !transition_warmup;
assign transition_blinds =
    transition_active && (transition_effect == 2'd2);
assign transition_fade =
    transition_active && (transition_effect == 2'd3);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        frame_request_prev  <= 1'b0;
        source_toggle_sync   <= 3'b000;
        bundle_seen         <= 1'b0;
        bundle_bank_seen    <= 2'd0;
        bundle_item_seen    <= 21'd0;
        active_bank         <= 2'd0;
        candidate_bank      <= 2'd0;
        candidate_item      <= 21'd0;
        transition_active   <= 1'b0;
        transition_effect   <= 2'd0;
        transition_progress <= 9'd0;
        transition_frame    <= 6'd0;
        display_valid       <= 1'b0;
        display_item        <= 21'd0;
        release_toggle      <= 1'b0;
        release_armed       <= 1'b0;
        transition_warmup   <= 1'b0;
    end else begin
        frame_request_prev <= frame_request;
        source_toggle_sync <= {source_toggle_sync[1:0],source_commit_toggle};

        if (frame_tick) begin
            bundle_seen      <= committed_valid;
            bundle_bank_seen <= committed_bank;
            bundle_item_seen <= committed_item;

            if (transition_active) begin
                if (finish_transition) begin
                    active_bank         <= candidate_bank;
                    display_item        <= candidate_item;
                    transition_active   <= 1'b0;
                    transition_progress <= 9'd0;
                    transition_frame    <= 6'd0;
                    release_armed       <= 1'b1;
                    transition_warmup   <= 1'b0;
                end else if (transition_warmup) begin
                    transition_warmup   <= 1'b0;
                    transition_frame    <= 6'd1;
                    transition_progress <= PROGRESS_STEP;
                end else begin
                    transition_frame <= transition_frame + 1'b1;
                    if ((transition_progress + PROGRESS_STEP) >= PROGRESS_FULL)
                        transition_progress <= PROGRESS_FULL;
                    else
                        transition_progress <= transition_progress + PROGRESS_STEP;
                end
            end else if (new_bundle) begin
                if (can_transition && (transition_mode != 2'd0)) begin
                    candidate_bank      <= committed_bank;
                    candidate_item      <= committed_item;
                    transition_effect   <= transition_mode;
                    transition_active   <= 1'b1;
                    transition_progress <= 9'd0;
                    transition_frame    <= 6'd0;
                    transition_warmup   <= 1'b1;
                end else begin
                    active_bank         <= committed_bank;
                    display_item        <= committed_item;
                    display_valid       <= committed_valid;
                    release_armed       <= 1'b1;
                end
            end
        end

        if (!transition_active && release_armed &&
            (release_toggle != source_toggle_sync[2])) begin
            release_toggle <= source_toggle_sync[2];
            release_armed  <= 1'b0;
        end
    end
end

endmodule
