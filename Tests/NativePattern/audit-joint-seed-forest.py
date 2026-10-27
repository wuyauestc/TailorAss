#!/usr/bin/env python3
"""Independent data/bit/forest audit. Does not replace fresh native geometry gates."""
import argparse,json,struct,hashlib
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();out=a.output;read=lambda q:json.loads(q.read_text());sha=lambda q:hashlib.sha256(q.read_bytes()).hexdigest()
def bits(x):
 if isinstance(x,dict):return tuple(struct.pack('>d',x[k]).hex()for k in ('x','y','z'))
 return tuple(struct.pack('>d',v).hex()for v in x)
def eq(a,b):return len(a)==len(b)and all(bits(x)==bits(y)for x,y in zip(a,b))
m=read(out/'input-manifest.json');assert all(sha(out/'source'/n)==h for n,h in m['sourceSnapshotFiles'].items());assert all(sha(Path(n))==h for n,h in m['nativeDependenciesSHA256'].items())
fixture=out/'source/fixture';fm=read(fixture/'manifest.json');assert all(sha(fixture/n)==x['sha256']for n,x in fm['files'].items())
seal=Path(fm['originalFullRunSealPath']);assert sha(seal)==fm['originalFullRunSealSHA256']
oldseal=read(seal)['filesSHA256']
for relative,want in fm['originalFileSHA256'].items():assert oldseal[relative]==want and sha(fixture/Path(relative).name)==want
legacy=read(fixture/'last-accepted-frame.json');state=read(fixture/'last-accepted-state.json');assert eq(legacy['accepted']['positions'],state['positions'])and eq(legacy['accepted']['velocities'],state['velocities'])
assert [(x['startTick'],x['endTick'],x['ticksPerMacroStep'])for x in legacy['physicalSubsteps']]==[(0,1,2),(1,2,2)]
assert fm['legacyOriginTag'].replace('-','')==sha(fixture/'last-accepted-frame.json')[:32]
results={}
for mode in ('seed923924','first481','depth2','cancel'):
 folder=out/mode
 if not(folder/'mode-summary.json').exists():continue
 summary=read(folder/'mode-summary.json');assert summary['passed'];rows=[]
 for rec in sorted(folder.rglob('accepted-frame.json')):
  r=read(rec);leaves=r['physicalSubsteps'];used=r['usedPhysicalSeeds'];ledger=r['physicalAttemptLedger'];step=r['accepted']['completedSteps'];depth=r['acceptedSeedControl']['maximumDepth'];den=1<<depth
  assert len(ledger)==2*len(leaves)-len(used)==r['report']['physicalSubstepAttempts']
  assert r['acceptedSeedControl']['originAcceptedFrameIdentity']==r['identity']and r['acceptedSeedControl']['originCompletedStep']==step
  x=r['previous']['positions'];v=r['previous']['velocities'];cursor=0
  for leaf in leaves:
   assert leaf['startTick']==cursor and leaf['ticksPerMacroStep']==den and eq(leaf['previousPositions'],x)and eq(leaf['previousVelocities'],v)
   # Reproduce exactly the declared actual tau/load, not an unexecuted macro chord.
   tau=(1/240)*(leaf['endTick']-leaf['startTick'])/den
   assert struct.pack('>d',tau)==struct.pack('>d',leaf['timeStepSeconds'])
   gravity=min(1,max(0,((step-480-1)+leaf['endTick']/den)/240));assert gravity==leaf['gravityFraction']
   assert leaf['report']['accepted']and leaf['sourceMotion']['status']=='clear'and leaf['sourceMotion']['completedAllTriangles']
   cursor=leaf['endTick'];x=leaf['acceptedPositions'];v=leaf['acceptedVelocities']
  assert cursor==den and eq(x,r['accepted']['positions'])and eq(v,r['accepted']['velocities'])and eq(r['predictor'],leaves[-1]['predictor'])
  proof=read(rec.parent/'fresh-frame-proof.json');assert proof['gradientInfinityNewton']<1e-6 and proof['preconditionedGradientInfinityMeters']<1e-7 and proof['pzRelativeResidual']<1e-6;assert proof['segmentCount']==len(leaves);assert all(x['gradientInfinityNewton']<1e-6 and x['preconditionedGradientInfinityMeters']<1e-7 and x['pzRelativeResidual']<1e-6 for x in proof['physicalSubsteps'])
  visible=read(rec.parent/'independent-visible-body.json');assert visible['completedAllSamples'] and visible['insideSamples']==0 and visible['uncertainSamples']==0
  rows.append({'step':step,'leaves':len(leaves),'seeds':len(used),'attempts':len(ledger)})
 if mode=='seed923924':
  r923=read(folder/'step923/accepted-frame.json');r924=read(folder/'step924/accepted-frame.json')
  assert [(x['startTick'],x['endTick'],x['ticksPerMacroStep'])for x in r923['usedPhysicalSeeds']]==[(0,4,8),(4,8,8)]
  assert r923['previousSeedControl']['originAcceptedFrameIdentity'].lower()==fm['legacyOriginTag'].lower()
  assert r924['previousSeedControl']==r923['acceptedSeedControl']and r924['usedPhysicalSeeds']==r923['acceptedSeedControl']['nextSeeds']
 if mode=='first481':
  a=read(folder/'rootOnly/after-state.json');b=read(folder/'committedPartition/after-state.json');assert eq(a['positions'],b['positions'])and eq(a['velocities'],b['velocities'])
 if mode=='depth2':
  q=read(folder/'step923/after-state.json');assert q['completedSteps']==922 and eq(q['positions'],state['positions'])and eq(q['velocities'],state['velocities'])
 if mode=='cancel':
  x=read(folder/'before-state.json');y=read(folder/'after-state.json');assert x['completedSteps']==y['completedSteps']==922 and eq(x['positions'],y['positions'])and eq(x['velocities'],y['velocities']);assert read(folder/'before-control.json')==read(folder/'after-control.json')
 results[mode]={'passed':True,'records':rows}
report={'passed':True,'scope':'Independent bit/partition/control/tau/load data audit; fresh native body/self/source and KKT remain production R evidence, not independently rerun here.','sourceAndNativeUnchanged':True,'modes':results,'noInitial0Qualification':True}
(out/'independent-data-audit.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
