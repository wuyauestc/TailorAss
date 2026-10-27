#!/usr/bin/env python3
"""Research-only: compile the independent FULL official IPC builder reference.
Requires an existing official-reference Ninja build of pinned v1.6.1 with
original TBB/Eigen dependencies. No download and no production port is linked.
Use its --canonical-candidates option when recreating sparse Hessian goldens.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,shlex
p=argparse.ArgumentParser();p.add_argument('--upstream-dir',type=Path,required=True);p.add_argument('--reference-build-dir',type=Path,required=True);p.add_argument('--ninja',default='ninja');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
pkg=Path(__file__).resolve().parent.parent;out=a.output.resolve();out.mkdir(parents=True,exist_ok=True);build=a.reference_build_dir.resolve()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((pkg/'Tests/Oracles/IPCFullSourceManifest.json').read_text());assert m['commit']=='19bcab7e1f5a0d2addfcd28513422ff248ea504e'
for f,w in m['files'].items():
 b=(a.upstream_dir/f).read_bytes();assert hashlib.sha256(b).hexdigest()==w['sha256'],f
 assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==w['gitBlobSHA1'],f
source=pkg/'Tests/Oracles/IPCClothFullReference.cpp'
lines=subprocess.check_output([a.ninja,'-C',str(build),'-t','commands','official-reference'],text=True).splitlines()
args=shlex.split(next(x for x in lines if ' -c ' in x and 'Reference.cpp' in x));compiled=[];i=0
while i<len(args):
 x=args[i]
 if x in ['-o','-MF','-MT']:
  compiled += [x,str(out/('reference.d' if x=='-MF' else 'reference.o'))];i+=2;continue
 if x.endswith('Reference.cpp'):x=str(source)
 compiled.append(x);i+=1
# Do not silently compile against a different toolkit source tree.
assert any(x.startswith('-I') and Path(x[2:]).resolve()==a.upstream_dir.resolve()/'src' for x in compiled),'Ninja build does not use requested upstream'
record={'commit':m['commit'],'sourceSHA256':sha(source),'upstreamManifestSHA256':sha(pkg/'Tests/Oracles/IPCFullSourceManifest.json'),'originalFullLibraryNotSerialPort':True,'compile':compiled}
def run(command,label):
 q=subprocess.run(command,cwd=build,capture_output=True,text=True);(out/(label+'.log')).write_text(q.stdout+q.stderr)
 if q.returncode:raise SystemExit(label+' failed; see '+str(out))
run(compiled,'compile')
line=next(x for x in reversed(lines) if ' -o official-reference ' in x);link=shlex.split(next(x for x in line.split('&&') if ' -o official-reference ' in x))
for i,x in enumerate(link):
 if x.endswith('Reference.cpp.o'):link[i]=str(out/'reference.o')
 if x=='official-reference' and i>0 and link[i-1]=='-o':link[i]=str(out/'ipc-cloth-full-reference')
record['link']=link;record['linkedLibrariesSHA256']={x:sha(build/x) for x in link if x.endswith('.a')};run(link,'link')
record['binarySHA256']=sha(out/'ipc-cloth-full-reference');(out/'manifest.json').write_text(json.dumps(record,indent=2)+'\n');print(out/'ipc-cloth-full-reference')
