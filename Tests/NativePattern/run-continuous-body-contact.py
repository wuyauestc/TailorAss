#!/usr/bin/env python3
"""Freeze the App bridge + actual local package and execute their SwiftPM link."""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssAppContinuousBody.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True)
snapshot=out/'source'
if snapshot.exists():raise SystemExit('Refusing to overwrite an existing frozen source')
shutil.copytree(repo/'NativeClothCollision',snapshot,ignore=shutil.ignore_patterns('.build','.swiftpm'))
app=snapshot/'Sources/AppContinuousBodyCheck';app.mkdir()
runner=(repo/'Tests/NativePattern/run-assembly-builder.sh').read_text()
models=re.findall(r'\$repo_dir/TrailorAss/Models/([A-Za-z0-9]+\.swift)',runner)
assert len(models)==len(set(models)) and 'GarmentCodeContinuousBodyContact.swift' in models
for name in models:shutil.copy2(repo/'TrailorAss/Models'/name,app/name)
shutil.copy2(repo/'Tests/NativePattern/ContinuousBodyContact.swift',app/'BridgeCheck.swift')
manifest=snapshot/'Package.swift'
original=manifest.read_text()
needle='        .testTarget('
assert original.count(needle)==1
manifest.write_text(original.replace(needle,'        .executableTarget(name: "AppContinuousBodyCheck", dependencies: ["NativeClothCollision"]),\n'+needle))
inputs=[{'path':str(f.relative_to(snapshot)),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
        for f in sorted(snapshot.rglob('*')) if f.is_file()]
(out/'source-manifest.json').write_text(json.dumps({'scope':'Frozen exact App models, real local native collision package and test driver; manifest adds only local executable target','files':inputs},indent=2)+'\n')
env=dict(os.environ,SWIFTPM_MODULECACHE_OVERRIDE=str(out/'manifest-cache'),CLANG_MODULE_CACHE_PATH=str(out/'clang-cache'))
cmd=['swift','run','--disable-sandbox','--build-system','native','--package-path',str(snapshot),'--scratch-path',str(out/'build'),
     '--cache-path',str(out/'cache'),'--config-path',str(out/'config'),'--security-path',str(out/'security'),'-c','release',
     '-Xswiftc','-warnings-as-errors','AppContinuousBodyCheck',
     str(snapshot/'Tests/NativeClothCollisionTests/Fixtures/upper-body-motion.json'),str(out/'real-app-body-path.json')]
t=time.monotonic()
with (out/'bridge-check.log').open('w') as log:r=subprocess.run(cmd,cwd=snapshot,env=env,stdout=log,stderr=subprocess.STDOUT)
unchanged=all(hashlib.sha256((snapshot/i['path']).read_bytes()).hexdigest()==i['sha256'] for i in inputs)
summary={'passed':r.returncode==0 and unchanged,'exitCode':r.returncode,'snapshotUnchanged':unchanged,'seconds':time.monotonic()-t,
         'scope':'Actual App Vector3 -> native continuous body path guard. No complete physical garment or cloth self CCD claimed.',
         'command':cmd,'output':str(out)}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2));raise SystemExit(0 if summary['passed'] else 1)
