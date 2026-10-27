#!/usr/bin/env python3
"""Bounded legacy922/480 diagnostics; no initial0 garment run or capability."""
from pathlib import Path
import argparse,json,hashlib,shutil,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--mode',choices=['all','seed923924','first481','depth2','cancel'],default='all');p.add_argument('--controls-source',type=Path,default=Path('/private/tmp/TailorAssJointSeedForestControls'));p.add_argument('--package-proof',type=Path,default=Path('/private/tmp/TailorAssFSCCriticalIntegratedSecond'));a=p.parse_args()
repo=Path(__file__).resolve().parents[2];out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);source=out/'source';proof=a.package_proof;cohort=a.controls_source
sha=lambda q:hashlib.sha256(q.read_bytes()).hexdigest()
assert json.loads((proof/'summary.json').read_text())['passed'] and json.loads((proof/'summary.json').read_text())['macTestsExecuted']==129
assert json.loads((cohort/'summary.json').read_text())['driverPassed']
old=json.loads((cohort/'source-manifest.json').read_text())['modelOriginalFiles'];shutil.copytree(proof/'snapshot',source);models=source/'Models';models.mkdir();model_hashes={}
for name,want in old.items():
 q=cohort/'source/Sources/AppJointResultDriver'/name;assert sha(q)==want,name;shutil.copyfile(q,models/name);model_hashes[name]=want
assert model_hashes['GarmentCodeJointSimulation.swift']=='d81b850aa36f726f4a62b8c984fa25d9cf326deaca0c195eaa101607b79c61d7'
assert model_hashes['GarmentCodeJointNewton.swift']=='2609fe9f134d9953e5e875080faf2692eb564d3ab563b4789f7d95889fd299e2'
assert model_hashes['GarmentCodeJointResult.swift']=='3359e3f357314b0c0c064320d42b58128e400fd812c2ebad4b303b9233a441e9'
resources=source/'TrailorAss/Resources';resources.parent.mkdir();shutil.copytree(cohort/'source/TrailorAss/Resources',resources)
fixture=source/'fixture';shutil.copytree(repo/'Tests/NativePattern/Fixtures/3d-joint-circle922-seed',fixture);fm=json.loads((fixture/'manifest.json').read_text())
for name,entry in fm['files'].items():assert sha(fixture/name)==entry['sha256'],name
# Original full archive seal stays a separately bound diagnostic origin; never a typed frame.
seal=Path(fm['originalFullRunSealPath']);assert sha(seal)==fm['originalFullRunSealSHA256']
original_seal=json.loads(seal.read_text())['filesSHA256']
for relative,want in fm['originalFileSHA256'].items():
 assert original_seal[relative]==want and sha(fixture/Path(relative).name)==want,relative
loader=(repo/'Tests/NativePattern/JointSeedForestLoader.swift.fragment').read_bytes();sim=models/'GarmentCodeJointSimulation.swift';production=sim.read_bytes();augmented=production+b'\n'+loader
if a.mode=='cancel':
 observer=(repo/'Tests/NativePattern/JointSeedForestCancellation.swift.fragment').read_bytes();needle=b'leaves.append(try leaf(value,previous,first,end))';assert production.count(needle)==1
 changed=production.replace(needle,needle+b'\n                        if first==6 && end==7 && denominator==8 {DiagnosticSeedCancellation.shared.trigger(leaves[leaves.count-1])}')
 augmented=changed+b'\n'+loader+b'\n'+observer
 (out/'observer-only.patch').write_text(''.join(__import__('difflib').unified_diff(production.decode().splitlines(True),changed.decode().splitlines(True),fromfile='S-production',tofile='S-observer-only')))
sim.write_bytes(augmented)
shutil.copyfile(repo/'Tests/NativePattern/JointSeedForest.swift',source/'Driver.swift')
lib=proof/'swiftpm/arm64-apple-macosx/release';includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build'];deps=[proof/'summary.json',proof/'delivery-manifest.json',lib/'libNativeClothCollision.a',cohort/'source-manifest.json',cohort/'delivery-manifest.json',seal]
for directory in includes:deps += [q for q in directory.rglob('*')if q.is_file() and q.suffix in ['.swiftmodule','.swiftdoc','.h','.modulemap']]
manifest={'scope':'Only bounded real legacy state diagnostics; no initial0/full garment qualification.','originalProductionModelsSHA256':model_hashes,'productionSPrefixSHA256':hashlib.sha256(production).hexdigest(),'testOnlyLoaderSHA256':hashlib.sha256(loader).hexdigest(),'nativeDependenciesSHA256':{str(q):sha(q)for q in deps},'sourceSnapshotFiles':{str(q.relative_to(source)):sha(q)for q in source.rglob('*')if q.is_file()}}
(out/'input-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
cmd=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
if a.mode=='cancel':cmd += ['-D','DIAGNOSTIC_SEED_CANCELLATION']
for q in includes:cmd += ['-I',str(q)]
cmd += [str(q)for q in sorted(models.glob('*.swift'))]+[str(source/'Driver.swift'),'-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(out/'joint-seed-forest')]
(out/'compile-command.json').write_text(json.dumps(cmd,indent=2)+'\n');start=time.monotonic()
with(out/'compile.log').open('w')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
print('COMPILE',r.returncode,time.monotonic()-start,flush=True)
if r.returncode: print((out/'compile.log').read_text()[-12000:]);raise SystemExit(r.returncode)
result={};modes=['seed923924','first481','depth2']if a.mode=='all'else[a.mode]
for mode in modes:
 d=out/mode;d.mkdir();cmd=[str(out/'joint-seed-forest'),str(source),str(fixture),str(d),mode];(d/'command.json').write_text(json.dumps(cmd,indent=2)+'\n');start=time.monotonic()
 with(d/'run.log').open('w')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
 result[mode]={'exitCode':r.returncode,'externalMonotonicSeconds':time.monotonic()-start,'numerical':json.loads((d/'mode-summary.json').read_text())if(d/'mode-summary.json').exists()else None};print('MODE_DONE',mode,r.returncode,flush=True)
 (out/'partial-summary.json').write_text(json.dumps(result,indent=2)+'\n')
 if r.returncode:print((d/'run.log').read_text()[-8000:]);break
unchanged=all(sha(source/n)==h for n,h in manifest['sourceSnapshotFiles'].items())and all(sha(Path(n))==h for n,h in manifest['nativeDependenciesSHA256'].items())
summary={'passed':len(result)==len(modes)and all(v['exitCode']==0 for v in result.values())and unchanged,'modes':result,'sourceAndNativeUnchanged':unchanged,'noCPPBuild':True,'noInitial0Run':True,'RValidatedProduced':False,'binarySHA256':sha(out/'joint-seed-forest')}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print('ALL_FOCUSED_DONE',summary['passed'],flush=True);raise SystemExit(0 if summary['passed']else 1)
