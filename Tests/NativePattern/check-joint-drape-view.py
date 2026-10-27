#!/usr/bin/env python3
"""Typecheck the actual 3D menu, both pages, and production iOS dependencies."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, tempfile, time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path)
parser.add_argument('--package-proof', type=Path, required=True)
a = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
out = a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointDrapeView.', dir='/private/tmp'))
out.mkdir(parents=True, exist_ok=True)
source = out / 'source'
source.mkdir(exist_ok=False)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
def hashes(directory):
    return {str(f.relative_to(directory)): sha(f) for f in directory.rglob('*') if f.is_file()}

shared = (repo / 'Tests/NativePattern/run-joint-input.sh').read_text()
lifecycle_names = re.search(r'for model in ([\s\S]*?); do', shared).group(1).replace('\\\n', ' ').split()
lifecycle_names += ['GarmentCodeMembranePath.swift', 'GarmentCodeJointBodyObjective.swift', 'GarmentCodeJointPreconditioner.swift',
                    'GarmentCodeJointContactPreconditioner.swift', 'GarmentCodeJointNewton.swift', 'GarmentCodeJointGarmentObjective.swift',
                    'GarmentCodeJointSimulation.swift', 'GarmentCodeBodyMeshQueries.swift', 'GarmentCodeVisibleBodyInspection.swift',
                    'GarmentCodeJointResult.swift', 'GarmentCodeJointFabric.swift', 'GarmentCodeJointWorkflow.swift',
                    'GarmentCodeMeshExport.swift', 'GarmentCodeLocalization.swift', 'GarmentCodeJointParameters.swift']
lifecycle_names = list(dict.fromkeys(lifecycle_names))
# NativeDesignView owns the real menu and its complete 2D/PDF/legacy branches.
# Include their actual sources instead of declaring fake SwiftUI destinations.
files = [repo / 'TrailorAss/Models/PatternDesignModels.swift']
files += sorted((repo / 'TrailorAss/Models').glob('GarmentCode*.swift'))
files += sorted((repo / 'TrailorAss/Views/Garment').glob('GarmentCode*.swift'))
files += sorted((repo / 'TrailorAss/Services').glob('GarmentCode*.swift'))
files += [repo / 'TrailorAss/App/AppTheme.swift']
before = {str(f): sha(f) for f in files}
manifest = []
for f in files:
    shutil.copy2(f, source / f.name)
    manifest.append({'source': str(f), 'snapshot': f.name, 'sha256': sha(f)})
assert all(sha(Path(f)) == h for f, h in before.items()), 'Source changed during copy'
assert all((source / name).is_file() for name in lifecycle_names)
route = (source / 'GarmentCodeNativeDesignView.swift').read_text()
page = (source / 'GarmentCodeJointDrapeView.swift').read_text()
route_checks = {
    'wholeGarmentMenu': 'Button("整衣 3D（实验）"' in route and 'drapeDestination = .wholeGarment' in route,
    'legacyPreviewMenu': 'Button("裙装与腰头预览"' in route and 'drapeDestination = .legacyPreview' in route,
    'actualJointDestination': 'case .wholeGarment:\n                GarmentCodeJointDrapeView(document: document)' in route,
    'actualLegacyDestination': 'case .legacyPreview:\n                GarmentCodeDrapeView(document: document)' in route,
    'explicitShapeForwarding': 'bodyShapeSelection:shape' in page,
    'materialInvalidatesPublication': 'set:{model.selectMaterial($0)}' in page and 'material=selection;materialChanged()' in page,
    'shapeInvalidatesPublication': 'set:{model.selectBodyShape($0)}' in page and 'bodyShapeSelection=selection;bodyShapeChanged()' in page,
    'poseInvalidatesPublication': 'set:{model.selectBodyPose($0)}' in page and 'bodyPoseSelection=selection;bodyPoseChanged()' in page,
    'fittedPoseNormalized': 'if bodyShapeSelection == .surfaceMeasurements {bodyPoseSelection = .matchPatternReference}' in page,
    'onlyValidatedPresentation': 'output:shown.result.validated.output' in page,
    'experimentalCoverageNotice': '部分款式仍在验证' in page,
}
assert all(route_checks.values()), route_checks
proof = a.package_proof.resolve()
proof_summary = json.loads((proof / 'summary.json').read_text())
assert proof_summary['passed'] and proof_summary['macTestsExecuted'] >= 91
native_before = hashes(proof / 'snapshot/Sources')
assert hashes(repo / 'NativeClothCollision/Sources') == native_before, 'Current native sources differ from proof'
if (proof / 'delivery-manifest.json').exists():
    delivery = json.loads((proof / 'delivery-manifest.json').read_text())
    assert delivery['nativeSources'] == native_before, 'Proof compiled Sources do not match snapshot'
bindings = []
platforms = [('ios', 'iphoneos', 'arm64-apple-ios17.0'), ('simulator-x86_64', 'iphonesimulator', 'x86_64-apple-ios17.0-simulator')]
for folder, _, _ in platforms:
    dep = proof / folder
    for directory in [dep, dep / 'CNativeClothCollision', dep / 'CIPCBodyContact', dep / 'CNativeClothSparse']:
        assert directory.is_dir(), directory
        for f in directory.rglob('*'):
            if f.is_file() and (f.suffix in {'.swiftmodule', '.swiftdoc', '.swiftinterface', '.modulemap', '.h'} or f.name.endswith('.abi.json')):
                bindings.append({'path': str(f), 'sha256': sha(f)})
bindings += [{'path': str(proof / 'summary.json'), 'sha256': sha(proof / 'summary.json')}]
# The lifecycle test selects only these exact model bytes from this larger UI snapshot.
(out / 'source-manifest.json').write_text(json.dumps({'files': manifest, 'lifecycleModels': lifecycle_names,
    'nativeModules': bindings, 'nativeSources': native_before, 'routingChecks': route_checks}, indent=2) + '\n')
commands = []
for folder, sdk_name, target in platforms:
    dep = proof / folder
    sdk = subprocess.check_output(['xcrun', '--sdk', sdk_name, '--show-sdk-path'], text=True).strip()
    cmd = ['xcrun', 'swiftc', '-disable-sandbox', '-typecheck', '-parse-as-library', '-swift-version', '5',
           '-default-isolation', 'MainActor', '-strict-concurrency=complete', '-enable-upcoming-feature', 'MemberImportVisibility',
           '-warnings-as-errors', '-target', target, '-sdk', sdk, '-module-cache-path', str(out / ('module-cache-' + folder))]
    for d in [dep, dep / 'CNativeClothCollision', dep / 'CIPCBodyContact', dep / 'CNativeClothSparse']:
        cmd += ['-I', str(d)]
    cmd += [str(source / f.name) for f in files]
    began = time.monotonic()
    with (out / (folder + '-typecheck.log')).open('w') as log:
        result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
    commands.append({'platform': folder, 'command': cmd, 'exitCode': result.returncode, 'seconds': time.monotonic() - began})
    if result.returncode:
        break
snapshot_ok = all(sha(source / x['snapshot']) == x['sha256'] for x in manifest)
original_ok = all(sha(Path(f)) == h for f, h in before.items())
native_ok = all(sha(Path(x['path'])) == x['sha256'] for x in bindings)
native_ok = native_ok and hashes(repo / 'NativeClothCollision/Sources') == native_before and hashes(proof / 'snapshot/Sources') == native_before
report = {'passed': len(commands) == 2 and all(x['exitCode'] == 0 for x in commands) and snapshot_ok and original_ok and native_ok,
          'commands': commands, 'snapshotUnchanged': snapshot_ok, 'originalSourcesUnchanged': original_ok, 'nativeUnchanged': native_ok,
          'routingChecks': route_checks, 'nativeTestsExecutedInReusedProof': proof_summary['macTestsExecuted'],
          'nativePackageRecompiled': False, 'pageRouted': True, 'uiRuntimeTested': False, 'completeGarmentProduced': False}
(out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
print(out)
print(json.dumps({k:v for k,v in report.items() if k != 'commands'}))
raise SystemExit(0 if report['passed'] else 1)
