#!/usr/bin/env python3
"""Strict isolated opt-in draft fitter; no default body/pose/cloth route change."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse,hashlib,json,shutil,subprocess,tempfile,time,sys
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path);parser.add_argument('--fitter-source',type=Path);parser.add_argument('--python-packages',type=Path);parser.add_argument('--package-proof',type=Path,required=True,help='Sealed Native proof with SDK archives/FPU bridge; C++ is never rebuilt');a=parser.parse_args()
repo=Path(__file__).resolve().parents[2];out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssBodySurfaceFitter-',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);s=out/'snapshot';(s/'models').mkdir(parents=True,exist_ok=False);(s/'resources/GarmentCodeStandardBodyRig').mkdir(parents=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeClothMaterial','GarmentCodeClothContact','GarmentCodeBodySurfaceContact','GarmentCodeStandardBody','GarmentCodeCircleDrape','GarmentCodeBodySurfaceMeasurements','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodyRig','GarmentCodeBodyMeshQueries','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
files=[]
for name in models:
    source=a.fitter_source.resolve() if name=='GarmentCodeBodySurfaceFitter' and a.fitter_source else repo/'TrailorAss/Models'/(name+'.swift')
    files.append((source,s/'models'/(name+'.swift')))
for name in ['BodySurfaceFitter.swift','FitReplaySDKSmoke.swift','BoundNativeSDK.py','ValidateBodySurfaceFit.py','BodyLocalFitOracle.py','ExactBodySurfaceGeometry.py','run-body-surface-fitter.py']:
    files.append((repo/'Tests/NativePattern'/name,s/'models'/name))
for name in ['GarmentCodeParameterCatalog.json','GarmentCodeStandardBody.json','GarmentCodeStandardBodySDF.bin','GarmentCodeStandardBodySource.json','GarmentCodeBodySurfaceMeasurements.json','GarmentCodeBodyFitAuxiliaryWeights.json','GarmentCodeStandardBodyRig/rig.json']:
    files.append((repo/'TrailorAss/Resources'/name,s/'resources'/name))
files.append((repo/'Tests/NativePattern/Fixtures/female-standing-mesher-source.json',s/'female-standing-mesher-source.json'))
manifest=[]
for source,target in files:
    before=sha(source);shutil.copy2(source,target);assert before==sha(target)==sha(source)
    manifest.append({'original':str(source),'path':str(target.relative_to(s)),'sha256':before})
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
common=['-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors']
sources=[str(s/'models'/(name+'.swift')) for name in models]
jobs=[('strict-compile',['xcrun','swiftc','-O']+common+['-module-cache-path',str(out/'module-cache')]+sources+[str(s/'models/BodySurfaceFitter.swift'),'-o',str(out/'body-surface-fitter')])]
jobs.append(('actual-bodies-and-controls',[str(out/'body-surface-fitter'),str(s),str(out)]))
oracle=[sys.executable,str(s/'models/ValidateBodySurfaceFit.py'),str(out)]
if a.python_packages:oracle+=['--python-packages',str(a.python_packages.resolve())]
jobs.append(('independent-fields',oracle+['--phase','fields']))
sys.path.insert(0,str(s/'models'));import BoundNativeSDK as SDK
native=SDK.prepare(a.package_proof,out)
commands=list(native['results'])
def execute(label,command):
    started=time.monotonic()
    with (out/(label+'.log')).open('w') as log:process=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
    return {'label':label,'command':command,'exitCode':process.returncode,'seconds':time.monotonic()-started}
for label,command in jobs if native['passed'] else []:
    record=execute(label,command);commands.append(record);(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    if record['exitCode']:break
if all(row['exitCode']==0 for row in commands):
    with ThreadPoolExecutor(max_workers=2) as pool:
        links=[pool.submit(execute,'sdk-static-link-'+platform,SDK.link_command(a.package_proof,out,platform,sources,s/'models/FitReplaySDKSmoke.swift')) for platform in ['ios','simulator-x86_64']]
        commands.extend(f.result() for f in links)
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
if all(row['exitCode']==0 for row in commands):
    # Two independent read-only endpoint geometry audits; no cloth/Newton.
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(execute,'complete-static-'+name,oracle+['--phase','geometry','--profile',name]) for name in ['default','female']]
        commands.extend(f.result() for f in futures)
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
snapshot_unchanged=all(sha(s/f['path'])==f['sha256'] for f in manifest);original_unchanged=all(sha(Path(f['original']))==f['sha256'] for f in manifest)
native_unchanged=SDK.verify_after(native,out)
report={'passed':len(commands)==9 and all(row['exitCode']==0 for row in commands) and snapshot_unchanged and original_unchanged and native_unchanged,'commands':commands,
        'compiledModels':models,'snapshotUnchanged':snapshot_unchanged,'originalInputsUnchanged':original_unchanged,
        'bodyCapabilityIssued':False,'productionIntegrated':False,'nativeCPPRecompiled':False,'nativeSwiftModulesReemitted':True,'sealedNativeSDKArchivesLinked':True,'nativeBoundInputsUnchanged':native_unchanged,'deviceOrSimulatorLaunched':False,'clothSimulationRun':False,
        'scope':'Four project surface measurement types on two actual source profiles only; complete static endpoint audits do not certify a swept deformation or26 independent body fields.','output':str(out)}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
