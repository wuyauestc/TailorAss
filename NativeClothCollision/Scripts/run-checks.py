#!/usr/bin/env python3
"""Snapshot, verify vendored bytes, SwiftPM Release tests, real Swift/iOS17 static linkage."""
from pathlib import Path
import argparse, concurrent.futures, hashlib, json, os, re, shutil, struct, subprocess, sys, tempfile, time
parser=argparse.ArgumentParser()
parser.add_argument("--output",type=Path)
parser.add_argument("--reuse-sdk-objects",type=Path,help="Reuse individually successful SDK C++ objects only after exact full C-source/header and compiler-argument verification")
args=parser.parse_args()
package=Path(__file__).resolve().parent.parent
out=args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="TailorAssNativeClothCollision.",dir="/private/tmp"))
out.mkdir(parents=True,exist_ok=True)
snapshot=out/"snapshot"
if snapshot.exists(): raise SystemExit("Refusing to overwrite an existing snapshot")
shutil.copytree(package,snapshot,ignore=shutil.ignore_patterns(".build",".swiftpm"))
def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
initial=[{"path":str(p.relative_to(snapshot)),"sha256":digest(p),"bytes":p.stat().st_size}
         for p in sorted(snapshot.rglob("*")) if p.is_file()]
(out/"source-manifest.json").write_text(json.dumps(initial,indent=2)+"\n")
vendor=json.loads((snapshot/"VendorManifest.json").read_text())
for x in vendor["files"]:
    b=(snapshot/x["path"]).read_bytes()
    assert hashlib.sha256(b).hexdigest()==x["sha256"],x["path"]
    assert hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()==x["gitBlobSHA1"],x["path"]
for x in json.loads((snapshot/"FixtureManifest.json").read_text())["files"]:
    assert digest(snapshot/x["path"])==x["sha256"],x["path"]
bodyVendor=json.loads((snapshot/"IPCBodyContactVendorManifest.json").read_text())
ipc=snapshot/"Sources/CIPCBodyContact"
identity=json.loads((snapshot/"IPCOrientationIdentityManifest.json").read_text())
assert digest(snapshot/"IPCBodyContactVendorManifest.json")==identity["historicalBodyManifestSHA256"]
for name,sha in identity["files"].items():assert digest(ipc/name)==sha,name
for x in bodyVendor["files"]:
    b=(ipc/x["path"]).read_bytes()
    if x["path"]==identity["historicalBodyWrapperPath"]:
        # This one file is our owned builder, not upstream vendor code. Preserve
        # the immutable historical manifest while auditing its explicit repair.
        assert x["sha256"]==identity["historicalBodyWrapperSHA256"]
        assert hashlib.sha256(b).hexdigest()==identity["files"][x["path"]]
    else:
        assert hashlib.sha256(b).hexdigest()==x["sha256"],x["path"]
        assert hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest()==x["gitBlobSHA1"],x["path"]
corrected=snapshot/"Tests/NativeClothCollisionTests/Fixtures/IPCOrientationIdentity"
correctedManifest=json.loads((corrected/"manifest.json").read_text())
for name,sha in correctedManifest["files"].items():assert digest(corrected/name)==sha,name
for name,sha in correctedManifest["sourceInputs"].items():assert digest(snapshot/"Tests/NativeClothCollisionTests/Fixtures"/name)==sha,name
for name,sha in correctedManifest["referenceSourcesSHA256"].items():assert digest(snapshot/name)==sha,name
bodyFixture=snapshot/"Tests/NativeClothCollisionTests/Fixtures/IPCBodyContact"
bodyFixtureManifest=json.loads((bodyFixture/"manifest.json").read_text())
for name,sha in bodyFixtureManifest["files"].items():assert digest(bodyFixture/name)==sha,name
assert digest(snapshot/"Scripts/archive-ipc-body-fixtures.py")==bodyFixtureManifest["generatorSHA256"]
clothManifest=json.loads((snapshot/"IPCClothContactManifest.json").read_text())
assert digest(snapshot/"IPCBodyContactVendorManifest.json")==clothManifest["sharedBodyVendorManifestSHA256"]
for name,sha in clothManifest["files"].items():assert digest(ipc/name)==sha,name
clothFixture=snapshot/"Tests/NativeClothCollisionTests/Fixtures/IPCClothContact"
clothFixtureManifest=json.loads((clothFixture/"manifest.json").read_text())
for name,sha in clothFixtureManifest["files"].items():assert digest(clothFixture/name)==sha,name
assert digest(snapshot/"Scripts/archive-ipc-cloth-fixtures.py")==clothFixtureManifest["generatorSHA256"]
assert digest(snapshot/"Tests/Oracles/IPCClothFullReference.cpp")==clothFixtureManifest["fullReferenceSourceSHA256"]
assert digest(snapshot/"Tests/Oracles/IPCFullSourceManifest.json")==clothFixtureManifest["fullSourceManifestSHA256"]
selfGuardFixtures=snapshot/"Tests/NativeClothCollisionTests/Fixtures"
selfGuardManifest=json.loads((selfGuardFixtures/"SelfContactGuard/manifest.json").read_text())
for name,sha in selfGuardManifest["files"].items():assert digest(selfGuardFixtures/(name+".json"))==sha,name
featureFixtures=selfGuardFixtures/"FeatureSeparationCertificate"
featureFixtureManifest=json.loads((featureFixtures/"manifest.json").read_text())
for name,sha in featureFixtureManifest["files"].items():assert digest(featureFixtures/name)==sha,name
deltaManifest=json.loads((snapshot/"ContactEnergyDeltaManifest.json").read_text())
for name,sha in deltaManifest["files"].items():assert digest(snapshot/name)==sha,name
deltaFixtures=selfGuardFixtures/"ContactEnergyDelta"
for name,sha in json.loads((deltaFixtures/"manifest.json").read_text())["files"].items():assert digest(deltaFixtures/name)==sha,name
selfSupplement=snapshot/"Tests/NativeClothCollisionTests/Fixtures/SelfEuclideanSupplement"
selfSupplementManifest=json.loads((selfSupplement/"manifest.json").read_text())
for name,sha in selfSupplementManifest["files"].items():assert digest(selfSupplement/name)==sha,name
assert digest(snapshot/"Tests/Oracles/self_feature_separation_fraction.py")==selfSupplementManifest["independentFractionVerifierSHA256"]
correlatedFixtures=selfGuardFixtures/"CorrelatedFeatureCertificate"
correlatedFixtureManifest=json.loads((correlatedFixtures/"manifest.json").read_text())
for name,sha in correlatedFixtureManifest["files"].items():assert digest(correlatedFixtures/name)==sha,name
correlatedManifest=json.loads((snapshot/"CorrelatedFeatureCertificateManifest.json").read_text())
for name,sha in correlatedManifest["files"].items():assert digest(snapshot/name)==sha,name
expansionFixtures=selfGuardFixtures/"ExpansionFeatureCertificate"
expansionFixtureManifest=json.loads((expansionFixtures/"manifest.json").read_text())
for name,sha in expansionFixtureManifest["files"].items():assert digest(expansionFixtures/name)==sha,name
expansionManifest=json.loads((snapshot/"ExpansionFeatureCertificateManifest.json").read_text())
for name,sha in expansionManifest["files"].items():assert digest(snapshot/name)==sha,name
elevationFixtures=selfGuardFixtures/"ElevatedFeatureCertificate"
elevationFixtureManifest=json.loads((elevationFixtures/"manifest.json").read_text())
for name,sha in elevationFixtureManifest["files"].items():assert digest(elevationFixtures/name)==sha,name
elevationManifest=json.loads((snapshot/"ElevatedFeatureCertificateManifest.json").read_text())
for name,sha in elevationManifest["files"].items():assert digest(snapshot/name)==sha,name
criticalFixtures=selfGuardFixtures/"CriticalFeatureCertificate"
for name,sha in json.loads((criticalFixtures/"manifest.json").read_text())["files"].items():assert digest(criticalFixtures/name)==sha,name
for name,sha in json.loads((snapshot/"CriticalFeatureCertificateManifest.json").read_text())["files"].items():assert digest(snapshot/name)==sha,name
affineFixtures=selfGuardFixtures/"AffineFeatureCertificate"
for name,sha in json.loads((affineFixtures/"manifest.json").read_text())["files"].items():assert digest(affineFixtures/name)==sha,name
for name,sha in json.loads((snapshot/"AffineFeatureCertificateManifest.json").read_text())["files"].items():assert digest(snapshot/name)==sha,name
results=[]
reuseSDK={}
if args.reuse_sdk_objects:
    prior=args.reuse_sdk_objects.resolve();oldSnapshot=prior/"snapshot"
    oldSources={str(p.relative_to(oldSnapshot)):digest(p)for p in oldSnapshot.glob("Sources/C*/**/*")if p.is_file()}
    newSources={str(p.relative_to(snapshot)):digest(p)for p in snapshot.glob("Sources/C*/**/*")if p.is_file()}
    assert oldSources==newSources,"Cannot reuse changed C++/header closure"
    oldSummary=json.loads((prior/"summary.json").read_text())
    for r in oldSummary["results"]:
        command=r["command"]
        if r["exitCode"]==0 and len(command)>1 and command[0:2]==["xcrun","clang++"] and "-c"in command and "-o"in command:
            oldObject=Path(command[command.index("-o")+1]);assert oldObject.is_file()
            normalized=[x.replace(str(prior),str(out))for x in command]
            reuseSDK[r["label"]]=(normalized,oldObject,digest(oldObject),r)
    assert reuseSDK,"No individually successful SDK objects to reuse"
    (out/"reused-sdk-source-closure.json").write_text(json.dumps({"prior":str(prior),"priorSummarySHA256":digest(prior/"summary.json"),"sourceClosure":oldSources,"wholePriorRunAccepted":oldSummary["passed"],"reuseScope":"Only verified individual successful C++ compilation objects; all Swift modules/clients and Mac tests are rebuilt"},indent=2)+"\n")
def run(cmd,label,env=None):
    cmd=[str(x)for x in cmd]
    if label in reuseSDK:
        normalized,oldObject,sha,old=reuseSDK[label]
        assert cmd==normalized,"SDK compile arguments changed: "+label
        assert digest(oldObject)==sha
        destination=Path(cmd[cmd.index("-o")+1]);destination.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(oldObject,destination)
        log=out/(label+".log");log.write_text(json.dumps({"reusedExactObject":str(oldObject),"objectSHA256":sha,"originalCommand":old["command"],"matchedCurrentCommand":cmd,"sourceClosureVerified":True},indent=2)+"\n")
        return {"label":label,"command":cmd,"exitCode":0,"seconds":0,"log":str(log),"reusedVerifiedObject":str(oldObject),"objectSHA256":sha,"originalExitCode":0}
    t=time.time();p=subprocess.run([str(x) for x in cmd],cwd=snapshot,env=env,capture_output=True,text=True)
    log=out/(label+".log");log.write_text(p.stdout+p.stderr)
    return {"label":label,"command":[str(x) for x in cmd],"exitCode":p.returncode,
            "seconds":time.time()-t,"log":str(log)}
env=dict(os.environ,SWIFTPM_MODULECACHE_OVERRIDE=str(out/"manifest-cache"),
         CLANG_MODULE_CACHE_PATH=str(out/"clang-cache"),NCC_BODY_GUARD_REPORT=str(out/"real-upper-guard.json"),
         NCC_FEATURE_SEPARATION_REPORT=str(out/"feature-separation-report.json"),
         NCC_BODY_CERTIFICATE_REPORT=str(out/"body-certificate-integration-report.json"),
         NCC_SELF_EUCLIDEAN_REPORT=str(out/"self-euclidean-supplement-report.json"),
         NCC_CORRELATED_FEATURE_REPORT=str(out/"correlated-feature-report.json"),
         NCC_CORRELATED_VARIANTS_REPORT=str(out/"correlated-variants-report.json"),
         NCC_CORRELATED_EDGE_REPORT=str(out/"correlated-edge-report.json"),
         NCC_EXPANSION_ARITHMETIC_REPORT=str(out/"expansion-arithmetic-report.json"),
         NCC_EXPANSION_FEATURE_REPORT=str(out/"expansion-feature-report.json"),
         NCC_EXPANSION_VARIANTS_REPORT=str(out/"expansion-variants-report.json"),
         NCC_EXPANSION_CONTACT_REPORT=str(out/"expansion-contacts-report.json"),
         NCC_EXPANSION_COMPLETE_SELF_REPORT=str(out/"expansion-complete-self-report.json"),
         NCC_ELEVATION_ARITHMETIC_REPORT=str(out/"elevation-arithmetic-report.json"),
         NCC_ELEVATION_FEATURE_REPORT=str(out/"elevation-feature-report.json"),
         NCC_ELEVATION_VARIANTS_REPORT=str(out/"elevation-variants-report.json"),
         NCC_ELEVATION_CONTACT_REPORT=str(out/"elevation-contact-report.json"),
         NCC_ELEVATION_COMPLETE_SELF_REPORT=str(out/"elevation-complete-self-report.json"),
         NCC_CRITICAL_ACTUAL_REPORT=str(out/"critical-actual-report.json"),
         NCC_CRITICAL_CONTROLS_REPORT=str(out/"critical-controls-report.json"),
         NCC_CRITICAL_VARIANTS_REPORT=str(out/"critical-variants-report.json"),
         NCC_CRITICAL_COMPLETE_SELF_REPORT=str(out/"critical-complete-self-report.json"),
         NCC_AFFINE_REPORT=str(out/"affine-feature-report.json"),
         NCC_COMMON_AFFINE_REPORT=str(out/"common-affine-feature-report.json"))
swiftpm=["swift","test","--disable-sandbox","--build-system","native","--package-path",snapshot,
         "--scratch-path",out/"swiftpm","--cache-path",out/"cache","--config-path",out/"config",
         "--security-path",out/"security","-c","release","-j","3","-Xswiftc","-warnings-as-errors"]
results.append(run(swiftpm,"swiftpm-release",env))
macLog=Path(results[-1]["log"]).read_text()
macTestsExecuted=max([int(x) for x in re.findall(r"Executed (\d+) tests?, with 0 failures",macLog)],default=0)
contactDeltaSuitePassed="Test Suite 'ContactEnergyDeltaTests' passed" in macLog
featureSuitesPassed=all("Test Suite '"+name+"' passed" in macLog for name in
                       ["FeatureSeparationCertificateTests","ContinuousBodyCertificateIntegrationTests"])
correlatedSuitePassed="Test Suite 'CorrelatedFeatureCertificateTests' passed" in macLog
correlatedFractionPassed=False
if correlatedSuitePassed and all((out/name).exists() for name in ["correlated-feature-report.json","correlated-variants-report.json","correlated-edge-report.json"]):
    results.append(run([sys.executable,snapshot/"Tests/Oracles/audit_correlated_feature.py",
        "--report",out/"correlated-feature-report.json","--report",out/"correlated-variants-report.json",
        "--report",out/"correlated-edge-report.json","--output",out/"correlated-fraction-audit.json"],
        "exact-fraction-correlated-feature-certificates"))
    if results[-1]["exitCode"]==0:correlatedFractionPassed=json.loads((out/"correlated-fraction-audit.json").read_text())["passed"]
expansionSuitePassed="Test Suite 'ExpansionFeatureCertificateTests' passed" in macLog
expansionArithmeticPassed=expansionFractionPassed=False
if expansionSuitePassed:
    results.append(run([sys.executable,snapshot/"Tests/Oracles/audit_expansion_arithmetic.py",
        "--report",out/"expansion-arithmetic-report.json","--output",out/"expansion-arithmetic-fraction.json"],"exact-fraction-expansion-arithmetic"))
    if results[-1]["exitCode"]==0:expansionArithmeticPassed=json.loads((out/"expansion-arithmetic-fraction.json").read_text())["passed"]
    results.append(run([sys.executable,snapshot/"Tests/Oracles/audit_correlated_feature.py",
        "--report",out/"expansion-feature-report.json","--report",out/"expansion-variants-report.json",
        "--report",out/"expansion-contacts-report.json","--output",out/"expansion-feature-fraction.json"],"exact-fraction-expansion-feature-certificates"))
    if results[-1]["exitCode"]==0:expansionFractionPassed=json.loads((out/"expansion-feature-fraction.json").read_text())["passed"]
elevationSuitePassed="Test Suite 'ElevatedFeatureCertificateTests' passed" in macLog
elevationArithmeticPassed=elevationFractionPassed=False
if elevationSuitePassed:
    results.append(run([sys.executable,snapshot/"Tests/Oracles/audit_elevation_arithmetic.py",
        "--report",out/"elevation-arithmetic-report.json","--output",out/"elevation-arithmetic-fraction.json"],"exact-fraction-integer-degree-elevation"))
    if results[-1]["exitCode"]==0:elevationArithmeticPassed=json.loads((out/"elevation-arithmetic-fraction.json").read_text())["passed"]
    results.append(run([sys.executable,snapshot/"Tests/Oracles/audit_correlated_feature.py",
        "--report",out/"elevation-feature-report.json","--report",out/"elevation-variants-report.json",
        "--report",out/"elevation-contact-report.json","--output",out/"elevation-feature-fraction.json"],"exact-fraction-elevated-feature-certificates"))
    if results[-1]["exitCode"]==0:elevationFractionPassed=json.loads((out/"elevation-feature-fraction.json").read_text())["passed"]
criticalSuitePassed="Test Suite 'CriticalFeatureCertificateTests' passed" in macLog
criticalFractionPassed=False
if criticalSuitePassed:
    results.append(run([sys.executable,snapshot/"Tests/Oracles/audit_correlated_feature.py",
        "--report",out/"critical-actual-report.json","--report",out/"critical-controls-report.json",
        "--report",out/"critical-variants-report.json","--output",out/"critical-fraction-audit.json"],"exact-fraction-critical-value-certificates"))
    if results[-1]["exitCode"]==0:criticalFractionPassed=json.loads((out/"critical-fraction-audit.json").read_text())["passed"]
affineSuitePassed="Test Suite 'AffineFeatureCertificateTests' passed" in macLog
affineFractionPassed=False
if affineSuitePassed:
    results.append(run([sys.executable,snapshot/"Tests/Oracles/audit_correlated_feature.py",
        "--report",out/"affine-feature-report.plist","--output",out/"affine-fraction-sturm-audit.json"],"exact-fraction-sturm-affine-normal-certificates"))
    if results[-1]["exitCode"]==0:affineFractionPassed=json.loads((out/"affine-fraction-sturm-audit.json").read_text())["passed"]
commonAffineFractionPassed=False
if affineSuitePassed and (out/"common-affine-feature-report.plist").exists():
    results.append(run([sys.executable,snapshot/"Tests/Oracles/audit_correlated_feature.py",
        "--report",out/"common-affine-feature-report.plist","--output",out/"common-affine-fraction-sturm-audit.json"],"exact-fraction-sturm-common-affine-certificates"))
    if results[-1]["exitCode"]==0:commonAffineFractionPassed=json.loads((out/"common-affine-fraction-sturm-audit.json").read_text())["passed"]
fractionPassed=False
if featureSuitesPassed and (out/"feature-separation-report.json").exists() and (out/"body-certificate-integration-report.json").exists():
    results.append(run([sys.executable,snapshot/"Tests/Oracles/feature_separation_fraction.py",
        "--report",out/"feature-separation-report.json","--fixtures",featureFixtures,
        "--output",out/"fraction-support-audit.json","--body-report",out/"body-certificate-integration-report.json"],"exact-fraction-feature-and-body-certificates"))
    if results[-1]["exitCode"]==0:
        fractionPassed=json.loads((out/"fraction-support-audit.json").read_text())["passed"]
oraclePassed=False
report=out/"real-upper-guard.json"
if report.exists():
    f=json.loads((snapshot/"Tests/NativeClothCollisionTests/Fixtures/upper-body-motion.json").read_text())
    r=json.loads(report.read_text())
    with (out/"oracle-input.bin").open("wb") as w:
        w.write(b"NCCB1\0\0\0")
        w.write(struct.pack("<4I",len(f["bodyPositions"]),len(f["bodyTriangleIndices"])//3,len(f["previous"]),len(f["clothTriangleIndices"])//3))
        for key,kind in [("bodyPositions","d"),("bodyTriangleIndices","I"),("previous","d"),("candidate","d"),("clothTriangleIndices","I")]:
            a=f[key];flat=[x for row in a for x in row] if a and isinstance(a[0],list) else a
            w.write(struct.pack("<"+str(len(flat))+kind,*flat))
        witness=r["witnessClothIDs"]+r["witnessBodyIDs"] if r["witnessKind"]=="edgeEdge" else [2**32-1]*4
        w.write(struct.pack("<4I",*witness))
    results.append(run(["xcrun","clang++","-std=c++17","-O2","-Wall","-Wextra","-Werror",snapshot/"Tests/Oracles/ContinuousBodyOracle.cpp","-o",out/"oracle"],"oracle-compile"))
    if results[-1]["exitCode"]==0:
        results.append(run([out/"oracle",out/"oracle-input.bin",str(r["safeTime"])],"independent-body-oracle"))
        if results[-1]["exitCode"]==0:
            oracle=json.loads(Path(results[-1]["log"]).read_text());oraclePassed=oracle["passed"]
            (out/"independent-body-oracle.json").write_text(json.dumps(oracle,indent=2)+"\n")
            root=oracle["independentWitnessEdgeTOI"]
            if root is not None:assert r["conservativeTOI"]<=root+1e-12 and r["safeTime"]<root
selfFractionPassed=False
if (out/"self-euclidean-supplement-report.json").exists():
    results.append(run([sys.executable,snapshot/"Tests/Oracles/self_feature_separation_fraction.py",
        "--report",out/"self-euclidean-supplement-report.json","--output",out/"self-euclidean-exact-fraction.json"],"exact-fraction-self-euclidean-certificates"))
    if results[-1]["exitCode"]==0:selfFractionPassed=json.loads((out/"self-euclidean-exact-fraction.json").read_text())["passed"]
c=snapshot/"Sources/CNativeClothCollision"
sources=[c/"tight_inclusion"/(x+".cpp") for x in ["ccd","interval","interval_root_finder","avx","logger"]]+sorted(c.glob("*.cpp"))
ipcSources=[ipc/x["path"] for x in bodyVendor["files"] if x["path"].endswith(".cpp")]+[ipc/x for x in clothManifest["files"] if x.endswith(".cpp")]
ipcSources+=[ipc/"src/IPCContactEnergyDelta.cpp"]
sparse=snapshot/"Sources/CNativeClothSparse"
sparseSources=[sparse/"NativeClothSparse.cpp"]
swiftSources=sorted((snapshot/"Sources/NativeClothCollision").glob("*.swift"));artifactDirs=[]
for platform,sdkName,triple,expectedPlatform in [("ios","iphoneos","arm64-apple-ios17.0","IOS"),("simulator-x86_64","iphonesimulator","x86_64-apple-ios17.0-simulator","IOSSIMULATOR")]:
    sdk=subprocess.check_output(["xcrun","--sdk",sdkName,"--show-sdk-path"],text=True).strip()
    target=out/platform;target.mkdir();artifactDirs.append(target)
    incs=["-I",c,"-I",c/"include","-I",c/"vendor/eigen","-I",c/"vendor/spdlog"]
    flags=["-target",triple,"-isysroot",sdk,"-std=c++17","-O2","-DNDEBUG","-DFMT_HEADER_ONLY","-DEIGEN_MPL2_ONLY","-fno-fast-math","-ffp-contract=off","-Werror"]
    tasks=[(["xcrun","clang++"]+flags+incs+["-c",f,"-o",target/(f.stem+".o")],platform+"-"+f.stem) for f in sources]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        rr=list(pool.map(lambda x:run(*x),tasks));results+=rr
    if not all(x["exitCode"]==0 for x in rr):continue
    sparseObjects=target/"SparseObjects";sparseObjects.mkdir()
    tasks=[(["xcrun","clang++"]+flags+["-I",sparse/"include","-c",f,"-o",sparseObjects/(f.stem+".o")],platform+"-sparse-"+f.stem) for f in sparseSources]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        rr=list(pool.map(lambda x:run(*x),tasks));results+=rr
    if not all(x["exitCode"]==0 for x in rr):continue
    ipcObjects=target/"IPCBodyObjects";ipcObjects.mkdir()
    ipcIncludes=["-I",ipc/"include","-I",ipc/"official","-I",ipc/"vendor/eigen","-I",ipc/"vendor/spdlog"]
    tasks=[(["xcrun","clang++"]+flags+ipcIncludes+["-c",f,"-o",ipcObjects/(f.stem+".o")],platform+"-ipc-"+f.stem) for f in ipcSources]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        rr=list(pool.map(lambda x:run(*x),tasks));results+=rr
    if not all(x["exitCode"]==0 for x in rr):continue
    module=target/"CNativeClothCollision";module.mkdir()
    (module/"module.modulemap").write_text('module CNativeClothCollision { '+''.join('header "'+str(h)+'" ' for h in sorted((c/"include").glob("*.h")))+'export * }\n')
    ipcModule=target/"CIPCBodyContact";ipcModule.mkdir()
    (ipcModule/"module.modulemap").write_text('module CIPCBodyContact { '+''.join('header "'+str(ipc/"include"/h)+'" ' for h in ["IPCContactBuilder.h","IPCClothContactBuilder.h","IPCContactEnergyDelta.h"])+'export * }\n')
    sparseModule=target/"CNativeClothSparse";sparseModule.mkdir()
    (sparseModule/"module.modulemap").write_text('module CNativeClothSparse { header "'+str(sparse/"include/NativeClothSparse.h")+'" export * }\n')
    flags=["-swift-version","5","-warnings-as-errors","-O","-whole-module-optimization","-parse-as-library","-target",triple,"-sdk",sdk,"-module-cache-path",out/(platform+"-swift-cache"),"-I",module,"-I",ipcModule,"-I",sparseModule]
    cmd=["xcrun","swiftc"]+flags+["-module-name","NativeClothCollision","-emit-module","-emit-module-path",target/"NativeClothCollision.swiftmodule","-emit-object"]+swiftSources+["-o",target/"NativeClothCollisionSwift.o"]
    results.append(run(cmd,platform+"-swift-library"))
    if results[-1]["exitCode"]!=0:continue
    objs=[target/(f.stem+".o") for f in sources]+[ipcObjects/(f.stem+".o") for f in ipcSources]+[sparseObjects/(f.stem+".o") for f in sparseSources]+[target/"NativeClothCollisionSwift.o"]
    results.append(run(["xcrun","libtool","-static","-o",target/"libNativeClothCollision.a"]+objs,platform+"-static-archive"))
    smoke=["xcrun","swiftc"]+flags+["-I",target,"-L",target,"-lNativeClothCollision","-lc++","-framework","Accelerate",snapshot/"Scripts/LinkSmoke.swift","-o",target/"NativeClothCollisionSmoke"]
    results.append(run(smoke,platform+"-swift-static-smoke-link"))
    if results[-1]["exitCode"]!=0:continue
    check=run(["xcrun","vtool","-show-build",target/"NativeClothCollisionSmoke"],platform+"-platform");results.append(check)
    text=Path(check["log"]).read_text()
    assert "platform "+expectedPlatform+"\n" in text and "minos 17.0" in text,text
    results.append(run(["xcrun","nm","-g",target/"NativeClothCollisionSmoke"],platform+"-linked-symbols"))
    bodySmoke=["xcrun","swiftc"]+flags+["-I",target,"-L",target,"-lNativeClothCollision","-lc++","-framework","Accelerate",snapshot/"Scripts/BodyPotentialLinkSmoke.swift","-o",target/"BodyPotentialSmoke"]
    results.append(run(bodySmoke,platform+"-body-potential-static-smoke-link"))
    if results[-1]["exitCode"]!=0:continue
    bodyCheck=run(["xcrun","vtool","-show-build",target/"BodyPotentialSmoke"],platform+"-body-potential-platform");results.append(bodyCheck)
    text=Path(bodyCheck["log"]).read_text()
    assert "platform "+expectedPlatform+"\n" in text and "minos 17.0" in text,text
    symbols=run(["xcrun","nm","-g",target/"BodyPotentialSmoke"],platform+"-body-potential-linked-symbols");results.append(symbols)
    text=Path(symbols["log"]).read_text();assert "_ipcb_create" in text and "_ipcb_evaluate" in text
    for sourceName,binaryName,required in [
        ("ClothPotentialLinkSmoke.swift","ClothPotentialSmoke",["_ipcc_create","_ipcc_evaluate","_ncc_floating_point_rounding_is_nearest"]),
        ("SparseLinkSmoke.swift","SparseSmoke",["_ncs_create","_ncs_refactor","_ncs_solve"]),
        ("SelfGuardLinkSmoke.swift","SelfGuardSmoke",["_ncc_self_triangle_certificate","_ncc_self_edge_certificate"]),
        ("FeatureSeparationLinkSmoke.swift","FeatureSeparationSmoke",["_ncc_floating_point_rounding_is_nearest"]),
        ("ContactEnergyDeltaLinkSmoke.swift","ContactEnergyDeltaSmoke",["_ipced_evaluate_local"]),
        ("CorrelatedFeatureLinkSmoke.swift","CorrelatedFeatureSmoke",["_ncc_floating_point_rounding_is_nearest"]),
        ("ExpansionFeatureLinkSmoke.swift","ExpansionFeatureSmoke",["_ncc_floating_point_rounding_is_nearest"]),
        ("ElevatedFeatureLinkSmoke.swift","ElevatedFeatureSmoke",["_ncc_floating_point_rounding_is_nearest"]),
        ("CriticalFeatureLinkSmoke.swift","CriticalFeatureSmoke",["_ncc_floating_point_rounding_is_nearest"]),
        ("AffineFeatureLinkSmoke.swift","AffineFeatureSmoke",["_ncc_floating_point_rounding_is_nearest"]),
        ("CommonAffineFeatureLinkSmoke.swift","CommonAffineFeatureSmoke",["_ncc_floating_point_rounding_is_nearest"])]:
        client=["xcrun","swiftc"]+flags+["-I",target,"-L",target,"-lNativeClothCollision","-lc++","-framework","Accelerate",snapshot/"Scripts"/sourceName,"-o",target/binaryName]
        results.append(run(client,platform+"-"+binaryName+"-static-link"))
        if results[-1]["exitCode"]!=0:continue
        check=run(["xcrun","vtool","-show-build",target/binaryName],platform+"-"+binaryName+"-platform");results.append(check)
        text=Path(check["log"]).read_text()
        assert "platform "+expectedPlatform+"\n" in text and "minos 17.0" in text,text
        symbols=run(["xcrun","nm","-g",target/binaryName],platform+"-"+binaryName+"-symbols");results.append(symbols)
        text=Path(symbols["log"]).read_text();assert all(x in text for x in required)
unchanged=all(digest(snapshot/x["path"])==x["sha256"] for x in initial)
passed=unchanged and oraclePassed and fractionPassed and selfFractionPassed and featureSuitesPassed and contactDeltaSuitePassed and correlatedSuitePassed and correlatedFractionPassed and expansionSuitePassed and expansionArithmeticPassed and expansionFractionPassed and elevationSuitePassed and elevationArithmeticPassed and elevationFractionPassed and criticalSuitePassed and criticalFractionPassed and affineSuitePassed and affineFractionPassed and commonAffineFractionPassed and macTestsExecuted>=137 and all(x["exitCode"]==0 for x in results) and all(any(x["label"]==p+"-platform" for x in results) for p in ["ios","simulator-x86_64"])
summary={"passed":passed,"sourceSnapshotUnchanged":unchanged,"vendorFileCount":len(vendor["files"]),
         "fixtureHashesVerified":True,"independentBodyOraclePassed":oraclePassed,
         "macTestsExecuted":macTestsExecuted,"featureSeparationSuitesPassed":featureSuitesPassed,
         "commonAffineIndependentFractionSturmPassed":commonAffineFractionPassed,
         "affineFeatureSuitePassed":affineSuitePassed,"affineIndependentFractionSturmPassed":affineFractionPassed,
         "criticalFeatureSuitePassed":criticalSuitePassed,"criticalIndependentFractionPassed":criticalFractionPassed,
         "elevationFeatureSuitePassed":elevationSuitePassed,"independentDegreeElevationArithmeticPassed":elevationArithmeticPassed,
         "independentElevatedFeatureFractionPassed":elevationFractionPassed,"elevationFixtureHashesVerified":True,
         "expansionFeatureSuitePassed":expansionSuitePassed,
         "independentExpansionArithmeticPassed":expansionArithmeticPassed,"independentExpansionFeatureFractionPassed":expansionFractionPassed,
         "expansionFeatureFixtureHashesVerified":True,
         "correlatedFeatureSuitePassed":correlatedSuitePassed,
         "correlatedFeatureFixtureHashesVerified":True,"independentCorrelatedFractionAuditPassed":correlatedFractionPassed,
         "contactEnergyDeltaSuitePassed":contactDeltaSuitePassed,"contactEnergyDeltaFixtureHashesVerified":True,
         "independentFractionSupportAuditPassed":fractionPassed,"macOS":"SwiftPM Release tests execute real Swift -> C -> C++",
         "ipcBodyContactVendorFileCount":len(bodyVendor["files"]),"ipcBodyHistoricalOriginalGoldenHashesVerified":True,
         "iOS":"arm64 iOS17 + x86_64 iOS17 Simulator static archives and real Swift client executables LINKED; not run on device",
         "ipcClothHistoricalOriginalGoldenHashesVerified":True,
         "orientationCorrectedIndependentFullBuilderGoldensVerified":True,
         "ownedBodyWrapperHistoricalExceptionExplicit":True,
         "thirdPartyFilesUnchanged":True,
         "selfGuardFixtureHashesVerified":True,"featureSeparationFixtureHashesVerified":True,
         "selfEuclideanSupplementFixtureHashesVerified":True,"independentSelfEuclideanFractionAuditPassed":selfFractionPassed,
         "scope":"CCD primitives, body/self path guards, independent IPC body/self endpoint potentials and sparse factorization; no complete garment claimed",
         "output":str(out),"results":results,
         "artifacts":[{"path":str(p.relative_to(out)),"sha256":digest(p),"bytes":p.stat().st_size}
                      for d in artifactDirs for p in d.iterdir() if p.is_file() and p.suffix in [".a",""]]}
(out/"summary.json").write_text(json.dumps(summary,indent=2)+"\n")
print(json.dumps({k:v for k,v in summary.items() if k not in ["results","artifacts"]},indent=2))
raise SystemExit(0 if passed else 1)

