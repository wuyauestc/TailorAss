#!/usr/bin/env python3
"""Offline, pinned CC0 auxiliary-point weights for optional fit replay.
Writes a NEW requested directory only; never changes an existing rig/template.
This is source data and provenance, not a validated body/collision capability.
"""
from pathlib import Path
import argparse,json,hashlib,math,struct,os,tempfile,shutil
COMMIT='a8bc2d54ff0ac92e78ff71431b1023eda42bf482'
WEIGHTS_SHA='0f3641d651ae3d00ad6b4ccee43142edb109d3bd909d27d9e4139ef1beed8625'
RIG_SHA='91e06b16078cb136678580fed690a0a4cd08f8284fca6c721e670aacfd7472ff'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def encode(d):return (json.dumps(d,ensure_ascii=False,separators=(',',':'),allow_nan=False)+'\n').encode()
def same(a,b):return struct.pack('<d',a)==struct.pack('<d',b)
def require(b,m):
 if not b:raise ValueError(m)
def prepare(source_dir,rig_path,template_path):
 source=source_dir/'default_weights.mhw';require(sha(source)==WEIGHTS_SHA,'unapproved CC0 weights bytes')
 require(sha(rig_path)==RIG_SHA,'unapproved original rig bytes')
 raw=json.loads(source.read_bytes());rig=json.loads(rig_path.read_bytes())
 require(raw['license']=='CC0'and rig['sourceCommit']==COMMIT and sha(template_path)==rig['templateResourceSHA256'],'license/template/commit mismatch')
 names=[b['name']for b in rig['bones']];lookup={n:i for i,n in enumerate(names)};table=rig['jointSourceVertexTable'];source_ids=[p['sourceVertexID']for p in table]
 require(len(source_ids)==len(set(source_ids))==1117,'helper source set mismatch')
 by_source={s:[]for s in source_ids};source_pairs=0
 for name,pairs in raw['weights'].items():
  require(name in lookup,'unknown weighted bone');seen=set()
  for offset,(v,w)in enumerate(pairs):
   require(isinstance(v,int)and 0<=v<rig['sourceVertexCount']and v not in seen and math.isfinite(w)and w>=0,'invalid source pair');seen.add(v);source_pairs+=1
   if v in by_source:by_source[v].append((lookup[name],float(w),offset))
 require(source_pairs==57107,'source pair count changed')
 offsets=[0];bones=[];weights=[];normalized=[];pair_offsets=[];sums=[];origins=[];visible=[];matched=0;hidden=0;maximum=0
 w=rig['weights']
 for point in table:
  sid=point['sourceVertexID'];row=sorted(by_source[sid]);require(row and len(row)<=64,'missing/budgeted auxiliary weights');maximum=max(maximum,len(row))
  vi=point['visibleVertexID'];visible.append(vi)
  ids=[b for b,_,_ in row];values=[x for _,x,_ in row];raw_offsets=[x for _,_,x in row]
  if vi is not None:
   a,b=w['vertexOffsets'][vi:vi+2]
   require(ids==w['boneIndices'][a:b]and raw_offsets==w['sourcePairOffsets'][a:b]and all(same(x,y)for x,y in zip(values,w['rawValues'][a:b])),'visible raw/source provenance mismatch')
   # Original visible normalized bits are authoritative; do not silently
   # recompute them with a different Python sum algorithm/version.
   norms=w['normalizedValues'][a:b];total=w['rawVertexSums'][vi];origins.append('pinnedVisibleRig');matched+=1
  else:
   total=0.0
   for x in values:total+=x
   require(total>0,'unweighted helper');norms=[x/total for x in values];origins.append('sequentialAscendingBoneRawNormalization');hidden+=1
  require(all(math.isfinite(x)and x>=0 for x in norms)and abs(math.fsum(norms)-1)<1e-12,'invalid normalized helper weights')
  bones+=ids;weights+=values;normalized+=norms;pair_offsets+=raw_offsets;sums.append(total);offsets.append(len(bones))
 payload={'format':'tailorass-fit-auxiliary-skin-weights-v1','license':'CC0-1.0','sourceCommit':COMMIT,'weightsSourceSHA256':WEIGHTS_SHA,'rigResourceSHA256':RIG_SHA,'templateResourceSHA256':sha(template_path),'sourceVertexCount':rig['sourceVertexCount'],'jointSourceVertexIDs':source_ids,'visibleVertexIDs':visible,'boneNames':names,'vertexOffsets':offsets,'boneIndices':bones,'rawValues':weights,'normalizedValues':normalized,'sourcePairOffsets':pair_offsets,'rawVertexSums':sums,'normalizationOrigins':origins,'scope':'Optional source-bound finite-point fit replay only; not a collision/pose receipt, body fit certificate, or legacy SDF replacement.'}
 stats={'helperPoints':len(source_ids),'visibleOverlapRowsBitwiseOriginal':matched,'hiddenPointsWithCompleteOriginalRawWeights':hidden,'weightPairs':len(bones),'maximumInfluences':maximum,'missingAuxiliaryWeights':0,'sourceRawPairs':source_pairs}
 require(matched==135 and hidden==982,'helper overlap counts changed');return payload,stats

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source-dir',type=Path,required=True);p.add_argument('--rig',type=Path,required=True);p.add_argument('--template',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 require(not a.output.exists(),'refusing overwrite');payload,stats=prepare(a.source_dir,a.rig,a.template);data=encode(payload)
 provenance={'scope':payload['scope'],'license':'CC0-1.0','sourceCommit':COMMIT,'auxiliaryResourceSHA256':hashlib.sha256(data).hexdigest(),'sourceWeightsPath':'makehuman/data/rigs/default_weights.mhw','sourceWeightsSHA256':WEIGHTS_SHA,'rigResourceSHA256':sha(a.rig),'templateResourceSHA256':sha(a.template),'generatorSHA256':sha(Path(__file__)),'statistics':stats}
 a.output.parent.mkdir(parents=True,exist_ok=True);temporary=Path(tempfile.mkdtemp(prefix='.aux-weights-',dir=a.output.parent))
 try:
  (temporary/'auxiliary-weights.json').write_bytes(data);(temporary/'provenance.json').write_bytes(encode(provenance));os.replace(temporary,a.output)
 except BaseException:shutil.rmtree(temporary,ignore_errors=True);raise
 print(json.dumps(provenance,indent=2))
if __name__=='__main__':main()
