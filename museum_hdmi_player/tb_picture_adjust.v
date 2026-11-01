`timescale 1ns/1ps

module tb_picture_adjust;

reg clk;
reg rst;
reg key4;
reg key3;
reg key2;

wire adjust_mode;
wire [1:0] parameter_index;
wire signed [7:0] brightness;
wire [7:0] contrast;
wire [3:0] sharpness;
wire auto_key;
wire [4:0] rotation_period;
wire rotation_period_toggle;
integer failures = 0;

picture_adjust_controller #(
    .CLK_FREQ_HZ  (1_000_000),
    .DEBOUNCE_MS  (1),
    .LONG_PRESS_MS(5),
    .AUTO_KEY_MS  (3)
) dut_control (
    .clk             (clk),
    .rst             (rst),
    .key4            (key4),
    .key3            (key3),
    .key2            (key2),
    .adjust_mode     (adjust_mode),
    .parameter_index (parameter_index),
    .brightness      (brightness),
    .contrast        (contrast),
    .sharpness       (sharpness),
    .auto_key_o      (auto_key),
    .rotation_period_s (rotation_period),
    .rotation_period_toggle(rotation_period_toggle)
);

task check_control;
    input condition;
    input [8*72-1:0] message;
    begin
        if (!condition) begin
            failures = failures + 1;
            $display("[FAIL] %0s", message);
        end else begin
            $display("[PASS] %0s", message);
        end
    end
endtask

task press_key4_short;
    begin
        key4 = 1'b0;
        repeat (1500) @(posedge clk);
        key4 = 1'b1;
        repeat (1200) @(posedge clk);
    end
endtask

task press_key4_long;
    begin
        key4 = 1'b0;
        repeat (6500) @(posedge clk);
        key4 = 1'b1;
        repeat (1200) @(posedge clk);
    end
endtask

task press_key3;
    begin
        key3 = 1'b0;
        repeat (1200) @(posedge clk);
        key3 = 1'b1;
        repeat (1200) @(posedge clk);
    end
endtask

task press_key2;
    begin
        key2 = 1'b0;
        repeat (1200) @(posedge clk);
        key2 = 1'b1;
        repeat (1200) @(posedge clk);
    end
endtask

reg [23:0] rgb_tone;
reg hs_tone;
reg vs_tone;
reg de_tone;
reg signed [7:0] tone_brightness;
reg [7:0] tone_contrast;
reg [3:0] tone_sharpness;
wire [23:0] rgb_tone_out;
wire hs_tone_out;
wire vs_tone_out;
wire de_tone_out;

picture_adjust_pipeline dut_pipeline (
    .clk          (clk),
    .rst          (rst),
    .rgb_in       (rgb_tone),
    .hs_in        (hs_tone),
    .vs_in        (vs_tone),
    .de_in        (de_tone),
    .brightness_i (tone_brightness),
    .contrast_i   (tone_contrast),
    .sharpness_i  (tone_sharpness),
    .rgb_out      (rgb_tone_out),
    .hs_out       (hs_tone_out),
    .vs_out       (vs_tone_out),
    .de_out       (de_tone_out)
);

reg osd_enable;
reg [1:0] osd_parameter;
reg signed [7:0] osd_brightness;
reg [7:0] osd_contrast;
reg [3:0] osd_sharpness;
reg [4:0] osd_rotation_period;
reg hs_osd;
reg vs_osd;
reg de_osd;
reg [23:0] rgb_osd;
wire hs_osd_out;
wire vs_osd_out;
wire de_osd_out;
wire [23:0] rgb_osd_out;
integer osd_changed;

picture_adjust_osd dut_osd (
    .clk             (clk),
    .rst             (rst),
    .enable          (osd_enable),
    .parameter_index (osd_parameter),
    .brightness      (osd_brightness),
    .contrast        (osd_contrast),
    .sharpness       (osd_sharpness),
    .rotation_period_s(osd_rotation_period),
    .hs_in           (hs_osd),
    .vs_in           (vs_osd),
    .de_in           (de_osd),
    .rgb_in          (rgb_osd),
    .hs_out          (hs_osd_out),
    .vs_out          (vs_osd_out),
    .de_out          (de_osd_out),
    .rgb_out         (rgb_osd_out)
);

always #5 clk = ~clk;

task scan_osd_frame;
    integer row;
    integer col;
    begin
        de_osd = 1'b0;
        vs_osd = 1'b1;
        repeat (2) @(posedge clk);
        vs_osd = 1'b0;
        repeat (2) @(posedge clk);
        for (row = 0; row < 480; row = row + 1) begin
            de_osd = 1'b1;
            for (col = 0; col < 640; col = col + 1) begin
                rgb_osd = 24'h123456;
                @(posedge clk);
                #1;
                if (de_osd_out && rgb_osd_out != rgb_osd)
                    osd_changed = osd_changed + 1;
            end
            de_osd = 1'b0;
            @(posedge clk);
            #1;
        end
    end
endtask

initial begin
    clk = 1'b0;
    rst = 1'b1;
    key4 = 1'b1;
    key3 = 1'b1;
    key2 = 1'b1;
    rgb_tone = 24'd0;
    hs_tone = 1'b0;
    vs_tone = 1'b0;
    de_tone = 1'b0;
    tone_brightness = 8'sd0;
    tone_contrast = 8'd100;
    tone_sharpness = 4'd0;
    osd_enable = 1'b0;
    osd_parameter = 2'd0;
    osd_brightness = 8'sd0;
    osd_contrast = 8'd100;
    osd_sharpness = 4'd0;
    osd_rotation_period = 5'd3;
    hs_osd = 1'b0;
    vs_osd = 1'b0;
    de_osd = 1'b0;
    rgb_osd = 24'd0;
    osd_changed = 0;

    repeat (8) @(posedge clk);
    rst = 1'b0;
    repeat (8) @(posedge clk);

    check_control(!adjust_mode, "reset leaves adjustment mode");

    press_key4_short;
    check_control(!auto_key, "short KEY4 drives AUTO/PLAY key pulse");
    check_control(!adjust_mode, "short KEY4 does not enter menu");

    press_key4_long;
    check_control(adjust_mode, "long KEY4 enters adjustment mode");
    check_control(auto_key,
                  "long KEY4 does not drive AUTO/PLAY key pulse");
    check_control(parameter_index == 2'd0, "menu starts at brightness");

    press_key4_short;
    check_control(parameter_index == 2'd1, "short KEY4 selects contrast");
    press_key3;
    check_control(contrast == 8'd110, "KEY3 increments contrast");
    press_key2;
    check_control(contrast == 8'd100, "KEY2 decrements contrast");

    press_key4_short;
    check_control(parameter_index == 2'd2, "short KEY4 selects sharpness");
    press_key3;
    check_control(sharpness == 4'd1, "KEY3 increments sharpness");
    press_key4_short;
    check_control(parameter_index == 2'd3, "short KEY4 selects rotation period");
    press_key3;
    check_control(rotation_period == 5'd4, "KEY3 increments rotation period");
    press_key2;
    check_control(rotation_period == 5'd3, "KEY2 decrements rotation period");
    press_key4_short;
    check_control(parameter_index == 2'd0, "parameter selection wraps");
    press_key3;
    check_control(brightness == 8'sd8, "KEY3 increments brightness");
    press_key2;
    check_control(brightness == 8'sd0, "KEY2 decrements brightness");

    press_key4_long;
    check_control(!adjust_mode, "long KEY4 exits adjustment mode");
    check_control(auto_key,
                  "long KEY4 exit does not drive AUTO/PLAY key pulse");
    press_key4_short;
    check_control(!auto_key,
                  "short KEY4 after menu drives AUTO/PLAY key pulse");

    // Pipeline identity and pixel-processing checks.
    @(negedge clk);
    de_tone = 1'b1;
    hs_tone = 1'b1;
    vs_tone = 1'b1;
    rgb_tone = 24'h4080C0;
    tone_brightness = 8'sd0;
    tone_contrast = 8'd100;
    tone_sharpness = 4'd0;
    @(posedge clk);
    #1;
    $display("[INFO] default RGB output = %06h", rgb_tone_out);
    check_control(rgb_tone_out == 24'h4080C0,
                  "default picture parameters preserve RGB");
    check_control(de_tone_out && hs_tone_out && vs_tone_out,
                  "pipeline preserves timing");

    tone_contrast = 8'd150;
    rgb_tone = 24'h404040;
    @(posedge clk);
    #1;
    check_control(rgb_tone_out == 24'h202020,
                  "150 percent contrast expands from mid-gray");
    tone_contrast = 8'd100;
    tone_brightness = 8'sd8;
    rgb_tone = 24'h808080;
    @(posedge clk);
    #1;
    check_control(rgb_tone_out == 24'h888888,
                  "brightness offset is applied");

    tone_brightness = 8'sd0;
    tone_sharpness = 4'd8;
    rgb_tone = 24'h323232;
    @(posedge clk);
    #1;
    rgb_tone = 24'h323232;
    @(posedge clk);
    #1;
    rgb_tone = 24'h646464;
    @(posedge clk);
    #1;
    $display("[INFO] sharpened RGB output = %06h", rgb_tone_out);
    check_control(rgb_tone_out == 24'hC8C8C8,
                  "maximum sharpness applies the 3-tap filter");

    de_tone = 1'b0;
    hs_tone = 1'b0;
    vs_tone = 1'b0;
    @(posedge clk);

    // OSD: no visible changes when disabled; a large right-side panel when on.
    osd_enable = 1'b0;
    osd_changed = 0;
    scan_osd_frame;
    check_control(osd_changed == 0, "disabled picture OSD is transparent");
    osd_enable = 1'b1;
    osd_changed = 0;
    scan_osd_frame;
    check_control(osd_changed > 10000,
                  "enabled picture OSD draws a right-side panel");

    if (failures == 0)
        $display("=== PASS: picture adjustment controller, pipeline and OSD ===");
    else
        $display("=== FAIL: %0d picture adjustment checks ===", failures);
    $finish;
end

endmodule
