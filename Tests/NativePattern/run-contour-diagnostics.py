#!/usr/bin/env python3
"""Original-source early crossing witnesses; no native package or simulation."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path)
p.add_argument('--catalog-inputs',type=Path,help='Optional frozen catalog export root containing inputs/')
a=p.parse_args();repo=Path(__file__).resolve().parents[2]
out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssContourDiagnostics.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True);snapshot=out/'source'
if snapshot.exists():raise SystemExit('Refusing to overwrite frozen source')
names=['PatternDesignModels.swift','GarmentCodeGeometry.swift','GarmentCodePrograms.swift','GarmentCodeNativeGenerator.swift','GarmentCodeLocalization.swift','GarmentCodeJointParameters.swift','GarmentCodeContourDiagnostics.swift']
pairs=[(repo/'TrailorAss/Models'/n,Path('TrailorAss/Models')/n) for n in names]
for relative in ['Tests/NativePattern/ContourDiagnostics.swift','Tests/NativePattern/Fixtures/source-contour-crossings.json','Tests/NativePattern/Fixtures/contour-diagnostics/nearly-parallel-simple.json','Tests/NativePattern/run-contour-diagnostics.py']:
    pairs.append((repo/relative,Path(relative)))
if a.catalog_inputs:
    root=a.catalog_inputs.resolve()/'inputs';manifest=json.loads((root/'catalog-input-manifest.json').read_text())
    files={'catalog-input-manifest.json'}|{x['patternFile'] for x in manifest['cases']}
    pairs += [(root/name,Path('Catalog/inputs')/name) for name in sorted(files)]
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
original={str(f):sha(f) for f,_ in pairs}
for f,r in pairs:
    target=snapshot/r;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,target)
assert all(original[str(f)]==sha(f)==sha(snapshot/r) for f,r in pairs)
command=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
command += [str(snapshot/'TrailorAss/Models'/n) for n in names]
command += [str(snapshot/'Tests/NativePattern/ContourDiagnostics.swift'),'-o',str(out/'contour-diagnostics')]
commands=[command,[str(out/'contour-diagnostics'),str(snapshot),str(out)]]
(out/'source-manifest.json').write_text(json.dumps({'originalFiles':original,'files':{str(r):sha(snapshot/r) for _,r in pairs},'commands':commands},indent=2)+'\n')
executed=[]
for i,cmd in enumerate(commands):
    log=out/('build.log' if i==0 else 'run.log')
    with log.open('w') as f:result=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT)
    executed.append({'command':cmd,'exitCode':result.returncode})
    if result.returncode:print(log.read_text()[-6000:]);break
unchanged=all(original[str(f)]==sha(f)==sha(snapshot/r) for f,r in pairs)
summary={'passed':result.returncode==0 and unchanged,'frozenInputsUnchanged':unchanged,'commands':executed,'completeGarmentAccepted':False}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
raise SystemExit(0 if summary['passed'] else 1)
