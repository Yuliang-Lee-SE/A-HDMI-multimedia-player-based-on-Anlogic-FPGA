import_device eagle_s20.db -package EG4S20BG256
import_db src/td_project/osd_punctuation_20261011_Runs/syn_1/HDMI1.4b_Transmitter_v1.0_gate.db
set cells [get_cells -hier -regexp {.*u_osd_text.*resources.*}]
puts "OSD_ROM_CELLS $cells"
foreach cell $cells {report_property $cell}
write_verilog osd_gate_audit.v
exit
