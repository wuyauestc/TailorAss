#!/usr/bin/env python3
"""Freeze and verify project surface measurements with real production loaders."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile,time,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);p.add_argument('--render',action='store_true',help='Also render Chinese front/side PNGs; requires Pillow');a=p.parse_args()
r=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssBodySurfaceMeasurements-',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);s=out/'snapshot';(s/'models').mkdir(parents=True,exist_ok=False);(s/'resources/GarmentCodeStandardBodyRig').mkdir(parents=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeClothMaterial','GarmentCodeClothContact','GarmentCodeBodySurfaceContact','GarmentCodeStandardBody','GarmentCodeCircleDrape','GarmentCodeBodySurfaceMeasurements','GarmentCodeBodyRig','GarmentCodeBodyMeshQueries','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
files=[(r/'TrailorAss/Models'/(n+'.swift'),s/'models'/(n+'.swift')) for n in models]
files += [(r/'Tests/NativePattern'/n,s/'models'/n) for n in ['BodySurfaceMeasurements.swift','ValidateBodySurfaceMeasurements.py','RenderBodySurfaceMeasurements.py','PrepareBodySurfaceMeasurements.py','PrepareBodyRig.py','run-body-surface-measurements.py']]
for name in ['GarmentCodeParameterCatalog.json','GarmentCodeStandardBody.json','GarmentCodeStandardBodySDF.bin','GarmentCodeStandardBodySource.json','GarmentCodeBodySurfaceMeasurements.json','GarmentCodeStandardBodyRig/rig.json']:
    files.append((r/'TrailorAss/Resources'/name,s/'resources'/name))
files.append((r/'Tests/NativePattern/Fixtures/female-standing-mesher-source.json',s/'female-standing-mesher-source.json'))
manifest=[]
for f,q in files:
    before=sha(f);shutil.copy2(f,q);assert before==sha(q)==sha(f)
    manifest.append({'original':str(f),'path':str(q.relative_to(s)),'sha256':before})
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
cmd=['xcrun','swiftc','-O','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(out/'module-cache')]+[str(s/'models'/(n+'.swift')) for n in models]+[str(s/'models/BodySurfaceMeasurements.swift'),'-o',str(out/'body-surface-measurements')]
commands=[];jobs=[('strict-compile',cmd)]
for sdk,target,label in [('iphoneos','arm64-apple-ios17.0','ios17-arm64-typecheck'),('iphonesimulator','arm64-apple-ios17.0-simulator','ios17-simulator-arm64-typecheck')]:
    sdk_path=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
    jobs.append((label,['xcrun','swiftc','-typecheck','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-target',target,'-sdk',sdk_path,'-module-cache-path',str(out/label/'module-cache')]+[str(s/'models'/(n+'.swift')) for n in models]))
jobs.extend([('actual-load-and-controls',[str(out/'body-surface-measurements'),str(s),str(out)]),('independent-oracle',[sys.executable,str(s/'models/ValidateBodySurfaceMeasurements.py'),str(out)])])
if a.render:
    for name,title in [('default','默认人体'),('female','女性人体')]:
        jobs.append((name+'-render',[sys.executable,str(s/'models/RenderBodySurfaceMeasurements.py'),'--report',str(out/(name+'-surface-measurements.json')),'--output',str(out/(name+'-surface-measurements.png')),'--profile',title]))
for label,command in jobs:
    started=time.monotonic()
    with (out/(label+'.log')).open('w') as log:result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
    commands.append({'label':label,'command':command,'exitCode':result.returncode,'seconds':time.monotonic()-started});(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    if result.returncode:break
snapshot_unchanged=all(sha(s/f['path'])==f['sha256'] for f in manifest)
original_unchanged=all(sha(Path(f['original']))==f['sha256'] for f in manifest)
report={'passed':result.returncode==0 and snapshot_unchanged and original_unchanged,'commands':commands,'snapshotUnchanged':snapshot_unchanged,'originalInputsUnchanged':original_unchanged,'compiledModels':models,'nativeCompiledOrLinked':False,'productionGeometryModified':False,'bodyFittingApplied':False,'clothSimulationRun':False,'output':str(out)}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
