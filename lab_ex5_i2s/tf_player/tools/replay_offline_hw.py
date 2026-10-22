"""Replay the unchanged prototype using existing read-only stage-1 fixtures."""
import hashlib,json,re,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1];lab=root.parent
out=root/'runs'/sys.argv[1];out.mkdir(parents=True,exist_ok=False)
original=Path('C:/Users/j1573/Documents/ChatGPT/PLD/repo-fat32-offline/lab_ex5_i2s/fat32_offline/runs/final_v2_20261017')
prior=json.loads((original/'results.json').read_text(encoding='utf-8'))
ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem')
def run(args,name):
 p=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,capture_output=True,text=True,errors='replace',timeout=180)
 t=p.stdout+p.stderr;(out/name).write_text(t,encoding='utf-8');return p.returncode,t
sources=[Path(sys.argv[2]).resolve() if len(sys.argv)>2 else lab/'fat32_offline/rtl/fat32_ro.sv',lab/'fat32_offline/sim/tb_fat32_ro.sv']
run(['vlib.exe','work'],'vlib.log');rc,t=run(['vlog.exe','-sv',*sources],'compile.log')
if rc or '** Error' in t:raise SystemExit(t)
results=[]
for c in prior['results']:
 name=c['case'];cap=c['max_files'];args=[f'-gMAX_FILES={cap}']
 if name=='dir_limit':args+=['-gDIR_LIMIT=16']
 if name=='chain_limit':args+=['-gCHAIN_LIMIT=2']
 args+=['work.tb_fat32_ro','+CASE='+(original/'fixtures'/name).as_posix()]
 if name.startswith('eoc'):args+=['+EOC='+name[3:]]
 rc,t=run(['vsim.exe','-c','-quiet','-onfinish','stop',*args,'-do','onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],f'{name}_{cap}.log')
 ok=rc==0 and 'FAT32_CASE_PASS' in t and not re.search(r'\bFAIL\b|\*\* (?:Error|Fatal)',t)
 results.append(dict(case=name,max_files=cap,passed=ok));print(f'{name}/{cap}: {ok}',flush=True)
summary=dict(passed=sum(c['passed'] for c in results),failed=sum(not c['passed'] for c in results),results=results,
 inputs={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},fixtures=str(original/'fixtures'))
(out/'results.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(summary['passed'],summary['failed'])
sys.exit(0 if not summary['failed'] else 1)
