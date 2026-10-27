#!/usr/bin/env python3
"""Build independent full IPC references with only the normal-EE identity repair.
Requires the pinned original full reference's manifest/archive build; no production
serial builder is linked. Never modifies the original tree or archives.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess,difflib
p=argparse.ArgumentParser();p.add_argument('--official-source',type=Path,required=True);p.add_argument('--reference-manifest',type=Path,required=True);p.add_argument('--reference-build',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parent.parent;out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source=a.official_source.resolve()/'src/ipc/collisions/normal/edge_edge.cpp';original=source.read_text();pinned=json.loads((root/'Tests/Oracles/IPCFullSourceManifest.json').read_text())
assert sha(source)==pinned['files']['src/ipc/collisions/normal/edge_edge.cpp']['sha256']
patch=(root/'Tests/Oracles/OrientationIdentityCorrection.patch').read_text()
# Apply the archived, reviewable constructor-only unified diff without changing
# its pinned original input. A failed context is an error, never a guessed patch.
target=out/'corrected-edge-edge.cpp';target.write_text(original)
subprocess.run(['patch',str(target)],input=patch,text=True,capture_output=True,check=True)
meta=json.loads(a.reference_manifest.read_text());prefix=meta['compile'][:meta['compile'].index('-MD')];commands=[]
for src,name,extra in [(target,'corrected-edge-edge.o',['-I',str(source.parent)]),(root/'Tests/Oracles/IPCClothFullReference.cpp','cloth-reference.o',[]),(root/'Tests/Oracles/IPCBodyFullReference.cpp','body-reference.o',[])]:
 cmd=prefix+extra+['-c',str(src),'-o',str(out/name)];commands.append(cmd)
 with (out/(name+'.log')).open('w') as f:subprocess.run(cmd,cwd=a.reference_build,stdout=f,stderr=subprocess.STDOUT,check=True)
link=meta['link'];idx=next(i for i,x in enumerate(link) if x.endswith('/reference.o'));before=link[:idx];after=link[link.index('reference-ipc/libipc_toolkit.a'):]
for kind in ['cloth','body']:
 cmd=before+[str(out/(kind+'-reference.o')),str(out/'corrected-edge-edge.o'),'-o',str(out/(kind+'-corrected-full-reference'))]+after;commands.append(cmd)
 with (out/(kind+'-link.log')).open('w') as f:subprocess.run(cmd,cwd=a.reference_build,stdout=f,stderr=subprocess.STDOUT,check=True)
libs={name:sha(a.reference_build/name) for name in meta['linkedLibrariesSHA256']};assert libs==meta['linkedLibrariesSHA256']
m={'scope':'Independent full original IPC builder with constructor-only EE identity correction; no production builder linked','commit':pinned['commit'],'originalSourceSHA256':sha(source),'correctedSourceSHA256':sha(target),'patchSHA256':sha(root/'Tests/Oracles/OrientationIdentityCorrection.patch'),'originalLibrariesSHA256':libs,'references':{kind:sha(out/(kind+'-corrected-full-reference')) for kind in ['cloth','body']},'commands':commands}
(out/'manifest.json').write_text(json.dumps(m,indent=2)+'\n');print(out)
