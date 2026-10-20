"""Independent P3 composition oracle and review previews (Pillow)."""
import json
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[1]
STATUS={
 'P':['11110','10001','10001','11110','10000','10000','10000'],
 'L':['10000']*6+['11111'],
 'A':['01110','10001','10001','11111','10001','10001','10001'],
 'Y':['10001','01010','00100','00100','00100','00100','00100'],
 'U':['10001']*6+['01110'], 'T':['11111']+['00100']*6,
 'O':['01110']+['10001']*5+['01110'],
 '1':['00100','01100','00100','00100','00100','00100','01110'],
 '2':['01110','10001','00001','00010','00100','01000','11111'],
 '3':['11110','00001','00001','01110','00001','00001','11110'],
 '4':['10010','10010','10010','11111','00010','00010','00010']}

def ink_pixels(model,case):
    _,ox,oy,_,_,auto,item,offset=case
    pixels={}
    text=('AUTO' if auto else 'PLAY')+' '+str(item+1)
    for j,c in enumerate(text):
        for row,bits in enumerate(STATUS.get(c,['00000']*7)):
            for col,bit in enumerate(bits):
                if bit=='1':
                    for dy in range(2):
                        for dx in range(2):pixels[(ox+16+j*12+col*2+dx,oy+8+row*2+dy)]=0xffff00
    for key,left,top,width,shift,color in [('title',ox+16,oy+30,256,0,0xffffff),('description',ox+16,oy+54,560,offset,0xd0e0ff)]:
        for j,char in enumerate(model['items'][item][key]):
            for row,bits in enumerate(model['glyphs'][model['chars'].index(char)]):
                for col in range(16):
                    x=left+j*16+col-shift
                    if left<=x<left+width and bits & (0x8000>>col):pixels[(x,top+row)]=color
    return pixels

def frame(model,case):
    show,ox,oy,alpha,shadow,_,_,_=case
    ink=ink_pixels(model,case)
    clip=lambda x,y: ((ox+16<=x<ox+272 and oy+30<=y<oy+46) or
                      (ox+16<=x<ox+576 and oy+54<=y<oy+70) or
                      (ox+16<=x<ox+88 and oy+8<=y<oy+22))
    values=[]
    for y in range(480):
        for x in range(640):
            base=(x%256,y%256,(x^y)%256)
            rgb=(base[0]<<16)|(base[1]<<8)|base[2]
            if show:
                if (x,y) in ink:rgb=ink[(x,y)]
                elif shadow and (x-1,y-1) in ink and clip(x,y):rgb=0
                elif ox<=x<ox+592 and oy<=y<oy+76:
                    if x<ox+2 or x>=ox+590 or y<oy+2 or y>=oy+74:rgb=0xffffff
                    else:
                        c=[((4-alpha)*b+alpha*p)//4 for b,p in zip(base,(16,32,64))]
                        rgb=(c[0]<<16)|(c[1]<<8)|c[2]
            values.append(rgb)
    return values

def main():
    m=json.loads((ROOT/'osd_assets/text_ids.json').read_text(encoding='utf-8'))
    cases=[(1,24,380,3,1,0,0,0),(1,24,380,0,1,1,1,0),
           (1,24,380,1,1,0,2,15),(1,24,380,2,1,1,3,0),
           (1,24,380,4,0,0,0,0),(0,24,380,3,1,0,0,0),
           (1,48,96,3,1,0,0,17),(1,0,404,3,1,1,2,16),
           (1,48,404,4,1,1,3,0)]
    dest=ROOT/'osd_sim_inputs';dest.mkdir(exist_ok=True)
    selections=['case(f)'];preview=None
    for f,c in enumerate(cases):
        show,x,y,a,shadow,auto,item,offset=c
        selections.append(f" {f}:begin cfg_show={show};cfg_x={x};cfg_y={y};cfg_alpha={a};cfg_shadow={shadow};am={auto};item={item};selected_offset={offset};end")
        values=frame(m,c)
        (dest/f'layers_{f}.hex').write_text(''.join(f'{v:06x}\n' for v in values),encoding='ascii')
        if f in (0,4):
            im=Image.new('RGB',(640,480));im.putdata([((v>>16)&255,(v>>8)&255,v&255) for v in values])
            if f==0:preview=im
            else:
                compare=Image.new('RGB',(1280,480));compare.paste(im,(0,0));compare.paste(preview,(640,0))
                ImageDraw.Draw(compare).text((30,350),'P2: opaque panel',fill='white')
                ImageDraw.Draw(compare).text((670,350),'P3: 75% panel + shadow',fill='white')
                compare.save(ROOT/'osd_assets/layers_preview_compare.png')
    selections.append('endcase')
    (dest/'layers_config.vh').write_text('\n'.join(selections)+'\n',encoding='ascii')
    preview.save(ROOT/'osd_assets/layers_preview.png')
    (ROOT/'osd_assets/layers_cases.json').write_text(json.dumps(cases,indent=2)+'\n',encoding='utf-8')
    print('Prepared 9 complete P3 frame goldens and P2/P3 comparison preview')

if __name__=='__main__':main()
