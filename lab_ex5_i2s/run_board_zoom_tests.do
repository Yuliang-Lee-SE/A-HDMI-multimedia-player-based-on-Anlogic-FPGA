onerror {quit -code 1 -f}
set ROOT [pwd]
set BUILD [file join $ROOT scaler_sim_build]
file mkdir $BUILD
cd $BUILD
if {![file exists work]} {vlib work}
vmap work work
set TEAM [file join $ROOT src user_source hdl_source team]
vlog [file join $TEAM image_scaler_2x_pingpong.v] [file join $TEAM bmp_center_zoom_2x.v] [file join $TEAM tb_bmp_center_zoom_2x.v]
onbreak {resume}
vsim -c -onfinish stop work.tb_bmp_center_zoom_2x
run -all
if {[examine -radix decimal sim:/tb_bmp_center_zoom_2x/errors] != 0 ||
    [examine -radix decimal sim:/tb_bmp_center_zoom_2x/received] != 64 ||
    [examine -radix decimal sim:/tb_bmp_center_zoom_2x/completed] != 1} {error "Small zoom test failed"}
quit -sim
vsim -c -onfinish stop -gW=640 -gH=480 work.tb_bmp_center_zoom_2x
run -all
if {[examine -radix decimal sim:/tb_bmp_center_zoom_2x/errors] != 0 ||
    [examine -radix decimal sim:/tb_bmp_center_zoom_2x/received] != 307200 ||
    [examine -radix decimal sim:/tb_bmp_center_zoom_2x/completed] != 1} {error "Full zoom test failed"}
quit -sim
puts "BOARD ZOOM TESTS: ALL PASS"
cd $ROOT
