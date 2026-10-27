#!/usr/bin/env python3
"""Freeze package, run only certificate tests, then independently audit every support leaf."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument("--output",type=Path);a=p.parse_args()
package=Path(__file__).resolve().parent.parent
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix="TailorAssFeatureSeparation.",dir="/private/tmp"))
out.mkdir(parents=True,exist_ok=True);source=out/"snapshot"
if source.exists():raise SystemExit("Refusing to overwrite an existing source snapshot")
shutil.copytree(package,source,ignore=shutil.ignore_patterns(".build",".swiftpm"))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=[{"path":str(p.relative_to(source)),"sha256":sha(p),"bytes":p.stat().st_size} for p in sorted(source.rglob("*")) if p.is_file()]
(out/"source-manifest.json").write_text(json.dumps(manifest,indent=2))
fixture=source/"Tests/NativeClothCollisionTests/Fixtures/FeatureSeparationCertificate"
for name,h in json.loads((fixture/"manifest.json").read_text())["files"].items():assert sha(fixture/name)==h
env=dict(os.environ,SWIFTPM_MODULECACHE_OVERRIDE=str(out/"manifest-cache"),CLANG_MODULE_CACHE_PATH=str(out/"clang-cache"),NCC_FEATURE_SEPARATION_REPORT=str(out/"feature-separation-report.json"),NCC_BODY_CERTIFICATE_REPORT=str(out/"body-certificate-integration-report.json"))
cmd=["swift","test","--disable-sandbox","--build-system","native","--package-path",source,"--scratch-path",out/"build","--cache-path",out/"cache","--config-path",out/"config","--security-path",out/"security",
 "-c","release","-j","3","--filter","FeatureSeparationCertificateTests|ContinuousBodyCertificateIntegrationTests","-Xswiftc","-warnings-as-errors","-Xswiftc","-strict-concurrency=complete"]
results=[]
def run(cmd,label):
 t=time.monotonic();r=subprocess.run([str(x) for x in cmd],env=env,capture_output=True,text=True)
 log=out/(label+".log");log.write_text(r.stdout+r.stderr);results.append({"label":label,"command":[str(x) for x in cmd],"exit":r.returncode,"seconds":time.monotonic()-t,"log":str(log)})
 (out/"commands.json").write_text(json.dumps(results,indent=2))
 if r.returncode:print(log.read_text());raise SystemExit(r.returncode)
run(cmd,"swiftpm-release-certificate")
run(["python3",source/"Tests/Oracles/feature_separation_fraction.py","--report",out/"feature-separation-report.json","--fixtures",fixture,"--output",out/"fraction-support-audit.json","--body-report",out/"body-certificate-integration-report.json"],"exact-fraction-leaves-and-convex-qp")
unchanged=all(sha(source/x["path"])==x["sha256"] for x in manifest)
summary={"passed":unchanged and json.loads((out/"fraction-support-audit.json").read_text())["passed"],"snapshotUnchanged":unchanged,
 "commands":results,"sourceManifestSHA256":sha(out/"source-manifest.json"),"report":str(out/"feature-separation-report.json"),"scope":"Separation primitive and complete body-guard integration; no native algorithm change or garment acceptance"}
(out/"summary.json").write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2));print(out)
raise SystemExit(0 if summary["passed"] else 1)

