# Compile the role-C subsystem tests in ModelSim/Questa.
# Run from lab_ex5_i2s/sim:
#   vsim -c -l compile.log -do "do ../compile.do; quit -f"

set SRCFOUND 0
foreach cand {../src/user_source/hdl_source src/user_source/hdl_source} {
    if {!$SRCFOUND && [file exists $cand/SD/bmp_read.v]} {
        set HDL [file normalize $cand]
        set SD  $HDL/SD
        set IP  $HDL/IP
        set TEAM $HDL/team
        set LABROOT [file normalize "$HDL/../../.."]
        set TFRTL $LABROOT/tf_player/rtl
        set SRCFOUND 1
        puts "==== using project HDL: $HDL ===="
    }
}
if {!$SRCFOUND} {
    set HDL rtl
    set SD  rtl
    set IP  rtl
    set TEAM rtl
    set LABROOT ..
    set TFRTL rtl
    puts "==== using local RTL copy ===="
}

if {![file exists work]} { vlib work }

vlog -work work +incdir+$SD +incdir+$HDL \
    $SD/bmp_read.v \
    $SD/sd_card_top.v $SD/sd_card_sec_read_write.v $SD/sd_card_cmd.v $SD/spi_master.v \
    $SD/sd_card_bmp.v \
    $SD/frame_fifo_write.v $SD/frame_fifo_read.v \
    $IP/afifo_16_32_256.v $IP/afifo_32_16_256.v \
    $SD/video_timing_data.v $SD/color_bar.v $SD/video_delay.v \
    $HDL/video_rgb_to_axis_640x480.v \
    $HDL/hdmi_audio_tone_i2s_64fs.v $HDL/I2S_receiver.v $HDL/audio_arc_calculate.v \
    $TEAM/audio_pcm_player.v $TFRTL/wav_pcm_loader.sv \
    sdram_model.v fake_sd_card.v fake_audio_rom.v \
    tb_bmp_read.v tb_sd_card.v tb_frame_fifo.v tb_audio_i2s.v tb_video_axis.v

if {[file exists $LABROOT/tb/tb_wav_pcm_loader.sv]} {
    vlog -work work +incdir+$SD +incdir+$HDL \
        $LABROOT/tb/tb_wav_pcm_loader.sv
    puts "==== compiled S6 WAV loader testbench ===="
} else {
    puts "==== skip S6: tb/tb_wav_pcm_loader.sv not found ===="
}

if {[file exists $LABROOT/tb/tb_key_control.v]} {
    vlog -work work +incdir+$SD +incdir+$HDL \
        fake_sd_card_multi.v $LABROOT/tb/tb_key_control.v
    puts "==== compiled S7 key-control testbench ===="
} else {
    puts "==== skip S7: tb/tb_key_control.v not found ===="
}

puts "==== compile.do complete ===="
