onerror {quit -code 1 -f}
onbreak {resume}
file mkdir osd_scroll_sim_build
if {![file exists osd_scroll_sim_build/work]} {vlib osd_scroll_sim_build/work}
vmap osd_scroll osd_scroll_sim_build/work
set rtl src/user_source/hdl_source
vlog -work osd_scroll $rtl/team/osd_resources.v $rtl/team/osd_text_renderer.v tb_osd_scroll_ctrl.v tb_osd_scroll_pixels.v
foreach bench {tb_osd_scroll_ctrl tb_osd_scroll_pixels} {
 vsim -onfinish stop osd_scroll.$bench
 run -all
 if {[examine -radix decimal sim:/$bench/errors]!=0 || [examine -radix decimal sim:/$bench/completed]!=1} {error "$bench failed"}
 quit -sim
}
puts "OSD SCROLL REGRESSIONS PASS"

vlog -work osd_scroll +incdir+src/user_source/hdl_source/SD $rtl/SD/color_bar.v $rtl/SD/video_timing_data.v $rtl/SD/frame_fifo_read.v $rtl/team/osd_display_commit.v tb_osd_scroll_video.v
vsim -onfinish stop osd_scroll.tb_osd_scroll_video
run -all
if {[examine -radix decimal sim:/tb_osd_scroll_video/errors]!=0 || [examine -radix decimal sim:/tb_osd_scroll_video/completed]!=1} {error "Real video scroll integration failed"}
quit -sim
puts "OSD SCROLL REAL VIDEO REGRESSION PASS"
