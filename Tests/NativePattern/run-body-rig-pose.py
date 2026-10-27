#!/usr/bin/env python3
"""Isolated strict Release optional-rig/pose proof; never alters old resources."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);a=p.parse_args()
r=Path(__file__).resolve().parents[2];out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssBodyRigPose.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True)
s=out/'snapshot';(s/'models').mkdir(parents=True,exist_ok=False);(s/'resources').mkdir()
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeClothMaterial','GarmentCodeClothContact','GarmentCodeBodySurfaceContact','GarmentCodeStandardBody','GarmentCodeCircleDrape','GarmentCodeBodyMeshQueries','GarmentCodeBodyRig','GarmentCodeBodySurfaceMeasurements','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
files=[r/'TrailorAss/Models'/(n+'.swift')for n in models]+[r/'Tests/NativePattern/BodyRigPose.swift']
oracle=r/'Tests/NativePattern/Oracles/body_rig_pose.py'
shutil.copy2(oracle,s/'body_rig_pose_oracle.py')
manifest=[{'source':str(oracle),'snapshot':'body_rig_pose_oracle.py','sha256':hashlib.sha256(oracle.read_bytes()).hexdigest()}]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for f in files:
 q=s/'models'/f.name;shutil.copy2(f,q);manifest.append({'source':str(f),'snapshot':str(q.relative_to(s)),'sha256':sha(q)})
for n in ['GarmentCodeParameterCatalog.json','GarmentCodeStandardBody.json','GarmentCodeStandardBodySDF.bin','GarmentCodeStandardBodySource.json']:
 f=r/'TrailorAss/Resources'/n;q=s/'resources'/n;shutil.copy2(f,q);manifest.append({'source':str(f),'snapshot':str(q.relative_to(s)),'sha256':sha(q)})
for f in sorted((r/'TrailorAss/Resources/GarmentCodeStandardBodyRig').rglob('*')):
 if f.is_file():
  q=s/'resources/GarmentCodeStandardBodyRig'/f.name;q.parent.mkdir(exist_ok=True);shutil.copy2(f,q);manifest.append({'source':str(f),'snapshot':str(q.relative_to(s)),'sha256':sha(q)})
f=r/'Tests/NativePattern/Fixtures/female-standing-mesher-source.json';q=s/f.name;shutil.copy2(f,q);manifest.append({'source':str(f),'snapshot':str(q.relative_to(s)),'sha256':sha(q)})
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2))
cmd=['xcrun','swiftc','-O','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(out/'module-cache')]+[str(s/'models'/(n+'.swift'))for n in models]+[str(s/'models/BodyRigPose.swift'),'-o',str(out/'body-rig-pose')]
commands=[]
def run(cmd,label):
 t=time.monotonic();p=subprocess.run(cmd,capture_output=True,text=True);(out/(label+'.log')).write_text(p.stdout+p.stderr);commands.append({'command':cmd,'label':label,'exit':p.returncode,'seconds':time.monotonic()-t});(out/'commands.json').write_text(json.dumps(commands,indent=2))
 if p.returncode:print(p.stdout+p.stderr);raise SystemExit(p.returncode)
run(cmd,'compile');run([str(out/'body-rig-pose'),str(s),str(out)],'run')
run(['python3',str(s/'body_rig_pose_oracle.py'),'--snapshot',str(s),'--results',str(out)],'independent-all-vertex-oracle')
result=json.loads((out/'body-rig-pose-summary.json').read_text());result['independentAllVertexOracle']=json.loads((out/'independent-pose-oracle.json').read_text());result['snapshotUnchanged']=all(sha(s/x['snapshot'])==x['sha256']for x in manifest);result['oldResourcesUnchanged']=all(sha(Path(x['source']))==x['sha256']for x in manifest if '/Resources/'in x['source']);result['commands']=commands
(out/'summary.json').write_text(json.dumps(result,indent=2));print(json.dumps({'passed':result['passed'] and result['snapshotUnchanged'] and result['oldResourcesUnchanged'],'output':str(out),'poses':[{'profile':x['profile'],'alpha':x.get('alpha'),'allowed':x['allowed'],'self':x.get('statistics',{}).get('selfInspection',{}).get('intersectingTrianglePairs',x.get('selfCrossings')),'reasons':x.get('rejectionReasons',x.get('reasons'))}for x in result['profiles']]},indent=2))
