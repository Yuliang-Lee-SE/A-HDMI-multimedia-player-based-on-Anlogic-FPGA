onerror {quit -code 1 -f}
onbreak {resume}
set bf_root [pwd]
set bf_build [file join $bf_root scaler_sim_build board_fifo]
file mkdir $bf_build
if {![file exists [file join $bf_build work]]} {vlib [file join $bf_build work]}
vmap board_fifo [file join $bf_build work]
set bf_rtl [file join $bf_root src user_source hdl_source]
vlog -work board_fifo [file join $bf_rtl IP afifo_16_32_256.v] [file join $bf_rtl IP afifo_32_16_256.v] [file join $bf_rtl SD frame_fifo_write.v] [file join $bf_rtl SD frame_fifo_read.v] [file join $bf_rtl SD frame_read_write.v] [file join $bf_rtl team image_scaler_2x_pingpong.v] [file join $bf_rtl team bmp_center_zoom_2x.v] [file join $bf_root tb_board_zoom_fifo.v]
vsim -onfinish stop board_fifo.tb_board_zoom_fifo
run -all
if {[examine -radix decimal sim:/tb_board_zoom_fifo/errors]!=0 ||
    [examine -radix decimal sim:/tb_board_zoom_fifo/completed]!=1} {error "Board FIFO test failed"}
quit -sim
puts "BOARD ZOOM FIFO TESTS: ALL PASS (real FIFO/scheduler, synthetic memory sink)"
