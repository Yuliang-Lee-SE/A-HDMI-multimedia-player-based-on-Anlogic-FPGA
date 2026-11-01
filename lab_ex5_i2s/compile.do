# Compile the active project's self-contained regression tests.
# Run from lab_ex5_i2s:
#   vsim -c -l compile.log -do "do compile.do; quit -f"

set SRCFOUND 0
foreach cand {src/user_source/hdl_source ../src/user_source/hdl_source} {
    if {!$SRCFOUND && [file exists $cand/SD/frame_fifo_write.v]} {
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
    error "Cannot find src/user_source/hdl_source/SD/frame_fifo_write.v"
}
if {![file exists $LABROOT/tb/tb_wav_pcm_loader.sv]} {
    error "Cannot find $LABROOT/tb/tb_wav_pcm_loader.sv"
}

if {![file exists work]} { vlib work }

# Frame-buffer path used by the current dual-bank display pipeline.
vlog -sv -work work +incdir+$SD +incdir+$HDL \
    $IP/afifo_16_32_256.v $IP/afifo_32_16_256.v \
    $SD/frame_fifo_write.v $SD/frame_fifo_read.v \
    sdram_model.v tb_frame_fifo.v

# Current audio path: TF-card WAV loader and PCM/I2S/ACR integration.
vlog -sv -work work +incdir+$SD +incdir+$HDL \
    $TEAM/audio_pcm_player.v $HDL/I2S_receiver.v $HDL/audio_arc_calculate.v \
    $TFRTL/wav_pcm_loader.sv \
    tb_audio_i2s.v $LABROOT/tb/tb_wav_pcm_loader.sv

# Current interaction, audio-visualization and reset modules.
vlog -sv -work work +incdir+$SD +incdir+$HDL \
    $TEAM/audio_spectrum_overlay.v $TEAM/board_key_debounce.v \
    $TEAM/key_short_long.v $TEAM/transition_mode_control.v \
    $TEAM/picture_adjust_controller.v $TEAM/picture_adjust_pipeline.v \
    $TEAM/picture_adjust_osd.v $TEAM/reset_startup_guard.v \
    $LABROOT/tb_audio_spectrum_overlay.v \
    $LABROOT/tb_transition_mode_control.v \
    $LABROOT/tb_picture_adjust.v \
    $LABROOT/tb_reset_startup_guard.v \
    $LABROOT/tb/tb_board_key_debounce.v

puts "==== compile.do complete ===="
