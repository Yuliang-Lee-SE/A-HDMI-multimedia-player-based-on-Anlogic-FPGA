import hashlib,json,re,subprocess,sys,time
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'runs'/sys.argv[1];out.mkdir(parents=True,exist_ok=False)
lab=root.parent;rtl=lab/'src/user_source/hdl_source';image=Path(sys.argv[2]).resolve()
bin=Path('D:/FPGA-learning/Icarus/iverilog/bin')
sources=[lab/'fat32_offline/rtl/fat32_ro.sv',*sorted((root/'rtl').glob('*.sv')),
 *[rtl/s for s in ['SD/spi_master.v','SD/sd_card_bmp.v','team/bmp_center_zoom_2x.v','team/image_scaler_2x_pingpong.v','team/osd_display_commit.v']],root/'sim/sd_card_model.sv',root/'sim/tb_tf_player.sv']
hashes={str(p.relative_to(lab)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
(out/'inputs.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
p=subprocess.run([str(bin/'iverilog.exe'),'-g2012','-s','tb_tf_player','-o',str(out/'player.vvp'),*map(str,sources)],capture_output=True,text=True)
(out/'compile.log').write_text(p.stdout+p.stderr,encoding='utf-8');print(p.stdout+p.stderr,flush=True)
if p.returncode:sys.exit(p.returncode)
with (out/'player.log').open('w',encoding='utf-8') as f:
 p=subprocess.Popen([str(bin/'vvp.exe'),str(out/'player.vvp'),'+IMAGE='+image.as_posix()],stdout=f,stderr=subprocess.STDOUT,cwd=out)
 try:rc=p.wait(timeout=3600)
 except subprocess.TimeoutExpired:p.terminate();p.wait();rc=-1
t=(out/'player.log').read_text(encoding='utf-8');print(t[-5000:])
ok=rc==0 and 'TF_PLAYER_PASS' in t and not re.search(r'FAIL|FATAL|ERROR',t)
(out/'results.json').write_text(json.dumps(dict(passed=ok,exit_code=rc,inputs=hashes),indent=2),encoding='utf-8')
sys.exit(0 if ok else 1)
