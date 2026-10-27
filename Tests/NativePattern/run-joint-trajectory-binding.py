#!/usr/bin/env python3
"""Pure certificate selection, real406 traces, and existing atomic S eight-step controls."""
from pathlib import Path
import argparse,gzip,hashlib,json,re,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);p.add_argument('--package-proof',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parents[2];o=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointTrajectoryBinding.',dir='/private/tmp'));o.mkdir(parents=True,exist_ok=True)
s=o/'source';(s/'models').mkdir(parents=True,exist_ok=False);sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
text=(r/'Tests/NativePattern/run-joint-input.sh').read_text();names=re.search(r'for model in ([\s\S]*?); do',text).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift','GarmentCodeJointGarmentObjective.swift','GarmentCodeJointSimulation.swift'];names=list(dict.fromkeys(names))
files=[r/'TrailorAss/Models'/n for n in names]+[r/'Tests/NativePattern/JointTrajectoryBinding.swift',r/'Tests/NativePattern/JointCoordinateCompetitionBoundaries.swift',r/'Tests/NativePattern/JointSimulation.swift',Path(__file__).resolve()]
before={str(f):sha(f) for f in files};manifest=[]
for f in files:
 q=s/'models'/f.name;shutil.copy2(f,q);manifest.append({'original':str(f),'snapshot':str(q.relative_to(s)),'sha256':sha(q)})
shutil.copytree(r/'TrailorAss/Resources',s/'TrailorAss/Resources')
fixture=r/'Tests/NativePattern/Fixtures/3d-joint-trajectory-binding';fm=json.loads((fixture/'manifest.json').read_text());payload=gzip.decompress((fixture/'actual-406-lines.json.gz').read_bytes());assert hashlib.sha256(payload).hexdigest()==fm['payloadSHA256'] and sha(fixture/'actual-406-lines.json.gz')==fm['gzipSHA256']
(s/'ActualTrajectoryBinding.json').write_bytes(payload);shutil.copy2(fixture/'manifest.json',s/'ActualTrajectoryBindingManifest.json')
# Only inject two focused calls into the already existing real-session driver;
# retain its complete preparation/8-step/cancellation/budget checks unchanged.
driver=s/'models/JointSimulation.swift';d=driver.read_text();needle='let root=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])';assert d.count(needle)==1
driver.write_text(d.replace(needle,needle+'\n        try JointTrajectoryBindingChecks.run(root:root,output:out)\n        try JointCoordinateCompetitionBoundaryChecks.run(output:out)'))
proof=a.package_proof.resolve();ps=json.loads((proof/'summary.json').read_text());assert ps['passed'] and ps['macTestsExecuted']>=117
lib=proof/'swiftpm/arm64-apple-macosx/release';includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
deps=[lib/'libNativeClothCollision.a',proof/'summary.json']
for folder in includes:deps += [p for p in folder.rglob('*') if p.is_file() and p.suffix in {'.swiftmodule','.swiftdoc','.modulemap','.h'}]
bindings={str(p):sha(p) for p in deps};snapshot={str(p.relative_to(s)):sha(p) for p in sorted(s.rglob('*')) if p.is_file()}
(o/'source-manifest.json').write_text(json.dumps({'frozenSource':snapshot,'originalSource':before,'nativeDependencies':bindings,'testDriverInjection':'Only two focused checks before unchanged existing Session eight-step driver'},indent=2)+'\n')
cmd=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(o/'module-cache')]
for folder in includes:cmd+=['-I',str(folder)]
cmd += [str(s/'models'/n) for n in names]+[str(s/'models'/n) for n in ['JointTrajectoryBinding.swift','JointCoordinateCompetitionBoundaries.swift','JointSimulation.swift']]+['-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(o/'joint-trajectory-binding')]
commands=[]
for label,command in [('compile-swift-only',cmd),('focused-and-real-eight-step-controls',[str(o/'joint-trajectory-binding'),str(s),str(o),'8','all'])]:
 t=time.monotonic()
 with (o/(label+'.log')).open('w') as f:run=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT)
 commands.append({'label':label,'command':command,'exitCode':run.returncode,'seconds':time.monotonic()-t});(o/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 if run.returncode:break
cases=[]
for name in ['circle-straight-band','shirt-sleeved']:
 p=o/name/'case-summary.json'
 if p.exists():cases.append(json.loads(p.read_text()))
unchanged=all(sha(s/p)==h for p,h in snapshot.items()) and all(sha(Path(p))==h for p,h in before.items()) and all(sha(Path(p))==h for p,h in bindings.items())
passed=run.returncode==0 and unchanged and len(cases)==2 and all(c['actualCompletedSteps']==8 and c['atomicCancellationVerified'] and c['atomicNewtonBudgetVerified'] and c['atomicPathBudgetVerified'] for c in cases)
summary={'passed':passed,'commands':commands,'allInputsUnchanged':unchanged,'cases':cases,'nativePackageRecompiled':False,'fullGarmentAccepted':False,'onlyRealSessionPrefixAdvanced':8}
(o/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k not in ['commands','cases']},indent=2));raise SystemExit(0 if passed else 1)
