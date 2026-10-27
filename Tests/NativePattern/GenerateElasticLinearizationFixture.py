#!/usr/bin/env python3
"""Archive exact actual mathematical Newton states; no coordinate synthesis."""
from pathlib import Path
import argparse,hashlib,json,shutil
p=argparse.ArgumentParser();p.add_argument('--output-dir',type=Path);p.add_argument('--r237',type=Path);p.add_argument('--verify-dir',type=Path);a=p.parse_args();here=Path(__file__).resolve().parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
if a.verify_dir:
 r=a.verify_dir;m=json.loads((r/'manifest.json').read_text());assert m['generatorSHA256']==sha(Path(__file__))
 for f,s in m['files'].items():assert sha(r/f)==s,f
 source=here/'Fixtures/3d-hinge/native-source-topology.json';assert sha(source)==m['sourceTopologyFixtureSHA256']
 assert json.loads(source.read_text())['sourceSHA256']==m['canonicalFullPaperSHA256']
 print(json.dumps({'passed':True,'statesUnmodified':True,'canonicalSource':m['canonicalFullPaperSHA256']}));raise SystemExit(0)
assert a.output_dir and a.r237,'--output-dir and explicit actual --r237 required'
r=a.output_dir;r.mkdir(parents=True,exist_ok=True);r236=here/'Fixtures/3d-joint-body-r237/accepted-r236.json';source=here/'Fixtures/3d-hinge/native-source-topology.json';s=json.loads(source.read_text());assert s['sourceSHA256']=='28eb56b2ec46feddde570c300896cd6422045e6d119d0a2af11f667ae7604a35'
for file,name in [(r236,'actual-r236.json'),(a.r237,'mathematical-r237.json')]:
 d=json.loads(file.read_text());assert len(d['positions'])==len(s['referencePositions'])==2000;shutil.copyfile(file,r/name)
m={'scope':'Actual fixed mathematical states only; r237 is NOT physical acceptance; no new physics or changed source/material',
 'canonicalFullPaperSHA256':s['sourceSHA256'],'sourceTopologyFixtureSHA256':sha(source),'generatorSHA256':sha(Path(__file__)),
 'files':{f:sha(r/f) for f in ['actual-r236.json','mathematical-r237.json']},'vertices':2000,'triangles':3472,'hinges':4948,
 'experimentalNonzeroBendingUsedOnlyForDerivativeControls':0.0002,'actualR237NewtonBending':0}
(r/'manifest.json').write_text(json.dumps(m,indent=2)+'\n');print('Archived original state bytes',m['files'])
