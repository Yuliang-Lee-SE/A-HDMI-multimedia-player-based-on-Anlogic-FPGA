"""Standard BMP originals are generated before independent FAT allocation."""
import hashlib,json,struct,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'fat32_offline/tools'))
from make_images import Image,p16,p32,materialize

def bmp(asset):
 pixels=bytearray()
 for y in range(480):
  for x in range(640):pixels.extend(((x+asset)&255,(y*3+asset)&255,(x^y^asset)&255))
 return struct.pack('<2sIHHI',b'BM',len(pixels)+54,0,0,54)+struct.pack('<IiiHHIIiiII',40,640,480,1,24,0,len(pixels),2835,2835,0,0)+pixels

def build(out):
 out.mkdir(parents=True,exist_ok=False);manifest=[]
 for spc,count in [(1,32),(8,64),(64,16)]:
  path=out/f'spc{spc}_n{count}';path.mkdir();im=Image(spc=spc,mbr=spc==8)
  entries=[];next_cluster=128
  ids=list(range(1,count))+[9999]
  for asset in ids:
   raw=bmp(asset);(path/f'{asset:04d}.bmp').write_bytes(raw)
   n=(len(raw)+spc*512-1)//(spc*512)
   chain=list(range(next_cluster,next_cluster+n));next_cluster+=n
   if asset%2:chain=chain[::2]+chain[1::2] # forced non-adjacent links
   for i,c in enumerate(chain):
    im.fat(c,chain[i+1] if i+1<n else 0x0fffffff)
    im.cluster(c,raw[i*spc*512:(i+1)*spc*512])
   e=bytearray(32);e[:11]=f'{asset:04d}    BMP'.encode();e[11]=32
   p16(e,20,chain[0]>>16);p16(e,26,chain[0]&65535);p32(e,28,len(raw));entries.append(e)
  directory=b''.join(reversed(entries))+bytes(32)
  roots=[2,3,4,5,6]
  for j in range((len(directory)+spc*512-1)//(spc*512)):
   im.fat(roots[j],roots[j+1] if (j+1)*spc*512<len(directory) else 0x0fffffff)
   im.cluster(roots[j],directory[j*spc*512:(j+1)*spc*512])
  im.save(path/'image.sectors');materialize(path/'image.sectors',path/'image.img',im.media)
  digest=hashlib.sha256()
  with (path/'image.img').open('rb') as stream:
   while chunk:=stream.read(1024*1024):digest.update(chunk)
  info=dict(spc=spc,count=count,media=im.media,ids=ids,sha256=digest.hexdigest(),
    bmp_sha256={f'{a:04d}':hashlib.sha256((path/f'{a:04d}.bmp').read_bytes()).hexdigest() for a in ids})
  (path/'info.json').write_text(json.dumps(info,indent=2),encoding='utf-8');manifest.append(info)
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
 return out
if __name__=='__main__':build(Path(sys.argv[1]))
