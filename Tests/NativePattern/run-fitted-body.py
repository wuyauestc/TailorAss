#!/usr/bin/env python3
"""Source-bound opt-in fitted body factory, complete surface and real SDK proof."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse,hashlib,json,shutil,subprocess,tempfile,time,sys
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);p.add_argument('--package-proof',type=Path,required=True);p.add_argument('--python-packages',type=Path);a=p.parse_args()
repo=Path(__file__).resolve().parents[2];out=a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssFittedBodyFinal-',dir='/private/tmp'));out.mkdir(parents=True,exist_ok=True)
s=out/'snapshot';(s/'models').mkdir(parents=True,exist_ok=False);(s/'resources/GarmentCodeStandardBodyRig').mkdir(parents=True)
models=['PatternDesignModels','GarmentCodeGeometry','GarmentCodePrograms','GarmentCodeNativeGenerator','GarmentCodeClothMaterial','GarmentCodeClothContact','GarmentCodeBodySurfaceContact','GarmentCodeStandardBody','GarmentCodeCircleDrape','GarmentCodeBodySurfaceMeasurements','GarmentCodeFitDeformationReplay','GarmentCodeBodySurfaceFitter','GarmentCodeBodyMeshQueries','GarmentCodeBodySurfaceValidator','GarmentCodeFittedBody']
files=[(repo/'TrailorAss/Models'/(n+'.swift'),s/'models'/(n+'.swift')) for n in models]
files += [(repo/'Tests/NativePattern'/n,s/'models'/n) for n in ['FittedBody.swift','FittedBodySDKSmoke.swift','BoundNativeSDK.py','ExactBodySurfaceGeometry.py','ValidateFittedBody.py','run-fitted-body.py']]
for name in ['GarmentCodeParameterCatalog.json','GarmentCodeStandardBody.json','GarmentCodeStandardBodySDF.bin','GarmentCodeStandardBodySource.json','GarmentCodeBodySurfaceMeasurements.json','GarmentCodeBodyFitAuxiliaryWeights.json','GarmentCodeStandardBodyRig/rig.json']:files.append((repo/'TrailorAss/Resources'/name,s/'resources'/name))
files.append((repo/'Tests/NativePattern/Fixtures/female-standing-mesher-source.json',s/'female-standing-mesher-source.json'))
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();manifest=[]
for source,target in files:
    before=sha(source);shutil.copyfile(source,target);assert before==sha(target)==sha(source);manifest.append({'original':str(source),'path':str(target.relative_to(s)),'sha256':before})
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');sys.path.insert(0,str(s/'models'));import BoundNativeSDK as SDK
native=SDK.prepare(a.package_proof,out);commands=list(native['results'])
def run(label,command,expected_failure=False):
    started=time.monotonic()
    with (out/(label+'.log')).open('w') as log:process=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT)
    return {'label':label,'command':command,'exitCode':process.returncode,'expectedFailure':expected_failure,'passed':process.returncode!=0 if expected_failure else process.returncode==0,'seconds':time.monotonic()-started}
def all_passed():return all(c.get('passed',c['exitCode']==0) for c in commands)
common=['-swift-version','5','-default-isolation','MainActor','-strict-concurrency=complete','-warnings-as-errors'];sources=[str(s/'models'/(n+'.swift')) for n in models]
jobs=[('strict-compile',['xcrun','swiftc','-O']+common+['-module-cache-path',str(out/'module-cache')]+sources+[str(s/'models/FittedBody.swift'),'-o',str(out/'fitted-body')]),('actual-factory-and-controls',[str(out/'fitted-body'),str(s),str(out)])]
if native['passed']:
    for label,command in jobs:
        commands.append(run(label,command));(out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
        if not all_passed():break
if all_passed():
    attack=out/'forge-receipt.swift';attack.write_text('''import Foundation
func forge(_ mesh: GarmentCodeBodySurfaceContact.BodyMesh, _ bindings: GarmentCodeFittedBody.Bindings, _ certificate: GarmentCodeBodySurfaceValidator.Certificate, _ recipe: GarmentCodeFittedBody.Recipe) {
    _ = GarmentCodeFittedBody.SurfaceReceipt.issue(mesh: mesh, bindings: bindings, certificate: certificate, originalRecipe: recipe)
}
''')
    decode=out/'decode-receipt.swift';decode.write_text('''import Foundation
func forge(_ bytes: Data) throws { _ = try JSONDecoder().decode(GarmentCodeFittedBody.SurfaceReceipt.self, from: bytes) }
''')
    for label,source in [('private-receipt-negative',attack),('decode-receipt-negative',decode)]:
        commands.append(run(label,['xcrun','swiftc','-typecheck']+common+['-module-cache-path',str(out/(label+'-cache'))]+sources+[str(source)],True))
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
if all_passed():
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(run,'sdk-static-link-'+platform,SDK.link_command(a.package_proof,out,platform,sources,s/'models/FittedBodySDKSmoke.swift')) for platform in ['ios','simulator-x86_64']]
        commands.extend(f.result() for f in futures)
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
if all_passed():
    oracle=[sys.executable,str(s/'models/ValidateFittedBody.py'),str(out)]
    if a.python_packages:oracle+=['--python-packages',str(a.python_packages.resolve())]
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures=[pool.submit(run,'independent-final-'+name,oracle+['--profile',name]) for name in ['default','female']]
        commands.extend(f.result() for f in futures)
    (out/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
unchanged=all(sha(s/r['path'])==r['sha256'] and sha(Path(r['original']))==r['sha256'] for r in manifest);native_unchanged=SDK.verify_after(native,out)
report={'passed':len(commands)==10 and all_passed() and unchanged and native_unchanged,'commands':commands,'compiledModels':models,'sourceInputsUnchanged':unchanged,'nativeBoundInputsUnchanged':native_unchanged,
        'actualPrivateSurfaceReceiptsIssued':all(any(c['label']=='actual-factory-and-controls' and c['exitCode']==0 for c in commands) for _ in [0]),'SDKArchivesLinked':all(any(c['label']=='sdk-static-link-'+platform and c['exitCode']==0 for c in commands) for platform in ['ios','simulator-x86_64']),
        'nativeCPPRecompiled':False,'nativeSwiftInterfacesReemitted':True,'deviceOrSimulatorLaunched':False,'legacyBodyOrSDFModified':False,'clothSimulationRun':False,'scope':'Opt-in fixed fitted body preparation only. No default routing, swept deformation or cloth simulation proof.','output':str(out)}
(out/'summary.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2));raise SystemExit(0 if report['passed'] else 1)
