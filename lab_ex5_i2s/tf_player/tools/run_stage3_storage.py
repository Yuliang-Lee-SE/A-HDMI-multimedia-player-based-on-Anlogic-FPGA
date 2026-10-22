"""Full real-controller regression. No fixtures copied; no waveform dump."""
import argparse, hashlib, json, re, subprocess, time
from pathlib import Path

lab=Path(__file__).resolve().parents[2]
ms=Path('D:/j1573/modelsim/modelsim_ase/win32aloem')
ap=argparse.ArgumentParser()
ap.add_argument('--out',type=Path,required=True)
ap.add_argument('--bench',default='tb_stage3_storage')
ap.add_argument('--image',type=Path)
ap.add_argument('--self-refresh',type=int,choices=[0,1],default=1,help='Actual controller parameter; default matches standard hardware')
ap.add_argument('--refresh',type=int,choices=[0,1],default=None)
ap.add_argument('--mode',type=int,choices=[0,1,2],default=None,
                help='Independent full-BMP old-frame/failure/recovery case for one scale')
a=ap.parse_args();out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
rtl=lab/'src/user_source/hdl_source'
sources=[rtl/'include'/s for s in ['sdr_as_ram.enc.v','sdr_init_ref.enc.v','sdr_wrrd.enc.v']]
sources += [rtl/s for s in ['team/osd_display_commit.v','IP/afifo_16_32_256.v','IP/afifo_32_16_256.v',
    'SD/frame_fifo_write.v','SD/frame_fifo_read.v','SD/frame_read_write.v',
    'team/image_scaler_2x_pingpong.v','team/bmp_center_zoom_2x.v']]
if a.bench=='tb_stage3_e2e':
    sources += [*sorted((lab/'tf_player/rtl').glob('*.sv')),
                rtl/'SD/spi_master.v',rtl/'SD/sd_card_bmp.v',lab/'tf_player/sim/sd_card_model.sv',
                rtl/'SD/color_bar.v',rtl/'SD/video_timing_data.v',rtl/'SD/video_delay.v']
sources += [lab/'diagnostic_sdram_pin_model.v',lab/f'tf_player/sim/{a.bench}.sv']
def hashes():
    return {str(p.relative_to(lab)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
before=hashes();(out/'inputs_before.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
def run(args,name,timeout=14400):
    started=time.monotonic()
    with (out/name).open('w',encoding='utf-8') as f:
        p=subprocess.run([str(ms/args[0]),*map(str,args[1:])],cwd=out,stdout=f,
                         stderr=subprocess.STDOUT,timeout=timeout)
    t=(out/name).read_text(encoding='utf-8',errors='replace')
    print(name, 'exit',p.returncode,'seconds',round(time.monotonic()-started,1),t[-2200:],flush=True)
    return p.returncode,t
rc,t=run(['vlib.exe','work'],'vlib.log',60)
if rc:raise SystemExit(rc)
rc,t=run(['vlog.exe','-sv','+incdir+'+str(lab/'src/td_project'),
          '+incdir+'+str(rtl/'include'),'+incdir+'+str(rtl/'SD'),*sources],'compile.log',180)
if rc or '** Error' in t:raise SystemExit(1)
results=[]
for refresh in ([0,1] if a.refresh is None else [a.refresh]):
    params=[f'-gFORCED_REFRESH={refresh}',f'-gSELF_REFRESH_OPEN={a.self_refresh}']
    if a.mode is not None: params += [f'-gTARGET_MODE={a.mode}']
    if a.image: params+=['+IMAGE='+str(a.image.resolve())]
    marker={'tb_stage3_storage':'STAGE3_STORAGE_PASS','tb_stage3_e2e':'STAGE3_E2E_PASS',
            'tb_stage3_cancel':'STAGE3_CANCEL_PASS'}[a.bench]
    rc,t=run(['vsim.exe','-c','-onfinish','stop',*params,'work.'+a.bench,'-do',
              'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'],f'refresh{refresh}.log')
    ok=rc==0 and marker in t and not re.search(r'\[FAIL\]|\bFAIL\b|\*\* (?:Error|Fatal)',t)
    results.append(dict(refresh=refresh,controller_self_refresh_open=a.self_refresh,target_mode=a.mode,passed=ok,exit_code=rc))
    (out/'results.json').write_text(json.dumps(dict(results=results,inputs=before,
        inputs_unchanged=hashes()==before,model='vendor encrypted RTL + original FIFO + custom pin model; no board'),indent=2),encoding='utf-8')
    if not ok:break
raise SystemExit(0 if all(r['passed'] for r in results) and hashes()==before else 1)
