#!/usr/bin/env python3
"""Run the exact production ViewModel with real workflow and cancellation."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,tempfile,time

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path)
p.add_argument('--package-proof',type=Path,required=True)
p.add_argument('--frozen-view-check',type=Path,help='Use the exact source of an earlier successful check-joint-drape-view output')
a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointDrapeLifecycle.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True)
source=out/'source';source.mkdir(exist_ok=False)
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
proof=a.package_proof.resolve()
native_summary=json.loads((proof/'summary.json').read_text())
assert native_summary['passed'] and native_summary['macTestsExecuted']>=91
def hashes(directory):
    return {str(f.relative_to(directory)):sha(f) for f in directory.rglob('*') if f.is_file()}
native_sources=hashes(proof/'snapshot/Sources')
delivery=None
if (proof/'delivery-manifest.json').exists():
    delivery=json.loads((proof/'delivery-manifest.json').read_text())
    assert delivery['nativeSources']==native_sources,'Compiled native Sources differ from snapshot'

if a.frozen_view_check:
    check=a.frozen_view_check.resolve()
    result=json.loads((check/'summary.json').read_text())
    assert result['passed'] and result['snapshotUnchanged']
    checked_manifest=json.loads((check/'source-manifest.json').read_text())
    entries=checked_manifest['files']
    assert all(sha(check/'source'/entry['snapshot'])==entry['sha256'] for entry in entries)
    if 'nativeSources' in checked_manifest:
        assert checked_manifest['nativeSources']==native_sources,'Frozen UI check used another Native source version'
    lifecycle_names=checked_manifest.get('lifecycleModels')
    inputs=[check/'source'/entry['snapshot'] for entry in entries
            if '/Models/' in entry['source'] and (lifecycle_names is None or entry['snapshot'] in lifecycle_names)]
    view=check/'source/GarmentCodeJointDrapeView.swift'
else:
    assert hashes(repo/'NativeClothCollision/Sources')==hashes(proof/'snapshot/Sources'),'Current native source differs from proof'
    shared=(repo/'Tests/NativePattern/run-joint-input.sh').read_text()
    names=re.search(r'for model in ([\s\S]*?); do',shared).group(1).replace('\\\n',' ').split()
    names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift',
            'GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift','GarmentCodeJointGarmentObjective.swift',
            'GarmentCodeJointSimulation.swift','GarmentCodeBodyMeshQueries.swift','GarmentCodeVisibleBodyInspection.swift',
            'GarmentCodeJointResult.swift','GarmentCodeJointFabric.swift','GarmentCodeJointWorkflow.swift',
            'GarmentCodeMeshExport.swift','GarmentCodeLocalization.swift','GarmentCodeJointParameters.swift']
    inputs=[repo/'TrailorAss/Models'/name for name in dict.fromkeys(names)]
    view=repo/'TrailorAss/Views/Garment/GarmentCodeJointDrapeView.swift'
inputs+=[view,repo/'Tests/NativePattern/JointDrapeLifecycle.swift',Path(__file__).resolve()]
before={str(path):sha(path) for path in inputs}
manifest=[]
for path in inputs:
    destination=source/path.name
    shutil.copy2(path,destination)
    manifest.append({'original':str(path),'snapshot':path.name,'sha256':sha(destination)})
assert all(sha(Path(path))==digest for path,digest in before.items()),'Source changed during copy'
resource_before=hashes(repo/'TrailorAss/Resources')
shutil.copytree(repo/'TrailorAss/Resources',source/'Resources')
assert hashes(source/'Resources')==resource_before and hashes(repo/'TrailorAss/Resources')==resource_before,'Resource changed during copy'
for path in (source/'Resources').rglob('*'):
    if path.is_file():manifest.append({'snapshot':str(path.relative_to(source)),'sha256':sha(path)})

text=(source/view.name).read_text()
start=text.index('@MainActor private final class GarmentCodeJointDrapeViewModel:ObservableObject {')
end=text.index('\nprivate extension View {',start)
model=text[start:end]
generated=source/'ActualViewModelLifecycle.swift'
generated.write_text('import Foundation\nimport Combine\n\n'+model+'\n'+(source/'JointDrapeLifecycle.swift').read_text())
manifest.append({'snapshot':generated.name,'sha256':sha(generated)})
lib=proof/'swiftpm/arm64-apple-macosx/release'
if delivery is not None:
    assert sha(lib/'libNativeClothCollision.a')==delivery['macArchiveSHA256'],'Native archive differs from compiled proof'
includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
dependencies=[lib/'libNativeClothCollision.a',proof/'summary.json']
for directory in includes:
    assert directory.is_dir(),directory
    dependencies += [f for f in directory.rglob('*') if f.is_file() and f.suffix in {'.swiftmodule','.swiftdoc','.modulemap','.h'}]
bindings=[{'path':str(path),'sha256':sha(path)} for path in dependencies]
capture={'files':manifest,'nativeDependencies':bindings,'nativeSources':native_sources,'resourceSHA256':resource_before,'viewModelExactSlice':{'originalSHA256':sha(source/view.name),'characterStart':start,'characterEnd':end,'sliceSHA256':hashlib.sha256(model.encode()).hexdigest()},'frozenViewCheck':str(a.frozen_view_check) if a.frozen_view_check else None}
(out/'source-manifest.json').write_text(json.dumps(capture,indent=2)+'\n')
command=['xcrun','swiftc','-O','-whole-module-optimization','-parse-as-library','-swift-version','5',
         '-default-isolation','MainActor','-strict-concurrency=complete','-enable-upcoming-feature','MemberImportVisibility',
         '-warnings-as-errors','-module-cache-path',str(out/'module-cache')]
for directory in includes:command+=['-I',str(directory)]
command += [str(source/path.name) for path in inputs if '/Models/' in str(path) or (a.frozen_view_check and path.suffix=='.swift' and path.name not in {view.name,'JointDrapeLifecycle.swift'})]
command += [str(generated),'-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(out/'joint-drape-lifecycle')]
commands=[]
for label,cmd in [('compile',command),('run',[str(out/'joint-drape-lifecycle'),str(source),str(out)])]:
    began=time.monotonic()
    with (out/(label+'.log')).open('w') as log:result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
    commands.append({'label':label,'command':cmd,'exitCode':result.returncode,'seconds':time.monotonic()-began})
    if result.returncode:break
unchanged=all(sha(source/entry['snapshot'])==entry['sha256'] for entry in manifest)
unchanged=unchanged and all(sha(Path(entry['path']))==entry['sha256'] for entry in bindings)
unchanged=unchanged and all(sha(Path(path))==digest for path,digest in before.items())
unchanged=unchanged and hashes(source/'Resources')==resource_before and hashes(repo/'TrailorAss/Resources')==resource_before
unchanged=unchanged and hashes(proof/'snapshot/Sources')==native_sources
report={'passed':result.returncode==0 and unchanged,'exitCode':result.returncode,'inputsUnchanged':unchanged,
        'commands':commands,'actualViewModelExtracted':True,'workflowMocked':False,'fakeValidatedConstructed':False,
        'uiRendered':False,'completeGarmentProduced':False}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='commands'}))
raise SystemExit(0 if report['passed'] else 1)
