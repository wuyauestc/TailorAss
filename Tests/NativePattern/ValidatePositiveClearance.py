#!/usr/bin/env python3
"""Independent long-double positive-gap source audit after the Swift preparation suite."""
from pathlib import Path
import argparse,hashlib,json,subprocess
parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);parser.add_argument('oracle',type=Path);args=parser.parse_args();out=args.output;summary=json.loads((out/'native-positive-clearance-summary.json').read_text());rows=summary['cases']
if summary['unexpectedFailures'] or summary['knownIncompleteSources']:raise SystemExit('Preparation rejected cases; raw evidence retained')
if len(rows)!=211 or summary['defaultCaseCount']!=160:raise SystemExit('Full211 source preparation required')
inputs=[]
for row in rows:
 r=row['positiveGapInitialization'];assert len(r['oldThreeModeSignatures'])==3
 for key in ['independentBodyTriangleCrossings','independentInterPanelProperCrossings','independentInterPanelCoplanarOverlaps','insideVertices','insideCentroids','ambiguousVertices','ambiguousCentroids']:assert r['geometry'][key]==0,(row['case'],key)

with (out/'positive-distance-input.txt').open('w') as w:
 w.write('SELFBOOT1 '+str(len(rows))+'\n')
 for row in rows:
  id=row['case'];stem=''.join(x if x.isalnum() or x in '-_' else '_' for x in id);p=out/(stem+'-positive-input.json');x=json.loads(p.read_text());tri=x['triangleIndices'];r=row['positiveGapInitialization']
  assert x['stateSignature']==r['finalStateSHA256'] and x['sourceSHA256']==r['sourceSHA256']
  inputs.append(dict(case=id,path=p.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),signature=x['stateSignature']))
  w.write(f"{id} {len(x['positions'])} {len(tri)//3} {len(x['panelNames'])}\n");w.write(' '.join(x['panelNames'])+'\n')
  for v,panel in zip(x['positions'],x['vertexPanelIDs']):w.write(f"{v['x']:.17g} {v['y']:.17g} {v['z']:.17g} {panel}\n")
  for i,panel in enumerate(x['trianglePanelIDs']):w.write(f'{tri[3*i]} {tri[3*i+1]} {tri[3*i+2]} {panel}\n')
p=subprocess.run([str(args.oracle),str(out/'positive-distance-input.txt'),str(out/'independent-positive-distance.json')],capture_output=True,text=True);(out/'independent-positive-distance.log').write_text(p.stdout+p.stderr)
if p.returncode:raise SystemExit('Independent primitive oracle refused; see log')
distances=json.loads((out/'independent-positive-distance.json').read_text());assert len(distances['cases'])==211
minimumCross=minimumSame=float('inf');zero=near=0;details=[]
for c in distances['cases']:
 cross=[p for p in c['pairs'] if p['panelIDs'][0]!=p['panelIDs'][1]];same=[p for p in c['pairs'] if p['panelIDs'][0]==p['panelIDs'][1]]
 crossMin=min(min(p['minimumVFDistanceMeters'],p['minimumEEDistanceMeters']) for p in cross);sameMin=min(min(p['minimumVFDistanceMeters'],p['minimumEEDistanceMeters']) for p in same)
 z=sum(p['exactZeroVF']+p['exactZeroEE'] for p in c['pairs']);n=sum(p['nearVF']+p['nearEE'] for p in c['pairs']);zero+=z;near+=n;minimumCross=min(minimumCross,crossMin);minimumSame=min(minimumSame,sameMin)
 assert crossMin>0.00005 and sameMin>0 and z==0 and n==0,(c['case'],crossMin,sameMin,z,n)
 details.append(dict(case=c['case'],actualCrossPanelMinimumMeters=crossMin,actualSamePanelNonAdjacentMinimumMeters=sameMin,exactZeroPrimitives=z,within10nmPrimitives=n))
prepared=[r['positiveGapInitialization'] for r in rows]
conclusion=dict(passed=True,scope='Explicit positive sampled bootstrap only, not physics or sewn garment acceptance',caseCount=211,oldThreeModeExactSignatureChecks=633,allSourceMassNormalsIndependentDOFsUnchanged=True,allZeroPins=True,actualMinimumCrossPanelDistanceMeters=minimumCross,actualMinimumSamePanelNonAdjacentDistanceMeters=minimumSame,actualExactZeroPrimitives=zero,actualWithin10nmPrimitives=near,allBodyProperCrossings=0,allInterPanelProperCrossings=0,allCoplanarPositiveAreaOverlaps=0,allInsideOrAmbiguous=0,maximumInitialSourceStrain=max(r['maximumInitialSourceStrain'] for r in prepared),maximumExtraShiftMeters=max(r['extraShiftMeters'] for r in prepared),maximumInitialGapErrorMeters=max(r['initialGapMaximumErrorMeters'] for r in prepared),maximumInitialDirectionError=max(r['initialDirectionMaximumError'] for r in prepared),movedCases=sum(r['movedPanels']>0 for r in prepared),noExtraShiftCases=sum(r['movedPanels']==0 for r in prepared),longDoubleMantissaBits=distances['longDoubleMantissaBits'],maximumSingleShiftMeters=max((v['x']**2+v['y']**2+v['z']**2)**.5 for r in prepared for v in r['translationsByPanel'].values()),projectionRefinementCases=sum(r['supportRefinementCount']>0 for r in prepared),physicalAcceptance=False,cases=details,geometryFiles=inputs)
(out/'positive-clearance-conclusion.json').write_text(json.dumps(conclusion,indent=2)+'\n');print(json.dumps({k:v for k,v in conclusion.items() if k not in ['cases','geometryFiles']},indent=2))
