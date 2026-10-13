onerror {quit -code 1 -f}
onbreak {resume}
file mkdir osd_layers_sim_build
if {![file exists osd_layers_sim_build/work]} {vlib osd_layers_sim_build/work}
vmap osd_layers osd_layers_sim_build/work
set rtl src/user_source/hdl_source
vlog -work osd_layers $rtl/team/osd_resources.v $rtl/team/osd_layer_renderer.v tb_osd_layers_config.v tb_osd_layers_pixels.v tb_osd_layers_scroll.v
foreach bench {tb_osd_layers_config tb_osd_layers_scroll tb_osd_layers_pixels} {
 vsim -onfinish stop osd_layers.$bench
 run -all
 if {[examine -radix decimal sim:/$bench/errors]!=0 || [examine -radix decimal sim:/$bench/completed]!=1} {error "$bench failed"}
 quit -sim
}
puts "OSD P3 CONFIG/PIXEL REGRESSIONS PASS"

vlog -work osd_layers $rtl/osd_overlay.v $rtl/team/osd_text_renderer.v $rtl/team/waveform_overlay.v tb_osd_layers_pipeline.v
vsim -onfinish stop osd_layers.tb_osd_layers_pipeline
run -all
if {[examine -radix decimal sim:/tb_osd_layers_pipeline/errors]!=0 || [examine -radix decimal sim:/tb_osd_layers_pipeline/completed]!=1} {error "P3 pipeline failed"}
quit -sim
puts "OSD P3 WAVEFORM/PIPELINE REGRESSION PASS"

vlog -work osd_layers +incdir+src/user_source/hdl_source/SD $rtl/SD/color_bar.v $rtl/SD/video_timing_data.v $rtl/SD/frame_fifo_read.v $rtl/team/osd_display_commit.v tb_osd_layers_video.v
vsim -onfinish stop osd_layers.tb_osd_layers_video
run -all
if {[examine -radix decimal sim:/tb_osd_layers_video/errors]!=0 || [examine -radix decimal sim:/tb_osd_layers_video/completed]!=1} {error "P3 real video commit failed"}
quit -sim
puts "OSD P3 REAL VIDEO REGRESSION PASS"
