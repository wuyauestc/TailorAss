#!/usr/bin/env python3
"""Freeze the real package and App joint objective, then execute their link."""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--package-source',type=Path);a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointBody.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);snapshot=out/'source'
if snapshot.exists():raise SystemExit('Refusing to overwrite an existing frozen source')
package=a.package_source.resolve() if a.package_source else repo/'NativeClothCollision'
shutil.copytree(package,snapshot,ignore=shutil.ignore_patterns('.build','.swiftpm'))
app=snapshot/'Sources/AppJointBodyCheck';app.mkdir()
runner=(repo/'Tests/NativePattern/run-joint-input.sh').read_text()
names=re.search(r'for model in ([\s\S]*?); do',runner).group(1).replace('\\\n',' ').split()
names.append('GarmentCodeJointBodyObjective.swift')
assert len(names)==len(set(names))
for name in names:shutil.copy2(repo/'TrailorAss/Models'/name,app/name)
shutil.copy2(repo/'Tests/NativePattern/JointBodyObjective.swift',app/'JointBodyCheck.swift')
for directory in ['3d-joint-body-r237','3d-hinge']:
 shutil.copytree(repo/'Tests/NativePattern/Fixtures'/directory,snapshot/'AppFixtures'/directory)
fixture=snapshot/'AppFixtures/3d-joint-body-r237';proof=json.loads((fixture/'manifest.json').read_text())
for name,digest in proof['files'].items():assert hashlib.sha256((fixture/name).read_bytes()).hexdigest()==digest,name
for name,digest in proof['sharedInputs'].items():
 if name.startswith('NativeClothCollision/'):
  q=snapshot/name.removeprefix('NativeClothCollision/')
 else:q=repo/name
 assert hashlib.sha256(q.read_bytes()).hexdigest()==digest,name
manifest=snapshot/'Package.swift';original=manifest.read_text();needle='        .testTarget('
assert original.count(needle)==1
target='        .executableTarget(name: "AppJointBodyCheck", dependencies: ["NativeClothCollision"], swiftSettings: [.unsafeFlags(["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"])]),\n'
manifest.write_text(original.replace(needle,target+needle))
inputs=[{'path':str(f.relative_to(snapshot)),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(snapshot.rglob('*')) if f.is_file()]
(out/'source-manifest.json').write_text(json.dumps({'scope':'Exact App cloth/body objective + real local package, only added local executable target; no complete physical garment','packageSource':str(package),'fixtureHashesVerified':True,'files':inputs},indent=2)+'\n')
env=dict(os.environ,SWIFTPM_MODULECACHE_OVERRIDE=str(out/'manifest-cache'),CLANG_MODULE_CACHE_PATH=str(out/'clang-cache'))
cmd=['swift','run','--disable-sandbox','--build-system','native','--package-path',str(snapshot),'--scratch-path',str(out/'build'),
 '--cache-path',str(out/'cache'),'--config-path',str(out/'config'),'--security-path',str(out/'security'),'-c','release','--jobs','2',
 'AppJointBodyCheck',str(snapshot),str(out)]
started=time.monotonic()
with (out/'joint-body-check.log').open('w') as log:result=subprocess.run(cmd,cwd=snapshot,env=env,stdout=log,stderr=subprocess.STDOUT)
unchanged=all(hashlib.sha256((snapshot/i['path']).read_bytes()).hexdigest()==i['sha256'] for i in inputs)
summary={'passed':result.returncode==0 and unchanged,'exitCode':result.returncode,'snapshotUnchanged':unchanged,'seconds':time.monotonic()-started,
 'scope':'Actual App joint cloth/body force integration. No cloth self-contact, accepted237 or garment completeness claim.','command':cmd,'output':str(out)}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2));raise SystemExit(0 if summary['passed'] else 1)
