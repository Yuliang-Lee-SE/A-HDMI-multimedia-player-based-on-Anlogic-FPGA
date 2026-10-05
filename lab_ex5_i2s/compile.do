# ============================================================
# 纯 RTL 子系统仿真：建库 + 编译全部源文件与 testbench
# 用法（必须先切到本 sim 目录）：
#     cd <工程>/sim
#     vsim -c -do compile.do          （或直接运行 run_all.bat）
# 源文件来源：
#   1) 优先用工程里的 ../src/user_source/hdl_source（保证和工程同步）
#   2) 若本目录被单独拷到别处（例如英文路径），则用同目录下的 rtl/ 副本
#   注意：ModelSim 不能在有中文的路径下建库，所以整体拷到
#        纯英文路径（或先用 copy_to_ascii_path.bat）再跑。
# ============================================================
# 依次找：工程里的源码（两种相对位置）-> 本目录的 rtl/ 副本
set SRCFOUND 0
foreach cand {../src/user_source/hdl_source src/user_source/hdl_source} {
    if {!$SRCFOUND && [file exists $cand/SD/bmp_read.v]} {
        set HDL $cand
        set SD  $HDL/SD
        set IP  $HDL/IP
        set SRCFOUND 1
        puts "==== 使用源码：$HDL ===="
    }
}
if {!$SRCFOUND} {
    set HDL rtl
    set SD  rtl
    set IP  rtl
    puts "==== 使用本目录下的 rtl/ 副本 ===="
}

if {![file exists work]} { vlib work }

vlog -work work +incdir+$SD +incdir+$HDL \
    $SD/bmp_read.v \
    $SD/sd_card_top.v $SD/sd_card_sec_read_write.v $SD/sd_card_cmd.v $SD/spi_master.v \
    $SD/frame_fifo_write.v $SD/frame_fifo_read.v \
    $IP/afifo_16_32_256.v $IP/afifo_32_16_256.v \
    $SD/video_timing_data.v $SD/color_bar.v $SD/video_delay.v \
    $HDL/video_rgb_to_axis_640x480.v \
    $HDL/hdmi_audio_tone_i2s_64fs.v $HDL/I2S_receiver.v $HDL/audio_arc_calculate.v \
    sdram_model.v fake_sd_card.v \
    tb_bmp_read.v tb_sd_card.v tb_frame_fifo.v tb_audio_i2s.v tb_video_axis.v

puts "==== compile.do 完成：work 库里已有 5 个子系统 DUT + 5 个 testbench ===="
