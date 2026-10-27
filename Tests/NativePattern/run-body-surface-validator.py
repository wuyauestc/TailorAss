#!/usr/bin/env python3
"""Freeze real production models and test complete static surface validation.
No cloth/Newton or C++ compilation. Optional SDK clients link sealed Native129
for its read-only rounding bridge and compile every consumer Swift source.
"""
from pathlib import Path
import argparse,json,hashlib,shutil,subprocess,tempfile,time,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);p.add_argument('--native-proof',type=Path);a=p.parse_args();repo=Path(__file__).resolve().parents[2]
out=a.output.resolve()if a.output else Path(tempfile.mkdtemp(prefix='TailorAssBodySurfaceValidator-',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True);s=out/'snapshot';(s/'models').mkdir(parents=True)
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeClothMaterial','GarmentCodeClothContact','GarmentCodeBodySurfaceContact','GarmentCodeStandardBody','GarmentCodeCircleDrape','GarmentCodeBodySurfaceMeasurements','GarmentCodeBodyRig','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceValidator','GarmentCodeBodyMeshQueries','GarmentCodeBodySurfaceFitter','GarmentCodeFittedBody']
for name in models:shutil.copy2(repo/'TrailorAss/Models'/(name+'.swift'),s/'models'/(name+'.swift'))
for name in ['BodySurfaceValidator.swift','ValidateBodySurfaceValidator.py','ExactBodySurfaceGeometry.py','BoundNativeSDK.py','run-body-surface-validator.py']:shutil.copy2(repo/'Tests/NativePattern'/name,s/name)
shutil.copytree(repo/'TrailorAss/Resources',s/'resources');shutil.copytree(repo/'Tests/NativePattern/Fixtures/body-surface-validator',s/'fixtures')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();inputs={str(p):sha(p)for p in s.rglob('*')if p.is_file()};(out/'input-manifest.json').write_text(json.dumps(inputs,indent=2)+'\n')
sources=[s/'models'/(name+'.swift') for name in models];command=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]+list(map(str,sources))+[str(s/'BodySurfaceValidator.swift'),'-o',str(out/'checks')]
commands=[]
def run(label,cmd):
 start=time.monotonic()
 with(out/(label+'.log')).open('w')as log:r=subprocess.run(list(map(str,cmd)),stdout=log,stderr=subprocess.STDOUT)
 commands.append({'label':label,'command':list(map(str,cmd)),'exitCode':r.returncode,'seconds':time.monotonic()-start});(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');print(label,r.returncode,flush=True)
 return r.returncode==0
ok=run('strict-Mac-compile',command)
if ok:ok=run('analytic-and-six-actual',[out/'checks',s/'resources',s/'fixtures',out])
if ok:ok=run('independent-Fraction-oracle',[sys.executable,s/'ValidateBodySurfaceValidator.py',out,s/'ExactBodySurfaceGeometry.py'])
binding=None
if ok and a.native_proof:
 sys.path.insert(0,str(s));import BoundNativeSDK as sdk
 binding=sdk.prepare(a.native_proof,out);ok=binding['passed']
 smoke=out/'SDKClient.swift';smoke.write_text('import Foundation\n@main struct SurfaceClient {static func main()throws {let p=[GarmentCodeCircleDrape.Vector3(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:1,z:0)];let c=try GarmentCodeBodySurfaceValidator.validate(positions:p,triangleIndices:[0,1,2]);try c.verify(positions:p,triangleIndices:[0,1,2]);print(c.geometrySHA256,c.report.completedAllPairs)}}\n')
 for platform in ['ios','simulator-x86_64']:
  if ok:ok=run(platform+'-actual-Swift-final-link',sdk.link_command(a.native_proof,out,platform,sources,smoke))
 if ok:ok=sdk.verify_after(binding,out)
unchanged=all(sha(Path(p))==h for p,h in inputs.items());summary={'passed':ok and unchanged,'inputsUnchanged':unchanged,'models':models,'commands':commands,'nativeBinding':str(out/'native-sdk-binding.json')if binding else None,'nativeCPPCompiled':False,'clothSimulated':False,'bodyReceiptIssuedHere':False}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({'passed':summary['passed'],'output':str(out)}));raise SystemExit(0 if summary['passed']else 1)
