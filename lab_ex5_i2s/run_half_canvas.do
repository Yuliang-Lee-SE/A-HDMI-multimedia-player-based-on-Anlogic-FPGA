onerror {quit -code 1 -f}
onbreak {resume}
file mkdir scaler_sim_build/half_canvas
vlib scaler_sim_build/half_canvas/work
vmap half_canvas scaler_sim_build/half_canvas/work
vlog -work half_canvas src/user_source/hdl_source/team/image_scaler_2x_pingpong.v src/user_source/hdl_source/team/bmp_center_zoom_2x.v tb_half_canvas.v
vsim -onfinish stop half_canvas.tb_half_canvas
run -all
if {[examine -radix decimal sim:/tb_half_canvas/errors]!=0 || [examine -radix decimal sim:/tb_half_canvas/completed]!=1} {error "Half canvas failed"}
quit -sim
puts "HALF CANVAS COMPLETE"
