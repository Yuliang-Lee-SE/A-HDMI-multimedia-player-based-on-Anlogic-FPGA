import hashlib,json,re,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'runs'/sys.argv[1];out.mkdir(parents=True,exist_ok=False)
image=Path(sys.argv[2]).resolve();ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem');lab=root.parent;rtl=lab/'src/user_source/hdl_source'
sources=[*sorted((root/'rtl').glob('*.sv')),
 *[rtl/s for s in ['SD/spi_master.v','SD/sd_card_bmp.v','SD/frame_fifo_write.v','SD/frame_read_write.v','team/bmp_center_zoom_2x.v','team/image_scaler_2x_pingpong.v','team/osd_display_commit.v','team/osd_text_renderer.v','team/osd_resources.v','team/audio_rom_player.v','osd_overlay.v','top_tf_hdmi_audio.v']],root/'sim/sd_card_model.sv',root/'sim/tb_tf_player.sv']
def run(args,name):
 p=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,capture_output=True,text=True,errors='replace',timeout=7200)
 t=p.stdout+p.stderr;(out/name).write_text(t,encoding='utf-8');print(t[-5000:],flush=True);return p.returncode,t
hashes={str(p.relative_to(lab)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
(out/'inputs.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
run(['vlib.exe','work'],'vlib.log');rc,t=run(['vlog.exe','-sv',*sources],'compile.log')
if rc or '** Error' in t:sys.exit(1)
params=['-gSMOKE_ONLY=1'] if '--smoke' in sys.argv else []
rc,t=run(['vsim.exe','-c','-onfinish','stop',*params,'work.tb_tf_player','+IMAGE='+str(image),'-do','onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],'player.log')
marker='TF_PLAYER_SMOKE_PASS' if params else 'TF_PLAYER_PASS'
ok=rc==0 and marker in t and not re.search(r'FAIL|\*\* (?:Error|Fatal)',t)
(out/'results.json').write_text(json.dumps(dict(passed=ok,exit_code=rc,inputs=hashes),indent=2),encoding='utf-8')
sys.exit(0 if ok else 1)
