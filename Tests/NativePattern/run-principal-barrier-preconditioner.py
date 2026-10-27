#!/usr/bin/env python3
"""Build current source-barrier PSD control; independently audit with NumPy."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,sys,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--package-proof',type=Path,required=True);p.add_argument('--package-source',type=Path)
p.add_argument('--oracle-python',type=Path,default=Path(sys.executable));a=p.parse_args();repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssBarrierPreconditioner.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True)
package=a.package_source.resolve() if a.package_source else repo/'NativeClothCollision'
source=out/'source';assert not source.exists(),'Refusing to overwrite frozen source';shutil.copytree(package,source,ignore=shutil.ignore_patterns('.build','.swiftpm'))
app=source/'Sources/AppBarrierPreconditioner';app.mkdir()
models=['PatternDesignModels.swift','GarmentCodeGeometry.swift','GarmentCodePrograms.swift','GarmentCodeNativeGenerator.swift','GarmentCodeClothMaterial.swift','GarmentCodeClothContact.swift','GarmentCodeBodySurfaceContact.swift','GarmentCodeStandardBody.swift','GarmentCodeCircleDrape.swift','GarmentCodeSewing.swift','GarmentCodePanelMesher.swift','GarmentCodeMembrane.swift','GarmentCodeHingeBending.swift','GarmentCodeElasticEnergyDelta.swift','GarmentCodeElasticLinearization.swift','GarmentCodeJointObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeBodyRig.swift','GarmentCodeBodyMeshQueries.swift','GarmentCodeBodySurfaceMeasurements.swift','GarmentCodeFitDeformationReplay.swift','GarmentCodeBodySurfaceFitter.swift','GarmentCodeBodySurfaceValidator.swift','GarmentCodeFittedBody.swift']
for n in models:shutil.copy2(repo/'TrailorAss/Models'/n,app/n)
shutil.copy2(repo/'Tests/NativePattern/PrincipalBarrierPreconditioner.swift',app/'PrincipalBarrierPreconditioner.swift')
shutil.copy2(repo/'Tests/NativePattern/CheckPrincipalBarrierPreconditioner.py',out/'independent-oracle.py')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
proof=a.package_proof.resolve();summary=json.loads((proof/'summary.json').read_text());assert summary['passed'] and summary['macTestsExecuted']>=91
def native_files(root,exclude=None):return {str(f.relative_to(root)):sha(f) for f in root.rglob('*') if f.is_file() and f.relative_to(root).parts[0]!=exclude}
assert native_files(proof/'snapshot/Sources')==native_files(source/'Sources','AppBarrierPreconditioner')
lib=proof/'swiftpm/arm64-apple-macosx/release';includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
dependencies=[lib/'libNativeClothCollision.a',proof/'summary.json']
for d in includes:dependencies += [f for f in d.rglob('*') if f.is_file() and f.suffix in {'.swiftmodule','.swiftdoc','.modulemap','.h'}]
native={str(f):sha(f) for f in dependencies};inputs={str(f.relative_to(source)):sha(f) for f in source.rglob('*') if f.is_file()}
(out/'input-manifest.json').write_text(json.dumps({'packageSource':str(package),'sourceFiles':inputs,'nativeDependencies':native,'oracleSHA256':sha(out/'independent-oracle.py'),'scope':'Pure P proxy; no true operator or garment acceptance'},indent=2)+'\n')
cmd=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
for d in includes:cmd += ['-I',str(d)]
cmd += [str(f) for f in sorted(app.glob('*.swift'))]+['-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(out/'barrier-preconditioner')]
commands=[cmd,[str(out/'barrier-preconditioner'),str(out)],[str(a.oracle_python),str(out/'independent-oracle.py'),str(out/'principal-barrier-preconditioner.json'),str(out/'independent-summary.json')]]
(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');results=[]
for index,c in enumerate(commands):
 t=time.monotonic()
 with (out/['compile.log','run.log','oracle.log'][index]).open('w') as log:r=subprocess.run(c,stdout=log,stderr=subprocess.STDOUT)
 results.append({'exitCode':r.returncode,'seconds':time.monotonic()-t})
 if r.returncode:break
unchanged=all(sha(source/n)==s for n,s in inputs.items()) and all(sha(Path(n))==s for n,s in native.items())
report={'passed':r.returncode==0 and unchanged,'inputsAndNativeDependenciesUnchanged':unchanged,'nativePackageRecompiled':False,'commands':results,'scope':'Source principal barrier PSD preconditioner; no nonlinear/physical garment acceptance'}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));raise SystemExit(0 if report['passed'] else 1)
