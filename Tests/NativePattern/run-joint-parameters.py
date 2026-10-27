#!/usr/bin/env python3
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);a=p.parse_args();r=Path(__file__).resolve().parents[2];o=a.output.resolve()if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointParameters.',dir='/private/tmp'));o.mkdir(parents=True,exist_ok=True);s=o/'source';s.mkdir(exist_ok=False)
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeLocalization','GarmentCodeJointParameters'];files=[r/'TrailorAss/Models'/(n+'.swift')for n in models]+[r/'Tests/NativePattern/JointParameters.swift',r/'TrailorAss/Resources/GarmentCodeParameterCatalog.json'];sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();manifest=[]
for f in files:shutil.copy2(f,s/f.name);manifest.append({'source':str(f),'snapshot':f.name,'sha256':sha(f)})
(o/'source-manifest.json').write_text(json.dumps(manifest,indent=2));cmd=['xcrun','swiftc','-O','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(o/'module-cache')]+[str(s/(n+'.swift'))for n in models]+[str(s/'JointParameters.swift'),'-o',str(o/'joint-parameters')];commands=[]
for label,cmd in [('compile',cmd),('roundtrip-and-refusals',[str(o/'joint-parameters'),str(s),str(o)])]:
 t=time.monotonic();p=subprocess.run(cmd,capture_output=True,text=True);(o/(label+'.log')).write_text(p.stdout+p.stderr);commands.append({'label':label,'command':cmd,'exit':p.returncode,'seconds':time.monotonic()-t});(o/'commands.json').write_text(json.dumps(commands,indent=2))
 if p.returncode:print(p.stdout+p.stderr);print(o);raise SystemExit(p.returncode)
result=json.loads((o/'joint-parameters-summary.json').read_text());result['snapshotUnchanged']=all(sha(s/x['snapshot'])==x['sha256']for x in manifest);result['commands']=commands;(o/'summary.json').write_text(json.dumps(result,indent=2));print(o)
