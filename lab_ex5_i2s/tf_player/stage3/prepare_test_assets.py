"""Generate ordinary BMP files in a NEW PC folder; never opens a raw device."""
import argparse, hashlib, json, struct
from pathlib import Path

ap=argparse.ArgumentParser()
ap.add_argument('--out',type=Path,required=True)
ap.add_argument('--count',type=int,choices=[16,32,64],default=32)
ap.add_argument('--case',choices=['normal','missing_ids','bad_bmp'],default='normal')
a=ap.parse_args()
a.out.mkdir(parents=True,exist_ok=False)
ids=list(range(1,a.count+1))
if a.case=='missing_ids': ids=[i if i<=5 else i+100 for i in ids[:-1]]+[9999]
records=[]
for asset in ids:
    pixels=bytearray()
    for y in range(480):
        for x in range(640): pixels.extend(((x+asset)&255,(y*3+asset)&255,(x^y^asset)&255))
    raw=bytearray(struct.pack('<2sIHHI',b'BM',921654,0,0,54)+
        struct.pack('<IiiHHIIiiII',40,640,480,1,24,0,921600,2835,2835,0,0)+pixels)
    rejected=a.case=='bad_bmp' and asset==2
    if rejected: struct.pack_into('<I',raw,30,1)  # BI_RLE8 is deliberately invalid for this player.
    p=a.out/f'{asset:04d}.BMP';p.write_bytes(raw)
    records.append(dict(name=p.name,asset=asset,bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),
                        expected='reject; keep previous display/audio' if rejected else 'valid BMP'))
(a.out/'PC_MANIFEST.json').write_text(json.dumps(dict(case=a.case,count=a.count,files=records,
    note='Copy only BMP files to FAT32 root. File contents do not guarantee physical contiguous/fragmented FAT allocation. 64 is a test-data option, not proof of a 64-image hardware build.'),indent=2),encoding='utf-8')
print(f'Prepared {len(records)} BMP files in {a.out.resolve()}')
