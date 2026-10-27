#!/usr/bin/env python3
"""Prepare optional CC0 skeleton data. Does not fit, pose or replace the body.

Only pinned OBJ/rig/weight ASSETS are read. No MakeHuman application, ruler
plugin, measurement paths, or skinning implementation is imported.
"""
import argparse,hashlib,json,math,os,shutil,struct,tempfile
from pathlib import Path

COMMIT='a8bc2d54ff0ac92e78ff71431b1023eda42bf482'
PINS={
 'base.obj':('makehuman/data/3dobjs/base.obj','8e761e6624b8f54536409135d1636da63b32486a90d4897f84e121d144f6fb4c'),
 'default.mhskel':('makehuman/data/rigs/default.mhskel','7131071b0c48c07d03a80a58aaefb4e0a2f9f5aaecddc536742d1ddb91754a4d'),
 'default_weights.mhw':('makehuman/data/rigs/default_weights.mhw','0f3641d651ae3d00ad6b4ccee43142edb109d3bd909d27d9e4139ef1beed8625'),
 'LICENSE.ASSETS.md':('LICENSE.ASSETS.md','f6089cba01cb570a24712b41ab8a586ccd3cc5ef53dc266ca50b95c288956d2c')}

def sha(data):return hashlib.sha256(data).hexdigest()
def encode(value):return (json.dumps(value,separators=(',',':'),ensure_ascii=False,allow_nan=False)+'\n').encode()
def require(condition,message):
 if not condition:raise ValueError(message)
def geometry_sha(positions,indices):
 h=hashlib.sha256(b'rigid-clearance-visible-body-v1\0');h.update(struct.pack('<QQ',len(positions),len(indices)))
 for p in positions:h.update(struct.pack('<ddd',*p))
 for i in indices:h.update(struct.pack('<I',i))
 return h.hexdigest()
def load_assets(directory):
 values={};records=[]
 for name,(relative,expected) in PINS.items():
  data=(directory/name).read_bytes();require(len(data)<4_000_000 and sha(data)==expected,'Unpinned CC0 asset: '+name)
  values[name]=data;records.append({'filename':name,'repositoryPath':relative,'sourceURL':f'https://github.com/makehumancommunity/makehuman/blob/{COMMIT}/{relative}',
   'sha256':expected,'gitBlobSHA1':hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest(),'bytes':len(data),'license':'CC0-1.0','licenseFilename':'LICENSE.CC0.txt'})
 for name in ['default.mhskel','default_weights.mhw']:
  d=json.loads(values[name]);require(d.get('license')=='CC0','Missing per-file CC0 declaration: '+name)
  next(r for r in records if r['filename']==name)['embeddedCopyright']=d.get('copyright')
 return values,records
def source_mesh(data):
 vertices=[];faces=[];group=''
 for line in data.decode().splitlines():
  p=line.split()
  if not p:continue
  if p[0]=='v':vertices.append([float(x) for x in p[1:4]])
  elif p[0]=='g':group=p[1]
  elif p[0]=='f' and group=='body':
   ids=[int(x.split('/')[0])-1 for x in p[1:]];faces.extend([ids[0],ids[i],ids[i+1]] for i in range(1,len(ids)-1))
 require(len(vertices)==19158 and all(len(p)==3 and all(map(math.isfinite,p)) for p in vertices),'Unexpected source vertices')
 used=sorted({i for f in faces for i in f});require(len(used)==13380,'Unexpected visible source set')
 remap={v:i for i,v in enumerate(used)}
 return vertices,faces,used,[remap[i] for f in faces for i in f]
def normalization(vertices,faces,used,baseline):
 # This is the project's own pinned scalar preprocessing field, also applied
 # separately to CC0 auxiliary joint vertices before taking their means.
 foot=min(vertices[i][1] for i in used);head=max(vertices[i][1] for i in used)
 def section(y):
  segments=[]
  for f in faces:
   ps=[vertices[i] for i in f];points=[]
   for a,b in zip(ps,ps[1:]+ps[:1]):
    if a[1]<=y<b[1] or b[1]<=y<a[1]:
     t=(y-a[1])/(b[1]-a[1]);points.append((a[0]+t*(b[0]-a[0]),a[2]+t*(b[2]-a[2])))
   if len(points)==2 and all(abs(p[0])<2.4 for p in points):segments.append(points)
  return segments
 waist,hips=section(2.75),section(.5);wc=sum(math.dist(a,b) for a,b in waist);hc=sum(math.dist(a,b) for a,b in hips)
 z=(min(p[1] for s in waist for p in s)+max(p[1] for s in waist for p in s))/2
 def transform(p):
  x,y,zz=p;t=max(0,min(1,(y-.5)/2.25));t=t*t*(3-2*t);h=baseline['hips']/hc+(baseline['waist']/wc-baseline['hips']/hc)*t
  yy=(y-2.75)*(baseline['height']-baseline['waistLevel'])/(head-2.75) if y>=2.75 else ((y-2.75)*baseline['hipLine']/2.25 if y>=.5 else -baseline['hipLine']+(y-.5)*(baseline['waistLevel']-baseline['hipLine'])/(.5-foot))
  return [round(x*h,7),round(yy,7),round((zz-z)*h,7)]
 return transform,{'sourceFootY':foot,'sourceHeadY':head,'sourceWaistY':2.75,'sourceHipY':.5,'sourceWaistPerimeter':wc,'sourceHipPerimeter':hc,'sourceZOrigin':z,'roundingDecimalPlaces':7,'baseline':baseline}
def prepare(directory,body_path):
 assets,sources=load_assets(directory);body=json.loads(body_path.read_bytes());rig=json.loads(assets['default.mhskel']);weights=json.loads(assets['default_weights.mhw'])
 require(body['format']=='tailorass-standard-body-v1' and body['sourceCommit']==COMMIT and body['sourceSHA256']==PINS['base.obj'][1],'Wrong template provenance')
 vertices,faces,used,indices=source_mesh(assets['base.obj']);transform,field=normalization(vertices,faces,used,body['baseline'])
 require(indices==body['triangleIndices'] and [transform(vertices[i]) for i in used]==body['positions'],'Existing visible mesh is not the exact pinned preprocessing output')
 names=sorted(rig['bones']);joint_names=sorted(rig['joints']);bone_index={n:i for i,n in enumerate(names)};joint_index={n:i for i,n in enumerate(joint_names)}
 require(len(names)==163 and len(joint_names)==326,'Unexpected rig structure')
 order=[];visiting=set();done=set()
 def visit(n):
  require(n not in visiting,'Bone parent cycle');
  if n in done:return
  visiting.add(n);parent=rig['bones'][n]['parent']
  if parent is not None:require(parent in bone_index,'Unknown parent');visit(parent)
  visiting.remove(n);done.add(n);order.append(bone_index[n])
 for n in names:visit(n)
 refs=sorted({i for ids in rig['joints'].values() for i in ids});require(all(isinstance(i,int) and 0<=i<len(vertices) for i in refs),'Bad joint source ID')
 helper_lookup={i:j for j,i in enumerate(refs)}
 source_to_visible=[-1]*len(vertices)
 for i,v in enumerate(used):source_to_visible[v]=i
 joints=[]
 for n in joint_names:
  ids=rig['joints'][n];require(ids and len(ids)==len(set(ids)),'Duplicate/empty joint references')
  transformed=[transform(vertices[i]) for i in ids]
  joints.append({'name':n,'sourceVertexIDs':ids,'sourceVertexTableIndices':[helper_lookup[i] for i in ids],
   'sourceMeanPosition':[sum(vertices[i][a] for i in ids)/len(ids) for a in range(3)],
   'templatePositionMeters':[sum(p[a] for p in transformed)/len(ids) for a in range(3)],'definition':'mean of individually template-transformed CC0 referenced vertices; bone proxy, not anthropometric landmark'})
 bones=[]
 for n in names:
  b=rig['bones'][n];require(b['head'] in joint_index and b['tail'] in joint_index and b['rotation_plane'] in rig['planes'],'Unresolved bone data')
  plane=rig['planes'][b['rotation_plane']];require(len(plane)==3 and all(x in joint_index for x in plane),'Bad rotation-plane anchors')
  bones.append({'name':n,'parent':None if b['parent'] is None else bone_index[b['parent']], 'head':joint_index[b['head']],'tail':joint_index[b['tail']],
   'rotationPlaneJointIndices':[joint_index[x] for x in plane],'sourceHead':b['head'],'sourceTail':b['tail'],'sourceRotationPlane':b['rotation_plane'],'sourceReference':b.get('reference')})
 rows=[[] for _ in used];raw_pairs=0
 for bone,pairs in weights['weights'].items():
  require(bone in bone_index,'Unknown weighted bone');seen=set()
  for offset,pair in enumerate(pairs):
   require(len(pair)==2,'Invalid weight pair');v,w=pair;raw_pairs+=1
   require(isinstance(v,int) and 0<=v<len(vertices) and v not in seen and isinstance(w,(int,float)) and math.isfinite(w) and w>=0,'Invalid/duplicate weight');seen.add(v)
   target=source_to_visible[v]
   if target>=0:rows[target].append((bone_index[bone],float(w),offset))
 require(all(rows) and raw_pairs==57107,'Incomplete raw/visible weights')
 starts=[0];bids=[];raw=[];normalized=[];raw_sums=[];offsets=[]
 for row in rows:
  row.sort();total=sum(w for _,w,_ in row);require(total>0 and len(row)<=64,'Unweighted vertex or weight budget')
  raw_sums.append(total)
  for b,w,o in row:bids.append(b);raw.append(w);normalized.append(w/total);offsets.append(o)
  starts.append(len(bids))
 payload={'format':'tailorass-optional-body-rig-v1','license':'CC0-1.0','sourceCommit':COMMIT,'templateResourceSHA256':sha(body_path.read_bytes()),
  'templateGeometrySHA256':geometry_sha(body['positions'],indices),'templateVertexCount':len(used),'sourceVertexCount':len(vertices),
  'coordinateSystem':'template metres; +Y up, +Z anterior; subject-left rig anchors use +X','runtimeEnabled':False,'fitterImplemented':False,'surfaceMeasurementContractImplemented':False,
  'scope':'Optional skeleton/pose inputs only. No anthropometric dimensions are fitted and no existing body mesh/SDF is changed.',
  'visibleToSource':used,'sourceToVisible':source_to_visible,'normalizationField':field,
  'jointSourceVertexTable':[{'sourceVertexID':i,'sourcePosition':vertices[i],'templatePositionMeters':transform(vertices[i]),'visibleVertexID':source_to_visible[i] if source_to_visible[i]>=0 else None} for i in refs],
  'joints':joints,'bones':bones,'boneEvaluationOrder':order,
  'weights':{'vertexOffsets':starts,'boneIndices':bids,'rawValues':raw,'normalizedValues':normalized,'sourcePairOffsets':offsets,'rawVertexSums':raw_sums,
   'normalization':'Each original visible vertex keeps ALL original bone pairs; normalized=raw/sum(raw) per vertex. Original raw values and source pair offsets are retained. No top-four pruning.'}}
 stats={'sourceVertices':len(vertices),'visibleVertices':len(used),'visibleTriangles':len(indices)//3,'bones':len(bones),'joints':len(joints),'jointReferencedVertices':len(refs),
  'jointReferencesOutsideVisibleSurface':sum(source_to_visible[i]<0 for i in refs),'sourceWeightPairs':raw_pairs,'visibleWeightPairs':len(raw),
  'maximumVisibleInfluences':max(starts[i+1]-starts[i] for i in range(len(used))),'minimumRawVisibleSum':min(raw_sums),'maximumRawVisibleSum':max(raw_sums),
  'maximumNormalizedSumError':max(abs(sum(normalized[starts[i]:starts[i+1]])-1) for i in range(len(used))),
  'visiblePositionsAndTrianglesExactlyReconstructed':True,'boneLandmarksAreMeasurementTruth':False}
 return payload,sources,stats,assets['LICENSE.ASSETS.md']
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source-dir',type=Path,required=True);p.add_argument('--body-resource',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--sleeve-axis-oracle',type=Path);a=p.parse_args()
 require(not a.output.exists(),'Refusing to overwrite rig bundle');before=sha(a.body_resource.read_bytes());payload,sources,stats,license_data=prepare(a.source_dir,a.body_resource);encoded=encode(payload)
 provenance={'format':'tailorass-optional-body-rig-provenance-v1','sourceCommit':COMMIT,'assets':sources,'rigResourceSHA256':sha(encoded),'templateResourceSHA256':before,
  'templateGeometrySHA256':payload['templateGeometrySHA256'],'generator':{'path':'Tests/NativePattern/PrepareBodyRig.py','sha256':sha(Path(__file__).read_bytes())},'statistics':stats,
  'notImported':['MakeHuman application code','AGPL measurement plugin/path indices','any body fitter or pose runtime'],'existingBodyResourceUnchanged':sha(a.body_resource.read_bytes())==before}
 if a.sleeve_axis_oracle:
  axis=json.loads(a.sleeve_axis_oracle.read_bytes());require(axis['format']=='tailorass-cc0-rig-garment-sleeve-axis-oracle-v1' and not axis['measurementCodeOrAGPLPathsUsed'],'Wrong sleeve coordinate oracle')
  provenance['poseConventionOracle']={'fixture':'Tests/NativePattern/Fixtures/body-rig-sleeve-axes.json','sha256':sha(a.sleeve_axis_oracle.read_bytes()),
   'scope':'Authored sleeve-coordinate placement only; not a human-bone angle or anthropometric measurement contract.'}
 require(provenance['existingBodyResourceUnchanged'],'Input body mutated');a.output.parent.mkdir(parents=True,exist_ok=True);temporary=Path(tempfile.mkdtemp(prefix='.body-rig-',dir=a.output.parent))
 try:
  (temporary/'rig.json').write_bytes(encoded);(temporary/'provenance.json').write_bytes(encode(provenance));(temporary/'LICENSE.CC0.txt').write_bytes(license_data);os.replace(temporary,a.output)
 except BaseException:shutil.rmtree(temporary,ignore_errors=True);raise
 print(json.dumps(stats,indent=2))
if __name__=='__main__':main()
