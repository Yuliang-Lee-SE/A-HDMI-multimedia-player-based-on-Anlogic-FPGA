"""Independent CMD59/CRC-mode cases with exact previous candidate counterexample."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
lab=Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True);ap.add_argument('--candidate',type=Path)
a=ap.parse_args();out=a.out.resolve();out.mkdir(exist_ok=False,parents=True)
reference=out/'sd_spi_reader_previous.sv'
reference.write_bytes(subprocess.check_output(['git','show','214abad:lab_ex5_i2s/tf_player/rtl/sd_spi_reader.sv'],cwd=lab.parent).replace(b'module sd_spi_reader #(',b'module sd_spi_reader_previous #(',1))
sources=[lab/'src/user_source/hdl_source/SD/spi_master.v',(a.candidate.resolve()/'sd_spi_reader.sv' if a.candidate else lab/'tf_player/rtl/sd_spi_reader.sv'),(a.candidate.resolve()/'sd_card_model.sv' if a.candidate else lab/'tf_player/sim/sd_card_model.sv'),reference,lab/'tf_player/sim/tb_cmd59_negotiation.sv']
ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem')
def hashes():return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,Path(__file__)]}
before=hashes();results=[]
def run(args,name):
 with (out/name).open('w',encoding='utf-8') as f:r=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,stdout=f,stderr=subprocess.STDOUT,timeout=180)
 text=(out/name).read_text(encoding='utf-8',errors='replace')
 assert r.returncode==0 and not re.search(r'FAIL|\*\* (?:Error|Fatal)',text),text[-2500:]
 return text
run(['vlib.exe','work'],'vlib.log');run(['vlog.exe','-sv',*sources],'compile.log')
for i in range(16):
 text=run(['vsim.exe','-c','-onfinish','stop',f'-gCASE_ID={i}','work.tb_cmd59_negotiation','-do','onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],f'case{i}.log')
 match=re.search(r'CMD59_NEGOTIATION_PASS[^\n]*',text);assert match;print(match[0],flush=True);results.append(dict(case=i,passed=True,result=match[0]))
assert before==hashes()
(out/'result.json').write_text(json.dumps(dict(passed=True,results=results,inputs=before,inputs_unchanged=True,scope=__doc__),indent=2),encoding='utf-8')
