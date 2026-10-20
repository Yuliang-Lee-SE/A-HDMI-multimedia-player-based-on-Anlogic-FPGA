onerror {quit -code 1 -f}
onbreak {resume}
file mkdir osd_video_sim_build
if {![file exists osd_video_sim_build/work]} {vlib osd_video_sim_build/work}
vmap osd_video osd_video_sim_build/work
set rtl src/user_source/hdl_source
vlog -work osd_video +incdir+src/td_project $rtl/SD/color_bar.v $rtl/SD/video_timing_data.v $rtl/SD/frame_fifo_read.v $rtl/team/osd_display_commit.v tb_osd_video_commit.v
vsim -onfinish stop osd_video.tb_osd_video_commit
run -all
if {[examine -radix decimal sim:/tb_osd_video_commit/errors]!=0 || [examine -radix decimal sim:/tb_osd_video_commit/completed]!=1} {error "Real video commit failed"}
quit -sim
puts "REAL VIDEO COMMIT REGRESSION PASS"
