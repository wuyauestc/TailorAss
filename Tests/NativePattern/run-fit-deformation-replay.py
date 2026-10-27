#!/usr/bin/env python3
from pathlib import Path
import argparse,json,hashlib,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--fit-fixtures',type=Path,default=Path(__file__).resolve().parent/'Fixtures/body-fit-replay');a=p.parse_args();repo=Path(__file__).resolve().parents[2]
out=a.output.resolve()if a.output else Path(tempfile.mkdtemp(prefix='TailorAssFitReplay.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True);snapshot=out/'snapshot';snapshot.mkdir();(snapshot/'models').mkdir();fixtures=out/'inputs';fixtures.mkdir()
names=['PatternDesignModels.swift','GarmentCodeGeometry.swift','GarmentCodePrograms.swift','GarmentCodeNativeGenerator.swift','GarmentCodeClothMaterial.swift','GarmentCodeClothContact.swift','GarmentCodeBodySurfaceContact.swift','GarmentCodeStandardBody.swift','GarmentCodeCircleDrape.swift','GarmentCodeBodySurfaceMeasurements.swift','GarmentCodeBodyRig.swift','GarmentCodeFitDeformationReplay.swift','GarmentCodeBodyMeshQueries.swift','GarmentCodeBodySurfaceFitter.swift','GarmentCodeBodySurfaceValidator.swift','GarmentCodeFittedBody.swift']
for name in names:shutil.copy2(repo/'TrailorAss/Models'/name,snapshot/'models'/name)
shutil.copy2(repo/'Tests/NativePattern/FitDeformationReplay.swift',snapshot/'FitDeformationReplay.swift');shutil.copytree(repo/'TrailorAss/Resources',snapshot/'resources')
for name in ['default','female']:
 source=a.fit_fixtures/(name+'-attempt.json')
 if not source.exists():source=a.fit_fixtures/(name+'-replay-golden.json')
 shutil.copy2(source,fixtures/(name+'-input.json'))
sha=lambda q:hashlib.sha256(q.read_bytes()).hexdigest();files={str(q):sha(q)for q in list(snapshot.rglob('*'))+list(fixtures.rglob('*'))if q.is_file()};(out/'input-manifest.json').write_text(json.dumps(files,indent=2)+'\n')
command=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]+[str(snapshot/'models'/n)for n in names]+[str(snapshot/'FitDeformationReplay.swift'),'-o',str(out/'replay')]
commands=[]
for label,cmd in [('strict-compile',command),('actual-replay',[str(out/'replay'),str(snapshot/'resources'),str(fixtures),str(out)])]:
 start=time.monotonic()
 with (out/(label+'.log')).open('w')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
 commands.append({'label':label,'command':cmd,'exitCode':r.returncode,'seconds':time.monotonic()-start});(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n');print(label,r.returncode,flush=True)
 if r.returncode:break
summary={'passed':r.returncode==0 and all(sha(Path(q))==h for q,h in files.items()),'steps':commands,'clothRun':False,'bodyCapabilityIssued':False};(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');raise SystemExit(r.returncode)
