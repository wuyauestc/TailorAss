#!/usr/bin/env python3
import json,struct,sys
from pathlib import Path
p=Path(sys.argv[1]);read=lambda q:json.loads(q.read_text())
def flat(v):return [x[k] for x in v for k in ('x','y','z')]
def same(a,b):return len(a)==len(b)and all(struct.pack('>d',x)==struct.pack('>d',y)for x,y in zip(a,b))
def diff(a,b):
 pairs=[(i,x,y)for i,(x,y)in enumerate(zip(a,b))if struct.pack('>d',x)!=struct.pack('>d',y)]
 return {'differentScalarCount':len(pairs),'maximumAbsoluteDifference':max((abs(x-y)for i,x,y in pairs),default=0),'maximumULPDifference':max((abs(int.from_bytes(struct.pack('>d',x),'big')-int.from_bytes(struct.pack('>d',y),'big'))for i,x,y in pairs),default=0)}
files={label:read(p/folder/policy/'accepted-frame.json')for label,folder,policy in [('first-root','first481','rootOnly'),('first-committed','first481','committedPartition'),('repeat-root','first481-repeat','rootOnly'),('repeat-committed','first481-repeat','committedPartition')]}
rows=[]
for a,b in [('first-root','first-committed'),('first-root','repeat-root'),('first-committed','repeat-committed')]:
 x,y=files[a],files[b];lx=x['physicalSubsteps'][0];ly=y['physicalSubsteps'][0]
 initial={name:same(flat(lx[name]),flat(ly[name]))for name in ['previousPositions','previousVelocities','predictor']};initial.update({name:same([lx[name]],[ly[name]])for name in ['timeStepSeconds','gravityFraction','sewingRamp']})
 g0=same([x['report']['newton']['initialGradientInfinityNewton']],[y['report']['newton']['initialGradientInfinityNewton']]);assert all(initial.values())and g0
 hx=x['report']['newton']['history'];hy=y['report']['newton']['history'];first=next((i for i,(u,v)in enumerate(zip(hx,hy))if u['linear']!=v['linear']or not same([u['gradientInfinityNewton']],[v['gradientInfinityNewton']])),None)
 rows.append({'a':a,'b':b,'initialXVelocityPredictorTimeLoadBitsEqual':initial,'initialGradientInfinityBitsEqual':g0,'samePreparedLinearizationWithinOriginalProcess':x['previousSeedControl']['linearizationSourceIdentity']==y['previousSeedControl']['linearizationSourceIdentity'],'acceptedPositionDifference':diff(flat(x['accepted']['positions']),flat(y['accepted']['positions'])),'acceptedVelocityDifference':diff(flat(x['accepted']['velocities']),flat(y['accepted']['velocities'])),'firstArchivedNewtonDifferenceZeroBased':first,'firstLinearA':hx[first]['linear']if first is not None else None,'firstLinearB':hy[first]['linear']if first is not None else None})
checks=[]
for label,r in files.items():
 folder='first481-repeat'if label.startswith('repeat')else'first481';policy='rootOnly'if label.endswith('root')else'committedPartition';f=read(p/folder/policy/'fresh-frame-proof.json')
 assert f['gradientInfinityNewton']<1e-6 and f['preconditionedGradientInfinityMeters']<1e-7 and f['pzRelativeResidual']<1e-6
 checks.append({'label':label,'updates':len(r['report']['newton']['history']),'gradientInfinityNewton':f['gradientInfinityNewton'],'preconditionedGradientInfinityMeters':f['preconditionedGradientInfinityMeters'],'pzRelativeResidual':f['pzRelativeResidual'],'allActualMotionSourcesBodySelfCompleteClear':all(z['status']=='clear'and z['completedAllTriangles']for z in f['sourceMotions'])and all(z['status']=='clear'and z['completedAllFeatures']for z in f['bodyMotions'])and all(z['status']=='clear'and z['completedAllFeatures']and z['completedDomainCertificates']for z in f['selfMotions'])})
report={'scope':'Same frozen binary; second invocation also repeats each same policy. No replacement of failed bitwise assertion.','strictBitwisePolicyComparisonPassed':False,'baselineSamePolicyRepeatAlsoDiffers':rows[1]['acceptedPositionDifference']['differentScalarCount']>0,'observedEarliestBoundary':'Same archived start x/v/predictor/tau/load and initial gradient infinity; the first archived CG result and its first accepted Newton endpoint already differ. Full initial force vector/P coefficients were not exported, so exact internal arithmetic source is not proved.','comparison':rows,'freshPhysicalGates':checks,'completeGarmentAccepted':False}
(p/'first481-repeatability-audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
