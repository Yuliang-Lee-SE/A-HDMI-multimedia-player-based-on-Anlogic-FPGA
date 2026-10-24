`timescale 1ns/1ps
// Volume/mute state machine in the SD-card clock domain.
// A long KEY3 press steps through:
// 100% -> 75% -> 50% -> 25% -> mute -> 100%.
// level is 4 for 100%, 3 for 75%, 2 for 50%, 1 for 25% and 0 for mute.
module audio_control #(
    parameter [2:0] INIT_LEVEL = 3'd4
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       step_press,
    output reg  [2:0] level,
    output reg        toggle
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            level  <= INIT_LEVEL;
            toggle <= 1'b0;
        end else if (step_press) begin
            level  <= (level == 3'd0) ? 3'd4 : (level - 3'd1);
            toggle <= ~toggle;
        end
    end
endmodule
