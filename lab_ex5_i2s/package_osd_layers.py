"""Archive a verified P3 candidate; retain previous deliveries and raw evidence."""
import hashlib,json,re,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent
RUN='osd_layers_20261013_final'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
    build=ROOT/'src/td_project'/f'{RUN}_Runs'
    result=json.loads((build/'build_result.json').read_text(encoding='utf-8-sig'))
    before=json.loads((build/'inputs_before.json').read_text(encoding='utf-8-sig'))
    after=json.loads((build/'inputs_after.json').read_text(encoding='utf-8-sig'))
    assert before['InputHashes']==after['InputHashes']
    for item in before['InputHashes']+before['Artifacts']:
        assert sha(Path(item['Path']))==item['SHA256'],item['Path']
    assert sha(Path(result['Bit']))==result['SHA256']
    assert all(result[k]>=0 for k in ['SetupWNS','SetupTNS','HoldWNS','HoldTNS'])
    logs=['osd_layers_release_layers.log','osd_layers_release_legacy_modules.log']
    markers=[['OSD P3 CONFIG COMPLETE errors=0',
              'OSD P3 SCROLL CONTROL COMPLETE frames=2243 errors=0',
              'OSD P3 PIXELS COMPLETE checked=2764800 errors=0',
              'OSD P3 PIPELINE COMPLETE checked=569408 overlap=6660 errors=0',
              'OSD P3 REAL VIDEO COMMIT COMPLETE frames=5 commits=4 errors=0',
              'OSD SCROLL CONTROL COMPLETE frames=2228 errors=0',
              'OSD SCROLL PIXELS COMPLETE checked=4300800 errors=0',
              'OSD SCROLL REAL VIDEO COMMIT COMPLETE frames=5 commits=4 errors=0'],
             ['OSD PIXELS COMPLETE checked=2150400 errors=0',
              'OSD ROM COMPLETE errors=0',
              'OSD STATUS/WAVEFORM PIPELINE COMPLETE checked=294144 errors=0',
              'REAL VIDEO/READ SCHEDULER COMMIT COMPLETE frames=4 commits=4 errors=0']]
    for name,required in zip(logs,markers):
        text=(ROOT/name).read_text(errors='replace')
        assert all(m in text for m in required)
        assert not re.search(r'\[FAIL\]|\[TEST FAIL\]|\*\* Error:',text)
    legacy=(ROOT/logs[1]).read_text(errors='replace')
    assert legacy.count('Board zoom controller integration is correct')==4
    audit=json.loads((ROOT/'osd_bram_init_check.json').read_text())
    assert audit['status']=='PASS'
    assert audit['source_sha256'].upper()==sha(ROOT/'src/user_source/hdl_source/team/osd_resources.v')
    assert audit['gate_db_sha256'].upper()==sha(build/'syn_1/HDMI1.4b_Transmitter_v1.0_gate.db')
    assert audit['audit_sha256'].upper()==sha(ROOT/'osd_rom_audit.log')
    timing=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_pr.timing').read_text(errors='replace')
    area=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_phy.area').read_text(errors='replace')
    exceptions=(build/'phy_1/HDMI1.4b_Transmitter_v1.0_exception.timing').read_text(errors='replace')
    assert len(re.findall(r'18\s+18\s+0\s+0\s+set_max_delay',exceptions))==2
    repo=ROOT.parent.as_posix()
    unchanged=['src/user_source/hdl_source/SD','src/user_source/hdl_source/team/bmp_center_zoom_2x.v','src/user_source/hdl_source/team/osd_display_commit.v']
    subprocess.run(['git','-c','safe.directory='+repo,'diff','--exit-code','04c90d7','HEAD','--',*unchanged],cwd=ROOT,check=True)
    dest=ROOT/'delivery/osd_layers_20261013'
    assert not dest.exists(),'Refusing to overwrite delivery'
    dest.mkdir()
    shutil.copyfile(result['Bit'],dest/'osd_layers_candidate.bit')
    for p in [build/'build_result.json',build/'inputs_before.json',build/'inputs_after.json',ROOT/'osd_rom_audit.log',ROOT/'osd_bram_init_check.json',*[ROOT/n for n in logs]]:
        shutil.copyfile(p,dest/p.name)
    for p in build.rglob('*'):
        if p.is_file() and (p.suffix in ['.timing','.area','.log','.logw','.rpt'] or p.name=='settings.cfg'):
            target=dest/'reports'/p.relative_to(build);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
    snapshots={}
    for name in ['top_tf_hdmi_audio.v','team/osd_layer_renderer.v','team/osd_resources.v']:
        source=ROOT/'src/user_source/hdl_source'/name
        target=dest/'source_snapshot'/name
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
        snapshots[name]=sha(source)
    result.update(Bit='osd_layers_candidate.bit',SourceCommit=subprocess.check_output(['git','-c','safe.directory='+repo,'rev-parse','HEAD'],cwd=ROOT,text=True).strip(),Baseline='04c90d7dd524783c8398ee4ac1fd245dbf7fdfb4',Board='UNVERIFIED P3 candidate',
      Coverage=re.search(r'STA coverage\s*:\s*([^\n]+)',timing).group(1).strip(),
      Utilization={k:int(re.search(r'#'+k+r'\s+(\d+)',area).group(1)) for k in ['lut','reg','bram9k','bram32k','dsp']},
      LayerPixelsCompared=2764800,LayerConfigAtomicity=True,DynamicScrollControlFrames=2243,
      PipelinePixelsCompared=569408,WaveformOverlapPixelsCompared=6660,
      ScrollControlFrames=2228,ScrollPixelsCompared=4300800,StaticPixelsCompared=2150400,StatusWaveformPixelsCompared=294144,
      MappedRomInitCheck=audit,InputFileCount=len(before['InputHashes']),
      SourceSHA256=snapshots,
      StorageEvidence='../osd_three_zoom_20261011/osd_three_storage_20261011.log',
      Limits='Storage/control/commit RTL unchanged; previous full SDRAM evidence retained, not rerun. Configuration is video-clock local, top uses reset defaults with cfg_valid=0; no new key bindings. No real SD/HDMI/audio physical validation. AUTO interval remains 3s, so use manual mode to view the whole long description. Copy/font still test resources.')
    (dest/'RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (dest/'README.md').write_text('# 半透明字幕面板与文字阴影\n\n使用 `osd_layers_candidate.bit`。底部面板保留25%的底图，文字加右下1像素黑影；继续保留滚动简介、三档缩放、状态序号、声音和波形。按键不变。\n\n本地像素、控制回归及综合布线通过，P3待上板。主要看面板后能否看见底图、文字是否清楚、滚动边缘有无残影，切图/缩放/声音是否正常。异常请拍画面并说明操作。\n\n本版预留显示开关、位置、透明度、阴影、暂停及速度接口，默认配置固定，暂不接新按键。看完整长简介仍请关闭轮播。\n\n已上板正常的P2回退版在 `../osd_scroll_20261011/`。\n',encoding='utf-8')
    hashes={p.relative_to(dest).as_posix():sha(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'SHA256SUMS.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
