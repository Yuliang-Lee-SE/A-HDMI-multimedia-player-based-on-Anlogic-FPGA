"""PC extraction from actual FAT chains, independent of fixture placement."""
import hashlib,json,re,struct,sys
from pathlib import Path
def audit(root):
 results=[]
 for folder in sorted(Path(root).glob('spc*_n*')):
  manifest=json.loads((folder/'info.json').read_text());files={}
  with (folder/'image.img').open('rb') as image:
   def sec(lba):image.seek(lba*512);b=image.read(512);assert len(b)==512;return b
   def u16(b,p):return struct.unpack_from('<H',b,p)[0]
   def u32(b,p):return struct.unpack_from('<I',b,p)[0]
   boot=sec(0);base=0
   if boot[0] not in (0xeb,0xe9):
    for p in range(446,510,16):
     if boot[p+4] in (0xb,0xc):base=u32(boot,p+8);break
    assert base;boot=sec(base)
   spc=boot[13];fat=base+u16(boot,14);data=fat+boot[16]*u32(boot,36)
   def chain(c):
    seen=set()
    while c<0xffffff8:
     assert c>=2 and c not in seen;seen.add(c);yield c
     c=u32(sec(fat+c//128),(c%128)*4)&0xfffffff
   def cluster(c):return b''.join(sec(data+(c-2)*spc+s) for s in range(spc))
   ended=False;fragmented=0
   for c in chain(u32(boot,44)):
    block=cluster(c)
    for p in range(0,len(block),32):
     e=block[p:p+32]
     if e[0]==0:ended=True;break
     if e[0]==0xe5 or e[11]&0x18 or not re.fullmatch(rb'\d{4}    BMP',e[:11]):continue
     asset=int(e[:4]);length=u32(e,28);contents=bytearray();prev=None;noncontiguous=False
     for fc in chain((u16(e,20)<<16)|u16(e,26)):
      if prev is not None and fc!=prev+1:noncontiguous=True
      prev=fc;contents+=cluster(fc)
      if len(contents)>=length:break
     contents=bytes(contents[:length]);expected=(folder/f'{asset:04d}.bmp').read_bytes()
     assert contents==expected and len(contents)==921654
     assert contents[:2]==b'BM' and struct.unpack_from('<iiHHI',contents,18)==(640,480,1,24,0)
     files[asset]=hashlib.sha256(contents).hexdigest();fragmented+=noncontiguous
    if ended:break
   assert sorted(files)==manifest['ids']
   assert {str(a).zfill(4):h for a,h in files.items()}==manifest['bmp_sha256']
   results.append(dict(case=folder.name,files=len(files),bytes=len(files)*921654,fragmented_files=fragmented,
    contiguous_files=len(files)-fragmented,sha256=files))
 return results
if __name__=='__main__':
 result=audit(sys.argv[1]);Path(sys.argv[2]).write_text(json.dumps(result,indent=2),encoding='utf-8')
 print('BMP_IMAGE_AUDIT_PASS',[(r['case'],r['files'],r['fragmented_files']) for r in result])
