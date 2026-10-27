#!/usr/bin/env python3
"""Freeze strict Swift controls and optional complete-source static replays."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, tempfile, time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--replay',type=Path,action='append',default=[]);a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssVisibleBodyInspection.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);source=out/'source'
if source.exists():raise SystemExit('Refusing to overwrite a frozen source')
source.mkdir()
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeClothMaterial',
 'GarmentCodeClothContact','GarmentCodeBodySurfaceContact','GarmentCodeStandardBody','GarmentCodeCircleDrape','GarmentCodeBodyMeshQueries','GarmentCodeVisibleBodyInspection','GarmentCodeBodyRig','GarmentCodeBodySurfaceMeasurements','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
inputs=[]
for name in models+['VisibleBodyInspection']:
 f=repo/('Tests/NativePattern' if name=='VisibleBodyInspection' else 'TrailorAss/Models')/(name+'.swift')
 dst=source/f.name;shutil.copy2(f,dst);inputs.append({'source':str(f),'snapshot':str(dst.relative_to(out)),'sha256':hashlib.sha256(dst.read_bytes()).hexdigest()})
for index,replay in enumerate(a.replay):
 directory=out/'replays'/(str(index)+'-'+replay.name);directory.mkdir(parents=True)
 state=replay/'last-accepted-state.json'
 if (replay/'uncommitted-candidate.json').exists():state=replay/'uncommitted-candidate.json'
 for f,name in [(replay/'complete-initial-input.json','complete-initial-input.json'),(state,'state.json')]:
  dst=directory/name;shutil.copy2(f,dst);inputs.append({'source':str(f),'snapshot':str(dst.relative_to(out)),'sha256':hashlib.sha256(dst.read_bytes()).hexdigest()})
(out/'source-manifest.json').write_text(json.dumps({'scope':'Independent static visible-body checks; no final garment','files':inputs},indent=2)+'\n')
cmd=['swiftc','-O','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(out/'module-cache')]
cmd += [str(source/(name+'.swift')) for name in models+['VisibleBodyInspection']]+['-o',str(out/'visible-body-inspection')]
t=time.monotonic();build=subprocess.run(cmd,capture_output=True,text=True);(out/'compile.log').write_text(build.stdout+build.stderr)
if build.returncode:print(build.stderr);raise SystemExit(build.returncode)
run=subprocess.run([str(out/'visible-body-inspection'),str(out)],capture_output=True,text=True);(out/'execution.log').write_text(run.stdout+run.stderr)
unchanged=all(hashlib.sha256((out/i['snapshot']).read_bytes()).hexdigest()==i['sha256'] for i in inputs)
summary={'passed':run.returncode==0 and unchanged,'exitCode':run.returncode,'snapshotUnchanged':unchanged,'seconds':time.monotonic()-t,'command':cmd,'output':str(out),'completeGarmentAccepted':False}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(run.stdout,run.stderr);print(json.dumps(summary,indent=2))
raise SystemExit(0 if summary['passed'] else 1)
