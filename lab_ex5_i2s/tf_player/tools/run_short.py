import hashlib,json,re,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1];lab=root.parent;rtl=lab/'src/user_source/hdl_source'
out=root/'runs'/sys.argv[1];out.mkdir(parents=True,exist_ok=False)
ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem')
sources=[*sorted((root/'rtl').glob('*.sv')),
 *[rtl/s for s in ['SD/spi_master.v','team/bmp_center_zoom_2x.v','team/image_scaler_2x_pingpong.v','team/osd_display_commit.v','team/board_key_debounce.v','team/key_short_long.v']],
 *[root/'sim'/s for s in ['tb_list_metadata.sv','tb_write_abort.sv','tb_bmp_headers.sv','tb_tf_deadlines.sv']]]
def run(args,name):
 p=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,capture_output=True,text=True,errors='replace',timeout=180)
 t=p.stdout+p.stderr;(out/name).write_text(t,encoding='utf-8');print(t[-2000:],flush=True);return p.returncode,t
hashes_before={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
run(['vlib.exe','work'],'vlib.log');rc,t=run(['vlog.exe','-sv',*sources],'compile.log')
if rc or '** Error' in t:sys.exit(1)
results=[]
jobs=[('tb_tf_deadlines',[],'TF_DEADLINES_PASS'),('tb_bmp_headers',[],'BMP_HEADERS_PASS'),('tb_write_abort',[],'WRITE_ABORT_PASS')]+[('tb_list_metadata',[f'-gMAX_FILES={n}'],'LIST_METADATA_PASS') for n in [16,32,64]]
for bench,params,marker in jobs:
 rc,t=run(['vsim.exe','-c','-onfinish','stop',*params,'work.'+bench,'-do','onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],bench+(''.join(params))+'.log')
 ok=rc==0 and marker in t and not re.search(r'FAIL|\*\* (?:Error|Fatal)',t)
 results.append(dict(bench=bench,params=params,passed=ok,exit_code=rc))
(out/'results.json').write_text(json.dumps(dict(results=results,inputs=hashes_before,inputs_unchanged=hashes_before=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}),indent=2),encoding='utf-8')
sys.exit(0 if all(r['passed'] for r in results) else 1)
