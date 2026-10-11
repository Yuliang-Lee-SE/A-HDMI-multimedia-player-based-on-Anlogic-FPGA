"""Package only a timing-clean candidate whose disk inputs still match."""
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def main(run,regression):
    build=ROOT/'src/td_project'/f'{run}_Runs'
    result=json.loads((build/'build_result.json').read_text(encoding='utf-8-sig'))
    assert all(result[k]>=0 for k in ['SetupWNS','SetupTNS','HoldWNS','HoldTNS'])
    before=json.loads((build/'inputs_before.json').read_text(encoding='utf-8-sig'))
    after=json.loads((build/'inputs_after.json').read_text(encoding='utf-8-sig'))
    assert before['InputHashes']==after['InputHashes']
    for item in before['InputHashes']+before['Artifacts']:
        assert sha(item['Path'])==item['SHA256'], 'Changed input: '+item['Path']
    assert sha(result['Bit'])==result['SHA256']
    resources=json.loads((ROOT/'osd_assets/manifest.json').read_text(encoding='utf-8'))
    assert sha(ROOT/'tools/generate_osd_resources.py').lower()==resources['generator_sha256']
    assert sha(ROOT/'osd_assets/captions_test.json').lower()==resources['config_sha256']
    for name,digest in resources['files'].items():assert sha(ROOT/name).lower()==digest
    rom_check=json.loads((ROOT/'osd_bram_init_check.json').read_text(encoding='utf-8'))
    assert rom_check['status']=='PASS'
    assert rom_check['source_sha256']==sha(ROOT/'src/user_source/hdl_source/team/osd_resources.v').lower()
    assert rom_check['audit_sha256']==sha(ROOT/'osd_rom_audit.log').lower()
    assert rom_check['gate_db_sha256']==sha(build/'syn_1/HDMI1.4b_Transmitter_v1.0_gate.db').lower()
    storage=ROOT/regression
    text=storage.read_text(encoding='utf-8',errors='replace')
    assert text.count('[TEST PASS] Center zoom to original FIFO/address scheduler is correct.')==2
    assert '[FAIL]' not in text and '[TEST FAIL]' not in text and '** Error:' not in text
    dest=ROOT/'delivery/osd_static_cn_20261011'
    if dest.exists():raise ValueError('Delivery directory exists; refusing to overwrite')
    dest.mkdir(parents=True)
    copies={Path(result['Bit']):dest/'osd_static_cn_candidate.bit',
            build/'build_result.json':dest/'build_result.json',
            build/'inputs_before.json':dest/'inputs_before.json',
            build/'inputs_after.json':dest/'inputs_after.json',
            ROOT/'OSD_STATIC_CN_20261011.md':dest/'README.md',
            ROOT/'osd_rom_audit.log':dest/'osd_rom_audit.log',
            ROOT/'osd_bram_init_check.json':dest/'osd_bram_init_check.json',
            storage:dest/storage.name,
            ROOT/'osd_reset_hold_checked_20261011.log':dest/'osd_reset_hold_checked_20261011.log'}
    for p in build.glob('**/*'):
        if p.is_file() and (p.suffix in ('.timing','.area','.log','.logw','.rpt') or p.name=='settings.cfg'):
            target=dest/'reports'/p.relative_to(build);target.parent.mkdir(parents=True,exist_ok=True);copies[p]=target
    unified=sorted(ROOT.glob('osd_validation_*.log'))[-1]
    utext=unified.read_text(encoding='utf-8',errors='replace')
    for marker in ['OSD PIXELS COMPLETE checked=2150400 errors=0','OSD ROM COMPLETE errors=0','OSD STATUS/WAVEFORM PIPELINE COMPLETE checked=294144 errors=0','REAL VIDEO/READ SCHEDULER COMMIT COMPLETE frames=4 commits=4 errors=0','[TEST PASS] BMP center zoom and 1x/2x/1x frame switching are correct.','[TEST PASS] Board zoom controller integration is correct.','[TEST PASS] Center zoom to original FIFO/address scheduler is correct.']:
        assert marker in utext
    assert '[TEST FAIL]' not in utext and '** Error:' not in utext
    copies[unified]=dest/unified.name
    for p,target in copies.items():shutil.copyfile(p,target)
    sources=[ROOT/'src/user_source/hdl_source'/p for p in ['top_tf_hdmi_audio.v','SD/sd_card_bmp.v','SD/frame_read_write.v','team/osd_resources.v','team/osd_text_renderer.v','team/osd_display_commit.v']]
    snapshots={}
    for p in sources:
        target=dest/'source_snapshot'/p.relative_to(ROOT/'src/user_source/hdl_source');target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(p,target);snapshots[str(p.relative_to(ROOT))]=sha(p)
    timing=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_pr.timing').read_text(errors='replace')
    area=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_phy.area').read_text(errors='replace')
    exceptions=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_exception.timing').read_text(errors='replace')
    assert exceptions.count('datapath_only 7.700')>=4
    assert len(re.findall(r'18\s+18\s+0\s+0\s+set_max_delay',exceptions))==2
    result.update(SourceCommit=subprocess.check_output(['git','-c','safe.directory='+str(ROOT.parent).replace('\\','/'),'rev-parse','HEAD'],cwd=ROOT,text=True).strip(),Baseline='cf3d3fb19154b1a978b25c14ac606c444e25fb7a',Branch='feat/osd-static-cn',
      InputFileCount=len(before['InputHashes']),SourceSHA256=snapshots,
      Coverage=re.search(r'STA coverage\s*:\s*([^\n]+)',timing).group(1).strip(),
      Utilization={k:int(re.search(r'#'+k+r'\s+(\d+)',area).group(1)) for k in ['lut','reg','bram9k','bram32k','dsp']},
      PixelsCompared=2150400,StatusWaveformPixelsCompared=294144,
      MappedRomInitCheck=rom_check,
      Board='UNVERIFIED',Copy='TEST ONLY; formal text/font not frozen',
      KnownLimits='Synthetic source/custom SDRAM model; new read waits 100 mem clocks; full automatic refresh not observed; physical tail after write finish retained; no physical HDMI/SD/Flash signing',
      EvidenceNote='Earlier unified long run was stopped after resources/display/control passed because final RTL superseded it; final quick entry, reset/FIFO and full-size/refresh SDRAM verified separately. The cancelled log is not a complete-suite pass')
    (dest/'RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifests={str(p.relative_to(dest)).replace('\\','/'):sha(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'SHA256SUMS.json').write_text(json.dumps(manifests,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--regression',required=True);a=p.parse_args();main(a.run,a.regression)
