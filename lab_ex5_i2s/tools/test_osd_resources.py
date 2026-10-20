import copy, importlib.util, json, tempfile
from pathlib import Path

p=Path(__file__).with_name('generate_osd_resources.py')
s=importlib.util.spec_from_file_location('osdgen',p);g=importlib.util.module_from_spec(s);s.loader.exec_module(g)
root=g.ROOT
font=Path('C:/Windows/Fonts/simhei.ttf')
config=json.loads((root/'osd_assets/captions_test.json').read_text(encoding='utf-8'))
(root/'osd_sim_inputs').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='osd_resources_',dir=root/'osd_sim_inputs') as temp:
    g.ROOT=Path(temp);g.OUT=g.ROOT/'resources.v'
    c=g.ROOT/'captions.json'
    def run(cfg):
        c.write_text(json.dumps(cfg,ensure_ascii=False),encoding='utf-8');return g.generate(c,font)
    m=run(config);first=g.OUT.read_bytes();run(config);assert first==g.OUT.read_bytes()
    assert m['glyphs'][0]==[0]*16
    assert m['glyphs'][1][1]==0x7ffe and m['glyphs'][1][14]==0x7ffe
    assert g.OUT.read_bytes()==(root/'src/user_source/hdl_source/team/osd_resources.v').read_bytes()
    edge=copy.deepcopy(config);edge['items'][0]['title']='测'*16;edge['items'][0]['description']='试'*64
    run(edge)
    edge['items'][0]['title']='';edge['items'][0]['description']='';run(edge)
    for key,value in [('title','测'*17),('description','试'*65),('title','\U0010ffff'),('title','\n')]:
        bad=copy.deepcopy(config);bad['items'][0][key]=value
        try:run(bad)
        except ValueError:pass
        else:raise AssertionError('Invalid resource accepted: '+key)
    for bad in [dict(items=[]),dict(items=[config['items'][0]]*2),dict(items=[dict(id=4,title='',description='')])]:
        try:run(bad)
        except ValueError:pass
        else:raise AssertionError('Invalid IDs accepted')
print('OSD RESOURCE TESTS PASS: deterministic ROM, space/fallback, 16/64 limits, empty, missing glyph, control/duplicate/out-of-range rejection')
