#!/usr/bin/env python3
"""Strict full-source fitted-body integration on workers; no cloth dynamics."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,os,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--package-proof',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[2];out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssFittedBodyAssembly.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True);s=out/'source';s.mkdir()
proof=a.package_proof.resolve();build=proof/'swiftpm/arm64-apple-macosx/release';package=proof/'snapshot'
runner=(r/'Tests/NativePattern/run-joint-input.sh').read_text();names=re.search(r'for model in ([\s\S]*?); do',runner).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointNewton.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointGarmentObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift'];names=list(dict.fromkeys(names))
models=s/'TrailorAss/Models';models.mkdir(parents=True)
before={n:hashlib.sha256((r/'TrailorAss/Models'/n).read_bytes()).hexdigest() for n in names}
for n in names:shutil.copy2(r/'TrailorAss/Models'/n,models/n)
assert all(hashlib.sha256((r/'TrailorAss/Models'/n).read_bytes()).hexdigest()==v and hashlib.sha256((models/n).read_bytes()).hexdigest()==v for n,v in before.items()),'Model source changed during snapshot'
shutil.copytree(r/'TrailorAss/Resources',s/'TrailorAss/Resources');tests=s/'Tests/NativePattern';tests.mkdir(parents=True);shutil.copytree(r/'Tests/NativePattern/Fixtures',tests/'Fixtures')
for n in ['FittedBodyAssembly.swift','NativeInitializationState.swift']:shutil.copy2(r/'Tests/NativePattern'/n,tests/n)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs={str(x.relative_to(s)):sha(x) for x in sorted(s.rglob('*')) if x.is_file()};(out/'source-manifest.json').write_text(json.dumps(inputs,indent=2)+'\n')
cmd=['xcrun','swiftc','-O','-whole-module-optimization','-parse-as-library','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(out/'module-cache'),'-I',str(build/'Modules'),'-Xcc','-fmodule-map-file='+str(package/'Sources/CNativeClothCollision/include/module.modulemap'),'-Xcc','-fmodule-map-file='+str(build/'CIPCBodyContact.build/module.modulemap'),'-Xcc','-fmodule-map-file='+str(build/'CNativeClothSparse.build/module.modulemap')]+[str(models/n) for n in names]+[str(tests/n) for n in ['FittedBodyAssembly.swift','NativeInitializationState.swift']]+[str(build/'libNativeClothCollision.a'),'-lc++','-framework','Accelerate','-o',str(out/'fitted-body-assembly')]
start=time.monotonic()
with (out/'compile.log').open('w') as f:c=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
if c.returncode:print('COMPILE FAIL',out);raise SystemExit(c.returncode)
with (out/'run.log').open('w') as f:c=subprocess.run([str(out/'fitted-body-assembly'),str(s),str(out)],stdout=f,stderr=subprocess.STDOUT)
summary={'passed':c.returncode==0,'exitCode':c.returncode,'sourceSnapshotUnchanged':all(sha(s/n)==v for n,v in inputs.items()),'nativeArchiveSHA256':sha(build/'libNativeClothCollision.a'),'seconds':time.monotonic()-start,'physicsRun':False,'compileCommand':cmd}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2));raise SystemExit(0 if summary['passed'] and summary['sourceSnapshotUnchanged'] else 1)
