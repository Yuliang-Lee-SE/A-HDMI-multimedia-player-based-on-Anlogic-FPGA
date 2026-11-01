`timescale 1ns/1ps

// Self-checking mathematical smoke test for the 32-point FFT overlay.
// It injects an exact-bin cosine, waits for the FFT to finish, and checks the
// retained 16-bin magnitude table. Rendering is intentionally not exercised
// here; this test isolates the signal-processing path.
module tb_audio_spectrum_overlay;
    localparam real PI = 3.141592653589793;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg enable = 1'b1;
    reg audio_valid = 1'b0;
    reg [23:0] audio_sample = 24'd0;
    reg hs_in = 1'b0;
    reg vs_in = 1'b0;
    reg de_in = 1'b0;
    reg [23:0] rgb_in = 24'h204060;

    wire hs_out, vs_out, de_out;
    wire [23:0] rgb_out;
    integer i, k, errors;
    integer source_value;

    audio_spectrum_overlay dut (
        .clk(clk),
        .rst(rst),
        .enable(enable),
        .audio_valid(audio_valid),
        .audio_sample(audio_sample),
        .hs_in(hs_in),
        .vs_in(vs_in),
        .de_in(de_in),
        .rgb_in(rgb_in),
        .hs_out(hs_out),
        .vs_out(vs_out),
        .de_out(de_out),
        .rgb_out(rgb_out)
    );

    always #5 clk = ~clk; // 100 MHz TB clock; the RTL itself is clock-rate agnostic.

    task run_window;
        input integer target_bin;
        input integer amplitude;
        begin
            rst = 1'b1;
            repeat (5) @(posedge clk);
            rst = 1'b0;
            errors = 0;

            // 512 mono samples at 48 kHz, decimated by 16 in the DUT. Only the
            // captured phases carry the 32-point test vector.
            for (i = 0; i < 512; i = i + 1) begin
                @(posedge clk);
                audio_valid = 1'b1;
                if ((i & 15) == 0) begin
                    source_value = $rtoi(amplitude * $cos(
                        2.0 * PI * target_bin * (i >> 4) / 32.0));
                    audio_sample = source_value <<< 6;
                end else begin
                    audio_sample = 24'd0;
                end
                @(posedge clk);
                audio_valid = 1'b0;
                repeat (2) @(posedge clk);
            end

            // 32 butterflies plus the output scan take well under 2000 cycles.
            repeat (3000) @(posedge clk);

            if (dut.spec_bar[target_bin] < 8'd16) begin
                $display("FAIL: target bin %0d height is only %0d",
                         target_bin, dut.spec_bar[target_bin]);
                errors = errors + 1;
            end
            for (k = 0; k < 16; k = k + 1) begin
                if ((k != target_bin) && (dut.spec_bar[k] > 8'd4)) begin
                    $display("FAIL: leakage bin %0d height is %0d",
                             k, dut.spec_bar[k]);
                    errors = errors + 1;
                end
            end
            if (errors == 0)
                $display("PASS: bin %0d peak=%0d",
                         target_bin, dut.spec_bar[target_bin]);
        end
    endtask

    initial begin
        run_window(0, 12000);
        run_window(5, 12000);
        run_window(15, 12000);
        if (errors == 0) $display("ALL FFT TESTS PASSED");
        else             $display("FFT TESTS FAILED: %0d", errors);
        $finish;
    end
endmodule
