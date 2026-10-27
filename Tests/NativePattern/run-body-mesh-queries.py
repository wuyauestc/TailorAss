#!/usr/bin/env python3
"""Snapshot all inputs before a strict Release compile. No installation/App run."""
import hashlib,json,os,shutil,subprocess,tempfile,sys,struct
from pathlib import Path
r=Path(__file__).resolve().parents[2]
d=Path(os.environ["BODY_MESH_QUERIES_PROOF"]) if "BODY_MESH_QUERIES_PROOF" in os.environ else Path(tempfile.mkdtemp(prefix="TailorAssBodyMeshQueries.",dir="/private/tmp"))
d.mkdir(parents=True,exist_ok=True)
models=["PatternDesignModels","GarmentCodeGeometry","GarmentCodePrograms","GarmentCodeNativeGenerator","GarmentCodeClothMaterial","GarmentCodeClothContact","GarmentCodeBodySurfaceContact","GarmentCodeStandardBody","GarmentCodeCircleDrape","GarmentCodeBodyMeshQueries",'GarmentCodeBodyRig','GarmentCodeBodySurfaceMeasurements','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
files=[r/"TrailorAss/Models"/(n+".swift") for n in models]+[r/"Tests/NativePattern/BodyMeshQueries.swift"]
files += [r/"TrailorAss/Resources"/name for name in ["GarmentCodeParameterCatalog.json","GarmentCodeStandardBody.json","GarmentCodeStandardBodySDF.bin","GarmentCodeStandardBodySource.json"]]
files += [r/"Tests/NativePattern/Fixtures/female-standing-mesher-source.json"]
files += [r/"Tests/NativePattern/Fixtures/body-mesh-queries-visible.json"]
manifest=[]
for p in files:
 out=d/("source/"+p.name if p.suffix==".swift" else ("resources/"+p.name if p.parent.name=="Resources" else p.name))
 out.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,out)
 manifest.append({"source":str(p),"snapshot":str(out.relative_to(d)),"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),"bytes":p.stat().st_size})
(d/"build-input-manifest.json").write_text(json.dumps(manifest,indent=2))
fixture=json.loads((d/"body-mesh-queries-visible.json").read_text())
for name,expected in fixture["resourceSHA256"].items():
 assert hashlib.sha256((d/"resources"/name).read_bytes()).hexdigest()==expected,name+" requires an explicit fixture/provenance update"
cmd=["swiftc","-O","-swift-version","5","-default-isolation","MainActor","-strict-concurrency=complete","-warnings-as-errors","-module-cache-path",str(d/"module-cache")]
cmd += [str(d/"source"/(n+".swift")) for n in models]+[str(d/"source/BodyMeshQueries.swift"),"-o",str(d/"body-mesh-queries")]
p=subprocess.run(cmd,capture_output=True,text=True);(d/"compile.log").write_text(p.stdout+p.stderr)
(d/"compile-result.json").write_text(json.dumps({"command":cmd,"exit":p.returncode},indent=2))
if p.returncode:print(p.stderr);print(d);sys.exit(p.returncode)
p=subprocess.run([str(d/"body-mesh-queries"),str(d)],capture_output=True,text=True)
(d/"execution.log").write_text(p.stdout+p.stderr);print(p.stdout,p.stderr)
if p.returncode:print(d);sys.exit(p.returncode)
summary=json.loads((d/"body-mesh-queries-summary.json").read_text())
# Canonical default visible binding is checked with Python binary serialization.
catalog=json.loads((d/"resources/GarmentCodeParameterCatalog.json").read_text())
asset=json.loads((d/"resources/GarmentCodeStandardBody.json").read_text());b=catalog["body"];bl=asset["baseline"]
ws=b["waist"]/100/bl["waist"];hs=b["hips"]/100/bl["hips"];hy=b["hips_line"]/100/bl["hipLine"]
wl=b["height"]-b["head_l"]-b["waist_line"]
ly=(wl-b["hips_line"])/100/(bl["waistLevel"]-bl["hipLine"]);uy=(b["height"]-wl)/100/(bl["height"]-bl["waistLevel"])
positions=[]
for x,y,z in asset["positions"]:
 t=max(0,min(1,(y+bl["hipLine"])/bl["hipLine"]));blend=t*t*(3-2*t);h=hs+(ws-hs)*blend
 yy=y*uy if y>=0 else (y*hy if y>=-bl["hipLine"] else -bl["hipLine"]*hy+(y+bl["hipLine"])*ly)
 positions.append((x*h,yy,z*h))
# Use the same documented raw/dependency operation order; pack independently.
defaultPayload=b"rigid-clearance-visible-body-v1\0"+struct.pack("<QQ",len(positions),len(asset["triangleIndices"]))
defaultPayload+=b"".join(struct.pack("<ddd",*p) for p in positions)+struct.pack("<"+str(len(asset["triangleIndices"]))+"I",*asset["triangleIndices"])
defaultHash=hashlib.sha256(defaultPayload).hexdigest()
assert defaultHash==summary["profiles"][0]["geometrySHA256"],"Swift mesh hash differs from exact Python input layout"
cube=[(-.5,-.5,-.5),(.5,-.5,-.5),(.5,.5,-.5),(-.5,.5,-.5),(-.5,-.5,.5),(.5,-.5,.5),(.5,.5,.5),(-.5,.5,.5)]
indices=[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]
payload=b"rigid-clearance-visible-body-v1\0"+struct.pack("<QQ",8,36)+b"".join(struct.pack("<ddd",*p) for p in cube)+struct.pack("<36I",*indices)
summary["independentPythonCubeSHA256"]=hashlib.sha256(payload).hexdigest()
assert summary["independentPythonCubeSHA256"]==summary["analyticCubeGeometrySHA256"]
summary["independentPythonDefaultGeometrySHA256"]=defaultHash
summary["snapshotDirectory"]=str(d);summary["sourceManifestSHA256"]=hashlib.sha256((d/"build-input-manifest.json").read_bytes()).hexdigest()
(d/"summary.json").write_text(json.dumps(summary,indent=2))
print(d)

