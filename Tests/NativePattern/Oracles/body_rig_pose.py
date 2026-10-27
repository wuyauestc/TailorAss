#!/usr/bin/env python3
"""Independent all-vertex pose oracle using projected-frame dot/cross rotations."""
import argparse,json,math
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--snapshot',type=Path,required=True);p.add_argument('--results',type=Path,required=True);a=p.parse_args();s=a.snapshot;o=a.results
r=json.loads((s/'resources/GarmentCodeStandardBodyRig/rig.json').read_text());t=json.loads((s/'resources/GarmentCodeStandardBody.json').read_text());cat=json.loads((s/'resources/GarmentCodeParameterCatalog.json').read_text())
female=json.loads((s/'female-standing-mesher-source.json').read_text())['parameters']['body'];bl=t['baseline'];bones=r['bones'];w=r['weights'];names={b['name']:i for i,b in enumerate(bones)}
def vec(p):return [p[x]for x in ['x','y','z']]if isinstance(p,dict)else p
def sub(a,b):return [x-y for x,y in zip(a,b)]
def ancestors(i):
 out=set()
 while i is not None:
  assert i not in out;out.add(i);i=bones[i]['parent']
 return out
sides={i:side for i in range(len(bones))for side in ['L','R']if names['upperarm01.'+side]in ancestors(i)}
rows=[]
for profile,values in [('default',cat['body']),('female',female)]:
 v=dict(values);v['_waist_level']=v['height']-v['head_l']-v['waist_line']
 ws=v['waist']/100/bl['waist'];hs=v['hips']/100/bl['hips'];hy=v['hips_line']/100/bl['hipLine'];ly=(v['_waist_level']-v['hips_line'])/100/(bl['waistLevel']-bl['hipLine']);uy=(v['height']-v['_waist_level'])/100/(bl['height']-bl['waistLevel'])
 def shape(p):
  x,y,z=p;q=max(0,min(1,(y+bl['hipLine'])/bl['hipLine']));h=hs+(ws-hs)*q*q*(3-2*q)
  # Keep the parenthesized blend used by the documented source field.
  h=hs+(ws-hs)*(q*q*(3-2*q))
  yy=y*uy if y>=0 else(y*hy if y>=-bl['hipLine']else -bl['hipLine']*hy+(y+bl['hipLine'])*ly)
  return [x*h,yy,z*h]
 rest=[shape(p)for p in t['positions']];helpers=[shape(p['templatePositionMeters'])for p in r['jointSourceVertexTable']]
 js=[[sum(helpers[i][axis]for i in j['sourceVertexTableIndices'])/len(j['sourceVertexTableIndices'])for axis in range(3)]for j in r['joints']]
 actualJoints=[vec(p)for p in json.loads((o/f'identity-{profile}-joints.json').read_text())]
 jointError=max(abs(x-y)for p,q in zip(js,actualJoints)for x,y in zip(p,q));assert jointError<5e-15,(profile,jointError)
 nonlinearError=max(abs(x-y)for p,q in zip(js,[shape(j['templatePositionMeters'])for j in r['joints']])for x,y in zip(p,q))
 for alpha in [30,45,60]:
  transforms={}
  for side in ['L','R']:
   root=bones[names['upperarm01.'+side]];elbow=bones[names['upperarm02.'+side]];pivot=js[root['head']];d=sub(js[elbow['tail']],pivot);length=math.hypot(d[0],d[1]);u=[d[0]/length,d[1]/length]
   desired=[(1 if side=='L'else -1)*math.cos(alpha*math.pi/180),-math.sin(alpha*math.pi/180)]
   # This oracle never computes the production atan2/rest-angle/delta angle.
   c=sum(x*y for x,y in zip(u,desired));sn=u[0]*desired[1]-u[1]*desired[0]
   transforms[side]=(pivot,c,sn)
  result=[]
  for i,p in enumerate(rest):
   delta=[0.,0.,0.]
   for k in range(w['vertexOffsets'][i],w['vertexOffsets'][i+1]):
    side=sides.get(w['boneIndices'][k])
    if side:
     pivot,c,sn=transforms[side];q=sub(p,pivot);dv=[(c-1)*q[0]-sn*q[1],sn*q[0]+(c-1)*q[1],0.];ww=w['normalizedValues'][k]
     for axis in range(3):delta[axis]+=ww*dv[axis]
   result.append([x+y for x,y in zip(p,delta)])
  actual=[vec(p)for p in json.loads((o/f'pose-{profile}-{alpha}-positions.json').read_text())]
  error=max(abs(x-y)for p,q in zip(result,actual)for x,y in zip(p,q));assert error<5e-15,(profile,alpha,error)
  rows.append({'profile':profile,'alpha':alpha,'vertexCount':len(actual),'maximumPositionErrorMeters':error,'allWeightPairs':len(w['boneIndices']),'all326JointMaximumErrorMeters':jointError,'meanThenWarpCounterfactualErrorMeters':nonlinearError})
report={'passed':True,'method':'Independent parent traversal, per-helper shape field and projected-frame dot/cross rotation (no production atan2 delta); compare all actual rounded vertices at 30/45/60 for both profiles. This is not a self-collision or measurement oracle.','rows':rows}
(o/'independent-pose-oracle.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
