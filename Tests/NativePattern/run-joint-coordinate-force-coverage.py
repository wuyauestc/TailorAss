#!/usr/bin/env python3
"""Analytical force/ULP selection controls; reuse a sealed Native archive, no C++ build."""
from pathlib import Path
import argparse,json,hashlib,re,shutil,subprocess,tempfile,time
parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path);parser.add_argument('--package-proof',type=Path,required=True);args=parser.parse_args()
repo=Path(__file__).resolve().parents[2];out=args.output.resolve()if args.output else Path(tempfile.mkdtemp(prefix='TailorAssCoordinateForceCoverage.',dir='/private/tmp'));out.mkdir(exist_ok=True,parents=True);source=out/'source';source.mkdir(exist_ok=False)
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
names=re.search(r'for model in ([\s\S]*?); do',(repo/'Tests/NativePattern/run-joint-input.sh').read_text()).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift'];assert len(names)==len(set(names))
original={str(Path('TrailorAss/Models')/n):sha(repo/'TrailorAss/Models'/n)for n in names}
for n in names:shutil.copyfile(repo/'TrailorAss/Models'/n,source/n)
shutil.copyfile(repo/'Tests/NativePattern/JointCoordinateForceCoverage.swift',source/'Checks.swift')
proof=args.package_proof.resolve();seal=json.loads((proof/'delivery-manifest.json').read_text());native=json.loads((proof/'summary.json').read_text());assert seal['passed']and native['passed']and native['macTestsExecuted']>=129
assert sha(proof/'summary.json')==seal['summarySHA256']
assert {str(f.relative_to(proof/'snapshot/Sources')):sha(f)for f in(proof/'snapshot/Sources').rglob('*')if f.is_file()}==seal['nativeSources']
lib=proof/'swiftpm/arm64-apple-macosx/release';assert sha(lib/'libNativeClothCollision.a')==seal['macArchiveSHA256']
includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
bindings={str(q):sha(q)for q in[lib/'libNativeClothCollision.a',proof/'summary.json',proof/'delivery-manifest.json']}
for directory in includes:bindings.update({str(q):sha(q)for q in directory.rglob('*')if q.is_file()and q.suffix in['.swiftmodule','.swiftdoc','.h','.modulemap']})
inputs={str(f.relative_to(source)):sha(f)for f in source.glob('*.swift')};(out/'input-manifest.json').write_text(json.dumps({'sourceFiles':inputs,'originalModels':original,'nativeDependencies':bindings,'scope':'Analytical counterexample and eligibility/cap/tie/underflow/cancel controls. No Session, garment or new native build.'},indent=2)+'\n')
command=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
for q in includes:command+=['-I',str(q)]
command +=[str(f)for f in sorted(source.glob('*.swift'))]+['-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(out/'checks')]
commands=[]
for label,cmd in [('compile',command),('checks',[str(out/'checks'),str(out/'checks.json')])]:
 start=time.monotonic()
 with(out/(label+'.log')).open('w')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
 commands.append({'label':label,'command':cmd,'exitCode':r.returncode,'seconds':time.monotonic()-start})
 if r.returncode:break
unchanged=all(sha(source/n)==v for n,v in inputs.items())and all(sha(repo/n)==v for n,v in original.items())and all(sha(Path(n))==v for n,v in bindings.items())
summary={'passed':len(commands)==2 and all(c['exitCode']==0 for c in commands)and unchanged and json.loads((out/'checks.json').read_text())['passed'],'sourceAndNativeUnchanged':unchanged,'nativePackageRecompiled':False,'nativeTestsProofReused':native['macTestsExecuted'],'commands':commands,'completeGarmentAccepted':False};(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items()if k!='commands'},indent=2));raise SystemExit(0 if summary['passed']else 1)
