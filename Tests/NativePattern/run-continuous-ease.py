#!/usr/bin/env python3
"""Strict full-source continuous-ease controls; reuses a sealed native package.
No Newton/full garment simulation is started. Native source/archive bindings,
all models, fixtures and resources are copied and hashed before compilation.
"""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,subprocess,tempfile,time
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);p.add_argument('--package-proof',type=Path,required=True);a=p.parse_args()
repo=Path(__file__).resolve().parents[2];out=a.output.resolve()if a.output else Path(tempfile.mkdtemp(prefix='TailorAssContinuousEase.',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True);src=out/'source'
if src.exists():raise SystemExit('Refusing to overwrite a frozen source')
sha=lambda q:hashlib.sha256(q.read_bytes()).hexdigest()
def hashes(root):return {str(q.relative_to(root)):sha(q)for q in sorted(root.rglob('*'))if q.is_file()and not any(v in {'.build','.swiftpm'}for v in q.relative_to(root).parts)}
proof=a.package_proof.resolve();proof_summary=json.loads((proof/'summary.json').read_text());assert proof_summary['passed']and proof_summary['macTestsExecuted']>=129,'A complete verified native package is required'
native=repo/'NativeClothCollision';assert hashes(native/'Sources')==hashes(proof/'snapshot/Sources'),'Current native source differs from sealed proof'
lib=proof/'swiftpm/arm64-apple-macosx/release';includes=[lib/'Modules',proof/'snapshot/Sources/CNativeClothCollision/include',lib/'CIPCBodyContact.build',lib/'CNativeClothSparse.build'];deps=[lib/'libNativeClothCollision.a',proof/'summary.json',proof/'delivery-manifest.json']
for d in includes:assert d.is_dir();deps += [q for q in d.rglob('*')if q.is_file()and q.suffix in {'.swiftmodule','.swiftdoc','.modulemap','.h'}]
dependencies={str(q):sha(q)for q in deps};(out/'native-dependencies.json').write_text(json.dumps(dependencies,indent=2)+'\n')
names=re.search(r'for model in ([\s\S]*?); do',(repo/'Tests/NativePattern/run-joint-input.sh').read_text()).group(1).replace('\\\n',' ').split()
names+=['GarmentCodeMembranePath.swift','GarmentCodeJointBodyObjective.swift','GarmentCodeJointPreconditioner.swift','GarmentCodeJointContactPreconditioner.swift','GarmentCodeJointNewton.swift','GarmentCodeJointGarmentObjective.swift','GarmentCodeJointSimulation.swift','GarmentCodeBodyMeshQueries.swift','GarmentCodeVisibleBodyInspection.swift','GarmentCodeJointResult.swift','GarmentCodeJointParameters.swift','GarmentCodeLocalization.swift','GarmentCodeWaistbandDrape.swift'];names=list(dict.fromkeys(names));models=src/'TrailorAss/Models';models.mkdir(parents=True)
originals={str(repo/'TrailorAss/Models'/n):sha(repo/'TrailorAss/Models'/n)for n in names}
for n in names:shutil.copyfile(repo/'TrailorAss/Models'/n,models/n)
tests=src/'Tests/NativePattern';tests.mkdir(parents=True)
for n in ['ContinuousEase.swift','EasedBudgetFallback.swift','Sewing.swift','SewnInput.swift','ContinuousEaseFractionCheck.py','JointContinuousSeamAudit.py']:
 q=repo/'Tests/NativePattern'/n;originals[str(q)]=sha(q);shutil.copyfile(q,tests/n)
fixtures=repo/'Tests/NativePattern/Fixtures/3d-continuous-ease';fm=json.loads((fixtures/'manifest.json').read_text());assert all(sha(fixtures/k)==v for k,v in fm['filesSHA256'].items()),'Fixture changed'
shutil.copytree(fixtures,tests/'Fixtures/3d-continuous-ease')
for n in ['waistband-straight.json','skirt-two-panel.json']:shutil.copyfile(repo/'Tests/NativePattern/Fixtures'/n,tests/'Fixtures'/n)
shutil.copytree(repo/'TrailorAss/Resources',src/'TrailorAss/Resources')
before=hashes(src);(out/'source-manifest.json').write_text(json.dumps({'scope':'Full-source sewing/input and independent complete-boundary controls; no physical integration or final capability','nativeProof':str(proof),'nativeMacTestsExecuted':proof_summary['macTestsExecuted'],'modelsOriginalSHA256':originals,'filesSHA256':before},indent=2)+'\n')
cmd=['xcrun','swiftc','-O','-whole-module-optimization','-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors','-parse-as-library','-D','CONTINUOUS_EASE_REGRESSION','-D','SEWN_INPUT_INTEGRATION','-module-cache-path',str(out/'module-cache')]
for d in includes:cmd+=['-I',str(d)]
cmd+=list(map(str,sorted(models.glob('*.swift'))))+[str(tests/n)for n in ['Sewing.swift','SewnInput.swift','ContinuousEase.swift','EasedBudgetFallback.swift']]+['-L',str(lib),'-lNativeClothCollision','-lc++','-framework','Accelerate','-o',str(out/'continuous-ease')]
commands=[]
def run(command,log,env=None):
 t=time.monotonic()
 with log.open('w')as f:r=subprocess.run(command,stdout=f,stderr=subprocess.STDOUT,env=env)
 commands.append({'command':command,'exitCode':r.returncode,'seconds':time.monotonic()-t});return r.returncode
code=run(cmd,out/'compile.log');result=out/'result';result.mkdir()
if code==0:
 env=dict(os.environ,GARMENTCODE_SEWN_INPUT_OUTPUT=str(out/'sewn-input'))
 code=run([str(out/'continuous-ease'),str(src),str(result)],out/'run.log',env)
if code==0:code=run(['python3',str(tests/'ContinuousEaseFractionCheck.py'),str(out),str(out/'fraction-check.json')],out/'fraction-check.log')
unchanged=hashes(src)==before and all(sha(Path(k))==v for k,v in originals.items())and all(sha(Path(k))==v for k,v in dependencies.items())
summary={'passed':code==0 and unchanged,'exitCode':code,'snapshotAndOriginalInputsUnchanged':unchanged,'commands':commands,'nativeRebuilt':False,'nativeProofMacTestsExecuted':proof_summary['macTestsExecuted'],'physicsOrNewtonRun':False,'RValidatedProduced':False,'output':str(out)}
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
if code:
 print('LAST_LOG',commands[-1]['command'][0]);print((out/('compile.log'if len(commands)==1 else 'run.log'if len(commands)==2 else'fraction-check.log')).read_text()[-10000:])
raise SystemExit(0 if summary['passed'] else 1)
