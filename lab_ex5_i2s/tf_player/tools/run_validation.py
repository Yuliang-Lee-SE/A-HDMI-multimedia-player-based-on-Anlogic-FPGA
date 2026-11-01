"""File/transport regression entry. Real SDRAM, builds and hardware are separate."""
import argparse,json,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1];lab=root.parent
ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path,required=True)
ap.add_argument('--fixtures',type=Path,required=True,help='Existing make_bmp_images.py output; never changed')
a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
fixtures=a.fixtures.resolve();jobs=[('spi','run_spi.py',[]),('short','run_short.py',[]),
 ('canvas','run_canvas.py',[str(fixtures)]),
 ('offline','replay_offline.py',[])]
results=[]
for name,tool,args in jobs:
 rc=subprocess.call([sys.executable,str(root/'tools'/tool),str(out/name),*args],cwd=lab)
 results.append(dict(suite=name,exit_code=rc))
 (out/'summary.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
 if rc:sys.exit(rc)
print('TF_PLAYER_MODULE_VALIDATION_PASS (real SDRAM/build/hardware are separate)')
