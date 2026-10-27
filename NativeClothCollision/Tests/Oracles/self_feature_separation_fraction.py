#!/usr/bin/env python3
"""Exact Fraction audit of default-zero-floor, two-moving-EE whole-line leaves.
Uses saved Float64 endpoints/directions as exact rationals, not production
closest-point code or any new distance tolerance. Does not prove bootstrap.
"""
from pathlib import Path
from fractions import Fraction as F
import argparse,json,struct,hashlib
from correlated_feature_fraction import verify_moving_leaves,verify_expansion_leaves,verify_critical_leaves
p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();d=json.loads(a.report.read_text());rows=[]
assert d['passed'] and len(d['rows'])==2
for r in d['rows']:
 x=r['actualWitnessStart'];y=r['actualWitnessEnd'];proof=r['featureProof'];floor=proof['minimumSeparationMeters'];assert floor==0 and proof['status']=='separated'
 b=bytearray(b'continuous-feature-separation-v1:edgeEdge\0');b+=struct.pack('<dQQ',floor,4,4)
 for v in x+y:b+=struct.pack('<3d',*v)
 assert hashlib.sha256(b).hexdigest()==proof['motionSHA256']
 leaves=sorted(proof['leafCertificates'],key=lambda v:v['startTime'])
 cover=[(F(v['startTime']),F(v['endTime'])) for v in leaves]
 cover+=verify_moving_leaves('edgeEdge',x,y,floor,proof.get('movingNormalCertificates',[]))
 cover+=verify_expansion_leaves('edgeEdge',x,y,floor,proof.get('expansionCertificates',[]))
 cover+=verify_critical_leaves('edgeEdge',x,y,floor,proof.get('criticalCertificates',[]));cover.sort()
 assert cover and cover[0][0]==0 and cover[-1][1]==1
 for first,last in zip(cover,cover[1:]):assert first[1]==last[0]
 minimum=None
 for leaf in leaves:
  n=list(map(F,leaf['direction']));n2=sum(v*v for v in n);nu=F(leaf['directionNormUpperBound']);lower=F(leaf['projectionLowerBound']);threshold=F(leaf['requiredProductUpperBound']);dl=F(leaf['distanceLowerBoundMeters'])
  assert nu>0 and nu*nu>=n2 and lower>threshold and threshold>=F(floor)*nu
  exact=[]
  for t in [F(leaf['startTime']),F(leaf['endTime'])]:
   for i in [0,1]:
    for j in [2,3]:
     d0=[F(x[i][k])-F(x[j][k]) for k in range(3)];d1=[F(y[i][k])-F(y[j][k]) for k in range(3)]
     exact.append(sum(n[k]*(d0[k]+t*(d1[k]-d0[k])) for k in range(3)))
  em=min(exact);assert 0<lower<=em and dl*nu<=lower and dl*dl*n2<=em*em
  minimum=dl if minimum is None else min(minimum,dl)
 s=r['wholeQueryStatistics'];assert r['wholeQueryStatus']=='clear' and s['completedAllFeatures'] and s['completedDomainCertificates']
 assert s['evaluatedFeatures']==s['uniqueVertexFace']+s['uniqueEdgeEdge'] and s['nativeQueries']==s['evaluatedFeatures']
 assert s['euclideanCertifiedAfterPrecisionLimit']>0 and s['euclideanCertifiedFeatures']>0
 rows.append({'case':r['name'],'sourceSHA256':r['sourceSHA256'],'witnessIDs':r['witnessVertexIDs'],'exactMotionSHA256':proof['motionSHA256'],'leafCount':len(cover),'fullIntervalCoverageExact':True,'allPairEndpointProjectionBoundsExact':True,'normAndDistanceBoundsExact':True,'distanceLowerBoundMeters':proof['minimumCertifiedDistanceLowerBoundMeters'],'completeGlobalFeaturesCheckedByGuard':s['evaluatedFeatures'],'bootstrapProvedByThisAudit':False,'physicsAccepted':False})
result={'passed':True,'scope':'Independent exact rational enclosure audit for the original4point whole-line distance proof, plus complete-query feature accounting; no source domain/bootstrap/garment acceptance substituted','rows':rows};a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
