#!/usr/bin/env python3
"""Offline validation of optional CC0 rig data; never modifies body assets."""
import argparse,hashlib,json,math,sys
from pathlib import Path
from PrepareBodyRig import COMMIT,PINS,prepare,sha,encode,geometry_sha,require

def validate(bundle,body_path,sources=None):
 rig_bytes=(bundle/'rig.json').read_bytes();r=json.loads(rig_bytes);p=json.loads((bundle/'provenance.json').read_bytes());body_bytes=body_path.read_bytes();body=json.loads(body_bytes)
 require(r['format']=='tailorass-optional-body-rig-v1' and r['sourceCommit']==COMMIT,'Wrong rig format/source')
 require(not r['runtimeEnabled'] and not r['fitterImplemented'] and not r['surfaceMeasurementContractImplemented'],'Data must not claim implemented fitting/posing')
 require(p['rigResourceSHA256']==sha(rig_bytes) and p['templateResourceSHA256']==sha(body_bytes)==r['templateResourceSHA256'],'Unbound rig/template resource')
 require(sha((bundle/'LICENSE.CC0.txt').read_bytes())==PINS['LICENSE.ASSETS.md'][1],'License changed')
 require(geometry_sha(body['positions'],body['triangleIndices'])==r['templateGeometrySHA256']==p['templateGeometrySHA256'],'Wrong visible mesh')
 nv=r['templateVertexCount'];ns=r['sourceVertexCount'];require(nv==13380 and ns==19158,'Unexpected topology')
 visible=r['visibleToSource'];inverse=r['sourceToVisible'];require(len(visible)==nv and len(set(visible))==nv and len(inverse)==ns,'Wrong source remap')
 require(all(0<=i<ns and inverse[i]==j for j,i in enumerate(visible)) and sum(x>=0 for x in inverse)==nv,'Remap not bijective on visible set')
 bones=r['bones'];joints=r['joints'];order=r['boneEvaluationOrder'];require(len(bones)==163 and len(joints)==326 and sorted(order)==list(range(len(bones))),'Wrong rig dimensions/order')
 done=set()
 for i in order:
  b=bones[i];require(b['parent'] is None or b['parent'] in done,'Bone DAG order broken');done.add(i)
  require(0<=b['head']<len(joints) and 0<=b['tail']<len(joints) and all(0<=j<len(joints) for j in b['rotationPlaneJointIndices']),'Unresolved bone anchors')
 table=r['jointSourceVertexTable'];lookup={v['sourceVertexID']:v for v in table};require(len(table)==len(lookup)==1117,'Joint source table mismatch')
 for j in joints:
  require(j['sourceVertexIDs'] and all(0<=i<ns and i in lookup for i in j['sourceVertexIDs']),'Untraceable joint')
  require([table[i]['sourceVertexID'] for i in j['sourceVertexTableIndices']]==j['sourceVertexIDs'],'Joint source table indirection')
  mean=[sum(lookup[i]['templatePositionMeters'][a] for i in j['sourceVertexIDs'])/len(j['sourceVertexIDs']) for a in range(3)]
  require(mean==j['templatePositionMeters'],'Joint mean not from individually transformed source vertices')
  require(all(math.isfinite(x) for x in mean),'Nonfinite joint')
 for v in table:
  i=v['sourceVertexID'];target=inverse[i]
  require(v['visibleVertexID']==(target if target>=0 else None),'Helper/visible mapping mismatch')
  if target>=0:require(v['templatePositionMeters']==body['positions'][target],'Visible joint source coordinates changed')
 w=r['weights'];starts=w['vertexOffsets'];n=len(w['boneIndices']);require(len(starts)==nv+1 and starts[0]==0 and starts[-1]==n and n==40156,'Incomplete visible weights')
 require(all(len(w[key])==n for key in ['rawValues','normalizedValues','sourcePairOffsets']) and len(w['rawVertexSums'])==nv,'Invalid CSR arrays')
 max_error=0;identity_error=0
 for i in range(nv):
  a,b=starts[i:i+2];require(0<=a<b<=n and b-a<=64,'Vertex weight range/coverage')
  ids=w['boneIndices'][a:b];raw=w['rawValues'][a:b];values=w['normalizedValues'][a:b];total=sum(raw)
  require(len(set(ids))==len(ids) and all(0<=x<len(bones) for x in ids),'Duplicate/unknown influence')
  require(all(math.isfinite(x) and x>=0 for x in raw+values) and total>0 and total==w['rawVertexSums'][i],'Invalid original weights')
  require(values==[x/total for x in raw],'Normalized weights do not retain original proportions')
  error=abs(sum(values)-1);max_error=max(max_error,error);require(error<1e-12,'Weights not normalized')
  for x in body['positions'][i]:identity_error=max(identity_error,abs(sum(x*v for v in values)-x))
 regenerated=False
 if sources:
  expected,asset_records,stats,license_data=prepare(sources,body_path)
  require(encode(expected)==rig_bytes and asset_records==p['assets'] and license_data==(bundle/'LICENSE.CC0.txt').read_bytes(),'Pinned regeneration mismatch')
  regenerated=True
 lengths=[]
 for b in bones:lengths.append(math.dist(joints[b['head']]['templatePositionMeters'],joints[b['tail']]['templatePositionMeters']))
 plane_areas=[]
 for b in bones:
  a,c,d=[joints[i]['templatePositionMeters'] for i in b['rotationPlaneJointIndices']];u=[c[i]-a[i] for i in range(3)];v=[d[i]-a[i] for i in range(3)]
  cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];plane_areas.append(sum(x*x for x in cross))
 by_name={b['name']:b for b in bones}
 require(joints[by_name['upperarm01.L']['head']]['templatePositionMeters'][0]>0 and joints[by_name['upperarm01.R']['head']]['templatePositionMeters'][0]<0,'Anatomical side convention changed')
 return {'passed':True,'visibleVertices':nv,'visibleWeightPairs':n,'bones':len(bones),'joints':len(joints),'allCurrentVerticesWeighted':True,
  'allOriginalVisiblePairsKept':True,'maximumNormalizedSumError':max_error,'identityBlendNumericalErrorMeters':identity_error,
  'identityBlendIsNotClaimedBitwiseIdentityPose':True,'minimumBoneProxyLengthMeters':min(lengths),'sourceRegenerationByteExact':regenerated,
  'minimumDeclaredRollPlaneCrossSquaredMeters4':min(plane_areas),'exactlyDegenerateDeclaredRollPlanes':sum(x==0 for x in plane_areas),
  'bodyResourceUnchanged':sha(body_path.read_bytes())==sha(body_bytes),'bodyGeometrySHA256':r['templateGeometrySHA256'],
  'scope':'Optional data only; no body fitting/posing runtime or anthropometric truth claim'}
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--bundle',type=Path,required=True);p.add_argument('--body-resource',type=Path,required=True);p.add_argument('--source-dir',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
 result=validate(a.bundle,a.body_resource,a.source_dir)
 data=json.dumps(result,indent=2)+'\n'
 if a.output:a.output.write_text(data)
 print(data,end='')
if __name__=='__main__':main()
