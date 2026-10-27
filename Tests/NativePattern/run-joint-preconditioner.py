#!/usr/bin/env python3
"""Isolated production-source test; thin Swift module is the real production Sparse API."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,tempfile,time
repo=Path(__file__).resolve().parents[2]
output=Path(os.environ.get('GARMENTCODE_JOINT_PRECONDITIONER_OUTPUT','/private/tmp/TailorAssJointPreconditioner'))
output.mkdir(parents=True,exist_ok=True);root=Path(tempfile.mkdtemp(prefix='TailorAssJointPreconditionerBuild.',dir='/private/tmp'));source=root/'source';(source/'Models').mkdir(parents=True)
models=['PatternDesignModels.swift','GarmentCodeGeometry.swift','GarmentCodePrograms.swift','GarmentCodeNativeGenerator.swift','GarmentCodeClothMaterial.swift','GarmentCodeClothContact.swift','GarmentCodeBodySurfaceContact.swift','GarmentCodeStandardBody.swift','GarmentCodeCircleDrape.swift','GarmentCodeSewing.swift','GarmentCodePanelMesher.swift','GarmentCodeMembrane.swift','GarmentCodeHingeBending.swift','GarmentCodeElasticEnergyDelta.swift','GarmentCodeElasticLinearization.swift','GarmentCodeJointObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeBodyRig.swift','GarmentCodeBodyMeshQueries.swift','GarmentCodeBodySurfaceMeasurements.swift','GarmentCodeFitDeformationReplay.swift','GarmentCodeBodySurfaceFitter.swift','GarmentCodeBodySurfaceValidator.swift','GarmentCodeFittedBody.swift']
for n in models:shutil.copy2(repo/'TrailorAss/Models'/n,source/'Models'/n)
shutil.copy2(repo/'Tests/NativePattern/JointPreconditioner.swift',source/'JointPreconditioner.swift')
for n in ['3d-hinge','3d-joint-preconditioner']:shutil.copytree(repo/'Tests/NativePattern/Fixtures'/n,source/'Fixtures'/n)
sparse=repo/'NativeClothCollision/Sources/CNativeClothSparse';shutil.copytree(sparse,source/'CNativeClothSparse')
shutil.copy2(repo/'NativeClothCollision/Sources/NativeClothCollision/NativeSparseCholesky.swift',source/'NativeSparseCholesky.swift')
(source/'CNativeClothSparse/module.modulemap').write_text('module CNativeClothSparse { header "include/NativeClothSparse.h" export * }\n')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for directory in ['3d-hinge','3d-joint-preconditioner']:
 manifest=json.loads((source/'Fixtures'/directory/'manifest.json').read_text())
 for name,digest in manifest['files'].items():assert sha(source/'Fixtures'/directory/name)==digest,name
(output/'build-input-manifest.json').write_text(json.dumps({'snapshotDirectory':str(source),'fixtureHashesVerified':True,'files':{str(p.relative_to(source)):sha(p) for p in sorted(source.rglob('*')) if p.is_file()}},indent=2))
commands=[]
def run(cmd,name):
 a=time.monotonic()
 with open(output/(name+'.log'),'w') as f:q=subprocess.run([str(x) for x in cmd],stdout=f,stderr=subprocess.STDOUT)
 commands.append({'command':[str(x) for x in cmd],'exitCode':q.returncode,'seconds':time.monotonic()-a})
 (output/'commands.json').write_text(json.dumps(commands,indent=2))
 if q.returncode:print((output/(name+'.log')).read_text());raise SystemExit(q.returncode)
cache=root/'module-cache';module=root/'module';module.mkdir()
run(['xcrun','clang++','-std=c++17','-O3','-Wall','-Wextra','-Werror','-I',source/'CNativeClothSparse/include','-c',source/'CNativeClothSparse/NativeClothSparse.cpp','-o',module/'Sparse.o'],'cpp')
run(['swiftc','-O','-swift-version','5','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',cache,'-I',source/'CNativeClothSparse','-emit-library','-static','-emit-module','-module-name','NativeClothCollision',source/'NativeSparseCholesky.swift',module/'Sparse.o','-o',module/'libNativeClothCollision.a','-emit-module-path',module/'NativeClothCollision.swiftmodule'],'module')
run(['swiftc','-O','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',cache,'-I',module,'-I',source/'CNativeClothSparse',*[source/'Models'/n for n in models],source/'JointPreconditioner.swift',module/'libNativeClothCollision.a','-framework','Accelerate','-lc++','-o',root/'joint-preconditioner'],'swift')
run([root/'joint-preconditioner',source/'Fixtures',output],'run')
print((output/'run.log').read_text());print('snapshot',source)
