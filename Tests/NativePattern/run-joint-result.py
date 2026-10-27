#!/usr/bin/env python3
"""Default: strict negative controls. --mode simulate: real sequential whole garment.

An exit code of zero means the driver completed its job. Only the independent
resultAccepted flag and validated artifacts mean final garment acceptance.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path);p.add_argument('--package-source',type=Path);p.add_argument('--models-source',type=Path)
p.add_argument('--package-proof',type=Path,help='Reuse a verified, byte-identical Mac native package; rebuild only App Swift')
p.add_argument('--mode',choices=['controls','simulate'],default='controls')
p.add_argument('--case',choices=['all','circle-straight-band','shirt-sleeved','source-pattern'],default='all')
p.add_argument('--pattern-json',type=Path,help='Complete native pattern with original body/design metadata; accepts any garment family through the same validator')
p.add_argument('--body-pose',choices=['legacyTemplate','matchPatternReference'],default='legacyTemplate')
p.add_argument('--body-shape',choices=['scaledTemplate','surfaceMeasurements'],default='scaledTemplate')
p.add_argument('--steps',type=int,default=2400,help='simulate only: bounded prefix; fixed 480/240 schedule is unchanged')
p.add_argument('--build-only',action='store_true',help='Freeze and compile; do not prepare or simulate any garment')
a=p.parse_args()
if a.body_shape=='surfaceMeasurements' and a.body_pose!='matchPatternReference':raise SystemExit('--body-shape surfaceMeasurements requires --body-pose matchPatternReference')
if not 1<=a.steps<=2400:raise SystemExit('--steps must be 1..2400; the original physical schedule is never shortened')
if a.pattern_json:
    if a.case not in {'all','source-pattern'}:raise SystemExit('--pattern-json cannot replace a named built-in case')
    if a.mode!='simulate' and not a.build_only:raise SystemExit('--pattern-json requires --mode simulate; negative controls use the named built-in scenes')
    a.case='source-pattern'
elif a.case=='source-pattern':raise SystemExit('--case source-pattern requires --pattern-json')
repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointResult.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);snapshot=out/'source'
if snapshot.exists():raise SystemExit('Refusing to overwrite frozen source')
package=a.package_source.resolve() if a.package_source else repo/'NativeClothCollision'
if package==out or package in out.parents:raise SystemExit('Output must be outside the package source')
def hashes(root):
    return {str(f.relative_to(root)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(root.rglob('*'))
            if f.is_file() and not any(x in {'.build','.swiftpm'} for x in f.relative_to(root).parts)}
package_before=hashes(package)
shutil.copytree(package,snapshot,ignore=shutil.ignore_patterns('.build','.swiftpm'))
if hashes(package)!=package_before or hashes(snapshot)!=package_before:
    raise SystemExit('Package changed during snapshot copy; no build or physics started')
app=snapshot/'Sources/AppJointResultDriver';app.mkdir()
runner=(repo/'Tests/NativePattern/run-joint-input.sh').read_text();names=re.search(r'for model in ([\s\S]*?); do',runner).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift','GarmentCodeJointGarmentObjective.swift','GarmentCodeJointSimulation.swift','GarmentCodeBodyMeshQueries.swift','GarmentCodeVisibleBodyInspection.swift','GarmentCodeJointResult.swift','GarmentCodeJointParameters.swift','GarmentCodeLocalization.swift']
names=list(dict.fromkeys(names))
models=a.models_source.resolve() if a.models_source else repo/'TrailorAss/Models'
models_before={name:hashlib.sha256((models/name).read_bytes()).hexdigest() for name in names}
for name in names:shutil.copy2(models/name,app/name)
if any(hashlib.sha256((models/name).read_bytes()).hexdigest()!=sha or hashlib.sha256((app/name).read_bytes()).hexdigest()!=sha for name,sha in models_before.items()):
    raise SystemExit('Models changed during snapshot copy; no build or physics started')
shutil.copy2(repo/'Tests/NativePattern/JointResult.swift',app/'JointResultCheck.swift')
shutil.copy2(repo/'Tests/NativePattern/JointPhysicalLeafValidationChecks.swift',app/'JointPhysicalLeafValidationChecks.swift')
resources=snapshot/'TrailorAss/Resources'
if not resources.exists():shutil.copytree(repo/'TrailorAss/Resources',resources)
pattern_input='-';pattern_metadata=None
if a.pattern_json:
    original=a.pattern_json.resolve();before_hash=hashlib.sha256(original.read_bytes()).hexdigest()
    copied=snapshot/'RequestedPattern.json';shutil.copy2(original,copied)
    if hashlib.sha256(original.read_bytes()).hexdigest()!=before_hash or hashlib.sha256(copied.read_bytes()).hexdigest()!=before_hash:
        raise SystemExit('Requested pattern changed during copy; no computation started')
    pattern_input=str(copied);pattern_metadata={'original':str(original),'sha256':before_hash,'snapshot':str(copied)}
manifest=snapshot/'Package.swift';text=manifest.read_text();needle='        .testTarget('
assert text.count(needle)==1
target='        .executableTarget(name: "AppJointResultDriver", dependencies: ["NativeClothCollision"], swiftSettings: [.unsafeFlags(["-swift-version", "5", "-default-isolation", "MainActor", "-strict-concurrency=complete", "-warnings-as-errors"])]),\n'
manifest.write_text(text.replace(needle,target+needle))
inputs=[{'path':str(f.relative_to(snapshot)),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(snapshot.rglob('*')) if f.is_file()]
(out/'source-manifest.json').write_text(json.dumps({'scope':'Real complete-source controls or sequential physical stepping; no synthetic stable state','mode':a.mode,'case':a.case,'requestedSteps':a.steps,'bodyPoseSelection':a.body_pose,'bodyShapeSelection':a.body_shape,'patternInput':pattern_metadata,'buildOnly':a.build_only,'packageSource':str(package),'modelsSource':str(models),'packageOriginalFiles':package_before,'modelOriginalFiles':models_before,'files':inputs},indent=2)+'\n')
env=dict(os.environ,SWIFTPM_MODULECACHE_OVERRIDE=str(out/'manifest-cache'),CLANG_MODULE_CACHE_PATH=str(out/'clang-cache'))
cmd=['swift','build' if a.build_only else 'run','--disable-sandbox','--build-system','native','--package-path',str(snapshot),'--scratch-path',str(out/'build'),
 '--cache-path',str(out/'cache'),'--config-path',str(out/'config'),'--security-path',str(out/'security'),'-c','release','--jobs','2']
cmd+=(['--product','AppJointResultDriver'] if a.build_only else ['AppJointResultDriver',str(snapshot),str(out),a.mode,a.case,str(a.steps),a.body_pose,pattern_input,a.body_shape])
commands=[cmd];dependencies=[]
if a.package_proof:
    proof=a.package_proof.resolve();native_summary=json.loads((proof/'summary.json').read_text())
    assert native_summary['passed'] and native_summary['macTestsExecuted']>=91,'Expected verified orientation-corrected native package'
    def native_sources(directory,exclude=None):
        return {str(f.relative_to(directory)):hashlib.sha256(f.read_bytes()).hexdigest()
                for f in directory.rglob('*') if f.is_file() and f.relative_to(directory).parts[0]!=exclude}
    assert native_sources(proof/'snapshot/Sources')==native_sources(snapshot/'Sources','AppJointResultDriver'),'Native source paths/bytes differ from proof'
    lib=proof/'swiftpm/arm64-apple-macosx/release'
    includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
    binding_files=[lib/'libNativeClothCollision.a',proof/'summary.json']
    for directory in includes:
        assert directory.is_dir(),str(directory)
        binding_files += [f for f in directory.rglob('*') if f.is_file() and f.suffix in {'.swiftmodule','.swiftdoc','.modulemap','.h'}]
    dependencies=[{'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in binding_files]
    (out/'native-dependencies.json').write_text(json.dumps(dependencies,indent=2)+'\n')
    compile=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor',
             '-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
    for directory in includes:compile += ['-I',str(directory)]
    compile += [str(f) for f in sorted(app.glob('*.swift'))]+['-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(out/'joint-result')]
    commands=[compile]
    if not a.build_only:commands.append([str(out/'joint-result'),str(snapshot),str(out),a.mode,a.case,str(a.steps),a.body_pose,pattern_input,a.body_shape])
t=time.monotonic();executed=[]
with (out/'joint-result.log').open('w') as log:
    for command in commands:
        started=time.monotonic();r=subprocess.run(command,cwd=snapshot,env=env,stdout=log,stderr=subprocess.STDOUT)
        executed.append({'command':command,'exitCode':r.returncode,'seconds':time.monotonic()-started})
        if r.returncode:break
unchanged=all(hashlib.sha256((snapshot/i['path']).read_bytes()).hexdigest()==i['sha256'] for i in inputs)
native_unchanged=all(hashlib.sha256(Path(i['path']).read_bytes()).hexdigest()==i['sha256'] for i in dependencies)
result_file=out/'simulation-results.json'
cases=json.loads(result_file.read_text()) if result_file.exists() else {}
accepted_cases=[name for name,row in cases.items() if row['resultAccepted']]
expected_cases={'circle-straight-band','shirt-sleeved'} if a.case=='all' else {a.case}
result_accepted=set(cases)==expected_cases and all(row['resultAccepted'] for row in cases.values())
d={'driverPassed':r.returncode==0 and unchanged and native_unchanged,'exitCode':r.returncode,'snapshotUnchanged':unchanged,
   'nativeDependenciesUnchanged':native_unchanged,'nativePackageRecompiled':not bool(a.package_proof),
   'seconds':time.monotonic()-t,'command':executed[-1]['command'],'commands':executed,'output':str(out),
   'mode':a.mode,'case':a.case,'requestedSteps':a.steps,'bodyPoseSelection':a.body_pose,'bodyShapeSelection':a.body_shape,'patternInput':pattern_metadata,'buildOnly':a.build_only,'resultAccepted':result_accepted,'acceptedCases':accepted_cases,
   'completeGarmentAccepted':result_accepted,'validatedPositiveBranchNotYetExercised':not accepted_cases,
   'meaningOfExitZero':'Driver completed; does not imply resultAccepted or physical garment acceptance'}
(out/'summary.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps(d,indent=2));raise SystemExit(0 if d['driverPassed'] else 1)
