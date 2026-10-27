#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,os,shutil,subprocess,tempfile,time
repo=Path(__file__).resolve().parents[2];out=Path(os.environ.get('GARMENTCODE_NATIVE_SPARSE_OUTPUT','/private/tmp/TailorAssNativeSparsePlatforms'));out.mkdir(parents=True,exist_ok=True)
root=Path(tempfile.mkdtemp(prefix='TailorAssNativeSparsePlatformBuild.',dir='/private/tmp'));source=root/'source';source.mkdir()
package=repo/'NativeClothCollision';shutil.copytree(package/'Sources/CNativeClothSparse',source/'CNativeClothSparse')
shutil.copy2(package/'Sources/NativeClothCollision/NativeSparseCholesky.swift',source/'NativeSparseCholesky.swift');shutil.copy2(package/'Scripts/SparseLinkSmoke.swift',source/'SparseLinkSmoke.swift')
(source/'CNativeClothSparse/module.modulemap').write_text('module CNativeClothSparse { header "include/NativeClothSparse.h" export * }\n')
(out/'source-manifest.json').write_text(json.dumps({str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(source.rglob('*')) if p.is_file()},indent=2))
results=[]
def run(cmd,name,env):
 a=time.monotonic()
 with open(out/(name+'.log'),'w') as f:q=subprocess.run([str(z) for z in cmd],stdout=f,stderr=subprocess.STDOUT,env=env)
 results.append({'label':name,'command':[str(z) for z in cmd],'exitCode':q.returncode,'seconds':time.monotonic()-a})
 (out/'results.json').write_text(json.dumps(results,indent=2))
 if q.returncode:print((out/(name+'.log')).read_text());raise SystemExit(q.returncode)
for name,sdkName,target,platform in [('mac','macosx','arm64-apple-macos13.0','MACOS'),('ios','iphoneos','arm64-apple-ios17.0','IOS'),('sim','iphonesimulator','x86_64-apple-ios17.0-simulator','IOSSIMULATOR')]:
 sdk=subprocess.check_output(['xcrun','--sdk',sdkName,'--show-sdk-path'],text=True).strip();dest=root/name;dest.mkdir();env=dict(os.environ,SDKROOT=sdk)
 run(['xcrun','clang++','-target',target,'-isysroot',sdk,'-std=c++17','-O3','-Wall','-Wextra','-Werror','-I',source/'CNativeClothSparse/include','-c',source/'CNativeClothSparse/NativeClothSparse.cpp','-o',dest/'Sparse.o'],name+'-cpp',env)
 flags=['-O','-swift-version','5','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-target',target,'-sdk',sdk,'-module-cache-path',dest/'module-cache','-I',source/'CNativeClothSparse']
 run(['xcrun','swiftc',*flags,'-emit-module','-emit-library','-static','-module-name','NativeClothCollision',source/'NativeSparseCholesky.swift',dest/'Sparse.o','-emit-module-path',dest/'NativeClothCollision.swiftmodule','-o',dest/'libNativeClothCollision.a'],name+'-swift-module',env)
 run(['xcrun','swiftc',*flags,'-I',dest,source/'SparseLinkSmoke.swift',dest/'libNativeClothCollision.a','-framework','Accelerate','-lc++','-o',dest/'SparseSmoke'],name+'-swift-final-link',env)
 run(['xcrun','vtool','-show-build',dest/'SparseSmoke'],name+'-platform',env)
 info=(out/(name+'-platform.log')).read_text();assert 'platform '+platform+'\n' in info
 if name!='mac':assert 'minos 17.0' in info
 if name=='mac':run([dest/'SparseSmoke'],name+'-actual-run',env)
 run(['xcrun','nm','-g',dest/'SparseSmoke'],name+'-symbols',env)
 text=(out/(name+'-symbols.log')).read_text();assert '_ncs_create' in text and '_ncs_refactor' in text and '_ncs_solve' in text
(out/'summary.json').write_text(json.dumps({'passed':all(z['exitCode']==0 for z in results),'sourceSnapshot':str(source),'scope':'Only new production NativeSparseCholesky target/wrapper, plus full SwiftPM7 tests separately; no cloth physics or iPhone runtime claim.','MacReleaseRealInteropExecuted':True,'iOS17Arm64RealSwiftCInteropLinked':True,'iOS17x86SimulatorRealSwiftCInteropLinked':True,'deviceExecuted':False,'results':results},indent=2));print('NativeSparse platforms PASS',out)
