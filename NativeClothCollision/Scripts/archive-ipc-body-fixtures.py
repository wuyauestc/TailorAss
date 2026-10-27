#!/usr/bin/env python3
"""Archive checked original full-builder outputs; normal tests use no TBB/libigl.
--research-dir must contain the frozen source/golden evidence from HANDOFF.
"""
from pathlib import Path
import hashlib,json,argparse
p=argparse.ArgumentParser();p.add_argument('--research-dir',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();r=a.research_dir;out=a.output;out.mkdir(parents=True,exist_ok=True)
def read(f):return json.loads((r/f).read_text())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def convert(c):
 nc=c['n_cloth'];rest=c['rest'];current=c['vertices'];assert current[nc:]==rest[nc:]
 cf=[];bf=[]
 for f in c['faces']:
  if f[0]<nc:assert all(v<nc for v in f);cf+=f
  else:assert all(v>=nc for v in f);bf += [v-nc for v in f]
 return {'name':c['name'],'clothRest':rest[:nc],'clothCurrent':current[:nc],'bodyPositions':rest[nc:],'clothTriangles':cf,'bodyTriangles':bf,'kappa':c['kappa'],'dmin':c['dmin'],'h':c['h']}
def golden(c):
 n=c['n_cloth']*3
 return {'name':c['name'],'energy':c['energy'],'clothGradient':c['gradient'][:n],
  'clothHessian':[[int(i),int(j),v] for i,j,v in c['hessian'] if i<n and j<n],
  'clothHessianPSD':[[int(i),int(j),v] for i,j,v in c['hessian_psd'] if i<n and j<n],
  'stencilCount':len(c['stencils']),'negativeStencilCount':sum(s['weight']<0 for s in c['stencils']),
  'fullVertexCount':c['n_vertices'],'referenceVertexAreas':c['vertex_areas'],'referenceEdgeAreas':c['edge_areas']}
files={'body-cases.json':{'cases':list(map(convert,read('cases.json')))},
 'canonical-goldens.json':{'metadata':{k:v for k,v in read('official-canonical-goldens.json').items() if k!='cases'},'cases':list(map(golden,read('official-canonical-goldens.json')['cases']))},
 'actual-case.json':convert(read('actual-case.json')),
 'actual-golden.json':{'metadata':{k:v for k,v in read('official-actual-golden.json').items() if k!='cases'},'case':golden(read('official-actual-golden.json')['cases'][0])},
 'generic-fd-cases.json':{'cases':list(map(convert,read('generic-cases.json'))),'originalFiniteDifferenceProof':read('official-generic-fd.json')}}
for name,value in files.items():(out/name).write_text(json.dumps(value,separators=(',',':'))+'\n')
refs=['cases.json','official-canonical-goldens.json','actual-case.json','official-actual-golden.json','generic-cases.json','official-generic-fd.json','cpp-builder-official-comparison.json','actual-cpp-official-comparison.json','official-source-manifest.json','HANDOFF.txt']
manifest={'scope':'Immutable original IPC Toolkit full-builder canonical outputs, restricted to cloth DOFs AFTER original whole-local PSD; no reference rebuilt by the portable production code',
 'ipcTag':'v1.6.1','ipcCommit':'19bcab7e1f5a0d2addfcd28513422ff248ea504e','canonicalCandidateOrderingRequired':True,
 'originalReferenceSourceFiles':{f:sha(r/f) for f in refs},'files':{f:sha(out/f) for f in files},'generatorSHA256':sha(Path(__file__)),
 'noTBBOrLibiglTestRuntimeDependency':True,'actual469RemainsRejectedCloth':True,'rawAndWholeLocalProjectedHessian':True,'officialFullBuilderCaseCount':18,'actualFullSourceStencilCount':863}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print('archived',len(files),'bytes',sum((out/f).stat().st_size for f in files))
