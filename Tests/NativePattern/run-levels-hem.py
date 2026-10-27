#!/usr/bin/env python3
"""Compile only pure 2D models against independent pinned asymmetric-tier cases."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess,tempfile

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path)
parser.add_argument('--models-source',type=Path)
parser.add_argument('--expect-legacy-mismatch',action='store_true')
args=parser.parse_args()
repo=Path(__file__).resolve().parents[2]
out=args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='TailorAssLevelsHem.',dir='/private/tmp'))
out.mkdir(parents=True,exist_ok=True)
snapshot=out/'source'
if snapshot.exists():raise SystemExit('Refusing to overwrite frozen source')
models=args.models_source.resolve() if args.models_source else repo/'TrailorAss/Models'
names=['PatternDesignModels.swift','GarmentCodeGeometry.swift','GarmentCodePrograms.swift','GarmentCodeNativeGenerator.swift',
       'GarmentCodeLocalization.swift','GarmentCodeJointParameters.swift']
pairs=[(models/n,Path('TrailorAss/Models')/n) for n in names]
for relative in ['Tests/NativePattern/LevelsHem.swift','Tests/NativePattern/GenerateLevelsAsymmetricGoldens.py',
                 'Tests/NativePattern/run-levels-hem.py','Tests/NativePattern/Fixtures/levels-asymmetric-oracles.json',
                 'TrailorAss/Resources/GarmentCodeParameterCatalog.json','TrailorAss/Resources/GarmentCodeSiggraphShape.json']:
    pairs.append((repo/relative,Path(relative)))
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
before={str(a):sha(a) for a,_ in pairs}
for original,relative in pairs:
    target=snapshot/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(original,target)
assert all(sha(a)==before[str(a)]==sha(snapshot/b) for a,b in pairs)
cmd=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor',
     '-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-module-cache-path',str(out/'module-cache')]
cmd += [str(snapshot/'TrailorAss/Models'/n) for n in names]
cmd += [str(snapshot/'Tests/NativePattern/LevelsHem.swift'),'-o',str(out/'levels-hem')]
manifest={'scope':'Pure source geometry only; no native package, mesher, initialization or cloth simulation',
          'originalFiles':before,'snapshotFiles':{str(b):sha(snapshot/b) for _,b in pairs},'commands':[cmd]}
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
with (out/'build.log').open('w')as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
if r.returncode:
    print((out/'build.log').read_text()[-6000:]);raise SystemExit(r.returncode)
run=[str(out/'levels-hem'),str(snapshot),str(out),'legacy' if args.expect_legacy_mismatch else 'fixed']
with(out/'run.log').open('w')as log:r=subprocess.run(run,stdout=log,stderr=subprocess.STDOUT)
unchanged=all(sha(a)==before[str(a)]==sha(snapshot/b) for a,b in pairs)
summary={'exitCode':r.returncode,'passed':r.returncode==0 and unchanged,'frozenInputsUnchanged':unchanged,
         'commands':[cmd,run],'completeGarmentAccepted':False}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2));print((out/'run.log').read_text()[-4000:])
raise SystemExit(0 if summary['passed'] else 1)
