from pathlib import Path
from fractions import Fraction as F
import importlib.util,json,hashlib,sys,math
base=Path(__file__).parent;run=Path(sys.argv[1]);dest=Path(sys.argv[2]);oracle=Path(__file__).with_name('JointContinuousSeamAudit.py');spec=importlib.util.spec_from_file_location('independent_oracle',oracle);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();rows=[]
cases=[('actual-pencil-old-pose','actual-pencil-new-plan.json','actual-pencil-old-pose.json','actual-pencil-old-pose-new-quality.json'),('eight-mm-bulge','eight-mm-bulge-plan.json','eight-mm-bulge-positions.json','eight-mm-bulge-quality.json')]
if (run/'result/reverse-near-knot-plan.json').exists():cases.append(('reverse-near-knot','reverse-near-knot-plan.json','reverse-near-knot-positions.json','reverse-near-knot-quality.json'))
if (run/'result/budget-preparation-summary.json').exists():
 for row in json.loads((run/'result/budget-preparation-summary.json').read_text()):cases.append(('budget-'+row['sourceSHA256'],row['planFile'],row['positionsFile'],row['qualityFile']))
for name,pn,xn,qn in cases:
 p=run/'result'/pn;x=run/'result'/xn;q=run/'result'/qn;plan=json.loads(p.read_text());positions=list(map(mod.vector,json.loads(x.read_text())));quality=json.loads(q.read_text());bdry={(v['edge']['panelID'],v['edge']['edgeIndex']):v for v in plan['allBoundaryPaths']};edge=lambda e:(e['panelID'],e['edgeIndex']);origin={o['stitchIndex']:o for c in plan['constraints']for o in c['origins']};reported={s['stitchIndex']:s for s in quality['continuousBoundary']['seams']};seams=[]
 for i,o in sorted(origin.items()):
  if 'gathered'in o['intent']:continue
  a=mod.curve(bdry[edge(o['a']['edge'])],positions,o['aDirection']);b=mod.curve(bdry[edge(o['b']['edge'])],positions,o['bDirection']);v,t,n=mod.maximum_squared_gap(a,b);upper=reported[i]['maximumGapUpperBoundMeters'];passed=F(upper)**2>=v
  if name.startswith('budget-') and 'eased' in o['intent']:
   fs=sorted(v['normalizedSeamFraction']for v in plan['anchors']if v['stitchIndex']==i);short=min(bdry[edge(o['a']['edge'])]['sourceLengthMeters'],bdry[edge(o['b']['edge'])]['sourceLengthMeters']);assert max((F(y)-F(x))*F(short)for x,y in zip(fs,fs[1:]))<=F(.06)
  seams.append({'stitchIndex':i,'sourceUnionKnotCount':n,'trueMaximumSquaredGap':str(v),'maximumAtTrueSeamFraction':str(t),'trueMaximumGapApprox':math.sqrt(float(v)),'runtimeUpperBound':upper,'runtimeUpperSquaredCoversExact':passed})
 rows.append({'case':name,'allSeamsUpperBounded':all(s['runtimeUpperSquaredCoversExact']for s in seams),'seams':seams,'runtimeFileSHA256':{str(f):sha(f)for f in [p,x,q]}})
result={'passed':all(r['allSeamsUpperBounded']for r in rows),'method':'Independent root exact Fraction curve/union/interpolation; compare rational square of actual runtime bound with exact squared maximum, not approximate sqrt comparison. Runtime JSONs are emitted after Swift typed decoding.','oracleFile':str(oracle),'oracleSHA256':sha(oracle),'cases':rows,'ownScriptSHA256':sha(Path(__file__))};dest.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'passed':result['passed'],'cases':[(r['case'],r['allSeamsUpperBounded'])for r in rows],'failedSeams':[(r['case'],s['stitchIndex'])for r in rows for s in r['seams']if not s['runtimeUpperSquaredCoversExact']]},indent=2))

raise SystemExit(0 if result["passed"] else 1)
