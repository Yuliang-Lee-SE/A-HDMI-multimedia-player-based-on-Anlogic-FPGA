# Reproduce the two-buffer transition regression from lab_ex5_i2s.
file mkdir transition_v2_build
if {![file exists transition_v2_build/work]} {
    vlib transition_v2_build/work
}
vmap transition_v2_build transition_v2_build/work

vlog -work transition_v2_build \
    src/user_source/hdl_source/team/frame_compose_read.v \
    src/user_source/hdl_source/team/frame_read_write_dual.v \
    src/user_source/hdl_source/team/transition_frame_owner.v \
    src/user_source/hdl_source/team/osd_display_commit.v \
    src/user_source/hdl_source/SD/frame_fifo_write.v \
    src/user_source/hdl_source/SD/video_timing_data.v \
    src/user_source/hdl_source/SD/video_delay.v \
    src/user_source/hdl_source/SD/color_bar.v \
    src/user_source/hdl_source/IP/afifo_16_32_256.v \
    src/user_source/hdl_source/IP/afifo_32_16_256.v \
    sdram_model.v tb_compose_read_sequence.v \
    tb_transition_owner.v tb_commit_release_v2.v \
    tb_top_commit_readback.v tb_transition_v2_e2e.v

vsim -c -onfinish stop transition_v2_build.tb_compose_read_sequence \
    -do "run -all"
if {[examine -radix decimal sim:/tb_compose_read_sequence/errors] != 0} {
    error "Compose read sequence test failed"
}
quit -sim

vsim -c -onfinish stop transition_v2_build.tb_transition_owner \
    -do "run -all"
if {[examine -radix decimal sim:/tb_transition_owner/errors] != 0} {
    error "Transition owner test failed"
}
quit -sim

vsim -c -onfinish stop transition_v2_build.tb_commit_release_v2 \
    -do "run -all"
if {[examine -radix decimal sim:/tb_commit_release_v2/errors] != 0} {
    error "Commit release test failed"
}
quit -sim

vsim -c -onfinish stop transition_v2_build.tb_top_commit_readback \
    -do "run -all"
if {[examine -radix decimal sim:/tb_top_commit_readback/errors] != 0} {
    error "Top commit/readback test failed"
}
quit -sim

vsim -c -onfinish stop transition_v2_build.tb_transition_v2_e2e \
    -do "run -all"
if {[examine -radix decimal sim:/tb_transition_v2_e2e/errors] != 0} {
    error "Transition E2E test failed"
}
quit -sim
puts "TRANSITION_V2_REGRESSION_PASS"
