#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path)
p.add_argument('--package-source',type=Path,help='Explicit frozen native source, for independent source-P tests during other native work')
p.add_argument('--package-proof',type=Path,help='Reuse a verified, byte-identical Mac native package; rebuild only App Swift')
a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointNewton.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);snapshot=out/'source'
if snapshot.exists():raise SystemExit('Refusing to overwrite frozen source')
package_source=a.package_source.resolve() if a.package_source else repo/'NativeClothCollision'
shutil.copytree(package_source,snapshot,ignore=shutil.ignore_patterns('.build','.swiftpm'))
app=snapshot/'Sources/AppJointNewtonCheck';app.mkdir()
runner=(repo/'Tests/NativePattern/run-joint-input.sh').read_text()
names=re.search(r'for model in ([\s\S]*?); do',runner).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift']
assert len(names)==len(set(names))
for name in names:shutil.copy2(repo/'TrailorAss/Models'/name,app/name)
shutil.copy2(repo/'Tests/NativePattern/JointNewton.swift',app/'JointNewtonCheck.swift')
shutil.copy2(repo/'Tests/NativePattern/JointCoordinateControls.swift',app/'JointCoordinateControls.swift')
shutil.copy2(repo/'Tests/NativePattern/JointCoordinateCompetitionControls.swift',app/'JointCoordinateCompetitionControls.swift')
shutil.copy2(repo/'Tests/NativePattern/JointCoordinateCompetitionBoundaries.swift',app/'JointCoordinateCompetitionBoundaries.swift')
for directory in ['3d-hinge','3d-joint-body-r237']:shutil.copytree(repo/'Tests/NativePattern/Fixtures'/directory,snapshot/'AppFixtures'/directory)
proof=json.loads((snapshot/'AppFixtures/3d-joint-body-r237/manifest.json').read_text())
for name,sha in proof['files'].items():assert hashlib.sha256((snapshot/'AppFixtures/3d-joint-body-r237'/name).read_bytes()).hexdigest()==sha,name
for name,sha in proof['sharedInputs'].items():
 q=snapshot/name.removeprefix('NativeClothCollision/') if name.startswith('NativeClothCollision/') else repo/name
 assert hashlib.sha256(q.read_bytes()).hexdigest()==sha,name
manifest=snapshot/'Package.swift';text=manifest.read_text();needle='        .testTarget('
assert text.count(needle)==1
target='        .executableTarget(name: "AppJointNewtonCheck", dependencies: ["NativeClothCollision"], swiftSettings: [.unsafeFlags(["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"])]),\n'
manifest.write_text(text.replace(needle,target+needle))
inputs=[{'path':str(f.relative_to(snapshot)),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(snapshot.rglob('*')) if f.is_file()]
(out/'source-manifest.json').write_text(json.dumps({'scope':'Production source/body Newton single subproblem, not accepted garment','fixtureHashesVerified':True,'files':inputs},indent=2)+'\n')
env=dict(os.environ,SWIFTPM_MODULECACHE_OVERRIDE=str(out/'manifest-cache'),CLANG_MODULE_CACHE_PATH=str(out/'clang-cache'))
cmd=['swift','run','--disable-sandbox','--build-system','native','--package-path',str(snapshot),'--scratch-path',str(out/'build'),
 '--cache-path',str(out/'cache'),'--config-path',str(out/'config'),'--security-path',str(out/'security'),'-c','release','--jobs','2',
 'AppJointNewtonCheck',str(snapshot),str(out)]
commands=[cmd];dependencies=[]
if a.package_proof:
 package=a.package_proof.resolve();package_summary=json.loads((package/'summary.json').read_text())
 assert package_summary['passed'] and package_summary['macTestsExecuted']>=87,'Expected verified native package'
 def native_sources(directory,exclude=None):
  return {str(f.relative_to(directory)):hashlib.sha256(f.read_bytes()).hexdigest()
          for f in directory.rglob('*') if f.is_file() and f.relative_to(directory).parts[0]!=exclude}
 assert native_sources(package/'snapshot/Sources')==native_sources(snapshot/'Sources','AppJointNewtonCheck'), 'Native source paths/bytes differ from proof'
 lib=package/'swiftpm/arm64-apple-macosx/release'
 includes=[lib/'Modules',package/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
 binding_files=[lib/'libNativeClothCollision.a',package/'summary.json']
 for d in includes:
  assert d.is_dir(),str(d)
  binding_files += [f for f in d.rglob('*') if f.is_file() and f.suffix in {'.swiftmodule','.swiftdoc','.modulemap','.h'}]
 dependencies=[{'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}for f in binding_files]
 (out/'native-dependencies.json').write_text(json.dumps(dependencies,indent=2)+'\n')
 compile=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor',
          '-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
 for d in includes:compile += ['-I',str(d)]
 compile += [str(f) for f in sorted(app.glob('*.swift'))]+['-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(out/'joint-newton')]
 commands=[compile,[str(out/'joint-newton'),str(snapshot),str(out)]]
t=time.monotonic()
executed=[]
with (out/'joint-newton.log').open('w') as log:
 for command in commands:
  started=time.monotonic();r=subprocess.run(command,cwd=snapshot,env=env,stdout=log,stderr=subprocess.STDOUT)
  executed.append({'command':command,'exitCode':r.returncode,'seconds':time.monotonic()-started})
  if r.returncode:break
unchanged=all(hashlib.sha256((snapshot/i['path']).read_bytes()).hexdigest()==i['sha256'] for i in inputs)
native_unchanged=all(hashlib.sha256(Path(i['path']).read_bytes()).hexdigest()==i['sha256']for i in dependencies)
summary={'passed':r.returncode==0 and unchanged and native_unchanged,'exitCode':r.returncode,'snapshotUnchanged':unchanged,
 'nativeDependenciesUnchanged':native_unchanged,'nativePackageRecompiled':not bool(a.package_proof),
 'seconds':time.monotonic()-t,'commands':executed,'output':str(out),'scope':'Math subproblem only, no complete garment accepted'}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2));raise SystemExit(0 if summary['passed'] else 1)
