#!/usr/bin/env python3
"""Isolated complete IPC native + production CP correctness regression."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--frozen-source',type=Path);p.add_argument('--package-source',type=Path)
p.add_argument('--package-proof',type=Path,help='Reuse a verified, byte-identical Mac native package; rebuild only App Swift')
a=p.parse_args();repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssContactPreconditioner.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True)
source=a.frozen_source.resolve() if a.frozen_source else out/'source'
models=['PatternDesignModels.swift','GarmentCodeGeometry.swift','GarmentCodePrograms.swift','GarmentCodeNativeGenerator.swift','GarmentCodeClothMaterial.swift','GarmentCodeClothContact.swift','GarmentCodeBodySurfaceContact.swift','GarmentCodeStandardBody.swift','GarmentCodeCircleDrape.swift','GarmentCodeSewing.swift','GarmentCodePanelMesher.swift','GarmentCodeMembrane.swift','GarmentCodeHingeBending.swift','GarmentCodeElasticEnergyDelta.swift','GarmentCodeElasticLinearization.swift','GarmentCodeJointObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift','GarmentCodeBodyRig.swift','GarmentCodeBodyMeshQueries.swift','GarmentCodeBodySurfaceMeasurements.swift','GarmentCodeFitDeformationReplay.swift','GarmentCodeBodySurfaceFitter.swift','GarmentCodeBodySurfaceValidator.swift','GarmentCodeFittedBody.swift']
if not a.frozen_source:
 if source.exists():raise SystemExit('Refusing to overwrite prior source')
 package=a.package_source.resolve() if a.package_source else repo/'NativeClothCollision'
 shutil.copytree(package,source,ignore=shutil.ignore_patterns('.build','.swiftpm'))
 app=source/'Sources/AppContactPreconditionerCheck';app.mkdir()
 for name in models:shutil.copy2(repo/'TrailorAss/Models'/name,app/name)
 shutil.copy2(repo/'Tests/NativePattern/JointContactPreconditioner.swift',app/'JointContactPreconditioner.swift')
 shutil.copytree(repo/'Tests/NativePattern/Fixtures/3d-contact-preconditioner',source/'AppFixtures/3d-contact-preconditioner')
app=source/'Sources/AppContactPreconditionerCheck';fixture=source/'AppFixtures/3d-contact-preconditioner';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((fixture/'manifest.json').read_text())
for name,digest in m['files'].items():assert sha(fixture/name)==digest,name
assert sha(fixture/'shirt-paper-source.json')==m['canonicalPaperSHA256']
for sub in ['IPCBodyContact','IPCClothContact','IPCOrientationIdentity']:
 base=source/'Tests/NativeClothCollisionTests/Fixtures'/sub;manifest=json.loads((base/'manifest.json').read_text())
 for name,digest in manifest['files'].items():assert sha(base/name)==digest,name
 for name,digest in manifest.get('sourceInputs',{}).items():assert sha(base.parent/name)==digest,name
package=source/'Package.swift';s=package.read_text();needle='        .testTarget('
assert s.count(needle)==1
if 'name: "AppContactPreconditionerCheck"' not in s:
 s=s.replace(needle,'        .executableTarget(name: "AppContactPreconditionerCheck", dependencies: ["NativeClothCollision"], swiftSettings: [.unsafeFlags(["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"])]),\n'+needle);package.write_text(s)
files={str(f.relative_to(source)):sha(f) for f in sorted(source.rglob('*')) if f.is_file()}
(out/'build-input-manifest.json').write_text(json.dumps({'scope':'CP correctness only, no nonlinear/dynamic garment acceptance','sourceSnapshot':str(source),'files':files,'nativeShirtSourceSHA256':m['canonicalPaperSHA256']},indent=2)+'\n')
env=dict(os.environ,SWIFTPM_MODULECACHE_OVERRIDE=str(out/'manifest-cache'),CLANG_MODULE_CACHE_PATH=str(out/'clang-cache'))
cmd=['swift','run','--disable-sandbox','--build-system','native','--package-path',str(source),'--scratch-path',str(out/'build'),'--cache-path',str(out/'cache'),'--config-path',str(out/'config'),'--security-path',str(out/'security'),'-c','release','--jobs','2','AppContactPreconditionerCheck',str(source),str(out)]
commands=[cmd];dependencies=[]
if a.package_proof:
 proof=a.package_proof.resolve();native_summary=json.loads((proof/'summary.json').read_text())
 assert native_summary['passed'] and native_summary['macTestsExecuted']>=91,'Expected verified orientation-corrected native package'
 def native_sources(directory,exclude=None):
  return {str(f.relative_to(directory)):sha(f) for f in directory.rglob('*')
          if f.is_file() and f.relative_to(directory).parts[0]!=exclude}
 assert native_sources(proof/'snapshot/Sources')==native_sources(source/'Sources','AppContactPreconditionerCheck'),'Native source paths/bytes differ from proof'
 corrected='Tests/NativeClothCollisionTests/Fixtures/IPCOrientationIdentity'
 assert native_sources(proof/'snapshot'/corrected)==native_sources(source/corrected),'Corrected independent oracle differs from verified package'
 lib=proof/'swiftpm/arm64-apple-macosx/release'
 includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
 binding_files=[lib/'libNativeClothCollision.a',proof/'summary.json']
 for directory in includes:
  assert directory.is_dir(),str(directory)
  binding_files += [f for f in directory.rglob('*') if f.is_file() and f.suffix in {'.swiftmodule','.swiftdoc','.modulemap','.h'}]
 dependencies=[{'path':str(f),'sha256':sha(f)} for f in binding_files]
 (out/'native-dependencies.json').write_text(json.dumps(dependencies,indent=2)+'\n')
 compile=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor',
          '-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
 for directory in includes:compile += ['-I',str(directory)]
 compile += [str(f) for f in sorted(app.glob('*.swift'))]+['-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(out/'contact-preconditioner')]
 commands=[compile,[str(out/'contact-preconditioner'),str(source),str(out)]]
t=time.monotonic();executed=[]
with (out/'contact-preconditioner.log').open('w') as log:
 for command in commands:
  started=time.monotonic();r=subprocess.run(command,env=env,cwd=source,stdout=log,stderr=subprocess.STDOUT)
  executed.append({'command':command,'exitCode':r.returncode,'seconds':time.monotonic()-started})
  if r.returncode:break
unchanged=all(sha(source/f)==digest for f,digest in files.items())
native_unchanged=all(sha(Path(i['path']))==i['sha256'] for i in dependencies)
report={'passed':r.returncode==0 and unchanged and native_unchanged,'exitCode':r.returncode,'sourceSnapshotUnchanged':unchanged,
        'nativeDependenciesUnchanged':native_unchanged,'nativePackageRecompiled':not bool(a.package_proof),
        'seconds':time.monotonic()-t,'commands':executed,'output':str(out),'scope':'CP correctness only, no nonlinear/dynamic garment acceptance'}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['passed','exitCode','sourceSnapshotUnchanged','nativeDependenciesUnchanged','nativePackageRecompiled','seconds','output']},indent=2))
raise SystemExit(0 if report['passed'] else 1)
