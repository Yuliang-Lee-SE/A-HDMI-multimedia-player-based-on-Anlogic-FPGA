"""Decode mapped EG_PHY_BRAM INIT data from TD report_property output."""
import hashlib,json,re
from pathlib import Path
root=Path(__file__).resolve().parent
log=(root/'osd_rom_audit.log').read_text(errors='replace')
model=json.loads((root/'osd_assets/text_ids.json').read_text(encoding='utf-8'))
chunks=re.split(r'start command "report_property ([^"]+)"',log)
cells={chunks[i]:chunks[i+1] for i in range(1,len(chunks),2) if 'resources/' in chunks[i] and 'REF_NAME' in chunks[i+1] and 'EG_PHY_BRAM' in chunks[i+1]}
assert len(cells)==5
def words(cell,width,count):
    attrs=cells['u_osd_layers/resources/'+cell]
    init=dict((int(n,16),int(v,16)) for n,v in re.findall(r"\bINIT_([0-9A-Fa-f]{2}) = =256'h([0-9A-Fa-f]+)",attrs))
    assert len(init)==32
    data=sum(v<<(256*n) for n,v in init.items())
    return [(data>>(width*i))&((1<<width)-1) for i in range(count)]
text_cell=next(full.rsplit('/',1)[1] for full in cells if '/ramread0_' in full)
text=words(text_cell,8,512)
assert text==model['text'], f'Text init mismatch at {next(i for i,(a,b) in enumerate(zip(text,model["text"])) if a!=b)}'
expected=[v for glyph in model['glyphs'] for v in glyph]+[0]*((model['glyph_depth']-len(model['chars']))*16)
# Read the actual nibble placement from mapped Verilog .doa wiring.
netlist=(root/'osd_gate_audit.v').read_text(errors='replace')
mapped=[0]*len(expected)
for full in cells:
    if '/ramread1_' not in full:continue
    cell=full.rsplit('/',1)[1]
    start=netlist.index('\\'+full+' ')
    block=netlist[start:netlist.index(');',start)]
    hi,shift=map(int,re.search(r'glyph \[(\d+):(\d+)\]',block).groups())
    assert hi-shift==3
    for i,v in enumerate(words(cell,4,len(expected))):mapped[i]|=v<<shift
assert mapped==expected, f'Glyph init mismatch at {next(i for i,(a,b) in enumerate(zip(mapped,expected)) if a!=b)}'
shadow_cells=[chunks[i] for i in range(1,len(chunks),2) if 'resources/' not in chunks[i] and 'REF_NAME' in chunks[i+1] and 'EG_PHY_BRAM' in chunks[i+1]]
assert len(shadow_cells)==1, shadow_cells
# Check the actual mapped row-bank separation, not just the RTL intention.
shadow_start=netlist.index('\\'+shadow_cells[0]+' ')
shadow_block=netlist[shadow_start:netlist.index(');',shadow_start)]
assert ".addra({2'b00,\\u_osd_layers/y2 [0],\\u_osd_layers/x2 })" in shadow_block
assert ".addrb({2'b00,\\u_osd_layers/mask_read_addr [10],\\u_osd_layers/x2 })" in shadow_block
inv=netlist.index('\\u_osd_layers/mask_read_addr[10]_syn_1 ')
inv_block=netlist[netlist.rfind('AL_MAP_LUT1 #(',0,inv):netlist.index(');',inv)]
assert ".INIT(2'h1)" in inv_block and '.a(\\u_osd_layers/y2 [0])' in inv_block
assert '.o(\\u_osd_layers/mask_read_addr [10])' in inv_block
result=dict(shadow_address_banks_inverted=True,shadow_bram_cells=shadow_cells,status='PASS',text_entries=512,glyph_rows=len(expected),bram_cells=list(cells),source_sha256=hashlib.sha256((root/'src/user_source/hdl_source/team/osd_resources.v').read_bytes()).hexdigest(),audit_sha256=hashlib.sha256((root/'osd_rom_audit.log').read_bytes()).hexdigest(),note='Mapped gate database ROM INIT words match generated text/glyph data; frontend HDL-5314 does not imply lost ROM initialization in this build')
result['gate_db_sha256']=hashlib.sha256((root/'src/td_project/osd_layers_20261013_final_Runs/syn_1/HDMI1.4b_Transmitter_v1.0_gate.db').read_bytes()).hexdigest()
result['mapped_netlist_sha256']=hashlib.sha256((root/'osd_gate_audit.v').read_bytes()).hexdigest()
(root/'osd_bram_init_check.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,indent=2))
