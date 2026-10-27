#!/usr/bin/env python3
"""Frozen new Frame/P schedule controls plus original three legacy P hashes.
Only the already-isolated real Sparse API is needed; unrelated Package work in
progress is deliberately not copied into this source matrix regression.
"""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,tempfile,time,argparse
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--model-source',type=Path);a=p.parse_args();repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssSewingSchedule.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True);source=out/'source'
if source.exists():raise SystemExit('Refusing to overwrite a source snapshot')
(source/'Models').mkdir(parents=True)
models=['PatternDesignModels.swift','GarmentCodeGeometry.swift','GarmentCodePrograms.swift','GarmentCodeNativeGenerator.swift','GarmentCodeClothMaterial.swift','GarmentCodeClothContact.swift','GarmentCodeBodySurfaceContact.swift','GarmentCodeStandardBody.swift','GarmentCodeCircleDrape.swift','GarmentCodeSewing.swift','GarmentCodePanelMesher.swift','GarmentCodeMembrane.swift','GarmentCodeHingeBending.swift','GarmentCodeElasticEnergyDelta.swift','GarmentCodeElasticLinearization.swift','GarmentCodeJointObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeBodyRig.swift','GarmentCodeBodyMeshQueries.swift','GarmentCodeBodySurfaceMeasurements.swift','GarmentCodeFitDeformationReplay.swift','GarmentCodeBodySurfaceFitter.swift','GarmentCodeBodySurfaceValidator.swift','GarmentCodeFittedBody.swift']
for name in models:shutil.copy2((a.model_source.resolve() if a.model_source else repo/'TrailorAss/Models')/name,source/'Models'/name)
shutil.copy2(repo/'Tests/NativePattern/JointSewingSchedule.swift',source/'JointSewingSchedule.swift')
legacy=repo/'Tests/NativePattern/JointPreconditioner.swift';text=legacy.read_text();needle='@main @MainActor struct JointPreconditionerRegression';assert needle in text
(source/'LegacyPreconditionerCheck.swift').write_text(text.replace(needle,'@MainActor struct LegacyJointPreconditionerRegression'))
for name in ['3d-hinge','3d-joint-preconditioner']:shutil.copytree(repo/'Tests/NativePattern/Fixtures'/name,source/'Fixtures'/name)
shutil.copytree(repo/'NativeClothCollision/Sources/CNativeClothSparse',source/'CNativeClothSparse')
shutil.copy2(repo/'NativeClothCollision/Sources/NativeClothCollision/NativeSparseCholesky.swift',source/'NativeSparseCholesky.swift')
(source/'CNativeClothSparse/module.modulemap').write_text('module CNativeClothSparse { header "include/NativeClothSparse.h" export * }\n')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for name in ['3d-hinge','3d-joint-preconditioner']:
 m=json.loads((source/'Fixtures'/name/'manifest.json').read_text())
 for f,s in m['files'].items():assert sha(source/'Fixtures'/name/f)==s,f
files={str(f.relative_to(source)):sha(f) for f in sorted(source.rglob('*')) if f.is_file()}
(out/'build-input-manifest.json').write_text(json.dumps({'scope':'New sewing schedule/P exact consistency; no physics or change to old CP proof','sourceSnapshot':str(source),'legacyHelperOriginalSHA256':sha(legacy),'legacyHelperOnlyMainTypeRenamed':True,'files':files},indent=2)+'\n')
commands=[]
def run(cmd,label):
 t=time.monotonic()
 with (out/(label+'.log')).open('w') as f:r=subprocess.run(list(map(str,cmd)),stdout=f,stderr=subprocess.STDOUT)
 commands.append({'label':label,'command':list(map(str,cmd)),'exitCode':r.returncode,'seconds':time.monotonic()-t});(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
 if r.returncode:raise SystemExit(r.returncode)
module=out/'module';module.mkdir();cache=out/'cache'
run(['xcrun','clang++','-std=c++17','-O3','-Wall','-Wextra','-Werror','-I',source/'CNativeClothSparse/include','-c',source/'CNativeClothSparse/NativeClothSparse.cpp','-o',module/'Sparse.o'],'cpp')
run(['swiftc','-O','-swift-version','5','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',cache,'-I',source/'CNativeClothSparse','-emit-library','-static','-emit-module','-module-name','NativeClothCollision',source/'NativeSparseCholesky.swift',module/'Sparse.o','-o',module/'libNativeClothCollision.a','-emit-module-path',module/'NativeClothCollision.swiftmodule'],'module')
run(['swiftc','-O','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',cache,'-I',module,'-I',source/'CNativeClothSparse',*[source/'Models'/n for n in models],source/'LegacyPreconditionerCheck.swift',source/'JointSewingSchedule.swift',module/'libNativeClothCollision.a','-framework','Accelerate','-lc++','-o',out/'sewing-schedule'],'swift')
run([out/'sewing-schedule',source/'Fixtures',out],'run')
# Independent arbitrary-precision intended quadratic Phi using the actual
# rounded candidate points and the original stored Double row coefficients.
# This is a test oracle only, never a tolerance in production Armijo/stopping.
from decimal import Decimal,localcontext
controls=json.loads((out/'sewing-schedule-summary.json').read_text())["finalDeltaControls"]
records=[]
for item in controls:
 estimates=[]
 for precision in [80,100]:
  with localcontext() as c:
   c.prec=precision;D=Decimal.from_float;k=D(float(item['k']));energy=[]
   for key in ['x','y']:
    e=Decimal(0)
    for row in item['rows']:
     q=[sum((D(float(w))*D(float(item[key][i][axis])) for i,w in zip(row['ids'],row['coefficients'])),Decimal(0)) for axis in range(3)]
     e+=k*sum((v*v for v in q),Decimal(0))/2
    energy.append(e)
   estimates.append(energy[1]-energy[0])
 reference=estimates[-1];assert reference!=0 and estimates[0].is_signed()==reference.is_signed()
 delta=Decimal.from_float(item['quadraticSewingDelta']);error=abs(delta-reference)/abs(reference)
 assert delta.is_signed()==reference.is_signed() and error<Decimal('1e-12')
 records.append({'initialK':item['initialK'],'oracle80':str(estimates[0]),'oracle100':str(reference),'quadraticDouble':item['quadraticSewingDelta'],'legacyRadialDouble':item['legacyRadialSewingDelta'],'relativeOracleError':str(error),'signMatches80and100':True})
(out/'quadratic-delta-oracle.json').write_text(json.dumps({'passed':True,'scope':'Resolvable actual-rounded-point quadratic increments; independent Decimal80/100. Not a production energy tolerance or universal sign proof.','results':records},indent=2)+'\n')
unchanged=all(sha(source/f)==s for f,s in files.items());report={'passed':unchanged,'sourceSnapshotUnchanged':unchanged,'commands':commands,'scope':'Default legacy source controls + exact new quadratic P consistency only; no physical solve'}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n');print('passed',unchanged,'output',out)
