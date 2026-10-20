"""Independent pixel golden frames and reviewed project source-list update."""
import argparse,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def update_project():
    paths=[ROOT/'src/td_project/HDMI1.4b_Transmitter_v1.0.al']+[ROOT/f'build_flow_templates/{s}/HDMI1.4b_Transmitter_v1.0.prj' for s in ['syn_1','phy_1']]
    for path in paths:
        t=path.read_text(encoding='utf-8')
        if 'team/osd_resources.v' in t:
            continue
        prefix='../' if path.suffix=='.al' else '../../../'
        nodes=[]
        for j,name in enumerate(['osd_resources','osd_text_renderer','osd_display_commit']):
            nodes.append(f'''            <File Path="{prefix}user_source/hdl_source/team/{name}.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{80+j}"/>
                </FileInfo>
            </File>
''')
        t=t.replace('        </Verilog>',''.join(nodes)+'        </Verilog>')
        path.write_text(t,encoding='utf-8')

def goldens():
    m=json.loads((ROOT/'osd_assets/text_ids.json').read_text(encoding='utf-8'))
    dest=ROOT/'osd_sim_inputs'
    dest.mkdir(exist_ok=True)
    for item in range(7):
        data=[]
        for y in range(480):
            for x in range(640):
                rgb=((x&255)<<16)|((y&255)<<8)|((x^y)&255)
                if item<4 or item==5:
                    kind = 'title' if 410<=y<426 else 'description' if 434<=y<450 else None
                    if kind and 40<=x<(296 if kind=='title' else 600):
                        idx=(x-40)//16
                        text=m['items'][item][kind] if item<4 else m['chars'][-1]*(16 if kind=='title' else 64)
                        if idx<len(text):
                            glyph=m['glyphs'][m['chars'].index(text[idx])]
                            if glyph[y-(410 if kind=='title' else 434)] & (0x8000>>((x-40)%16)):
                                rgb=0xffffff if kind=='title' else 0xd0e0ff
                data.append(f'{rgb:06x}\n')
        (dest/f'golden_{item}.hex').write_text(''.join(data),encoding='ascii')
    (dest/'glyph_rows.hex').write_text(''.join(f'{v:04x}\n' for g in m['glyphs'] for v in g)+('0000\n'*((m['glyph_depth']-len(m['chars']))*16)),encoding='ascii')
    (dest/'text_rom.hex').write_text(''.join(f'{v:02x}\n' for v in m['text']),encoding='ascii')
    (dest/'config.vh').write_text(f"`define OSD_LAST_GLYPH {len(m['chars'])-1}\n`define OSD_GLYPH_ROWS {m['glyph_depth']*16}\n",encoding='ascii')
    print('Prepared 7 full-frame RGB goldens and exhaustive ROM goldens')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--update-project',action='store_true')
    if parser.parse_args().update_project:update_project()
    goldens()
