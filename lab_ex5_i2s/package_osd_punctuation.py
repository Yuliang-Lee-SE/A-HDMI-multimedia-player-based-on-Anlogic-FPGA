"""Package the punctuation-only revision without overwriting the board-tested bit."""
import hashlib, json, re, shutil, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def main():
    build = ROOT/'src/td_project/osd_punctuation_20261011_Runs'
    result = json.loads((build/'build_result.json').read_text(encoding='utf-8-sig'))
    before = json.loads((build/'inputs_before.json').read_text(encoding='utf-8-sig'))
    after = json.loads((build/'inputs_after.json').read_text(encoding='utf-8-sig'))
    assert before['InputHashes'] == after['InputHashes']
    for item in before['InputHashes'] + before['Artifacts']:
        assert sha(Path(item['Path'])) == item['SHA256'], item['Path']
    assert all(result[k] >= 0 for k in ['SetupWNS','SetupTNS','HoldWNS','HoldTNS'])
    assert sha(Path(result['Bit'])) == result['SHA256']
    log = (ROOT/'osd_punctuation_modules.log').read_text(errors='replace')
    for marker in ['OSD PIXELS COMPLETE checked=2150400 errors=0', 'OSD ROM COMPLETE errors=0', 'OSD STATUS/WAVEFORM PIPELINE COMPLETE checked=294144 errors=0', 'REAL VIDEO/READ SCHEDULER COMMIT COMPLETE frames=4 commits=4 errors=0']:
        assert marker in log
    assert '[FAIL]' not in log and '[TEST FAIL]' not in log and '** Error:' not in log
    assert log.count('Board zoom controller integration is correct') == 4
    audit = json.loads((ROOT/'osd_bram_init_check.json').read_text())
    assert audit['status'] == 'PASS'
    assert audit['source_sha256'].upper() == sha(ROOT/'src/user_source/hdl_source/team/osd_resources.v')
    assert audit['gate_db_sha256'].upper() == sha(build/'syn_1/HDMI1.4b_Transmitter_v1.0_gate.db')
    exceptions = (build/'phy_1/HDMI1.4b_Transmitter_v1.0_exception.timing').read_text(errors='replace')
    assert len(re.findall(r'18\s+18\s+0\s+0\s+set_max_delay', exceptions)) == 2
    dest = ROOT/'delivery/osd_punctuation_20261011'
    assert not dest.exists(), 'Refusing to overwrite delivery'
    dest.mkdir()
    shutil.copyfile(result['Bit'], dest/'osd_captions_punctuation.bit')
    for p in [build/'inputs_before.json', build/'inputs_after.json', ROOT/'osd_punctuation_modules.log', ROOT/'osd_rom_audit.log', ROOT/'osd_bram_init_check.json']:
        shutil.copyfile(p, dest/p.name)
    for p in build.rglob('*'):
        if p.is_file() and (p.suffix in ['.timing','.area','.log','.logw','.rpt'] or p.name == 'settings.cfg'):
            target = dest/'reports'/p.relative_to(build)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(p, target)
    result.update(Bit='osd_captions_punctuation.bit', SourceCommit=subprocess.check_output(['git','-c','safe.directory='+ROOT.parent.as_posix(),'rev-parse','HEAD'],cwd=ROOT,text=True).strip(), PreviousBoardTested='4d4830f', Board='UNVERIFIED punctuation revision', StorageEvidence='../osd_three_zoom_20261011/osd_three_storage_20261011.log', Scope='Font placement only; storage/control RTL unchanged from board-tested version; storage regression not repeated', MappedRomInitCheck=audit)
    (dest/'RESULTS.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (dest/'README.md').write_text('# 中文字幕标点修正\n\n使用 `osd_captions_punctuation.bit`。修正逗号、句号悬在中间的问题，其他功能沿用上一版。\n\n本地像素、控制回归和综合布线通过，修正版待上板。主要确认标点靠下、文字清楚，切图与缩放正常。\n\n上一版已上板正常，保留在 `../osd_three_zoom_20261011/` 可回退。文案仍是测试内容。\n',encoding='utf-8')
    hashes = {p.relative_to(dest).as_posix():sha(p) for p in sorted(dest.rglob('*')) if p.is_file()}
    (dest/'SHA256SUMS.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))

if __name__ == '__main__':
    main()
