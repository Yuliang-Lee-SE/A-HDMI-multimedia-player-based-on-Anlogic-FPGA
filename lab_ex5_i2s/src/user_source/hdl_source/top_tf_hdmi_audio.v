
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key2,           // 自动播放 开/关
    input                       key3,           // Board KEY3 / B1: 1x <-> center 2x

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter TF_MAX_FILES = 32; // Verified configurations: 16, 32, 64.
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter [ADDR_BITS-1:0] FRAME_PIXELS = 307200;   // 640*480，与 frame_read_write 的地址端口同宽
parameter [ADDR_BITS-1:0] BUF0_ADDR    = 0;
parameter [ADDR_BITS-1:0] BUF1_ADDR    = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire sd_card_write_ready;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire [23:0] osd_rgb;
wire        osd_hs;
wire        osd_vs;
wire        osd_de;
wire        osd_auto_mode_sd;
wire [13:0] display_asset_sd;
wire [6:0] display_ordinal_sd;
wire write_abort,write_abort_done,audio_enabled;
reg         osd_auto_sync0;
reg         osd_auto_sync1;
reg         osd_auto_frame;
wire        display_valid;
wire display_commit_toggle, display_commit_ack, video_display_valid;
wire [1:0] video_bank;
wire [20:0] video_item;
wire [13:0] video_asset=video_item[13:0];
wire [6:0] video_ordinal=video_item[20:14];
wire caption_valid=(video_asset==1 || video_asset==2 || video_asset==3 || video_asset==4);
wire [1:0] caption_index=(video_asset==1) ? 2'd0 :
                          (video_asset==2) ? 2'd1 :
                          (video_asset==3) ? 2'd2 : 2'd3;
wire memory_read_req;
wire [23:0] caption_rgb;
wire caption_hs, caption_vs, caption_de;

// 角色 C：音频可视化波形层的输出（串在 osd_overlay 之后）
wire [23:0] wav_rgb;
wire        wav_hs;
wire        wav_vs;
wire        wav_de;

wire [3:0]  state_code;
wire [19:0] tf_init_diagnostic;
wire [6:0]  seg_data_0;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

// 角色 C：片内 ROM 语音通路（音频段索引/换段从 sd_card_clk 域传过来）
wire        audio_track_toggle;
wire [1:0]  audio_track_idx;
wire [7:0]  audio_rom_data;
wire [15:0] audio_rom_addr;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
wire    audio_pll_lock;
wire    sys_pll_lock;
wire    video_pll_lock;        
wire rst_all;
assign rst_all = ~rst_n | ~audio_pll_lock | ~video_pll_lock | ~sys_pll_lock;

// The TF scheduler/FAT/SD transaction machines use synchronous reset, while
// the byte SPI engine resets asynchronously. Hold any asynchronous reset
// assertion through three SD edges so the complete TF stack resets together.
// Release is synchronized to sd_card_clk; PLL wiring and legacy resets stay.
(* async_reg = "true" *) reg [2:0] tf_reset_pipe;
always @(posedge sd_card_clk or posedge rst_all) begin
    if (rst_all) tf_reset_pipe <= 3'b111;
    else tf_reset_pipe <= {tf_reset_pipe[1:0],1'b0};
end
wire rst_tf = tf_reset_pipe[2];


// 保持你原来的 TF / SDRAM / video 时钟
wire ext_mem_clk_sft_raw;
wire ext_mem_clk_raw;

sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk_raw),
    .clk2_out   (ext_mem_clk_sft_raw),
    .reset      (1'b0),
    .extlock    (sys_pll_lock)
);

EG_LOGIC_BUFG bufg_mem_sft (
    .i (ext_mem_clk_sft_raw),
    .o (ext_mem_clk_sft)
);

EG_LOGIC_BUFG bufg_mem (
    .i (ext_mem_clk_raw),
    .o (ext_mem_clk)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .reset      (1'b0),
    .extlock    (video_pll_lock)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (1'b0),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_all) begin
    if (rst_all)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
tf_file_player #(.MAX_FILES(TF_MAX_FILES)) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (rst_tf),
    .key_next          (key1),
    .key_auto          (key2),
    .key_zoom          (key3),
    .write_ready       (sd_card_write_ready),
    .state_code        (state_code),
    .init_diagnostic   (tf_init_diagnostic),
    .display_valid     (display_valid),
    .osd_auto_mode     (osd_auto_mode_sd),
    .display_asset(display_asset_sd),.display_ordinal(display_ordinal_sd),
    .write_abort(write_abort),.write_abort_done(write_abort_done),.audio_enabled(audio_enabled),
    .display_commit_toggle(display_commit_toggle),
    .display_commit_ack(display_commit_ack),

    // 音画联动：当前图号 + 换段脉冲（音频域内部自己同步）
    .audio_track_idx   (audio_track_idx),
    .audio_track_toggle(audio_track_toggle),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// Frozen failure payload crossing: synchronize its held-valid indication,
// wait two more scan clocks, then capture the stable word. Payload is held
// until reset/reinitialization and never feeds protocol/frame control.
(* async_reg = "true" *) reg [1:0] init_diag_valid_sync;
reg [19:0] init_diag_sync;
reg [1:0] init_diag_settle;
always @(posedge clk or posedge rst_all) begin
    if(rst_all) begin init_diag_valid_sync<=0;init_diag_sync<=0;init_diag_settle<=0;end
    else begin
        init_diag_valid_sync<={init_diag_valid_sync[0],|tf_init_diagnostic[19:16]};
        if(!init_diag_valid_sync[1]) init_diag_settle<=0;
        else begin
            init_diag_settle<={init_diag_settle[0],1'b1};
            if(!init_diag_settle[1]) init_diag_sync<=tf_init_diagnostic;
        end
    end
end
wire [34:0] init_diag_segments;
genvar diag_digit;
generate for(diag_digit=0;diag_digit<5;diag_digit=diag_digit+1) begin: init_diag_decode
    seg_decoder decode(.bin_data(init_diag_sync[19-diag_digit*4 -: 4]),
                       .seg_data(init_diag_segments[diag_digit*7 +: 7]));
end endgenerate

seg_decoder seg_decoder_m0(
    .bin_data          (state_code),
    .seg_data          (seg_data_0)
);

seg_scan seg_scan_m0(
    .clk               (clk),
    .rst_n             (rst_n),
    .seg_sel           (seg_sel),
    .seg_data          (seg_data),
    .seg_data_0        ({1'b1,(init_diag_settle[1] ? init_diag_segments[0 +: 7]:7'b1111111)}),
    .seg_data_1        ({1'b1,(init_diag_settle[1] ? init_diag_segments[7 +: 7]:7'b1111111)}),
    .seg_data_2        ({1'b1,(init_diag_settle[1] ? init_diag_segments[14 +: 7]:7'b1111111)}),
    .seg_data_3        ({1'b1,(init_diag_settle[1] ? init_diag_segments[21 +: 7]:7'b1111111)}),
    .seg_data_4        ({1'b1,(init_diag_settle[1] ? init_diag_segments[28 +: 7]:7'b1111111)}),
    .seg_data_5        ({1'b1,seg_data_0})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_all),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
assign vout_data = video_display_valid ? vout_data_raw : 24'd0;

osd_display_commit #(.ITEM_W(21)) u_display_commit(
    .clk(video_clk),.rst(rst_all),.src_toggle(display_commit_toggle),
    .src_bank(disp_buf_idx),.src_item({display_ordinal_sd,display_asset_sd}),.src_valid(display_valid),
    .frame_read_req(video_read_req),.mem_read_ack(video_read_req_ack),
    .read_req(memory_read_req),.ack_toggle(display_commit_ack),
    .bank(video_bank),.item(video_item),.valid(video_display_valid));

// Status changes slowly in the 100 MHz SD domain; synchronize them before
// using them in the 25 MHz video-pixel domain.
always @(posedge video_clk or posedge rst_all) begin
    if (rst_all) begin
        osd_auto_sync0 <= 1'b0;
        osd_auto_sync1 <= 1'b0;
        osd_auto_frame <= 1'b0;
    end else begin
        osd_auto_sync0 <= osd_auto_mode_sd;
        osd_auto_sync1 <= osd_auto_sync0;
        if(video_read_req) osd_auto_frame <= osd_auto_sync1;
    end
end

osd_layer_renderer u_osd_layers(
    .clk(video_clk),.rst(rst_all),.enable(video_display_valid),
    .auto_mode(osd_auto_frame),.item_index(video_ordinal-7'd1),
    .caption_index(caption_index),.caption_enable(caption_valid),
    .hs_in(hs),.vs_in(vs),.de_in(de),.rgb_in(vout_data),
    .hs_out(caption_hs),.vs_out(caption_vs),.de_out(caption_de),.rgb_out(caption_rgb),
    .cfg_valid(1'b0),.cfg_ready(),.cfg_show(1'b1),.cfg_x(10'd24),.cfg_y(10'd380),
    .cfg_alpha(3'd3),.cfg_shadow(1'b1),.cfg_pause(1'b0),.cfg_step(4'd2));

// 角色 C：音频可视化（时域波形）。串在 OSD 之后，只改像素、不改时序，
// 与输入同延迟 1 拍。位置/大小是波形模块的参数，可用参数挪走或缩窄。
waveform_overlay #(
    .WAV_X (64),
    .WAV_Y (16),
    .WAV_W (512),
    .WAV_H (72)
) u_waveform_overlay (
    .clk          (video_clk),
    .rst          (rst_all),
    .enable       (video_display_valid),
    .audio_valid  (audio_valid),
    .audio_sample (audio_left_data),
    .hs_in        (caption_hs),
    .vs_in        (caption_vs),
    .de_in        (caption_de),
    .rgb_in       (caption_rgb),
    .hs_out       (wav_hs),
    .vs_out       (wav_vs),
    .de_out       (wav_de),
    .rgb_out      (wav_rgb)
);

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_all),
    .write_abort(write_abort),.write_abort_done(write_abort_done),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (memory_read_req),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       ({ADDR_BITS{1'b0}}),
    .read_addr_3       ({ADDR_BITS{1'b0}}),
    .read_addr_index   (video_bank),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      ({ADDR_BITS{1'b0}}),
    .write_addr_3      ({ADDR_BITS{1'b0}}),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .write_ready       (sd_card_write_ready)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_all),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 音频：片内 ROM 语音（角色 C） =====================
// 素材：4 段 × 1.536s @ 8kHz signed 8bit（team/audio_speech_rom.mif）
// ROM 读口挂在 audio_mclk 上，读延迟 1 拍由播放器内部对齐
AUDIO_SPEECH_ROM u_audio_speech_rom (
    .doa    (audio_rom_data),
    .addra  (audio_rom_addr),
    .clka   (audio_mclk)
);

audio_rom_player #(
    .ENABLE_MUTE(1),
    .MCLK_HZ     (12295000),
    .SRC_HZ      (8000),
    .SEG_SAMPLES (12288),
    .TRACK0_ADDR (16'd0),
    .TRACK1_ADDR (16'd12288),
    .TRACK2_ADDR (16'd24576),
    .TRACK3_ADDR (16'd36864),
    .RAMP_FRAMES (960)
) u_audio_rom_player (
    .I_mclk          (audio_mclk),
    .I_rst           (rst_all),
    .I_track_idx     (audio_track_idx),
    .I_enabled(audio_enabled),
    .I_track_toggle  (audio_track_toggle),
    .I_rom_data      (audio_rom_data),
    .O_rom_addr      (audio_rom_addr),
    .O_i2s_BCLK      (audio_i2s_bclk),
    .O_i2s_LRCK      (audio_i2s_lrck),
    .O_i2s_DOUT      (audio_i2s_dout)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_all),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_all),
    .I_vs          (wav_vs),
    .I_de          (wav_de),
    .I_rgb         (wav_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_all),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_all),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_all),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
