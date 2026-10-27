#!/usr/bin/env python3
"""Audit the actual private production header with exact binary64 rational checks."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);a=p.parse_args()
package=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssTriangleNormAudit.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);source=out/'source'
if source.exists():raise SystemExit('Refuse overwrite frozen audit inputs')
files=['Sources/CNativeClothCollision/TriangleNormCertificate.hpp','Sources/CNativeClothCollision/NativeClothCollision.cpp','Tests/Oracles/TriangleNormCertificateAudit.cpp','Tests/Oracles/verify_triangle_norm_certificate.py','Tests/NativeClothCollisionTests/Fixtures/cloth-triangle-rotation.json']
for name in files:
 dest=source/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(package/name,dest)
w=json.loads((source/files[-1]).read_text());(out/'actual-input.txt').write_text(' '.join(map(repr,w['queryStartXYZ'][3:]+w['queryEndXYZ'][3:]))+'\n')
wrapper=(source/files[1]).read_text();fast=wrapper[wrapper.index('bool triangleCertified'):wrapper.index('// Preserve the original successful')]
expected='a2c9de4a94c5192622ea68934b393b7c20267925d9140f512111b11a4f2f7db5'
assert hashlib.sha256(fast.encode()).hexdigest()==expected,'Original successful fixed-normal fast path changed'
manifest={'scope':'Actual private wrapper domain-certificate audit only; no public API, vendor, CCD predicate or cloth solver changes','originalFastPathSHA256':expected,'files':{name:hashlib.sha256((source/name).read_bytes()).hexdigest() for name in files}}
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
cmd=['xcrun','clang++','-std=c++17','-O2','-fno-fast-math','-ffp-contract=off','-Wall','-Wextra','-Werror',str(source/files[2]),'-o',str(out/'audit')]
subprocess.run(cmd,check=True)
with (out/'results.json').open('w') as result,(out/'benchmark.log').open('w') as log:subprocess.run([str(out/'audit'),str(out/'actual-input.txt'),'10000'],stdout=result,stderr=log,check=True)
subprocess.run(['python3',str(source/files[3]),str(out)],check=True)
# Production's default FP contraction is also audited; no proof relies on an
# unrecorded compiler switch that could change the outward enclosures.
default=out/'default-fp-contract';default.mkdir()
defaultcmd=[x for x in cmd if x!='-ffp-contract=off'];defaultcmd[-1]=str(default/'audit')
subprocess.run(defaultcmd,check=True);shutil.copy2(out/'actual-input.txt',default/'actual-input.txt')
with (default/'results.json').open('w') as result:subprocess.run([str(default/'audit'),str(default/'actual-input.txt')],stdout=result,check=True)
subprocess.run(['python3',str(source/files[3]),str(default)],check=True)
# Fast-math is explicitly unsupported by the fallback. It must not certify,
# irrespective of what the compiler assumes for general floating arithmetic.
fastcmd=cmd[:];fastcmd[fastcmd.index('-fno-fast-math')]='-ffast-math';fastcmd.remove('-ffp-contract=off');fastcmd[-1]=str(out/'unsupported-fast-math-audit')
build=subprocess.run(fastcmd,capture_output=True,text=True)
if build.returncode:
 assert '-Wnan-infinity-disabled' in build.stderr and 'floating-point options' in build.stderr,build.stderr
 unsupported={'allFallbackCertificatesRefused':True,'compilerRejectedUnsupportedMode':True,'exitCode':build.returncode,'compilerDiagnostic':build.stderr}
else:
 r=subprocess.run([str(out/'unsupported-fast-math-audit'),str(out/'actual-input.txt')],capture_output=True,text=True)
 x=json.loads(r.stdout);assert all(not c['certified'] and c['reason']=='unsupportedIEEEEnvironment' for c in x['cases'])
 unsupported={'allFallbackCertificatesRefused':True,'compilerRejectedUnsupportedMode':False,'exitCode':r.returncode,'caseCount':len(x['cases'])}
(out/'unsupported-fast-math.json').write_text(json.dumps(unsupported,indent=2)+'\n')
print(json.dumps({'passed':True,'output':str(out),'privateFallbackOnly':True,'publicOrVendorAPIChanged':False},indent=2))
