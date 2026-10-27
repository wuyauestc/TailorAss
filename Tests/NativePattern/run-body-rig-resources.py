#!/usr/bin/env python3
from pathlib import Path
import argparse,copy,hashlib,json,os,re,shutil,subprocess,tempfile
from ValidateBodyRig import validate
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);p.add_argument('--source-dir',type=Path);a=p.parse_args()
repo=Path(__file__).resolve().parents[2];out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssBodyRigCheck.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True)
bundle=repo/'TrailorAss/Resources/GarmentCodeStandardBodyRig';body=repo/'TrailorAss/Resources/GarmentCodeStandardBody.json'
checks=validate(bundle,body,a.source_dir)
negative=[]
def malformed(label,change):
 with tempfile.TemporaryDirectory(prefix='invalid-rig-',dir=out) as path:
  path=Path(path);shutil.copytree(bundle,path/'bundle');target=path/'bundle';rig=json.loads((target/'rig.json').read_bytes());change(rig)
  encoded=(json.dumps(rig,separators=(',',':'),allow_nan=False)+'\n').encode();(target/'rig.json').write_bytes(encoded)
  meta=json.loads((target/'provenance.json').read_bytes());meta['rigResourceSHA256']=hashlib.sha256(encoded).hexdigest();(target/'provenance.json').write_text(json.dumps(meta))
  try:validate(target,body)
  except ValueError as error:negative.append({'case':label,'refused':True,'reason':str(error)})
  else:raise AssertionError('Malformed rig accepted: '+label)
malformed('unknown influence bone',lambda r:r['weights']['boneIndices'].__setitem__(0,999))
malformed('unweighted current vertex',lambda r:r['weights']['vertexOffsets'].__setitem__(1,0))
malformed('negative source weight',lambda r:r['weights']['rawValues'].__setitem__(0,-0.1))
malformed('changed weight proportions',lambda r:r['weights']['normalizedValues'].__setitem__(0,0.25))
malformed('broken source-visible identity',lambda r:r['sourceToVisible'].__setitem__(r['visibleToSource'][0],1))
malformed('bone hierarchy cycle',lambda r:r['bones'][r['boneEvaluationOrder'][0]].__setitem__('parent',r['boneEvaluationOrder'][0]))
protected=[repo/'TrailorAss/Resources'/n for n in ['GarmentCodeStandardBody.json','GarmentCodeStandardBodySDF.bin','GarmentCodeStandardBodySource.json','MakeHuman-CC0-LICENSE.txt']];before={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in protected}
snapshot=out/'source';(snapshot/'TrailorAss/Models').mkdir(parents=True,exist_ok=False);(snapshot/'Tests/NativePattern/Fixtures').mkdir(parents=True)
text=(repo/'Tests/NativePattern/run-upper-placement.sh').read_text();names=re.search(r'for model in ([\s\S]*?); do',text).group(1).replace('\\\n',' ').split()
for name in names:shutil.copy2(repo/'TrailorAss/Models'/name,snapshot/'TrailorAss/Models'/name)
shutil.copytree(repo/'TrailorAss/Resources',snapshot/'TrailorAss/Resources')
shutil.copy2(repo/'Tests/NativePattern/BodyRigSleeveAxes.swift',snapshot/'Tests/NativePattern/BodyRigSleeveAxes.swift')
shutil.copy2(repo/'Tests/NativePattern/Fixtures/body-rig-sleeve-axes.json',snapshot/'Tests/NativePattern/Fixtures/body-rig-sleeve-axes.json')
manifest={str(f.relative_to(snapshot)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(snapshot.rglob('*')) if f.is_file()};(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
cmd=['xcrun','swiftc','-O','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-module-cache-path',str(out/'module-cache')]+[str(snapshot/'TrailorAss/Models'/name) for name in names]+[str(snapshot/'Tests/NativePattern/BodyRigSleeveAxes.swift'),'-o',str(out/'body-rig-axes')]
with (out/'compile.log').open('w') as log:r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT)
if r.returncode:raise SystemExit(r.returncode)
with (out/'run.log').open('w') as log:r=subprocess.run([str(out/'body-rig-axes'),str(snapshot),str(out/'sleeve-axis-results.json')],stdout=log,stderr=subprocess.STDOUT)
unchanged=all(hashlib.sha256(f.read_bytes()).hexdigest()==before[str(f)] for f in protected);frozen=all(hashlib.sha256((snapshot/name).read_bytes()).hexdigest()==h for name,h in manifest.items())
summary={'passed':r.returncode==0 and unchanged and frozen,'rig':checks,'malformedDataControls':negative,'existingBodyAndSDFBytesUnchanged':unchanged,'snapshotUnchanged':frozen,'protectedSHA256':before,'compileCommand':cmd,'scope':'Optional data preparation and coordinate conventions only; no fitter/pose runtime installed'}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2));raise SystemExit(0 if summary['passed'] else 1)
