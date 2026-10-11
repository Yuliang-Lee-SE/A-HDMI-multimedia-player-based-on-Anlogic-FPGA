onerror {quit -code 1 -f}
onbreak {resume}
file mkdir scaler_sim_build/half_bmp_control
vlib scaler_sim_build/half_bmp_control/work
vmap half_bmp_control scaler_sim_build/half_bmp_control/work
vlog -work half_bmp_control src/user_source/hdl_source/team/image_scaler_2x_pingpong.v src/user_source/hdl_source/team/bmp_center_zoom_2x.v src/user_source/hdl_source/SD/bmp_read.v src/user_source/hdl_source/SD/sd_card_bmp.v tb_half_bmp_control.v
vsim -onfinish stop half_bmp_control.tb_half_bmp_control
run -all
if {[examine -radix decimal sim:/tb_half_bmp_control/errors]!=0 || [examine -radix decimal sim:/tb_half_bmp_control/completed]!=1} {error "Real BMP controller failed"}
quit -sim
puts "REAL BMP THREE-MODE CONTROL COMPLETE"
