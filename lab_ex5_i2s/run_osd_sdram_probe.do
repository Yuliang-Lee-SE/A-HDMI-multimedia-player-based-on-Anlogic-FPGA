onerror {quit -code 1 -f}
file mkdir osd_probe_sim_build
if {![file exists osd_probe_sim_build/work]} {vlib osd_probe_sim_build/work}
vmap osd_probe osd_probe_sim_build/work
vlog -work osd_probe tb_osd_sdram_probe.v
vsim -L real_sdram_diag -onfinish stop osd_probe.tb_osd_sdram_probe
run 2 ms
quit -f
