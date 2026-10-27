#!/usr/bin/env python3
"""Strict factory/constitutive proof; link frozen native package, rebuild no C++."""
from pathlib import Path
import argparse,hashlib,json,re,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--package-proof',type=Path,default=Path('/private/tmp/TailorAssNativeContactCertificateIntegratedFirst'));a=p.parse_args()
r=Path(__file__).resolve().parents[2];o=a.output.resolve()if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointFabric.',dir='/private/tmp'));o.mkdir(parents=True,exist_ok=True);s=o/'snapshot';s.mkdir(exist_ok=False)
base=(r/'Tests/NativePattern/run-joint-input.sh').read_text();names=re.search(r'for model in ([\s\S]*?); do',base).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift','GarmentCodeJointGarmentObjective.swift','GarmentCodeJointSimulation.swift','GarmentCodeJointFabric.swift']
assert len(names)==len(set(names))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
files=[r/'TrailorAss/Models'/n for n in names]+[r/'Tests/NativePattern/JointFabric.swift',r/'Tests/NativePattern/JointSimulation.swift',r/'Tests/NativePattern/run-joint-input.sh']
before={str(p):sha(p)for p in files};manifest=[]
for p in files:
 q=s/p.name;shutil.copy2(p,q);manifest.append({'source':str(p),'snapshot':q.name,'sha256':sha(q)})
assert all(sha(Path(p))==h for p,h in before.items()),'Dependencies changed during snapshot; retry from a coherent checkpoint'
fixture=r/'Tests/NativePattern/Fixtures/3d-hinge';fm=json.loads((fixture/'manifest.json').read_text())
for n in ['native-source-topology.json','manifest.json']:
 p=fixture/n;q=s/n;shutil.copy2(p,q);manifest.append({'source':str(p),'snapshot':q.name,'sha256':sha(q)})
assert sha(s/'native-source-topology.json')==fm['files']['native-source-topology.json']
# Reuse the exact current regression-control expression, not a second material table.
control=(s/'JointSimulation.swift').read_text();start=control.index('T.Materials(',control.index('let materials='));i=start+len('T.Materials');depth=0
for end in range(i,len(control)):
 c=control[end]
 if c=='(':depth+=1
 elif c==')':
  depth-=1
  if depth==0:break
expr=control[start:end+1]
settings=re.search(r'            var settings=T.K.Settings\(\);[\s\S]*?settings.bodyResourceDirectory=root.appendingPathComponent\("TrailorAss/Resources"\)',control).group(0).replace('root.appendingPathComponent("TrailorAss/Resources")','bodyResourceDirectory')
generated='import Foundation\n@MainActor func baselineJointMaterials()throws->GarmentCodeJointSimulation.Materials {\n typealias T=GarmentCodeJointSimulation\n return '+expr+'\n}\n@MainActor func baselineJointSourceSettings(bodyResourceDirectory:URL)->GarmentCodeJointSimulation.K.Settings {\n typealias T=GarmentCodeJointSimulation\n'+settings+'\n return settings\n}\n'
(s/'BaselineMaterials.swift').write_text(generated);manifest.append({'source':'generated exact current JointSimulation.swift baseline expressions','snapshot':'BaselineMaterials.swift','sha256':sha(s/'BaselineMaterials.swift')})
package=a.package_proof.resolve();lib=package/'swiftpm/arm64-apple-macosx/release';deps=[lib/'Modules',package/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build']
for q in deps:assert q.exists(),q
packageBindings={'proof':str(package),'nativeStaticLibrarySHA256':sha(lib/'libNativeClothCollision.a'),'packageSummarySHA256':sha(package/'summary.json')}
(o/'source-manifest.json').write_text(json.dumps({'files':manifest,'package':packageBindings},indent=2))
cmd=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(o/'module-cache')]
for d in deps:cmd+=['-I',str(d)]
cmd += [str(s/n)for n in names]+[str(s/'BaselineMaterials.swift'),str(s/'JointFabric.swift'),'-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(o/'joint-fabric')]
commands=[]
def run(cmd,label):
 t=time.monotonic();p=subprocess.run(cmd,capture_output=True,text=True);(o/(label+'.log')).write_text(p.stdout+p.stderr);commands.append({'label':label,'command':cmd,'exit':p.returncode,'seconds':time.monotonic()-t});(o/'commands.json').write_text(json.dumps(commands,indent=2))
 if p.returncode:print(p.stdout+p.stderr);print(o);raise SystemExit(p.returncode)
run(cmd,'compile-swift-only');run([str(o/'joint-fabric'),str(s),str(o)],'actual-constitutive-tests')
result=json.loads((o/'joint-fabric-summary.json').read_text());result['snapshotUnchanged']=all(sha(s/x['snapshot'])==x['sha256']for x in manifest);result['commands']=commands;result['packageRecompiled']=False;result['packageBindings']=packageBindings
(o/'summary.json').write_text(json.dumps(result,indent=2));print(json.dumps({'passed':result['passed'] and result['snapshotUnchanged'],'output':str(o),'rows':result['rows'],'nativePackageRecompiled':False},indent=2))
