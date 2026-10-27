#!/usr/bin/env python3
"""True Swift/device+Simulator linkage, using an explicitly supplied frozen package build."""
import argparse,concurrent.futures,hashlib,json,shutil,subprocess,tempfile,time
from pathlib import Path
parser=argparse.ArgumentParser()
parser.add_argument("--package-artifacts",type=Path,required=True,help="output of NativeClothCollision/Scripts/run-checks.py (contains ios and simulator-x86_64)")
parser.add_argument("--output",type=Path)
a=parser.parse_args();r=Path(__file__).resolve().parents[2];package=a.package_artifacts.resolve()
d=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix="TailorAssBodyMeshPlatforms.",dir="/private/tmp"));d.mkdir(parents=True,exist_ok=True)
models=["PatternDesignModels","GarmentCodeGeometry","GarmentCodePrograms","GarmentCodeNativeGenerator","GarmentCodeClothMaterial","GarmentCodeClothContact","GarmentCodeBodySurfaceContact","GarmentCodeStandardBody","GarmentCodeCircleDrape","GarmentCodeBodyMeshQueries",'GarmentCodeBodyRig','GarmentCodeBodySurfaceMeasurements','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
manifest=[]
def record(p,snapshot=None):
 manifest.append({"path":str(p),"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),"bytes":p.stat().st_size,**({"snapshot":str(snapshot)} if snapshot else {})})
for name in models:
 p=r/"TrailorAss/Models"/(name+".swift");out=d/"source"/p.name;out.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,out);record(p,out)
smoke=r/"Tests/NativePattern/BodyMeshQueriesLinkSmoke.swift";shutil.copyfile(smoke,d/"source"/smoke.name);record(smoke,d/"source"/smoke.name)
for platform in ["ios","simulator-x86_64"]:
 for filename in ["libNativeClothCollision.a","NativeClothCollision.swiftmodule","CNativeClothCollision/module.modulemap","CIPCBodyContact/module.modulemap","CNativeClothSparse/module.modulemap"]:record(package/platform/filename)
for p in sorted((package/"snapshot/Sources").glob("*/include/*.h")):record(p)
for name in ["source-manifest.json","summary.json"]:
 if (package/name).exists():record(package/name)
(d/"source-manifest.json").write_text(json.dumps(manifest,indent=2))
def one(platform,sdkName,triple):
 out=d/platform;out.mkdir();lib=package/platform
 sdk=subprocess.check_output(["xcrun","--sdk",sdkName,"--show-sdk-path"],text=True).strip()
 cmd=["xcrun","swiftc","-O","-swift-version","5","-default-isolation","MainActor","-strict-concurrency=complete","-warnings-as-errors","-whole-module-optimization","-parse-as-library",
  "-target",triple,"-sdk",sdk,"-module-cache-path",str(out/"module-cache")]
 for name in ["CNativeClothCollision","CIPCBodyContact","CNativeClothSparse"]:cmd+=["-I",str(lib/name)]
 cmd+=["-I",str(lib),"-L",str(lib),"-lNativeClothCollision","-lc++","-framework","Accelerate"]
 cmd += [str(d/"source"/(name+".swift")) for name in models]+[str(d/"source"/smoke.name),"-o",str(out/"smoke")]
 t=time.time();p=subprocess.run(cmd,capture_output=True,text=True);(out/"compile-link.log").write_text(p.stdout+p.stderr)
 result={"platform":platform,"command":cmd,"exit":p.returncode,"seconds":time.time()-t}
 if p.returncode==0:
  v=subprocess.run(["xcrun","vtool","-show-build",str(out/"smoke")],capture_output=True,text=True);(out/"vtool.log").write_text(v.stdout+v.stderr)
  n=subprocess.run(["xcrun","nm",str(out/"smoke")],capture_output=True,text=True);(out/"nm.log").write_text(n.stdout+n.stderr)
  expected="IOS" if platform=="ios" else "IOSSIMULATOR"
  result.update({"vtoolExit":v.returncode,"nmExit":n.returncode,"expectedPlatformPresent":expected in v.stdout,
   "minimumIOS17Present":"minos 17.0" in v.stdout,"actualFloatingPointCBridgeLinked":"_ncc_floating_point_rounding_is_nearest" in n.stdout})
 return result
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 results=list(pool.map(lambda x:one(*x),[("ios","iphoneos","arm64-apple-ios17.0"),("simulator-x86_64","iphonesimulator","x86_64-apple-ios17.0-simulator")]))
unchanged=all(hashlib.sha256(Path(x["path"]).read_bytes()).hexdigest()==x["sha256"] for x in manifest)
summary={"passed":all(x["exit"]==0 and x.get("vtoolExit")==0 and x.get("nmExit")==0 and x.get("expectedPlatformPresent") and x.get("minimumIOS17Present") and x.get("actualFloatingPointCBridgeLinked") for x in results) and unchanged,
 "sourceAndPackageInputsUnchanged":unchanged,"packageArtifacts":str(package),"results":results}
(d/"summary.json").write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2));print(d)
raise SystemExit(0 if summary["passed"] else 1)

