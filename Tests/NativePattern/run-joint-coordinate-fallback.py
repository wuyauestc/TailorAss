#!/usr/bin/env python3
"""Swift-only real Shirt403/405/406/407 coordinate regressions; no full garment resume.

Default: --steps 403 405. Add 406 for the persisted tiny-normal-step starvation
regression. A diagnostic403 result is never called converged unless fresh KKT
actually passes. Native compilation is never performed by this runner.
"""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,tempfile,time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path)
parser.add_argument('--package-proof',type=Path,required=True,help='Sealed tested Native snapshot and matching Mac archive/modules')
parser.add_argument('--baseline-newton',type=Path,help='Optional exact prior N source, compiled as a separate diagnostic variant')
parser.add_argument('--steps',type=int,nargs='+',choices=[403,405,406,407],default=[403,405],help='Actual saved mathematical frames (default: 403 405)')
args=parser.parse_args()
if len(set(args.steps))!=len(args.steps):parser.error('--steps must not contain duplicates')
repo=Path(__file__).resolve().parents[2]
out=args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='TailorAssJointCoordinateFallback.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);source=out/'source';source.mkdir(exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
selection=Path('Tests/NativePattern/run-joint-input.sh')
script=(repo/selection).read_text()
names=re.search(r'for model in ([\s\S]*?); do',script).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift',
        'GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift','GarmentCodeJointGarmentObjective.swift',
        'GarmentCodeJointSimulation.swift','GarmentCodeJointParameters.swift','GarmentCodeLocalization.swift']
names=list(dict.fromkeys(names))
files=[Path('TrailorAss/Models')/name for name in names]
files += [Path('Tests/NativePattern/JointCoordinateFallback.swift'),Path('Tests/NativePattern/run-joint-coordinate-fallback.py'),selection]
fixtures=[Path('Tests/NativePattern/Fixtures')/f'3d-joint-shirt{s}' for s in args.steps]
for fixture in fixtures:files += [p.relative_to(repo) for p in sorted((repo/fixture).glob('*')) if p.is_file()]
files += [p.relative_to(repo) for p in sorted((repo/'TrailorAss/Resources').rglob('*')) if p.is_file()]
before={str(p):sha(repo/p) for p in files}
for p in files:
    copied=source/p;copied.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(repo/p,copied)
assert all(sha(repo/p)==before[str(p)]==sha(source/p) for p in files),'Source/resource changed while freezing'
for fixture in fixtures:
    fixture_manifest=json.loads((source/fixture/'manifest.json').read_text())
    assert fixture_manifest['files'],'Empty original fixture'
    for name,row in fixture_manifest['files'].items():
        path=source/fixture/name
        assert path.is_file() and sha(path)==row['sha256'] and path.stat().st_size==row['bytes'],str(path)

proof=args.package_proof.resolve();native=json.loads((proof/'summary.json').read_text())
seal=json.loads((proof/'delivery-manifest.json').read_text())
assert native['passed'] and native['macTestsExecuted']>=105 and seal['passed'],'Expected sealed tested native package'
assert sha(proof/'summary.json')==seal['summarySHA256']
assert sha(proof/'source-manifest.json')==seal['sourceManifestSHA256']
package_manifest=json.loads((proof/'source-manifest.json').read_text())
def native_sources():
    return {str(p.relative_to(proof/'snapshot/Sources')):sha(p) for p in sorted((proof/'snapshot/Sources').rglob('*')) if p.is_file()}
compiled_native=native_sources()
assert compiled_native==seal['nativeSources'],'Native complete Sources path set or bytes differ from sealed compilation'
assert all(package_manifest['Sources/'+name]==h for name,h in compiled_native.items())
package_sha=sha(proof/'snapshot/Package.swift')
assert package_manifest['Package.swift']==package_sha,'Native compiled Package.swift changed'
lib=proof/'swiftpm/arm64-apple-macosx/release'
archive=lib/'libNativeClothCollision.a'
assert sha(archive)==seal['macArchiveSHA256']
if native.get('macArchiveSHA256'):assert sha(archive)==native['macArchiveSHA256']
includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
dependencies=[archive,proof/'summary.json',proof/'delivery-manifest.json',proof/'source-manifest.json',proof/'snapshot/Package.swift']
for directory in includes:
    assert directory.is_dir(),str(directory)
    dependencies += [p for p in sorted(directory.rglob('*')) if p.is_file() and p.suffix in {'.swiftmodule','.swiftdoc','.swiftsourceinfo','.modulemap','.h'}]
bindings={str(p):sha(p) for p in dependencies}
command=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor',
         '-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
for directory in includes:command += ['-I',str(directory)]
command += [str(source/'TrailorAss/Models'/name) for name in names]
command += [str(source/'Tests/NativePattern/JointCoordinateFallback.swift'),'-L',str(lib),'-lNativeClothCollision','-lc++',
            '-framework','Accelerate','-o',str(out/'joint-coordinate-fallback')]
inputs={str(p.relative_to(source)):sha(p) for p in sorted(source.rglob('*')) if p.is_file()}
(out/'source-manifest.json').write_text(json.dumps({'scope':'Actual saved mathematical frames and true ordered path certificates; no Session or complete garment',
    'steps':args.steps,'files':inputs,'nativeDependencies':bindings,'nativeCompiledSources':compiled_native,
    'nativePackageSHA256':package_sha,'nativeProof':str(proof),'nativePackageRecompiled':False,
    'nativeScope':'Exact complete compiled Sources and Package.swift; archive/module/header binding. Does not claim noncompiled package documentation is unchanged.'},indent=2,sort_keys=True)+'\n')
commands=[];regressions={};variants=[('production',None)]
if args.baseline_newton:variants.insert(0,('priorN',args.baseline_newton.resolve()))
last_code=1
for variant,baseline in variants:
    binary=out/f'joint-coordinate-{variant}';sources=list(command);sources[-1]=str(binary)
    if not baseline:sources[2:2]=['-D','COUPLED_COORDINATE_PROPOSALS']
    if baseline:
        frozen=out/'prior-N.swift';shutil.copy2(baseline,frozen);assert sha(frozen)==sha(baseline)
        sources[sources.index(str(source/'TrailorAss/Models/GarmentCodeJointNewton.swift'))]=str(frozen)
        (out/'baseline-source.json').write_text(json.dumps({'original':str(baseline),'frozenSHA256':sha(frozen)},indent=2)+'\n')
    todo=[(f'{variant}-compile',sources)]
    for step in args.steps:
        case=out/variant/f'frame{step}';case.mkdir(parents=True,exist_ok=False)
        todo.append((f'{variant}-frame{step}',[str(binary),str(source),str(case),str(step),'baseline' if baseline else 'production']))
    for label,cmd in todo:
        started=time.monotonic()
        with (out/(label+'.log')).open('w') as log:r=subprocess.run(cmd,cwd=source,stdout=log,stderr=subprocess.STDOUT)
        last_code=r.returncode
        commands.append({'label':label,'command':cmd,'exitCode':last_code,'seconds':time.monotonic()-started})
        (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
        if last_code:break
    if last_code:break
    regressions[variant]={str(step):json.loads((out/variant/f'frame{step}'/'coordinate-regression.json').read_text()) for step in args.steps}
unchanged=all(sha(source/p)==h for p,h in inputs.items()) and all(sha(repo/p)==h for p,h in before.items())
native_unchanged=all(sha(Path(p))==h for p,h in bindings.items()) and native_sources()==compiled_native
subproblems=[{'step':int(step),'label':key,'status':row[key]['status'],'mathematicalSubproblemConverged':row[key]['mathematicalSubproblemConverged'],
              'freshGradientInfinityN':row[key]['freshGradientInfinityN']} for step,row in regressions.get('production',{}).items() for key in ['actualInner','wholeFrame']]
summary={'passed':last_code==0 and unchanged and native_unchanged and 'production' in regressions,
         'sourceUnchanged':unchanged,'nativeDependenciesUnchanged':native_unchanged,'nativePackageRecompiled':False,
         'nativeTestsProofReused':native['macTestsExecuted'],'steps':args.steps,'output':str(out),'commands':commands,'regressions':regressions,
         'actualSubproblems':subproblems,'allMathematicalSubproblemsConverged':bool(subproblems) and all(d['mathematicalSubproblemConverged'] for d in subproblems),
         'meaningOfPassed':'Fixture/source/binding/controls and required positive405/406/407 gates passed. Read actual403 status; passed is not blanket convergence or garment acceptance.',
         'originalPhysicalFrameAccepted':False,'completeGarmentAccepted':False}
(out/'summary.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n')
print(json.dumps({k:v for k,v in summary.items() if k not in {'commands','regressions'}},indent=2))
raise SystemExit(0 if summary['passed'] else 1)
