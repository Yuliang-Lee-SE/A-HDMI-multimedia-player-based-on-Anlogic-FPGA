"""Package only a timing-clean candidate whose disk inputs still match."""
import argparse,hashlib,json,re,shutil,subprocess
from pathlib import Path

README='# 三档缩放＋中文字幕\n\nKEY3按1×→中心2×→居中0.5×循环。底部增加四组中文测试标题和简介，保留PLAY/AUTO、图片序号、切图、轮播、音频和波形。字幕跟随图片更新，缩放时位置和字号固定；简介暂不滚动。\n\n使用本目录的 `osd_three_zoom_candidate.bit`。本地仿真和编译已通过，待上板。三档独立版已上板正常；这份整合版需重新上板验证，正常版先留着回退。\n\n上板主要看：\n\n1. KEY3循环三档，0.5×图像居中，黑边无残留，字幕字号和位置不变。\n2. 手动切图、轮播时，图片、序号和字幕是否对应。\n3. 加载中连按KEY3、轮播中缩放是否正常；加载期间应保留旧图旧字幕。\n4. 声音和波形是否正常，字幕是否清楚；复位是否恢复首图。\n\n有异常请拍下画面，并说明当时按了什么键。文案目前为测试内容，后面再换正式的。\n\n详细结果和文件校验值见 `RESULTS.json`、`SHA256SUMS.json`，日志和报告留作排查。\n'
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
    dest=ROOT/'delivery/osd_three_zoom_20261011'
    if dest.exists():raise ValueError('Delivery directory exists; refusing to overwrite')
    dest.mkdir(parents=True)
    copies={Path(result['Bit']):dest/'osd_three_zoom_candidate.bit',
            build/'build_result.json':dest/'build_result.json',
            build/'inputs_before.json':dest/'inputs_before.json',
            build/'inputs_after.json':dest/'inputs_after.json',
            ROOT/'osd_rom_audit.log':dest/'osd_rom_audit.log',
            ROOT/'osd_bram_init_check.json':dest/'osd_bram_init_check.json',
            storage:dest/storage.name,
            ROOT/'osd_three_control_checked_20261011.log':dest/'osd_three_control_checked_20261011.log'}
    for p in build.glob('**/*'):
        if p.is_file() and (p.suffix in ('.timing','.area','.log','.logw','.rpt') or p.name=='settings.cfg'):
            target=dest/'reports'/p.relative_to(build);target.parent.mkdir(parents=True,exist_ok=True);copies[p]=target
    unified=ROOT/'osd_three_final_modules.log'
    utext=unified.read_text(encoding='utf-8',errors='replace')
    for marker in ['OSD PIXELS COMPLETE checked=2150400 errors=0','OSD ROM COMPLETE errors=0','OSD STATUS/WAVEFORM PIPELINE COMPLETE checked=294144 errors=0','REAL VIDEO/READ SCHEDULER COMMIT COMPLETE frames=4 commits=4 errors=0','[TEST PASS] BMP center zoom and 1x/2x/1x frame switching are correct.','[TEST PASS] Board zoom controller integration is correct.','[TEST PASS] Center zoom to original FIFO/address scheduler is correct.']:
        assert marker in utext
    assert '[TEST FAIL]' not in utext and '[FAIL]' not in utext and '** Error:' not in utext
    btext=(ROOT/'osd_three_control_checked_20261011.log').read_text(errors='replace')
    assert '[TEST PASS] Board zoom controller integration is correct.' in btext and '[FAIL]' not in btext and '** Error:' not in btext
    for mode in range(3):
        assert text.count(f'[NEW FRAME] mode={mode} ')==2
    assert 'underflows=0' in text
    copies[unified]=dest/unified.name
    for p,target in copies.items():shutil.copyfile(p,target)
    (dest/'README.md').write_text(README,encoding='utf-8')
    sources=[ROOT/'src/user_source/hdl_source'/p for p in ['top_tf_hdmi_audio.v','SD/sd_card_bmp.v','SD/frame_read_write.v','team/osd_resources.v','team/osd_text_renderer.v','team/osd_display_commit.v','SD/bmp_read.v','team/bmp_center_zoom_2x.v']]
    snapshots={}
    for p in sources:
        target=dest/'source_snapshot'/p.relative_to(ROOT/'src/user_source/hdl_source');target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(p,target);snapshots[str(p.relative_to(ROOT))]=sha(p)
    timing=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_pr.timing').read_text(errors='replace')
    area=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_phy.area').read_text(errors='replace')
    exceptions=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_exception.timing').read_text(errors='replace')
    assert exceptions.count('datapath_only 7.700')>=4
    assert len(re.findall(r'18\s+18\s+0\s+0\s+set_max_delay',exceptions))==2
    result.update(SourceCommit=subprocess.check_output(['git','-c','safe.directory='+str(ROOT.parent).replace('\\','/'),'rev-parse','HEAD'],cwd=ROOT,text=True).strip(),Baseline='cf3d3fb19154b1a978b25c14ac606c444e25fb7a',Bit='osd_three_zoom_candidate.bit',Branch='feat/osd-three-zoom',IntegratedFrom=['3da821f','8f50462'],
      InputFileCount=len(before['InputHashes']),SourceSHA256=snapshots,
      Coverage=re.search(r'STA coverage\s*:\s*([^\n]+)',timing).group(1).strip(),
      Utilization={k:int(re.search(r'#'+k+r'\s+(\d+)',area).group(1)) for k in ['lut','reg','bram9k','bram32k','dsp']},
      PixelsCompared=2150400,StatusWaveformPixelsCompared=294144,
      MappedRomInitCheck=rom_check,
      Board='UNVERIFIED',Copy='TEST ONLY; formal text/font not frozen',
      KnownLimits='Synthetic source/custom SDRAM model; new read waits 100 mem clocks; full automatic refresh not observed; physical tail after write finish retained; no physical HDMI/SD/Flash signing',
      EvidenceNote='Integrated three-mode source verified with modules, real-BMP display-commit test, and full-size/forced-refresh SDRAM readback. Separate feature board feedback does not qualify the integrated candidate.')
    (dest/'RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifests={str(p.relative_to(dest)).replace('\\','/'):sha(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'SHA256SUMS.json').write_text(json.dumps(manifests,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--run',required=True);p.add_argument('--regression',required=True);a=p.parse_args();main(a.run,a.regression)
