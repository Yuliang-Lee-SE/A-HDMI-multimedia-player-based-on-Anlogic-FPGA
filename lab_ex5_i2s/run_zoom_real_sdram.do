onerror {quit -code 1 -f}
onbreak {resume}
set bf_root [pwd]
if {![info exists diag_library]} {set diag_library real_sdram_diag}
set bf_build [file join $bf_root scaler_sim_build $diag_library]
file mkdir $bf_build
if {![file exists [file join $bf_build work]]} {vlib [file join $bf_build work]}
vmap $diag_library [file join $bf_build work]
set bf_rtl [file join $bf_root src user_source hdl_source]
vlog -work $diag_library +incdir+src/td_project +incdir+src/user_source/hdl_source/include src/user_source/hdl_source/include/sdr_as_ram.enc.v src/user_source/hdl_source/include/sdr_init_ref.enc.v src/user_source/hdl_source/include/sdr_wrrd.enc.v
vlog -work $diag_library [file join $bf_rtl IP afifo_16_32_256.v] [file join $bf_rtl IP afifo_32_16_256.v] [file join $bf_rtl SD frame_fifo_write.v] [file join $bf_rtl SD frame_fifo_read.v] [file join $bf_rtl SD frame_read_write.v] [file join $bf_rtl team image_scaler_2x_pingpong.v] [file join $bf_rtl team bmp_center_zoom_2x.v] [file join $bf_root diagnostic_sdram_pin_model.v] [file join $bf_root tb_zoom_real_sdram.v]
if {![info exists forced_refresh]} {set forced_refresh 0}
if {![info exists diag_height]} {set diag_height 48}
if {![info exists output_div]} {set output_div 1}
if {![info exists pace_zoom]} {set pace_zoom 1}
vsim -onfinish stop -gPACE_ZOOM=$pace_zoom -gOUTPUT_DIV=$output_div -gFORCED_REFRESH=$forced_refresh -gH=$diag_height $diag_library.tb_zoom_real_sdram
run -all
if {[examine -radix decimal sim:/tb_zoom_real_sdram/errors]!=0 ||
    [examine -radix decimal sim:/tb_zoom_real_sdram/completed]!=1} {error "Board FIFO test failed"}
quit -sim
puts "REAL SDRAM DIAGNOSTIC COMPLETE (custom model, 640x$diag_height, not official PHY or board proof)"
