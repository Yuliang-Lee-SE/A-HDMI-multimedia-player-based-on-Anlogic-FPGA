onerror {quit -code 1 -f}
onbreak {resume}
set root [pwd]
file mkdir osd_sim_build
if {![file exists osd_sim_build/work]} {vlib osd_sim_build/work}
vmap osd_work osd_sim_build/work
set rtl src/user_source/hdl_source
vlog -work osd_work $rtl/team/osd_resources.v $rtl/team/osd_text_renderer.v tb_osd_pixels.v
vsim -onfinish stop osd_work.tb_osd_pixels
run -all
if {[examine -radix decimal sim:/tb_osd_pixels/errors]!=0 || [examine -radix decimal sim:/tb_osd_pixels/completed]!=1} {error "OSD pixel regression failed"}
quit -sim
puts "OSD PIXEL REGRESSION PASS"
vlog -work osd_work $rtl/osd_overlay.v $rtl/team/waveform_overlay.v tb_osd_rom.v tb_osd_pipeline.v
foreach bench {tb_osd_rom tb_osd_pipeline} {
 vsim -onfinish stop osd_work.$bench
 run -all
 if {[examine -radix decimal sim:/$bench/errors]!=0 || [examine -radix decimal sim:/$bench/completed]!=1} {error "$bench failed"}
 quit -sim
}
puts "OSD ROM AND STATUS/WAVEFORM REGRESSIONS PASS"
