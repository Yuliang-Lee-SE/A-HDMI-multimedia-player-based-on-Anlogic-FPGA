"""Independent screen-coordinate goldens plus animated P2 preview."""
import json
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]

def pixel(model,item,offset,x,y):
    color=((x&255)<<16)|((y&255)<<8)|((x^y)&255)
    if 410<=y<426 and 40<=x<296:
        text=model['items'][item]['title'];pos=x-40;row=y-410;ink=0xffffff
    elif 434<=y<450 and 40<=x<600:
        text=model['items'][item]['description'];pos=x-40+offset;row=y-434;ink=0xd0e0ff
    else:return color
    if pos//16<len(text):
        glyph=model['glyphs'][model['chars'].index(text[pos//16])]
        if glyph[row] & (0x8000>>(pos%16)):return ink
    return color

def main():
    m=json.loads((ROOT/'osd_assets/text_ids.json').read_text(encoding='utf-8'))
    width=len(m['items'][0]['description'])*16
    cases=[(0,n) for n in [0,1,15,16,17,width-560,width-1,width,width+16,width+31]]
    cases += [(1,0),(2,15),(3,0),(0,0)]
    dest=ROOT/'osd_sim_inputs';dest.mkdir(exist_ok=True)
    (dest/'scroll_cases.hex').write_text(''.join(f'{(i<<11)|o:04x}\n' for i,o in cases),encoding='ascii')
    for f,(item,offset) in enumerate(cases):
        (dest/f'scroll_{f}.hex').write_text(''.join(f'{pixel(m,item,offset,x,y):06x}\n' for y in range(480) for x in range(640)),encoding='ascii')
    # A compact 2x preview of the actual text window, 2px every 4 frames
    # in the GIF, matching the hardware's mean 1px/2 frames at ~60Hz.
    base=Image.open(ROOT/'osd_assets/preview_1.png').convert('RGB')
    frames=[];durations=[]
    offsets=list(range(0,width+32,2))
    tail=width-560
    if tail not in offsets:offsets.append(tail);offsets.sort()
    for offset in offsets:
        im=base.copy()
        for y in range(434,450):
            for x in range(40,600):
                value=pixel(m,0,offset,x,y)
                im.putpixel((x,y),(208,224,255) if value==0xd0e0ff else (16,32,64))
        frames.append(im.crop((24,380,616,456)).resize((1184,152),Image.Resampling.NEAREST))
        durations.append(750 if offset in (0,tail) else 67)
    frames[0].save(ROOT/'osd_assets/scroll_preview.gif',save_all=True,append_images=frames[1:],duration=durations,loop=0,optimize=True)
    print(f'Prepared {len(cases)} full-frame scroll goldens and animated preview')

if __name__=='__main__':main()
