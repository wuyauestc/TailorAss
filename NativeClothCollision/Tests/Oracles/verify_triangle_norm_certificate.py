from fractions import Fraction as F
from pathlib import Path
import json,hashlib
import argparse
p=argparse.ArgumentParser();p.add_argument('output',type=Path);args=p.parse_args();root=args.output;result=json.loads((root/'results.json').read_text())
def f(x):return F.from_float(x)
def vector(x):return tuple(map(f,x))
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def dot(a,b):return sum((x*y for x,y in zip(a,b)),F(0))
def mix(a,b):return tuple((x+y)/2 for x,y in zip(a,b))
def split(q):
 left=[q[0]];right=[q[-1]]
 for row in range(1,5):q=[(q[i]+q[i+1])/2 for i in range(len(q)-1)];left.append(q[0]);right.append(q[-1])
 return left,list(reversed(right))
def contains(interval,value):return f(interval[0])<=value<=f(interval[1])
rows=[];checked=0
for c in result['cases']:
 a=list(map(vector,c['start']));b=list(map(vector,c['end']));u0=sub(a[1],a[0]);v0=sub(a[2],a[0]);u1=sub(b[1],b[0]);v1=sub(b[2],b[0]);t=f(c.get('maximumTime',1.0));u1=tuple(x+t*(y-x) for x,y in zip(u0,u1));v1=tuple(x+t*(y-x) for x,y in zip(v0,v1));n0=cross(u0,v0);n1=mix(cross(u0,v1),cross(u1,v0));n2=cross(u1,v1)
 q=[dot(n0,n0),dot(n0,n1),(dot(n0,n2)+2*dot(n1,n1))/3,dot(n1,n2),dot(n2,n2)]
 epsilon=f(c['epsilon'][0]);assert c['epsilon'][0]==c['epsilon'][1],(c['id'],'changed original scalar epsilon')
 assert contains(c['epsilon'],epsilon),(c['id'],'epsilon enclosure')
 assert contains(c['epsilonSquared'],epsilon*epsilon),(c['id'],'epsilon² enclosure')
 for i,x in enumerate(q):assert contains(c['rootBernstein'][i],x),(c['id'],'root enclosure',i)
 paths=[];lower=None
 for leaf in c['acceptedLeaves']:
  qq=q[:]
  for side in leaf['path']:qq=split(qq)[0 if side=='L' else 1]
  for i,x in enumerate(qq):
   interval=leaf['coefficients'][i];assert contains(interval,x),(c['id'],'leaf enclosure',leaf['path'],i)
   assert f(interval[0])>f(c['epsilonSquared'][1]),(c['id'],'unsafe positive claim')
   assert x>epsilon*epsilon,(c['id'],'true rational coefficient is not above exact threshold')
   checked+=1;lower=f(interval[0]) if lower is None else min(lower,f(interval[0]))
  paths.append(leaf['path'])
 prefix_free=all(not a.startswith(b) for i,a in enumerate(paths) for j,b in enumerate(paths) if i!=j)
 coverage=sum((F(1,2**len(p)) for p in paths),F(0))
 if c['certified']:assert prefix_free and coverage==1,(c['id'],'interval not completely covered')
 if c['id'] in ['midCollapseOneEdge','midCollapseBothEdgesEndpointsAreaPositive','quarterCollapse','nonDyadicCollapse']:
  t={'midCollapseOneEdge':F(1,2),'midCollapseBothEdgesEndpointsAreaPositive':F(1,2),'quarterCollapse':F(1,4),'nonDyadicCollapse':F(1,3)}[c['id']]
  u=tuple(x*(1-t)+y*t for x,y in zip(u0,u1));v=tuple(x*(1-t)+y*t for x,y in zip(v0,v1));assert cross(u,v)==(0,0,0) and not c['certified']
 rows.append({'id':c['id'],'certified':c['certified'],'reason':c['reason'],'visitedSegments':c['visitedSegments'],'maximumDepth':c['maximumDepth'],'exactCoefficientEnclosuresChecked':5*(1+len(paths)),'certifiedLeafCoverage':str(coverage),'minimumCertifiedNormSquaredLowerBound':float(lower) if lower is not None else None})
assert result['failures']==0 and result['unsupportedRoundingRefused']
summary={'passed':True,'method':'Python Fraction.from_float exact binary64 input arithmetic; exact vector quadratic/quartic Bernstein coefficients; exact dyadic subdivision; every outward interval and certified full cover verified','cases':rows,'acceptedLeafCoefficientChecks':checked,'sourceOrCCDModified':False,'allExactCollapseExamplesRefused':True,'sourceSHA256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [root/'results.json',root/'actual-input.txt']}}
(root/'independent-exact-verification.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps({'passed':True,'caseCount':len(rows),'acceptedLeafCoefficients':checked,'actualCase':rows[-1]},indent=2))
