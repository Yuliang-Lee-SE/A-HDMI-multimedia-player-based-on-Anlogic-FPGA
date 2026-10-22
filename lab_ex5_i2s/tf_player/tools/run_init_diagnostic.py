"""Exact published-reference lockstep and initialization failure diagnostics."""
import hashlib,json,re,subprocess,argparse
from pathlib import Path
lab=Path(__file__).resolve().parents[2]
ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True)
ap.add_argument('--reference-cmd59',action='store_true',help='Explicitly add only CMD59 negotiation to the 716e816 protocol reference; not an unchanged published reference')
a=ap.parse_args()
out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
published=subprocess.check_output(['git','show','716e8161a146614e0b614a4899bfe758a66d6139:lab_ex5_i2s/tf_player/rtl/sd_spi_reader.sv'],cwd=lab.parent)
reference=out/'sd_spi_reader_reference.sv'
reference_bytes=published
if a.reference_cmd59:
 for v in [0,1]:
  old=f'v2<={v};release_to(RELEASED);phase<=2;'.encode()
  assert reference_bytes.count(old)==1
  reference_bytes=reference_bytes.replace(old,f'v2<={v};release_to(RELEASED);phase<=8;'.encode())
 old=b'     2: if(response==1 || response==0)'
 assert old in reference_bytes
 reference_bytes=reference_bytes.replace(old,b"     8: if(response==1) begin release_to(RELEASED);phase<=2;end else read_fail();\n"+old)
 old=b'     2:command_io(55,0,2);';assert old in reference_bytes
 reference_bytes=reference_bytes.replace(old,b'     8:command_io(59,1,8);\n'+old)
reference.write_bytes(reference_bytes.replace(b'module sd_spi_reader #(',b'module sd_spi_reader_reference #(',1))
sources=[lab/'src/user_source/hdl_source/SD/spi_master.v',lab/'tf_player/rtl/sd_spi_reader.sv',reference,
 lab/'tf_player/sim/sd_card_model.sv',lab/'tf_player/sim/tb_sd_init_diagnostic.sv']
ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem')
def hashes():return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [*sources,Path(__file__)]}
before=hashes()
def run(args,name):
 with (out/name).open('w',encoding='utf-8') as f:
  result=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,stdout=f,stderr=subprocess.STDOUT,timeout=240)
 text=(out/name).read_text(encoding='utf-8',errors='replace');print(name,result.returncode,text[-650:],flush=True)
 assert result.returncode==0 and not re.search(r'FAIL|\*\* (?:Error|Fatal)',text)
 return text
run(['vlib.exe','work'],'vlib.log');run(['vlog.exe','-sv',*sources],'compile.log')
results=[]
for case in range(12):
 text=run(['vsim.exe','-c','-onfinish','stop',f'-gCASE_ID={case}','work.tb_sd_init_diagnostic','-do',
 'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],f'case{case}.log')
 assert f'INIT_DIAG_PASS case={case} ' in text
 results.append(dict(case=case,passed=True,lockstep_cycles=int(re.search(r'lockstep_cycles=(\d+)',text)[1])))
same=before==hashes();assert same
(out/'result.json').write_text(json.dumps(dict(passed=True,results=results,inputs=before,inputs_unchanged=same,
 published_reference_commit='716e8161a146614e0b614a4899bfe758a66d6139',published_reference_sha256=hashlib.sha256(published).hexdigest(),
 reference_adjustment='CMD59 phase 8 only; explicit intentional protocol delta, NOT unchanged published behavior' if a.reference_cmd59 else 'none',
 scope=__doc__),indent=2),encoding='utf-8')
print('INIT_DIAGNOSTIC_MATRIX_PASS cases=12',flush=True)
