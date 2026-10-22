"""Read-only stage-2 identity/dependency audit; write new stage-3 evidence only."""
import argparse, hashlib, json
from pathlib import Path

lab = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser()
ap.add_argument('--out', type=Path, required=True)
a = ap.parse_args()
a.out.mkdir(parents=True, exist_ok=False)
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()
def save(name, obj):
    (a.out/name).write_text(json.dumps(obj, indent=2), encoding='utf-8')
overlay = json.loads((lab/'tf_player/evidence/final_overlay_manifest.json').read_text(encoding='utf-8-sig'))
project = json.loads((lab/'tf_player/evidence/project_inputs_final_v2.json').read_text(encoding='utf-8-sig'))
checks = []
for group, entries, key, value in [('overlay', overlay['files'], 'path', 'sha256'),
        ('project', project['InputHashes'], 'Path', 'SHA256'),
        ('templates', project['Artifacts'], 'Path', 'SHA256')]:
    for entry in entries:
        p = lab/entry[key]
        actual = sha(p) if p.is_file() else None
        checks.append(dict(group=group, path=str(p), expected=entry[value].lower(),
                           actual=actual, matched=actual == entry[value].lower()))
save('initial_identity.json', dict(stage2_identity=overlay['overlay_identity_sha256'], checks=checks))
# A matching source dependency is necessary for reuse, but does not expand a
# test's coverage. The intermediate player suite is always scheduled again.
matrix = []
for run in ['offline_replay01', 'spi_final02', 'canvas01', 'short_final04',
            'player02', 'player_final_smoke02']:
    folder = lab/'tf_player/runs'/run
    p = folder/'results.json'
    if not p.exists():
        matrix.append(dict(run=run, note='inspect original log/input evidence separately'))
        continue
    obj = json.loads(p.read_text(encoding='utf-8-sig'))
    inputs = obj.get('inputs', {})
    differences = []
    for name, expected in inputs.items():
        src = Path(name)
        if not src.is_absolute(): src = lab/src
        if not src.is_file() or sha(src) != expected.lower(): differences.append(name)
    matrix.append(dict(run=run, evidence=str(p), source_inputs=len(inputs),
        differences=differences, action='rerun full sequence' if run=='player02' else
        ('rerun affected coverage' if differences else 'eligible for explicit bounded reuse')))
save('validation_input_matrix.json', matrix)
bad = [c for c in checks if not c['matched']]
print(f"STAGE3_IDENTITY {'PASS' if not bad else 'FAIL'}: {len(checks)} checks; {len(bad)} differences")
raise SystemExit(bool(bad))
