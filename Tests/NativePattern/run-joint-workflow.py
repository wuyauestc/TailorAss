#!/usr/bin/env python3
"""Test actual async preparation/cancellation/failure using a frozen native library."""
from pathlib import Path
import argparse, hashlib, json, re, shutil, subprocess, tempfile, time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path)
p.add_argument('--package-proof', type=Path, required=True)
p.add_argument('--positive-waistband', action='store_true', help='Also run a real default waistband to final acceptance through the async App workflow')
p.add_argument('--gathered-only', action='store_true', help='Only prepare a real gathered source and verify App refusal before any numerical assembly')
a = p.parse_args()
if a.gathered_only and a.positive_waistband:
    p.error('--gathered-only and --positive-waistband cannot be combined')
repo = Path(__file__).resolve().parents[2]
out = a.output.resolve() if a.output else Path(tempfile.mkdtemp(prefix='TailorAssJointWorkflow.', dir='/private/tmp'))
out.mkdir(parents=True, exist_ok=True)
source = out / 'source'
source.mkdir(exist_ok=False)
sha = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
script = (repo / 'Tests/NativePattern/run-joint-input.sh').read_text()
names = re.search(r'for model in ([\s\S]*?); do', script).group(1).replace('\\\n', ' ').split()
names += ['GarmentCodeMembranePath.swift', 'GarmentCodeJointBodyObjective.swift',
          'GarmentCodeJointPreconditioner.swift', 'GarmentCodeJointContactPreconditioner.swift',
          'GarmentCodeJointNewton.swift', 'GarmentCodeJointGarmentObjective.swift',
          'GarmentCodeJointSimulation.swift', 'GarmentCodeBodyMeshQueries.swift',
          'GarmentCodeVisibleBodyInspection.swift', 'GarmentCodeJointResult.swift',
          'GarmentCodeJointFabric.swift', 'GarmentCodeJointWorkflow.swift']
names = list(dict.fromkeys(names))
files = [repo / 'TrailorAss/Models' / n for n in names]
files += [repo / 'Tests/NativePattern/JointWorkflow.swift', Path(__file__).resolve()]
before = {str(f): sha(f) for f in files}
manifest = []
for f in files:
    dest = source / f.name
    shutil.copy2(f, dest)
    manifest.append({'source': str(f), 'snapshot': f.name, 'sha256': sha(dest)})
resources = source / 'Resources'
shutil.copytree(repo / 'TrailorAss/Resources', resources)
for f in sorted(resources.rglob('*')):
    if f.is_file(): manifest.append({'snapshot': str(f.relative_to(source)), 'sha256': sha(f)})
assert all(sha(Path(f)) == digest for f, digest in before.items()), 'Source changed during capture'

proof = a.package_proof.resolve()
summary = json.loads((proof / 'summary.json').read_text())
assert summary['passed'] and summary['macTestsExecuted'] >= 91, 'Expected verified orientation-corrected native package'
def native_sources(directory):
    return {str(f.relative_to(directory)):sha(f) for f in directory.rglob('*') if f.is_file()}
assert native_sources(repo/'NativeClothCollision/Sources') == native_sources(proof/'snapshot/Sources'), 'Current native source paths/bytes differ from proof'
lib = proof / 'swiftpm/arm64-apple-macosx/release'
includes = [lib / 'Modules', proof / 'snapshot/Sources/CNativeClothCollision/include',
            lib / 'CIPCBodyContact.build', lib / 'CNativeClothSparse.build']
dependencies = [lib / 'libNativeClothCollision.a', proof / 'summary.json']
for directory in includes:
    assert directory.is_dir(), directory
    dependencies += [f for f in directory.rglob('*') if f.is_file() and f.suffix in {'.swiftmodule', '.swiftdoc', '.modulemap', '.h'}]
bindings = [{'path': str(f), 'sha256': sha(f)} for f in dependencies]
(out / 'source-manifest.json').write_text(json.dumps({'files': manifest, 'nativeDependencies': bindings}, indent=2) + '\n')
cmd = ['xcrun', 'swiftc', '-O', '-whole-module-optimization', '-swift-version', '5', '-default-isolation', 'MainActor',
       '-strict-concurrency=complete', '-warnings-as-errors', '-parse-as-library', '-module-cache-path', str(out / 'module-cache')]
for directory in includes: cmd += ['-I', str(directory)]
cmd += [str(source / n) for n in names] + [str(source / 'JointWorkflow.swift'), '-L', str(lib),
        '-lNativeClothCollision', '-lc++', '-framework', 'Accelerate', '-o', str(out / 'joint-workflow')]
commands = []
test_command = [str(out / 'joint-workflow'), str(resources), str(out)]
if a.positive_waistband: test_command.append('--positive-waistband')
if a.gathered_only: test_command.append('--gathered-only')
for label, command in [('compile-swift-only', cmd), ('actual-workflow-tests', test_command)]:
    start = time.monotonic()
    with (out / (label + '.log')).open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    commands.append({'label': label, 'command': command, 'exitCode': result.returncode, 'seconds': time.monotonic() - start})
    (out / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    if result.returncode:
        print((out / (label + '.log')).read_text()); print(out)
        raise SystemExit(result.returncode)
tests = json.loads((out / 'workflow-tests.json').read_text())
unchanged = all(sha(source / f['snapshot']) == f['sha256'] for f in manifest)
native_unchanged = all(sha(Path(f['path'])) == f['sha256'] for f in bindings)
report = {'passed': tests['passed'] and unchanged and native_unchanged, 'sourceSnapshotUnchanged': unchanged,
          'nativeDependenciesUnchanged': native_unchanged, 'nativePackageRecompiled': False, 'output': str(out),
          'completeGarmentAccepted': False, 'commands': commands, 'tests': tests}
report['validatedStandaloneComponentProduced'] = tests['validatedStandaloneComponentProduced']
(out / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({'passed': report['passed'], 'output': str(out), 'completeGarmentAccepted': False,
                  'validatedStandaloneComponentProduced': report['validatedStandaloneComponentProduced']}, indent=2))
raise SystemExit(0 if report['passed'] else 1)
