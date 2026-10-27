#!/usr/bin/env python3
"""Archive original full IPC self-builder goldens; daily tests require no TBB.
The separately built full reference is original v1.6.1, not the serial port.
"""
from pathlib import Path
import hashlib,json,argparse
p=argparse.ArgumentParser();p.add_argument('--research-dir',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();r=a.research_dir;out=a.output;out.mkdir(parents=True,exist_ok=True)
def read(f):return json.loads((r/f).read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def convert(c):
 assert c['n_cloth']==len(c['vertices'])==len(c['rest'])
 return dict(name=c['name'],rest=c['rest'],current=c['vertices'],triangles=sum(c['faces'],[]),kappa=c['kappa'],dmin=c['dmin'],h=c['h'])
def golden(c):
 assert c['n_cloth']==c['n_vertices']
 return dict(name=c['name'],energy=c['energy'],gradient=c['gradient'],hessian=c['hessian'],hessianPSD=c['hessian_psd'],stencilCount=len(c['stencils']),negativeStencilCount=sum(s['weight']<0 for s in c['stencils']),referenceVertexAreas=c['vertex_areas'],referenceEdgeAreas=c['edge_areas'])
files={'cloth-cases.json':{'cases':list(map(convert,read('cases.json')))},
 'canonical-goldens.json':{'metadata':{k:v for k,v in read('official-canonical-goldens.json').items() if k!='cases'},'cases':list(map(golden,read('official-canonical-goldens.json')['cases']))},
 'generic-fd-cases.json':{'cases':list(map(convert,read('generic-cases.json'))),'originalFiniteDifferenceProof':read('official-fullmoving-fd.json')}}
for prefix,casefile,goldenfile in [('shirt','shirt-case.json','official-shirt-golden.json'),('clear','actual-case.json','official-actual-golden.json'),('r237','r237-case.json','official-r237-golden.json')]:
 files[prefix+'-case.json']=convert(read(casefile));files[prefix+'-golden.json']={'case':golden(read(goldenfile)['cases'][0])}
for name,value in files.items():(out/name).write_text(json.dumps(value,separators=(',',':'))+'\n')
refs=['cases.json','official-canonical-goldens.json','official-broadphase-goldens.json','SelfReference.cpp','build-reference.py','IPCClothContactBuilder.cpp','IPCClothContactBuilder.h','reference-build-manifest.json','serial-full-builder-comparison.json','shirt-case.json','official-shirt-golden.json','shirt-serial-comparison.json','actual-case.json','official-actual-golden.json','actual-serial-comparison.json','official-fullmoving-fd.json','domains-and-rigid.json','r237-case.json','official-r237-golden.json','r237-global-minimum.json']
manifest={'scope':'All-moving triangle self potential; original full IPC builder independent canonical sparse E/G/raw H/whole-signed-local PSD H goldens; no reference recomputed by the portable port',
 'ipcCommit':'19bcab7e1f5a0d2addfcd28513422ff248ea504e','ipcTag':'v1.6.1','canonicalCandidateOrderingRequired':True,
 'primitiveAdjacencyOnly':True,'sewnDistinctIDsNeverExcluded':True,'fullOfficialControlCount':20,
 'referenceEvidenceSHA256':{f:sha(r/f) for f in refs},'files':{f:sha(out/f) for f in files},'generatorSHA256':sha(Path(__file__)),'fullReferenceSourceSHA256':sha(Path(__file__).resolve().parent.parent/'Tests/Oracles/IPCClothFullReference.cpp'),'fullSourceManifestSHA256':sha(Path(__file__).resolve().parent.parent/'Tests/Oracles/IPCFullSourceManifest.json'),
 'actualShirtSourceSHA256':read('shirt-case.json')['sourceSHA256'],'actualShirtVertices':1732,'actualShirtTriangles':2710,'actualShirtStencils':391,
 'r237IsStaticMathematicalStateNotPhysicalAcceptance':True,'noTBBLibiglRuntime':True}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print('archived',len(files),'files',sum((out/f).stat().st_size for f in files),'bytes')
