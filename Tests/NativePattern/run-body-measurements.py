#!/usr/bin/env python3
"""Strict, isolated reference measurement proof; no cloth solver or App route."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile,time,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);a=p.parse_args()
r=Path(__file__).resolve().parents[2];out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssBodyMeasurements.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True)
s=out/'snapshot';(s/'models').mkdir(parents=True,exist_ok=False);(s/'resources').mkdir();sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeClothMaterial','GarmentCodeClothContact','GarmentCodeBodySurfaceContact','GarmentCodeStandardBody','GarmentCodeCircleDrape','GarmentCodeBodySections','GarmentCodeBodyMeasurements','GarmentCodeBodyRig','GarmentCodeBodyMeshQueries','GarmentCodeBodySurfaceMeasurements','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
files=[r/'TrailorAss/Models'/(n+'.swift') for n in models]+[r/'Tests/NativePattern/BodyMeasurements.swift',r/'Tests/NativePattern/ValidateBodyMeasurements.py',Path(__file__).resolve()]
manifest=[]
for f in files:
 q=s/'models'/f.name;shutil.copy2(f,q);manifest.append({'original':str(f),'path':str(q.relative_to(s)),'sha256':sha(q)})
for n in ['GarmentCodeParameterCatalog.json','GarmentCodeStandardBody.json','GarmentCodeStandardBodySDF.bin','GarmentCodeStandardBodySource.json']:
 f=r/'TrailorAss/Resources'/n;q=s/'resources'/n;shutil.copy2(f,q);manifest.append({'original':str(f),'path':str(q.relative_to(s)),'sha256':sha(q)})
f=r/'Tests/NativePattern/Fixtures/female-standing-mesher-source.json';q=s/f.name;shutil.copy2(f,q);manifest.append({'original':str(f),'path':str(q.relative_to(s)),'sha256':sha(q)})
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
cmd=['xcrun','swiftc','-O','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(out/'module-cache')]+[str(s/'models'/(n+'.swift')) for n in models]+[str(s/'models/BodyMeasurements.swift'),'-o',str(out/'body-measurements')]
commands=[]
for label,command in [('strict-compile',cmd),('focused-controls',[str(out/'body-measurements'),str(s),str(out)]),('independent-oracle',[sys.executable,str(s/'models/ValidateBodyMeasurements.py'),str(out)])]:
 t=time.monotonic()
 with (out/(label+'.log')).open('w') as f:result=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT)
 commands.append({'label':label,'command':command,'exitCode':result.returncode,'seconds':time.monotonic()-t});(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 if result.returncode:break
snapshot_unchanged=all(sha(s/f['path'])==f['sha256'] for f in manifest)
original_unchanged=all(sha(Path(f['original']))==f['sha256'] for f in manifest)
report={'passed':result.returncode==0 and snapshot_unchanged and original_unchanged,'commands':commands,'snapshotUnchanged':snapshot_unchanged,'originalInputsUnchanged':original_unchanged,'productionGeometryModified':False,'bodyFittingApplied':False,'clothSimulationRun':False,'output':str(out)}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
