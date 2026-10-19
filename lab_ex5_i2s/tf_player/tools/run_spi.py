import hashlib,json,re,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
out=(root/'runs'/sys.argv[1]).resolve()
out.mkdir(parents=True,exist_ok=False)
ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem')
sources=[root.parents[0]/'src/user_source/hdl_source/SD/spi_master.v',root/'rtl/sd_spi_reader.sv',root/'sim/sd_card_model.sv',root/'sim/tb_sd_spi_reader.sv']
hashes={str(p.relative_to(root.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
def run(args,name):
 p=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,capture_output=True,text=True,errors='replace',timeout=180)
 txt=p.stdout+p.stderr;(out/name).write_text(txt,encoding='utf-8');print(txt[-4000:]);return p.returncode,txt
run(['vlib.exe','work'],'vlib.log')
rc,t=run(['vlog.exe','-sv',*sources],'compile.log')
if rc or '** Error' in t:sys.exit(1)
rc,t=run(['vsim.exe','-c','-onfinish','stop','work.tb_sd_spi_reader','-do','onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],'spi.log')
ok=rc==0 and 'SD_SPI_PASS' in t and not re.search(r'FAIL|\*\* (?:Error|Fatal)',t)
(out/'result.json').write_text(json.dumps(dict(passed=ok,exit_code=rc,inputs=hashes),indent=2),encoding='utf-8')
sys.exit(0 if ok else 1)
