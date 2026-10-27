#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--package-source',type=Path);p.add_argument('--models-source',type=Path);p.add_argument('--steps',type=int,default=8);p.add_argument('--case',choices=['all','circle-straight-band','shirt-sleeved'],default='all');p.add_argument('--sewing-start',type=float);a=p.parse_args()
if not 1<=a.steps<=2400:raise SystemExit('steps must be 1..2400; this does not change the fixed 480/240 schedule')
repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointSimulation.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);snapshot=out/'source'
if snapshot.exists():raise SystemExit('Refusing to overwrite frozen source')
package=a.package_source.resolve() if a.package_source else repo/'NativeClothCollision'
shutil.copytree(package,snapshot,ignore=shutil.ignore_patterns('.build','.swiftpm'))
app=snapshot/'Sources/AppJointSimulationCheck';app.mkdir()
runner=(repo/'Tests/NativePattern/run-joint-input.sh').read_text();names=re.search(r'for model in ([\s\S]*?); do',runner).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift','GarmentCodeJointGarmentObjective.swift','GarmentCodeJointSimulation.swift']
assert len(names)==len(set(names))
models=a.models_source.resolve() if a.models_source else repo/'TrailorAss/Models'
for name in names:shutil.copy2(models/name,app/name)
shutil.copy2(repo/'Tests/NativePattern/JointSimulation.swift',app/'JointSimulationCheck.swift')
shutil.copytree(repo/'TrailorAss/Resources',snapshot/'TrailorAss/Resources')
manifest=snapshot/'Package.swift';text=manifest.read_text();needle='        .testTarget('
assert text.count(needle)==1
target='        .executableTarget(name: "AppJointSimulationCheck", dependencies: ["NativeClothCollision"], swiftSettings: [.unsafeFlags(["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"])]),\n'
manifest.write_text(text.replace(needle,target+needle))
inputs=[{'path':str(f.relative_to(snapshot)),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(snapshot.rglob('*')) if f.is_file()]
(out/'source-manifest.json').write_text(json.dumps({'scope':'Actual complete source joint stepping, no garment output','packageSource':str(package),'modelsSource':str(models),'files':inputs},indent=2)+'\n')
env=dict(os.environ,SWIFTPM_MODULECACHE_OVERRIDE=str(out/'manifest-cache'),CLANG_MODULE_CACHE_PATH=str(out/'clang-cache'))
cmd=['swift','run','--disable-sandbox','--build-system','native','--package-path',str(snapshot),'--scratch-path',str(out/'build'),
 '--cache-path',str(out/'cache'),'--config-path',str(out/'config'),'--security-path',str(out/'security'),'-c','release','--jobs','2',
 'AppJointSimulationCheck',str(snapshot),str(out),str(a.steps),a.case]
if a.sewing_start is not None:cmd.append(str(a.sewing_start))
t=time.monotonic()
with (out/'joint-simulation.log').open('w') as log:r=subprocess.run(cmd,cwd=snapshot,env=env,stdout=log,stderr=subprocess.STDOUT)
unchanged=all(hashlib.sha256((snapshot/i['path']).read_bytes()).hexdigest()==i['sha256'] for i in inputs)
d={'driverPassed':r.returncode==0 and unchanged,'exitCode':r.returncode,'snapshotUnchanged':unchanged,'seconds':time.monotonic()-t,'command':cmd,'requestedSteps':a.steps,'scope':'Full forces and complete body/self path; actual accepted/rejected step results are in case summaries','output':str(out)}
(out/'summary.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d,indent=2));raise SystemExit(0 if d['driverPassed'] else 1)
