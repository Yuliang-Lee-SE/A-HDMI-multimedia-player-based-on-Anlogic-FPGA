"""Archive a verified P2 candidate; retain previous deliveries and raw evidence."""
import hashlib,json,re,shutil,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parent
RUN='osd_scroll_20261011'
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
    logs=['osd_scroll_final_scroll.log','osd_scroll_final_legacy_modules.log']
    markers=[['OSD SCROLL CONTROL COMPLETE frames=2228 errors=0',
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
    subprocess.run(['git','-c','safe.directory='+repo,'diff','--exit-code','d5d3eed','HEAD','--',*unchanged],cwd=ROOT,check=True)
    dest=ROOT/'delivery'/RUN
    assert not dest.exists(),'Refusing to overwrite delivery'
    dest.mkdir()
    shutil.copyfile(result['Bit'],dest/'osd_scroll_candidate.bit')
    for p in [build/'build_result.json',build/'inputs_before.json',build/'inputs_after.json',ROOT/'osd_rom_audit.log',ROOT/'osd_bram_init_check.json',*[ROOT/n for n in logs]]:
        shutil.copyfile(p,dest/p.name)
    for p in build.rglob('*'):
        if p.is_file() and (p.suffix in ['.timing','.area','.log','.logw','.rpt'] or p.name=='settings.cfg'):
            target=dest/'reports'/p.relative_to(build);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,target)
    snapshots={}
    for name in ['top_tf_hdmi_audio.v','team/osd_text_renderer.v','team/osd_resources.v']:
        source=ROOT/'src/user_source/hdl_source'/name
        target=dest/'source_snapshot'/name
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
        snapshots[name]=sha(source)
    result.update(Bit='osd_scroll_candidate.bit',SourceCommit=subprocess.check_output(['git','-c','safe.directory='+repo,'rev-parse','HEAD'],cwd=ROOT,text=True).strip(),Baseline='d5d3eed',Board='UNVERIFIED P2 candidate',
      Coverage=re.search(r'STA coverage\s*:\s*([^\n]+)',timing).group(1).strip(),
      Utilization={k:int(re.search(r'#'+k+r'\s+(\d+)',area).group(1)) for k in ['lut','reg','bram9k','bram32k','dsp']},
      ScrollControlFrames=2228,ScrollPixelsCompared=4300800,StaticPixelsCompared=2150400,StatusWaveformPixelsCompared=294144,
      MappedRomInitCheck=audit,InputFileCount=len(before['InputHashes']),
      SourceSHA256=snapshots,
      StorageEvidence='../osd_three_zoom_20261011/osd_three_storage_20261011.log',
      Limits='Storage/control/commit RTL unchanged; previous full SDRAM evidence retained, not rerun. No real SD/HDMI/audio physical validation. AUTO interval remains 3s, so use manual mode to view the whole long description. Copy/font still test resources.')
    (dest/'RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (dest/'README.md').write_text('# 滚动简介字幕\n\n使用 `osd_scroll_candidate.bit`。标题固定，长简介向左滚动，短简介不动；切图从头开始，同图缩放继续滚动。按键操作沿用原版。\n\n图片1、3使用加长测试简介，图片2、4保留短文。每2帧移动1像素，开头和末尾停约0.75秒。轮播仍为3秒一张，想看完整简介请关闭轮播、停留在当前图片。\n\n本地像素、控制回归及综合布线通过，待上板。主要检查滚动是否流畅、边缘有无残影，切图与缩放时字幕是否对应，声音和波形是否正常。异常请拍画面并说明按键操作。\n\n回退版在 `../osd_punctuation_20261011/`；之前已上板的静态版在 `../osd_three_zoom_20261011/`。\n',encoding='utf-8')
    hashes={p.relative_to(dest).as_posix():sha(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'SHA256SUMS.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
