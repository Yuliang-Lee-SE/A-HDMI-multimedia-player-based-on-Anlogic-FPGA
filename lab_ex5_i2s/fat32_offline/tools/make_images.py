"""Deterministic sector fixtures; golden bytes exist BEFORE filesystem allocation.
No RTL algorithm or FAT walk is used to produce expected file content.
Only populated sectors are stored in .sectors; .img can be materialized on demand.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

def p16(b, o, v): struct.pack_into('<H', b, o, v)
def p32(b, o, v): struct.pack_into('<I', b, o, v)

def payload(asset, size):
    return hashlib.shake_256(f'fat32-offline-v1/asset/{asset}'.encode()).digest(size)

class Image:
    def __init__(self, spc=1, mbr=False, active=False):
        self.spc, self.base = spc, 2048 if mbr else 0
        self.fats, self.fsize, self.reserved, self.nclus = 2, 512, 32, 65525
        self.data = self.base + self.reserved + self.fats*self.fsize
        self.total = self.reserved+self.fats*self.fsize+self.nclus*spc
        self.media = self.base+self.total
        self.sectors = {}
        boot = bytearray(512)
        boot[:3] = b'\xeb\x58\x90'; boot[3:11] = b'OFFLINE '
        p16(boot,11,512); boot[13]=spc; p16(boot,14,self.reserved)
        boot[16]=self.fats; boot[21]=0xf8
        p32(boot,28,self.base); p32(boot,32,self.total); p32(boot,36,self.fsize)
        p16(boot,40,0x81 if active else 0); p32(boot,44,2)
        p16(boot,48,1); p16(boot,50,6); boot[66]=0x29
        p32(boot,67,0x12345678); boot[71:82]=b'OFFLINE    '; boot[82:90]=b'FAT32   '
        boot[510:]=b'\x55\xaa'
        self.sectors[self.base]=boot
        self.sectors[self.base+6]=bytearray(boot)
        fsinfo=bytearray(512); p32(fsinfo,0,0x41615252); p32(fsinfo,484,0x61417272)
        p32(fsinfo,488,0xffffffff); p32(fsinfo,492,0xffffffff); p32(fsinfo,508,0xaa550000)
        self.sectors[self.base+1]=fsinfo
        if mbr:
            m=bytearray(512); o=446+16*2  # FAT32 in third primary slot
            m[o+4]=0x0c; p32(m,o+8,self.base); p32(m,o+12,self.total)
            m[510:]=b'\x55\xaa'; self.sectors[0]=m
        self.fat(0,0x0ffffff8); self.fat(1,0xffffffff)
        self.fat(2,0x0fffffff)
        if active:  # first FAT deliberately unusable; active FAT1 must be honored
            self.sectors[self.base+self.reserved]=bytearray(512)
    def fat(self, c, v):
        for copy in range(self.fats):
            lba=self.base+self.reserved+copy*self.fsize+c//128
            b=self.sectors.setdefault(lba,bytearray(512)); p32(b,(c%128)*4,v)
    def cluster(self,c,content):
        content=content.ljust(self.spc*512,b'\xa7')
        for j in range(self.spc):
            self.sectors[self.data+(c-2)*self.spc+j]=bytearray(content[j*512:(j+1)*512])
    def file(self,asset,size,chain,eoc=0x0fffffff):
        content=payload(asset,size)
        for i,c in enumerate(chain):
            self.fat(c,(chain[i+1]|0xa0000000) if i+1<len(chain) else eoc)
            self.cluster(c,content[i*self.spc*512:(i+1)*self.spc*512])
        e=bytearray(32); e[:11]=f'{asset:04d}    BMP'.encode(); e[11]=0x20
        c=chain[0] if chain else 0; p16(e,20,c>>16); p16(e,26,c&65535); p32(e,28,size)
        return e, content
    def save(self,path):
        # Portable compact representation: count + (LBA,512B) records in text hex.
        with path.open('w',encoding='ascii') as f:
            f.write(f'{len(self.sectors):x}\n')
            for lba,data in sorted(self.sectors.items()):
                f.write(f'{lba:08x}\n'); f.write(data.hex(' ')+'\n')

def build(out):
    out.mkdir(parents=True,exist_ok=True)
    cases=[]
    def case(name, spc=1, count=3, mbr=False, active=False, mutation=None,
             mount_error=0, file_error=0, inject=0, eoc=0x0fffffff,
             crossing=False, empty=False, zero=False, no_end=False, target='data'):
        im=Image(spc,mbr,active); entries=[]; gold=[]
        # Deleted, LFN, directory, volume and non-target entries precede target entries.
        deleted=bytearray(32); deleted[0]=0xe5
        lfn=bytearray(32); lfn[0]=0x41; lfn[11]=0x0f
        sub=bytearray(32); sub[:11]=b'0009    BMP'; sub[11]=0x10
        vol=bytearray(sub); vol[11]=8
        other=bytearray(32); other[:11]=b'OTHER   TXT'; other[11]=0x20
        entries=[deleted,lfn,sub,vol,other] if not empty else []
        if empty: count=0
        for i in range(count):
            asset=(i+1)*2-1  # stable IDs with missing numbers, includes >64
            if i==0:
                chain=[127,128,300]; size=spc*512*2+37
            elif i==1:
                chain=[400,401,402]; size=spc*512*2+511
            else:
                chain=[1000+i]; size=1+(i*71)%500
            if zero and i==0: chain=[]; size=0
            e,content=im.file(asset,size,chain,eoc)
            entries.append(e); gold.append((asset,content))
        # Reverse physical order to force sorting. Root chain is noncontiguous.
        prefix=entries[:5] if not empty else []
        targets=entries[5:] if not empty else []
        entries=prefix+list(reversed(targets))
        if crossing:
            padding=spc*16-len(prefix)
            entries=prefix+[deleted]*padding+list(reversed(targets))
        raw=b''.join(entries)
        if no_end:
            raw=raw+bytes(deleted)*((-len(raw)//32) % (spc*16))
        else: raw+=bytes(32)
        roots=[2]+list(range(130,146))
        for j in range((len(raw)+spc*512-1)//(spc*512)):
            im.fat(roots[j],roots[j+1] if (j+1)*spc*512<len(raw) else eoc)
            im.cluster(roots[j],raw[j*spc*512:(j+1)*spc*512])
        if mutation: mutation(im,entries)
        if active:
            for lba in list(im.sectors):
                if im.base+im.reserved<=lba<im.base+im.reserved+im.fsize:
                    im.sectors[lba]=bytearray(512)
        path=out/name; path.mkdir(exist_ok=True); im.save(path/'image.sectors')
        golden=b''.join(x[1] for x in sorted(gold))
        (path/'expected.hex').write_text(golden.hex(' ')+'\n' if golden else '00\n',encoding='ascii')
        target_lba={'data':im.data+(127-2)*spc,'fat':im.base+im.reserved,
                    'fat_next':im.base+im.reserved+1,'root':im.data,'boot':0}[target]
        metadata=[im.media,len(gold),mount_error,file_error,inject,target_lba]
        with (path/'case.txt').open('w',encoding='ascii') as f:
            f.write(' '.join(map(str,metadata))+'\n')
            for asset,content in sorted(gold): f.write(f'{asset} {len(content)}\n')
        cases.append(dict(name=name,spc=spc,files=len(gold),media_sectors=im.media,
                          mount_error=mount_error,file_error=file_error,inject=inject,
                          golden_sha256=hashlib.sha256(golden).hexdigest(),
                          sectors_sha256=hashlib.sha256((path/'image.sectors').read_bytes()).hexdigest()))
    for s in [1,2,4,8,16,32,64]: case(f'spc{s}',spc=s,crossing=True,mbr=s in [2,16,64],active=s==8)
    for n in [16,32,64]: case(f'count{n}',count=n,crossing=True)
    case('empty',empty=True); case('zero',zero=True)
    for v in range(8): case(f'eoc{v}',eoc=0xaffffff8+v,crossing=True,no_end=True)
    case('over_limit',count=65,mount_error=6)
    def bootfield(offset,value,width=4):
        return lambda im,e: (p16 if width==2 else p32)(im.sectors[im.base],offset,value)
    for name,off,value,width,err in [
        ('bps',11,1024,2,1),('fat16',17,512,2,1),('version',42,1,2,1),
        ('root_oob',44,65527,4,2),('total_oob',32,0xffffffff,4,2),
        ('small_fat',36,1,4,2),('fat_too_small_volume',32,5000,4,2),
        ('active_oob',40,0x82,2,1),('reserved_zero',14,0,2,1)]:
        case(name,mutation=bootfield(off,value,width),mount_error=err)
    case('bad_spc',mutation=lambda im,e: im.sectors[0].__setitem__(13,3),mount_error=1)
    case('bad_signature',mutation=lambda im,e: im.sectors[0].__setitem__(510,0),mount_error=1)
    for name,value,err in [('bad_cluster',0x0ffffff7,8),('reserved_cluster',0x0ffffff0,8),
        ('free_cluster',0,8),('oob_cluster',65527,8),('early_eoc',0x0ffffff8,10),('cycle',127,9)]:
        case(name,mutation=lambda im,e,v=value:im.fat(127,v),file_error=err)
    def dirloop(im,e):
        im.cluster(2,bytes([0xe5])+bytes(31))  # fill full directory with deleted items
        for j in range(im.spc):
            im.sectors[im.data+j]=bytearray((bytes([0xe5])+bytes(31))*16)
        im.fat(2,2)
    case('dir_cycle',mutation=dirloop,mount_error=9)
    case('dir_limit',crossing=True,mount_error=6)
    case('chain_limit',count=1,crossing=True,file_error=6)
    def duplicate(im,e):
        buf=im.sectors[im.data]; buf[5*32:6*32]=buf[7*32:8*32]
    case('duplicate',mutation=duplicate,mount_error=7)
    def part(im,slot,kind,start,size):
        b=im.sectors[0]; off=446+16*slot; b[off+4]=kind
        p32(b,off+8,start); p32(b,off+12,size)
    case('mbr_other_primary',mbr=True,mutation=lambda im,e:part(im,0,0x83,1,100))
    case('mbr_last_slot',mbr=True,mutation=lambda im,e:(part(im,2,0,0,0),part(im,3,0x0b,im.base,im.total)))
    case('mbr_overlap',mbr=True,mutation=lambda im,e:part(im,0,0x83,im.base,100),mount_error=2)
    case('mbr_overflow',mbr=True,mutation=lambda im,e:part(im,0,0x83,0xfffffff0,100),mount_error=2)
    case('gpt',mbr=True,mutation=lambda im,e:part(im,0,0xee,1,100),mount_error=1)
    case('extended',mbr=True,mutation=lambda im,e:part(im,0,0x0f,1,100),mount_error=1)
    case('no_fat32',mbr=True,mutation=lambda im,e:part(im,2,0x07,im.base,im.total),mount_error=1)
    for name,inject,me,fe in [('sector_error',1,0,3),('timeout',2,0,4),
          ('short_sector',3,0,5),('long_sector',4,0,5),('late_tag',5,0,0),
          ('backpressure_timeout',6,0,12),('reset_receive',7,0,0),('reset_stream',8,0,0),
          ('mount_read_error',9,3,0),('req_timeout',10,4,0)]:
        case(name,inject=inject,mount_error=me,file_error=fe)
    for name,mode,error in [('partial_error',11,3),('partial_timeout',12,4),('missing_done',13,4)]:
        case(name,inject=mode,file_error=error)
    case('fat_read_error',inject=15,file_error=3,target='fat')
    case('mount_timeout',inject=16,mount_error=4,target='boot')
    case('directory_read_error',inject=17,mount_error=3,target='root')
    case('done_with_last_byte',inject=18)
    case('partial_fat_reopen',inject=19,file_error=3,target='fat_next')
    case('two_cluster_cycle',mutation=lambda im,e:im.fat(128,127),file_error=9)
    (out/'manifest.json').write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8')
    return cases

def materialize(sector_path, img_path, media_sectors):
    words=sector_path.read_text().split(); n=int(words[0],16); at=1
    with img_path.open('wb') as f:
        if __import__('os').name=='nt':
            import ctypes, msvcrt
            returned=ctypes.c_ulong()
            ok=ctypes.windll.kernel32.DeviceIoControl(ctypes.c_void_p(msvcrt.get_osfhandle(f.fileno())),
                0x900c4,None,0,None,0,ctypes.byref(returned),None)
            if not ok: raise OSError('Cannot mark sparse image; refusing large allocation')
        f.truncate(media_sectors*512)
        for _ in range(n):
            lba=int(words[at],16); at+=1
            data=bytes(int(w,16) for w in words[at:at+512]); at+=512
            f.seek(lba*512); f.write(data)

if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('out',type=Path); p.add_argument('--raw',action='store_true')
    a=p.parse_args(); cases=build(a.out)
    if a.raw:
        for c in cases: materialize(a.out/c['name']/'image.sectors',a.out/c['name']/'image.img',c['media_sectors'])
    print(f'Generated {len(cases)} deterministic FAT32 fixtures')
