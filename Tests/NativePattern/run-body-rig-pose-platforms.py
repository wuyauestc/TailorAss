#!/usr/bin/env python3
"""True iOS17 device/x86 Simulator links of the optional Swift rig consumer."""
from pathlib import Path
import argparse,concurrent.futures,hashlib,json,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--package-proof',type=Path,default=Path('/private/tmp/TailorAssNativeContactCertificateIntegratedFirst'));a=p.parse_args()
r=Path(__file__).resolve().parents[2];o=a.output.resolve()if a.output else Path(tempfile.mkdtemp(prefix='TailorAssBodyRigPosePlatforms.',dir='/private/tmp'));o.mkdir(parents=True,exist_ok=True);s=o/'snapshot';s.mkdir(exist_ok=False)
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeClothMaterial','GarmentCodeClothContact','GarmentCodeBodySurfaceContact','GarmentCodeStandardBody','GarmentCodeCircleDrape','GarmentCodeBodyMeshQueries','GarmentCodeBodyRig','GarmentCodeBodySurfaceMeasurements','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
files=[r/'TrailorAss/Models'/(n+'.swift')for n in models]+[r/'Tests/NativePattern/BodyRigPoseLinkSmoke.swift'];manifest=[]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
for f in files:shutil.copy2(f,s/f.name);manifest.append({'source':str(f),'snapshot':f.name,'sha256':sha(f)})
(o/'source-manifest.json').write_text(json.dumps(manifest,indent=2))
def run(platform,sdk,target):
 d=o/platform;d.mkdir();deps=a.package_proof/platform
 modules=[deps/'CNativeClothCollision',deps/'CIPCBodyContact',deps/'CNativeClothSparse',deps]
 for q in modules:assert q.exists(),q
 sdkpath=subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip()
 cmd=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-target',target,'-sdk',sdkpath,'-module-cache-path',str(d/'module-cache')]
 for q in modules:cmd+=['-I',str(q)]
 cmd += [str(s/(n+'.swift'))for n in models]+[str(s/'BodyRigPoseLinkSmoke.swift'),'-L',str(deps),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(d/'BodyRigPoseSmoke')]
 t=time.monotonic();p=subprocess.run(cmd,capture_output=True,text=True);(d/'link.log').write_text(p.stdout+p.stderr)
 result={'platform':platform,'target':target,'command':cmd,'exit':p.returncode,'seconds':time.monotonic()-t}
 if p.returncode:return result
 for label,command in [('vtool',['xcrun','vtool','-show-build',str(d/'BodyRigPoseSmoke')]),('nm',['xcrun','nm',str(d/'BodyRigPoseSmoke')])]:
  p=subprocess.run(command,capture_output=True,text=True);(d/(label+'.log')).write_text(p.stdout+p.stderr);result[label+'Exit']=p.returncode
 assert 'minos 17.0' in (d/'vtool.log').read_text(),platform
 assert '_main' in (d/'nm.log').read_text(),platform
 result['binarySHA256']=sha(d/'BodyRigPoseSmoke');result['packageStaticLibrarySHA256']=sha(deps/'libNativeClothCollision.a')
 return result
with concurrent.futures.ThreadPoolExecutor(2)as pool:results=list(pool.map(lambda args:run(*args),[('ios','iphoneos','arm64-apple-ios17.0'),('simulator-x86_64','iphonesimulator','x86_64-apple-ios17.0-simulator')]))
summary={'passed':all(x['exit']==0 and x.get('vtoolExit')==0 and x.get('nmExit')==0 for x in results),'results':results,'snapshotUnchanged':all(sha(s/x['snapshot'])==x['sha256']for x in manifest),'packageProof':str(a.package_proof),'scope':'Actual final Swift iOS17 links only; no simulator/device launch or App route installed.'}
(o/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps({'passed':summary['passed'],'directory':str(o),'results':[{k:v for k,v in x.items()if k!='command'}for x in results]},indent=2));raise SystemExit(0 if summary['passed']else 1)
