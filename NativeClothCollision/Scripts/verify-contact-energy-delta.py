#!/usr/bin/env python3
"""Independent fixed IPC leaf oracle: exact binary64 input at80/100 decimal digits.
Requires developer-only mpmath1.3.0; no dependency is used by the offline App.
This validates real-valued formulas and fixture integrity, not a universal online
rounding/sign certificate and not a complete garment simulation.
"""
from pathlib import Path
import argparse,json
import mpmath as mp
p=argparse.ArgumentParser();p.add_argument('--fixtures',type=Path);p.add_argument('--output',type=Path);a=p.parse_args()
f=a.fixtures or Path(__file__).resolve().parents[1]/'Tests/NativeClothCollisionTests/Fixtures/ContactEnergyDelta'
def exact(x):
 n,d=x.as_integer_ratio() if isinstance(x,float) else (x,1)
 return mp.mpf(n)/d
sub=lambda a,b:tuple(x-y for x,y in zip(a,b))
add=lambda a,b:tuple(x+y for x,y in zip(a,b))
dot=lambda a,b:sum(x*y for x,y in zip(a,b))
cross=lambda a,b:(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
norm2=lambda a:dot(a,a)
def line(p,a,b):
 return norm2(cross(sub(p,a),sub(b,a)))/norm2(sub(b,a))
def plane(p,a,b,c):
 n=cross(sub(b,a),sub(c,a))
 return dot(sub(p,a),n)**2/norm2(n)
def distance(q,k,t):
 if k==0:return norm2(sub(q[0],q[1]))
 if k==1:
  if t<2:return norm2(sub(q[0],q[t+1]))
  return line(q[0],q[1],q[2])
 if k==2:
  if t<4:return norm2(sub(q[t//2],q[2+t%2]))
  if t<6:return line(q[t-2],q[0],q[1])
  if t<8:return line(q[t-6],q[2],q[3])
  n=cross(sub(q[1],q[0]),sub(q[3],q[2]))
  return dot(sub(q[0],q[2]),n)**2/norm2(n)
 if t<3:return norm2(sub(q[0],q[t+1]))
 if t<6:
  a,b=[(1,2),(2,3),(3,1)][t-3]
  return line(q[0],q[a],q[b])
 return plane(q[0],q[1],q[2],q[3])
def evaluate(row,z,constants):
 q=[tuple(exact(v) for v in x) for x in row['positions']]
 rest=[tuple(exact(v) for v in x) for x in row['rest']]
 dm,h,k=map(exact,[row['dmin'],row['dhat'],row['kappa']])
 d2=distance(q,row['kind'],z['effectiveDistanceType'])
 if constants=='nativeFrozen':
  qmin,Q,scale=map(exact,[z['qmin'],z['Q'],z['scale']])
 else:qmin,Q=dm*dm,(2*dm+h)*h;scale=k*h/(Q*Q)
 qq=d2-qmin
 assert qq>0
 if qq>=Q:b=mp.mpf(0)
 else:b=-(qq-Q)**2*mp.log(qq/Q)
 m=mp.mpf(1)
 if row['kind']==2:
  if constants=='nativeFrozen':eps=exact(z['eps'])
  else:eps=exact(.001)*norm2(sub(rest[1],rest[0]))*norm2(sub(rest[3],rest[2]))
  cr=norm2(cross(sub(q[1],q[0]),sub(q[3],q[2])))
  if cr<eps:
   zz=cr/eps;m=zz*(2-zz)
 return exact(row['signedArea'])*m*scale*b

result={};total=0
for file in ['actual-fresh005.json','synthetic.json']:
 cases=json.loads((f/file).read_text())['cases']
 constants=json.loads((f/'actual-native-constants.json').read_text()) if file.startswith('actual') else []
 maxPrecision=mp.mpf(0);maxFixture=mp.mpf(0)
 for i,c in enumerate(cases):
  if constants:z=constants[i]
  else:
   def l2(a,b):return sum((x-y)**2 for x,y in zip(a,b))
   dm,h,k=c['dmin'],c['h'],c['kappa'];Q=(2*dm+h)*h
   z={'qmin':dm*dm,'Q':Q,'scale':k*h/(Q*Q),'effectiveDistanceType':c['effectiveType'],'eps':0}
   if c['kind']==2:z['eps']=.001*l2(c['rest'][0],c['rest'][1])*l2(c['rest'][2],c['rest'][3])
  row={'kind':c['kind'],'rest':c['rest'],'dmin':c['dmin'],'dhat':c['h'],'kappa':c['kappa'],'signedArea':c['weight']}
  ds=[]
  for digits in [80,100]:
   with mp.workdps(digits):
    row['positions']=c['previous'];old=evaluate(row,z,'nativeFrozen')
    row['positions']=c['current'];new=evaluate(row,z,'nativeFrozen');ds.append(new-old)
  with mp.workdps(100):
   pd=abs(ds[0]-ds[1]);fd=abs(ds[1]-mp.mpf(c['oracleDelta100']))
   assert pd<mp.mpf('1e-70'),(file,c['name'],'precision',pd)
   assert fd<mp.mpf('1e-90'),(file,c['name'],'fixture',fd)
   maxPrecision=max(maxPrecision,pd);maxFixture=max(maxFixture,fd)
 result[file]={'cases':len(cases),'maximum80vs100AbsoluteJoules':str(maxPrecision),'maximum100vsFixtureAbsoluteJoules':str(maxFixture)}
 total+=len(cases)
summary={'passed':True,'cases':total,'mpmathVersion':mp.__version__,'precisions':[80,100],'longDouble':False,'fullGarmentProof':False,'results':result}
if a.output:a.output.write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2))
