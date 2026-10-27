#!/usr/bin/env python3
"""Swift-only real Shirt403 bounded regression; never resumes a full garment."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,tempfile,time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path)
parser.add_argument('--package-proof',type=Path,required=True)
args=parser.parse_args()
repo=Path(__file__).resolve().parents[2]
out=args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='TailorAssJointNewtonFallback.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);source=out/'source';source.mkdir(exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
script=(repo/'Tests/NativePattern/run-joint-input.sh').read_text()
names=re.search(r'for model in ([\s\S]*?); do',script).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift',
        'GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift','GarmentCodeJointGarmentObjective.swift',
        'GarmentCodeJointSimulation.swift','GarmentCodeJointParameters.swift','GarmentCodeLocalization.swift']
names=list(dict.fromkeys(names))
files=[Path('TrailorAss/Models')/name for name in names]
files += [Path('Tests/NativePattern/JointNewtonFallback.swift'),Path('Tests/NativePattern/run-joint-newton-fallback.py')]
fixture=Path('Tests/NativePattern/Fixtures/3d-joint-shirt403')
files += [p.relative_to(repo) for p in (repo/fixture).glob('*') if p.is_file()]
before={str(p):sha(repo/p) for p in files}
for p in files:
    copied=source/p;copied.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(repo/p,copied)
resources=source/'TrailorAss/Resources';shutil.copytree(repo/'TrailorAss/Resources',resources)
assert all(sha(repo/p)==before[str(p)]==sha(source/p) for p in files),'Source changed while freezing'
fixture_manifest=json.loads((source/fixture/'manifest.json').read_text())
for name,row in fixture_manifest['files'].items():assert sha(source/fixture/name)==row['sha256']
proof=args.package_proof.resolve();native=json.loads((proof/'summary.json').read_text())
assert native['passed'] and native['macTestsExecuted']>=105,'Expected frozen, fully tested self-Euclidean native package'
lib=proof/'swiftpm/arm64-apple-macosx/release'
includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
dependencies=[lib/'libNativeClothCollision.a',proof/'summary.json']
for directory in includes:
    assert directory.is_dir(),str(directory)
    dependencies += [p for p in directory.rglob('*') if p.is_file() and p.suffix in {'.swiftmodule','.swiftdoc','.modulemap','.h'}]
bindings={str(p):sha(p) for p in dependencies}
command=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor',
         '-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
for directory in includes:command += ['-I',str(directory)]
command += [str(source/'TrailorAss/Models'/name) for name in names]
command += [str(source/'Tests/NativePattern/JointNewtonFallback.swift'),'-L',str(lib),'-lNativeClothCollision','-lc++',
            '-framework','Accelerate','-o',str(out/'joint-newton-fallback')]
inputs={str(p.relative_to(source)):sha(p) for p in sorted(source.rglob('*')) if p.is_file()}
(out/'source-manifest.json').write_text(json.dumps({'scope':'Observer-free production solver, same real403 frame only; no complete garment',
    'files':inputs,'nativeDependencies':bindings,'nativePackageRecompiled':False},indent=2,sort_keys=True)+'\n')
commands=[]
for label,cmd in [('compile-swift-only',command),('actual-full-frame-and-controls',[str(out/'joint-newton-fallback'),str(source),str(out)])]:
    started=time.monotonic()
    with (out/(label+'.log')).open('w') as log:r=subprocess.run(cmd,cwd=source,stdout=log,stderr=subprocess.STDOUT)
    commands.append({'label':label,'command':cmd,'exitCode':r.returncode,'seconds':time.monotonic()-started})
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
    if r.returncode:break
unchanged=all(sha(source/p)==h for p,h in inputs.items()) and all(sha(repo/p)==h for p,h in before.items())
native_unchanged=all(sha(Path(p))==h for p,h in bindings.items())
results=json.loads((out/'fallback-regression.json').read_text()) if (out/'fallback-regression.json').exists() else None
summary={'passed':r.returncode==0 and unchanged and native_unchanged and results is not None and results['passed'],
         'sourceUnchanged':unchanged,'nativeDependenciesUnchanged':native_unchanged,'nativePackageRecompiled':False,
         'output':str(out),'commands':commands,'regression':results,'originalPhysicalFrameAccepted':False,'completeGarmentAccepted':False}
(out/'summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in {'commands','regression'}},indent=2))
raise SystemExit(0 if summary['passed'] else 1)
