onerror {quit -code 1 -f}
onbreak {resume}
set control_root [pwd]
set control_build [file join $control_root scaler_sim_build board_control]
file mkdir $control_build
if {![file exists [file join $control_build work]]} {vlib [file join $control_build work]}
vmap board_control [file join $control_build work]
set control_rtl [file join $control_root src user_source hdl_source]
vlog -work board_control [file join $control_rtl team image_scaler_2x_pingpong.v] [file join $control_rtl team bmp_center_zoom_2x.v] [file join $control_rtl SD sd_card_bmp.v] [file join $control_root tb_board_zoom_control.v]
vsim -onfinish stop board_control.tb_board_zoom_control
run -all
if {[examine -radix decimal sim:/tb_board_zoom_control/errors] != 0 ||
    [examine -radix decimal sim:/tb_board_zoom_control/completed] != 1} {error "Controller test failed"}
quit -sim
puts "BOARD ZOOM CONTROL TESTS: ALL PASS (synthetic source and memory sink)"
