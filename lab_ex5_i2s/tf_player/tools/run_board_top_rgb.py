"""Actual top through final RGB/AXIS, independent library and read-only fixture.

Ideal PLL clocks, custom SDRAM pin model, exact MIF bytes in behavioral ROM,
and HDMI sink/serializer boundary models. No physical HDMI/board claim.
"""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
lab=Path(__file__).resolve().parents[2];rtl=lab/'src/user_source/hdl_source'
ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True)
ap.add_argument('--image',type=Path,required=True)
ap.add_argument('--bench',choices=['tb_board_top_rgb','tb_board_reset_pulse','tb_board_init_diagnostic','tb_board_cmd8_rgb'],default='tb_board_top_rgb')
ap.add_argument('--top-source',type=Path,help='Explicit isolated candidate top; actual selected file is hashed')
ap.add_argument('--sd-source',type=Path,help='Explicit SD reference for negative control; actual selected file is hashed')
a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem')
sources=[rtl/'include'/s for s in ['sdr_as_ram.enc.v','sdr_init_ref.enc.v','sdr_wrrd.enc.v']]
sources += [rtl/s for s in ['top_tf_hdmi_audio.v',
 'IP/afifo_16_32_256.v','IP/afifo_32_16_256.v',
 'SD/frame_fifo_write.v','SD/frame_fifo_read.v','SD/frame_read_write.v','SD/sdram.v',
 'SD/spi_master.v','SD/sd_card_bmp.v','SD/seg_scan.v','SD/seg_decoder.v',
 'SD/color_bar.v','SD/video_timing_data.v','SD/video_delay.v',
 'team/osd_display_commit.v','team/image_scaler_2x_pingpong.v','team/bmp_center_zoom_2x.v',
 'osd_overlay.v','team/osd_text_renderer.v','team/osd_resources.v','team/waveform_overlay.v',
 'team/audio_rom_player.v','I2S_receiver.v','audio_arc_calculate.v',
 'video_rgb_to_axis_640x480.v','startup_pulse.v']]
if a.top_source:
 sources[sources.index(rtl/'top_tf_hdmi_audio.v')]=a.top_source.resolve()
sources += [*sorted((lab/'tf_player/rtl').glob('*.sv')),lab/'tf_player/sim/sd_card_model.sv',
 lab/'diagnostic_sdram_pin_model.v',lab/'tf_player/sim/tb_board_top_rgb.sv']
if a.sd_source:
 sources[sources.index(lab/'tf_player/rtl/sd_spi_reader.sv')]=a.sd_source.resolve()
if a.bench!='tb_board_top_rgb':sources.append(lab/f'tf_player/sim/{a.bench}.sv')
hdmi=rtl/'hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.enc.v'
header=hdmi.read_text(encoding='utf-8').split('`pragma protect begin_protected')[0]
stub=out/'hdmi_sink.v'
stub.write_text(header+'\nassign O_axis_s_ready=1;\nendmodule\n',encoding='utf-8')
sources.append(stub)
mif=rtl/'team/audio_speech_rom.mif'
contents=mif.read_text(encoding='utf-8')
pairs=re.findall(r'^\s*([0-9a-fA-F]+)\s*:\s*([0-9a-fA-F]+)\s*;',contents,re.M)
if not re.search(r'ADDRESS_RADIX\s*=\s*UNS\s*;',contents) or not re.search(r'DATA_RADIX\s*=\s*HEX\s*;',contents):
 raise SystemExit('Unexpected audio MIF radix')
values={int(addr,10):int(value,16) for addr,value in pairs}
if len(values)!=49152 or set(values)!=set(range(49152)) or any(v>255 for v in values.values()):
 raise SystemExit('Unexpected audio MIF format; refusing empty/approximate ROM')
rom=out/'audio.hex';rom.write_text(''.join(f'{values[i]:02x}\n' for i in range(49152)),encoding='ascii')
audited=[*sources,hdmi,mif,rtl/'SD/video_define.v',rtl/'include/global_def.v']
def hashes():return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in audited}
before=hashes();(out/'inputs_before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
def run(args,name,timeout):
 started=time.monotonic()
 with (out/name).open('w',encoding='utf-8') as f:
  p=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
 s=(out/name).read_text(encoding='utf-8',errors='replace')
 print(name,p.returncode,round(time.monotonic()-started,1),s[-2200:],flush=True)
 return p.returncode,s
for args,name in [(['vlib.exe','work'],'vlib.log'),(['vlog.exe',
 '+incdir+'+str(lab/'src/td_project'),'+incdir+'+str(rtl/'include'),
 '+incdir+'+str(rtl/'SD'),*sources],'compile.log')]:
 rc,s=run(args,name,180)
 if rc or '** Error' in s:raise SystemExit(1)
rc,s=run(['vsim.exe','-c','-onfinish','stop','work.'+a.bench,
 '+IMAGE='+str(a.image.resolve()),'+ROMHEX='+str(rom),'-do',
 'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],'sim.log',14400)
unchanged=hashes()==before
marker={'tb_board_top_rgb':'BOARD_TOP_RGB_PASS','tb_board_reset_pulse':'BOARD_RESET_PULSE_PASS',
 'tb_board_init_diagnostic':'BOARD_INIT_DIAGNOSTIC_PASS','tb_board_cmd8_rgb':'BOARD_TOP_RGB_PASS'}[a.bench]
ok=rc==0 and marker in s and not re.search(r'FAIL|\*\* (?:Error|Fatal)',s)
(out/'result.json').write_text(json.dumps(dict(passed=ok,inputs_unchanged=unchanged,inputs=before,
 image=str(a.image.resolve()),scope=__doc__),indent=2),encoding='utf-8')
raise SystemExit(0 if ok and unchanged else 1)
