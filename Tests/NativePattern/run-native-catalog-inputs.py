#!/usr/bin/env python3
"""Export reproducible complete PaperJSON inputs for later R --pattern-json runs.

Only pure 2D Swift models are compiled. No package/native build, source meshing,
3D initialization, cloth simulation or App changes occur. Exit zero means this
export job completed and its inventories/byte reproducibility passed; inspect
rejected cases separately, and never treat it as completeGarmentAccepted.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
out = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='TailorAssNativeCatalogInputs.', dir='/private/tmp'))
out.mkdir(parents=True, exist_ok=True)
snapshot = out / 'source'
if snapshot.exists():
    raise SystemExit('Refusing to overwrite an existing frozen source snapshot')
models = ['PatternDesignModels.swift', 'GarmentCodeGeometry.swift', 'GarmentCodePrograms.swift',
          'GarmentCodeNativeGenerator.swift', 'GarmentCodeLocalization.swift', 'GarmentCodeJointParameters.swift']
helpers = ['SourceMeshCaseDefinitions.swift', 'NativeCatalogCases.swift', 'GenerateNativeCatalogInputs.swift',
           'JointParameterRestoreControls.swift',
           'run-native-catalog-inputs.py', 'Fixtures/native-catalog-input-definitions.json']
fixtures = ['meta-grid-defaults.json', 'meta-grid-female.json', 'upper-placement-oracles.json',
            'native-assembly-levels-oracles.json', 'composition-rise-oracles.json', 'lower-branch-oracles.json',
            'native-initialization-three-mode-goldens.json']
paths = [Path('TrailorAss/Models') / n for n in models]
paths += [Path('Tests/NativePattern') / n for n in helpers]
paths += [Path('Tests/NativePattern/Fixtures') / n for n in fixtures]
paths += [Path('TrailorAss/Resources/GarmentCodeParameterCatalog.json')]
paths += [Path('TrailorAss/Resources/GarmentCodeSiggraphShape.json')]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


before = {str(p): sha(repo / p) for p in paths}
for relative in paths:
    copied = snapshot / relative
    copied.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo / relative, copied)
if any(sha(repo / p) != before[str(p)] or sha(snapshot / p) != before[str(p)] for p in paths):
    raise SystemExit('Input sources changed during copy; no compilation or generation started')
definition = json.loads((snapshot / 'Tests/NativePattern/Fixtures/native-catalog-input-definitions.json').read_text())
assert definition['fixtureFiles'] == fixtures
assert definition['originalInitializationDefinitionCount'] == 211
assert definition['originalSourceMeshDefinitionCount'] == 27
assert definition['simulationPerformed'] is False
source_manifest = {'format': 'GarmentCodeNativeCatalogBuild/v1', 'scope': 'Pure 2D complete-source export only',
                   'files': before, 'nativePackageCompiled': False, 'meshingPerformed': False,
                   'initializationPerformed': False, 'simulationPerformed': False}
(out / 'source-manifest.json').write_text(json.dumps(source_manifest, indent=2, sort_keys=True) + '\n')
binary = out / 'native-catalog-inputs'
compile_command = ['xcrun', 'swiftc', '-O', '-whole-module-optimization', '-swift-version', '5',
                   '-default-isolation', 'MainActor', '-strict-concurrency=complete', '-warnings-as-errors',
                   '-parse-as-library', '-module-cache-path', str(out / 'module-cache')]
compile_command += [str(snapshot / 'TrailorAss/Models' / n) for n in models]
compile_command += [str(snapshot / 'Tests/NativePattern' / n) for n in helpers if n.endswith('.swift')]
compile_command += ['-o', str(binary)]
commands = [compile_command, [str(binary), str(snapshot), str(out / 'inputs')],
            [str(binary), str(snapshot), str(out / 'repeat-inputs')]]
environment = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(out / 'clang-cache'))
executed = []
started = time.monotonic()
with (out / 'generation.log').open('w') as log:
    for command in commands:
        t = time.monotonic()
        result = subprocess.run(command, cwd=snapshot, env=environment, stdout=log, stderr=subprocess.STDOUT)
        executed.append({'command': command, 'exitCode': result.returncode, 'seconds': time.monotonic() - t})
        if result.returncode:
            break
unchanged = all(sha(repo / p) == before[str(p)] and sha(snapshot / p) == before[str(p)] for p in paths)
proof = {'driverPassed': False, 'exitCode': result.returncode, 'sourceSnapshotUnchanged': unchanged,
         'nativePackageCompiled': False, 'meshingPerformed': False, 'initializationPerformed': False,
         'simulationPerformed': False, 'completeGarmentAccepted': False, 'output': str(out),
         'seconds': time.monotonic() - started, 'commands': executed}
if result.returncode == 0:
    def inventory(directory):
        return {str(f.relative_to(directory)): sha(f) for f in sorted(directory.rglob('*')) if f.is_file()}
    first, second = inventory(out / 'inputs'), inventory(out / 'repeat-inputs')
    reproducible = first == second
    manifest = json.loads((out / 'inputs/catalog-input-manifest.json').read_text())
    rows = manifest['cases']
    coverage = manifest['coverage']
    assert manifest['generationJobCompleted'] and not manifest['simulationPerformed']
    assert len(rows) == len({r['caseID'] for r in rows})
    assert coverage['original211DefinitionsIndexed'] and coverage['original27ProfilesIndexed'] == 54
    assert len(coverage['original27DefinitionIDs']) == 27
    assert len(coverage['mainStyles']) == 12 and len(coverage['mainStylesByProfile']) == 2
    assert all(not r['missingDefinitions'] for r in coverage['discreteOptionsByProfile'])
    expected_styles = set(coverage['mainStyles'])
    assert all(set(r['requestedStandalone']) == expected_styles for r in coverage['mainStylesByProfile'])
    for row in rows:
        assert not row['completeGarmentAccepted'] and not row['simulationPerformed'] and not row['meshingPerformed']
        parameter_file = out / 'inputs' / row['parameterFile']
        assert sha(parameter_file) == row['parameterJSONBytesSHA256']
        if 'patternFile' in row:
            paper = out / 'inputs' / row['patternFile']
            assert sha(paper) == row['paperJSONBytesSHA256']
            assert row['sourceSHA256'] == row['uiDocumentSignatureSHA256'] == row['fullRegenerationSHA256']
            data = json.loads(paper.read_text())
            assert len(data['pattern']['panels']) == row['panelCount']
            assert sorted(data['pattern']['panels']) == row['panelIDs']
            assert len(data['pattern']['stitches']) == row['sourceStitchCount']
            assert 'body' in data['parameters'] and 'design' in data['parameters']
        else:
            assert row['status'] == 'rejected' and row['reason'] and row['rejectionPhase']
    proof.update({'driverPassed': unchanged and reproducible, 'byteReproducibleAcrossTwoProcesses': reproducible,
                  'requestedCaseCount': len(rows), 'readyInputCount': manifest['readyInputCount'],
                  'rejectedCaseCount': manifest['rejectedCaseCount'], 'uniquePaperJSONCount': manifest['uniquePaperJSONCount'],
                  'original211ReadyCount': coverage['original211ReadyCount'],
                  'allRequestedSourcesReady': manifest['allRequestedSourcesReady'],
                  'original211DefinitionsIndexed': True, 'original27ProfilesIndexed': 54,
                  'binarySHA256': sha(binary), 'manifestSHA256': sha(out / 'inputs/catalog-input-manifest.json'),
                  'exportedFiles': first,
                  'meaningOfExitZero': 'Exporter and definition/reproducibility controls completed. It does not imply all inputs generated or any garment passed 3D.'})
(out / 'summary.json').write_text(json.dumps(proof, indent=2, sort_keys=True) + '\n')
compact = {k: v for k, v in proof.items() if k not in {'commands', 'exportedFiles'}}
print(json.dumps(compact, indent=2, sort_keys=True))
raise SystemExit(0 if proof['driverPassed'] else 1)
