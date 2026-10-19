import hashlib,json,re,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from make_bmp_images import build
root=Path(__file__).resolve().parents[1];out=root/'runs'/sys.argv[1];out.mkdir(parents=True,exist_ok=False)
fixtures=Path(sys.argv[2]).resolve() if len(sys.argv)>2 else build(out/'fixtures')
ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem');lab=root.parent;rtl=lab/'src/user_source/hdl_source'
sources=[root/'rtl/fat32_ro.sv',root/'rtl/bmp_file_stream.sv',rtl/'team/bmp_center_zoom_2x.v',rtl/'team/image_scaler_2x_pingpong.v',root/'sim/tb_file_canvas.sv']
def run(args,name):
 p=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,capture_output=True,text=True,errors='replace',timeout=14400)
 t=p.stdout+p.stderr;(out/name).write_text(t,encoding='utf-8');print(t[-3200:],flush=True);return p.returncode,t
hashes_before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
run(['vlib.exe','work'],'vlib.log');rc,t=run(['vlog.exe','-sv',*sources],'compile.log')
if rc or '** Error' in t:sys.exit(1)
results=[]
for spc,count in [(1,32),(8,64),(64,16)]:
 d=fixtures/f'spc{spc}_n{count}';info=json.loads((d/'info.json').read_text())
 rc,t=run(['vsim.exe','-c','-onfinish','stop',f'-gMAX_FILES={count}','work.tb_file_canvas','+IMAGE='+str(d/'image.img'),'+MEDIA='+str(info['media']),'-do','onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],f'spc{spc}.log')
 ok=rc==0 and 'FILE_CANVAS_PASS' in t and not re.search(r'FAIL|\*\* (?:Error|Fatal)',t)
 results.append(dict(spc=spc,count=count,passed=ok,exit_code=rc))
 if not ok:break
(out/'results.json').write_text(json.dumps(dict(results=results,inputs=hashes_before,inputs_unchanged=hashes_before=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}),indent=2),encoding='utf-8')
sys.exit(0 if len(results)==3 and all(r['passed'] for r in results) else 1)
