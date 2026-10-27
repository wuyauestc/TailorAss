"""Bind sealed Native SDK archives and emit matching Swift interfaces only.

No C++ source is compiled and no Native test suite is rerun. The interfaces are
freshly emitted from the complete sealed Swift source set, so their hashes are
bound to source rather than assuming an old unrecorded .swiftmodule is intact.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib,json,shutil,subprocess,time

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def prepare(proof,root):
    proof=Path(proof).resolve();root=Path(root).resolve()
    delivery=json.loads((proof/'delivery-manifest.json').read_text());source=json.loads((proof/'source-manifest.json').read_text());summary=json.loads((proof/'summary.json').read_text())
    assert delivery['passed'] and summary['passed'] and delivery['macTestsExecuted']>=129
    assert sha(proof/'summary.json')==delivery['summarySHA256'] and sha(proof/'source-manifest.json')==delivery['sourceManifestSHA256']
    assert all(sha(proof/'snapshot'/p)==h for p,h in source.items())
    actual={str(p.relative_to(proof/'snapshot/Sources')):sha(p) for p in (proof/'snapshot/Sources').rglob('*') if p.is_file()}
    assert actual==delivery['nativeSources'] and source['Package.swift']==sha(proof/'snapshot/Package.swift')
    artifacts={p['path']:p['sha256'] for p in summary['artifacts']}
    def emit(platform):
        sdk='iphoneos' if platform=='ios' else 'iphonesimulator';out=root/'native-sdk'/platform;out.mkdir(parents=True)
        for name in ['CNativeClothCollision','CIPCBodyContact','CNativeClothSparse']:shutil.copytree(proof/platform/name,out/name)
        library=proof/platform/'libNativeClothCollision.a';assert sha(library)==artifacts[platform+'/'+library.name];shutil.copyfile(library,out/library.name)
        cmd=list(next(x['command'] for x in summary['results'] if x['label']==platform+'-swift-library'))
        cmd.remove('-emit-object');index=cmd.index('-o');del cmd[index:index+2]
        cmd[cmd.index('-emit-module-path')+1]=str(out/'NativeClothCollision.swiftmodule');cmd[cmd.index('-module-cache-path')+1]=str(root/(platform+'-native-module-cache'))
        for i,x in enumerate(cmd):
            for name in ['CNativeClothCollision','CIPCBodyContact','CNativeClothSparse']:
                if x==str(proof/platform/name):cmd[i]=str(out/name)
        cmd[1:1]=['--sdk',sdk]
        inputs=[Path(x) for x in cmd if x.endswith('.swift')]
        assert set(inputs)==set((proof/'snapshot/Sources/NativeClothCollision').glob('*.swift'))
        started=time.monotonic()
        with (root/(platform+'-native-module.log')).open('w') as log:process=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
        result={'label':platform+'-native-swift-module','command':cmd,'exitCode':process.returncode,'seconds':time.monotonic()-started,
                'archiveSHA256':sha(out/library.name),'sourceInputs':{str(p):sha(p) for p in inputs},'cppCompilationPerformed':False}
        if process.returncode==0:result['freshModuleFiles']={str(p.relative_to(out)):sha(p) for p in out.glob('NativeClothCollision.*') if p.is_file()}
        (root/(platform+'-native-module-command.json')).write_text(json.dumps(result,indent=2)+'\n');return result
    with ThreadPoolExecutor(max_workers=2) as pool:results=list(pool.map(emit,['ios','simulator-x86_64']))
    assert all(sha(proof/'snapshot'/p)==h for p,h in source.items())
    bound={str(p.relative_to(root)):sha(p) for p in (root/'native-sdk').rglob('*') if p.is_file()}
    binding={'passed':all(x['exitCode']==0 for x in results),'proof':str(proof),'deliveryManifestSHA256':sha(proof/'delivery-manifest.json'),
             'fullSourceManifestSHA256':sha(proof/'source-manifest.json'),'nativeSourceCount':len(actual),'results':results,'frozenSDKFiles':bound,
             'scope':'Reuse sealed SDK archives and C modulemaps/headers. Emit only matching Swift modules from all sealed Swift sources. No C++ compilation or Native suite rerun.'}
    (root/'native-sdk-binding.json').write_text(json.dumps(binding,indent=2)+'\n');return binding

def link_command(proof,root,platform,sources,smoke):
    proof=Path(proof).resolve();root=Path(root).resolve();summary=json.loads((proof/'summary.json').read_text())
    cmd=list(next(x['command'] for x in summary['results'] if x['label']==platform+'-CriticalFeatureSmoke-static-link'))
    cmd[cmd.index('-module-cache-path')+1]=str(root/(platform+'-consumer-cache'))
    for i,x in enumerate(cmd):
        if x==str(proof/platform) or any(x==str(proof/platform/n) for n in ['CNativeClothCollision','CIPCBodyContact','CNativeClothSparse']):cmd[i]=str(root/'native-sdk'/platform/Path(x).relative_to(proof/platform))
    index=next(i for i,x in enumerate(cmd) if x.endswith('/CriticalFeatureLinkSmoke.swift'));cmd[index:index+1]=list(map(str,sources))+[str(smoke)]
    cmd[cmd.index('-o')+1]=str(root/(platform+'-consumer-smoke'))
    cmd[2:2]=['-default-isolation','MainActor','-strict-concurrency=complete'];cmd[1:1]=['--sdk','iphoneos' if platform=='ios' else 'iphonesimulator']
    return cmd

def verify_after(binding,root):
    root=Path(root);proof=Path(binding['proof']);source=json.loads((proof/'source-manifest.json').read_text())
    return all(sha(root/p)==h for p,h in binding['frozenSDKFiles'].items()) and all(sha(proof/'snapshot'/p)==h for p,h in source.items()) and sha(proof/'delivery-manifest.json')==binding['deliveryManifestSHA256']
