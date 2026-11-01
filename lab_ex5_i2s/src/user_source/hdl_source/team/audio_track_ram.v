`timescale 1ns/1ps
// One current narration track. SD-domain write port, audio-clock read port.
// 24576 x 16 = 48 KB, matching the former speech ROM capacity.
module audio_track_ram (
    input  wire        wr_clk,
    input  wire        we,
    input  wire [14:0] wr_addr,
    input  wire [15:0] wr_data,
    input  wire        rd_clk,
    input  wire [14:0] rd_addr,
    output wire [15:0] rd_data
);
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A (16),
        .DATA_WIDTH_B (16),
        .ADDR_WIDTH_A (15),
        .ADDR_WIDTH_B (15),
        .DATA_DEPTH_A (24576),
        .DATA_DEPTH_B (24576),
        .MODE         ("DP"),
        .REGMODE_A    ("NOREG"),
        .REGMODE_B    ("NOREG"),
        .WRITEMODE_A  ("NORMAL"),
        .WRITEMODE_B  ("NORMAL"),
        .RESETMODE    ("SYNC"),
        .IMPLEMENT    ("32K"),
        .INIT_FILE    ("NONE"),
        .FILL_ALL     ("NONE")
    ) inst (
        .dia   (wr_data),
        .dib   (16'd0),
        .addra (wr_addr),
        .addrb (rd_addr),
        .cea   (1'b1),
        .ceb   (1'b1),
        .ocea  (1'b0),
        .oceb  (1'b0),
        .clka  (wr_clk),
        .clkb  (rd_clk),
        .wea   (we),
        // BYTE_ENABLE is disabled, so this single byte-enable bit is active
        // high and must remain asserted while wea is high.
        .bea   (1'b1),
        .web   (1'b0),
        .beb   (1'b0),
        .rsta  (1'b0),
        .rstb  (1'b0),
        .doa   (),
        .dob   (rd_data)
    );
endmodule
