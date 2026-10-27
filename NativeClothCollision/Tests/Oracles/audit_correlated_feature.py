#!/usr/bin/env python3
"""Audit fixed and moving-normal leaves using exact Fraction, not sampling."""
from pathlib import Path
from fractions import Fraction as F
import argparse,json,struct,hashlib,plistlib
from affine_feature_fraction import verify_affine_leaves
from correlated_feature_fraction import verify_moving_leaves,verify_fixed_leaves,verify_expansion_leaves,verify_critical_leaves,vec,sub,dot,cross,add,scale
p=argparse.ArgumentParser();p.add_argument('--report',type=Path,action='append',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();checks=[]
for file in a.report:
 data=plistlib.loads(file.read_bytes())if file.suffix=='.plist'else json.loads(file.read_text());assert data['passed']
 for row in data['rows']:
  m,r=row['motion'],row['proof'];kind=m['kind'];x,y=m['start'],m['end'];floor=m['floor']
  for k,points in [('runtimeStartBits',x),('runtimeEndBits',y)]:
   if k in row:assert [[format(struct.unpack('<Q',struct.pack('<d',float(z)))[0],'x')for z in vec(v)]for v in points]==row[k]
  b=bytearray(('continuous-feature-separation-v1:'+kind+'\0').encode());b+=struct.pack('<dQQ',floor,4,4)
  for v in x+y:b+=struct.pack('<3d',*map(float,vec(v)))
  assert hashlib.sha256(b).hexdigest()==r['motionSHA256']
  fixed=verify_fixed_leaves(kind,x,y,floor,r['leafCertificates']);moving=verify_moving_leaves(kind,x,y,floor,r['movingNormalCertificates']);exact=verify_expansion_leaves(kind,x,y,floor,r.get("expansionCertificates",[]));critical=verify_critical_leaves(kind,x,y,floor,r.get("criticalCertificates",[]));affine=verify_affine_leaves(kind,x,y,floor,r.get('affineNormalCertificates',[]));cover=sorted(fixed+moving+exact+critical+affine)
  assert (r['status']=='separated')==m['expectedSeparated']
  if r['status']=='separated':
   assert cover and cover[0][0]==0 and cover[-1][1]==1 and all(u[1]==v[0]for u,v in zip(cover,cover[1:]))
   assert sum((v-u for u,v in cover),F(0))==1
   assert r['fixedIntervalsCertified']==len(fixed)and r['movingNormalIntervalsCertified']==len(moving)
   assert r['certifiedIntervals']==len(cover)
   assert r.get('expansionIntervalsCertified',0)==len(exact)
   assert r.get('criticalIntervalsCertified',0)==len(critical)
   assert r.get('affineNormalIntervalsCertified',0)==len(affine)
  contact=None
  times={'moving-VF-tangent-at-midpoint':F(1,2),'moving-VF-two-real-crossings':F(7,16),'EE-cross':F(1,2),'VF-degenerate-contact':F(0),'exact-VF-tangent':F(1,2),'exact-EE-real-cross':F(1,2)}
  if m['name']in times:
   t=times[m['name']];xx,yy=[list(map(vec,z))for z in [x,y]];q=[add(u,scale(sub(v,u),t))for u,v in zip(xx,yy)]
   if kind=='vertexFace':
    if m['name']=='VF-degenerate-contact':assert q[0]==q[1]
    else:
     u,v,w=sub(q[2],q[1]),sub(q[3],q[1]),sub(q[0],q[1]);nn=cross(u,v);assert dot(w,nn)==0
     uu,uv,vv,wu,wv=dot(u,u),dot(u,v),dot(v,v),dot(w,u),dot(w,v);den=uu*vv-uv*uv;assert den>0
     s,z=(wu*vv-wv*uv)/den,(wv*uu-wu*uv)/den;assert s>=0 and z>=0 and s+z<=1
   else:
    u,v,w=sub(q[1],q[0]),sub(q[3],q[2]),sub(q[2],q[0]);n=cross(u,v);D=dot(n,n);assert D>0 and dot(w,n)==0
    s,z=dot(cross(w,v),n)/D,dot(cross(w,u),n)/D;assert 0<=s<=1 and 0<=z<=1
   contact={'exactTime':str(t),'closedFeatureContactExactlyProved':True}
  checks.append({'name':m['name'],'status':r['status'],'fixedLeaves':len(fixed),'movingLeaves':len(moving),'expansionLeaves':len(exact),'criticalLeaves':len(critical),'affineLeaves':len(affine),'allBernsteinControlEnclosuresAndNormProductBoundsExact':True,'fullPartitionVerified':r['status']=='separated','exactContact':contact})
result={'passed':True,'method':'Exact rational interpolation and Bernstein products, all interval controls enclosed, strict signed g lower and norm/product upper, fixed/moving full partition. False contact cases have exact dyadic-time closed-feature witnesses. No domain/bootstrap/garment claim.','rows':checks};a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'passed':True,'rows':len(checks),'movingLeaves':sum(v['movingLeaves']for v in checks)},indent=2))
