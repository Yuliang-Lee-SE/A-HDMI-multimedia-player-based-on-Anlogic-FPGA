"""Generate deterministic 16x16 monochrome test captions (Pillow required)."""
import argparse, hashlib, json, struct
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'src/user_source/hdl_source/team/osd_resources.v'
MAX_ITEMS = 32
SLOT_STRIDE = 80
GLYPH_ALPHA_THRESHOLD = 96

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def has_glyph(font_path, char):
    """Check SFNT Unicode cmap directly; do not silently render .notdef."""
    b=font_path.read_bytes()
    u16=lambda p:struct.unpack_from('>H',b,p)[0]
    u32=lambda p:struct.unpack_from('>I',b,p)[0]
    base=u32(12) if b[:4]==b'ttcf' else 0
    cmap=None
    for n in range(u16(base+4)):
        p=base+12+n*16
        if b[p:p+4]==b'cmap':cmap=u32(p+8)
    if cmap is None:raise ValueError('Font has no cmap')
    code=ord(char)
    for n in range(u16(cmap+2)):
        p=cmap+4+n*8
        platform,encoding=u16(p),u16(p+2)
        if platform!=0 and not(platform==3 and encoding in (1,10)):continue
        q=cmap+u32(p+4);fmt=u16(q)
        if fmt==12:
            for j in range(u32(q+12)):
                r=q+16+j*12;first,last,gid=u32(r),u32(r+4),u32(r+8)
                if first<=code<=last and gid+code-first:return True
        elif fmt==4 and code<=65535:
            count=u16(q+6)//2
            for j in range(count):
                end=u16(q+14+2*j);start=u16(q+16+2*count+2*j)
                if start<=code<=end:
                    delta=u16(q+16+4*count+2*j)
                    rp=q+16+6*count+2*j;offset=u16(rp)
                    gid=u16(rp+offset+2*(code-start)) if offset else code
                    if gid and ((gid+delta)&65535):return True
    return False

def generate(config, font_path):
    cfg = json.loads(config.read_text(encoding='utf-8'))
    supplied_items = cfg['items']
    if not 1 <= len(supplied_items) <= MAX_ITEMS:
        raise ValueError('Expected 1..32 items')
    if len({i['id'] for i in supplied_items}) != len(supplied_items) or any(i['id'] not in range(MAX_ITEMS) for i in supplied_items):
        raise ValueError('Duplicate or invalid item ID')
    by_id = {item['id']: item for item in supplied_items}
    items = []
    for item_id in range(MAX_ITEMS):
        item = by_id.get(item_id)
        if item is None:
            item = {
                'id': item_id,
                'title': f'南京博物院展品{item_id + 1:02d}',
                'description': '该展品正式简介与讲解资料待补充。'
            }
        items.append(item)
    for item in items:
        if len(item['title']) > 16 or len(item['description']) > 64:
            raise ValueError('Title/description exceeds 16/64 glyphs')
        if any(ord(c)<32 for c in item['title']+item['description']):
            raise ValueError('Control characters are not supported')
    chars = [' ', '\u25a1'] + sorted(set(''.join(i['title'] + i['description'] for i in items)) - {' ', '\u25a1'})
    if len(chars) > 256:
        raise ValueError('More than 256 glyphs')
    font = ImageFont.truetype(str(font_path), 16)
    # Share one font origin/baseline: punctuation retains its native bearings.
    boxes = [font.getbbox(c) for c in chars if c not in (' ', '\u25a1')]
    cell_top = min(0, min(b[1] for b in boxes))
    cell_bottom = max(16, max(b[3] for b in boxes))
    glyphs = []
    for char in chars:
        im = Image.new('L', (16, 16))
        if char == '\u25a1':
            ImageDraw.Draw(im).rectangle((1, 1, 14, 14), outline=255)
        elif char != ' ':
            if not has_glyph(font_path,char):raise ValueError('Missing glyph: '+repr(char))
            im = Image.new('L', (16, cell_bottom-cell_top))
            ImageDraw.Draw(im).text((0, -cell_top), char, font=font, fill=255)
            if im.height != 16:
                im = im.resize((16,16), Image.Resampling.NEAREST)
            if not im.getbbox():
                raise ValueError('Empty glyph: ' + char)
        glyphs.append([sum((1 << (15-x)) for x in range(16)
                           if im.getpixel((x,y)) >= GLYPH_ALPHA_THRESHOLD)
                       for y in range(16)])
    text_depth = MAX_ITEMS * SLOT_STRIDE
    text_addr_bits = (text_depth - 1).bit_length()
    text = [0] * text_depth
    for item in items:
        for key, offset in [('title',0), ('description',16)]:
            for pos, char in enumerate(item[key]):
                text[item['id']*SLOT_STRIDE+offset+pos] = chars.index(char)
    # Keep the exact glyph count. Power-of-two padding pushes 244 glyphs from
    # seven BRAM blocks to eight and exceeds EG4S20's 9Kb block budget.
    depth = max(2, len(chars))
    lines = ['// Generated; edit captions_test.json and rerun tools/generate_osd_resources.py.',
             f'module osd_resources(input clk, input [{text_addr_bits-1}:0] text_addr, output reg [7:0] text_id,',
             ' input [11:0] glyph_addr, output reg [15:0] glyph_row);',
             f'reg [7:0] text_rom [0:{text_depth-1}];', f'reg [15:0] glyph_rom [0:{depth*16-1}];', 'initial begin']
    lines += [f"text_rom[{i}] = 8'h{v:02x};" for i,v in enumerate(text)]
    flat = [v for g in glyphs for v in g]
    lines += [f"glyph_rom[{i}] = 16'h{v:04x};" for i,v in enumerate(flat)]
    lines += ['end', 'always @(posedge clk) begin', ' text_id <= text_rom[text_addr];', f' glyph_row <= glyph_rom[glyph_addr[{(depth*16-1).bit_length()-1}:0]];', 'end', 'endmodule', '', 'module osd_text_lengths(input [4:0] item_index, output reg [6:0] description_length);', 'always @* begin', ' case(item_index)']
    lines += [f"  5'd{i['id']}: description_length = 7'd{len(i['description'])};" for i in items]
    lines += ["  default: description_length = 7'd0;", ' endcase', 'end', 'endmodule', '']
    OUT.write_text('\n'.join(lines), encoding='utf-8')
    res = ROOT/'osd_assets'
    res.mkdir(exist_ok=True)
    entries=[dict(id=i['id'],title_offset=i['id']*SLOT_STRIDE,title_length=len(i['title']),description_offset=i['id']*SLOT_STRIDE+16,description_length=len(i['description'])) for i in items]
    model = dict(chars=chars, glyphs=glyphs, text=text, items=items, entries=entries,glyph_depth=depth)
    (res/'text_ids.json').write_text(json.dumps(model, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
    for item in items:
        im = Image.new('RGB',(640,480),(48,64,80))
        d = ImageDraw.Draw(im)
        d.rectangle((24,380,615,455),fill='#102040',outline='white',width=2)
        status={'P':['11110','10001','10001','11110','10000','10000','10000'],
                'L':['10000']*6+['11111'],
                'A':['01110','10001','10001','11111','10001','10001','10001'],
                'Y':['10001','01010','00100','00100','00100','00100','00100'],
                '1':['00100','01100','00100','00100','00100','00100','01110'],
                '2':['01110','10001','00001','00010','00100','01000','11111'],
                '3':['11110','00001','00001','01110','00001','00001','11110'],
                '4':['10010','10010','10010','11111','00010','00010','00010']}
        for j,c in enumerate(f"PLAY {item['id']+1}"):
            for y,row in enumerate(status.get(c,['00000']*7)):
                for x,bit in enumerate(row):
                    if bit=='1':d.rectangle((40+j*12+x*2,388+y*2,41+j*12+x*2,389+y*2),fill='yellow')
        for key,y,limit,color in [('title',410,16,(255,255,255)),('description',434,35,(208,224,255))]:
            for j,char in enumerate(item[key][:limit]):
                for r,bits in enumerate(glyphs[chars.index(char)]):
                    for x in range(16):
                        if bits & (1 << (15-x)):
                            im.putpixel((40+j*16+x,y+r),color)
        im.save(res/f"preview_{item['id']+1}.png")
    manifest = dict(status='32-slot caption architecture; formal exhibit copy pending',font_name=font_path.name,font_sha256=sha(font_path),config_sha256=sha(config),generator_sha256=sha(__file__),pillow=__import__('PIL').__version__,glyph_count=len(chars),glyph_rom_bytes=depth*32,text_bytes=text_depth,files={})
    for p in [OUT,res/'text_ids.json',*sorted(res.glob('preview_*.png'))]:
        manifest['files'][str(p.relative_to(ROOT)).replace('\\','/')] = sha(p)
    (res/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'Generated {len(chars)} glyphs; {depth*32} glyph bytes, {text_depth} text bytes')
    return model

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--config',type=Path,default=ROOT/'osd_assets/captions_test.json')
    p.add_argument('--font',type=Path,
                   default=Path('C:/Windows/Fonts/NotoSansSC-Medium.otf'))
    a=p.parse_args()
    generate(a.config,a.font)
