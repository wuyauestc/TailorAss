#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssHingeBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_HINGE_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_HINGE_OUTPUT-/private/tmp/TailorAssHinge}"
python_bin="${GARMENTCODE_HINGE_PYTHON-/Users/wuya/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift \
 GarmentCodeStandardBody.swift GarmentCodeCircleDrape.swift GarmentCodeHingeBending.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
for test in HingeBending.swift GenerateHingeBendingFixture.py HingeBendingOracle.py; do
 cp "$script_dir/$test" "$snapshot_dir/Tests/NativePattern/$test"
done
cp -R "$script_dir/Fixtures/3d-hinge" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-hinge"
fixture_dir="$snapshot_dir/Tests/NativePattern/Fixtures/3d-hinge"
"$python_bin" "$snapshot_dir/Tests/NativePattern/GenerateHingeBendingFixture.py" --verify-dir "$fixture_dir" > "$output_dir/fixture-verification.json"
"$python_bin" - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
fixture=root/'Tests/NativePattern/Fixtures/3d-hinge';m=json.loads((fixture/'manifest.json').read_text())
assert m['generatorSHA256']==hashlib.sha256((root/'Tests/NativePattern/GenerateHingeBendingFixture.py').read_bytes()).hexdigest(),'Fixture generator changed'
Path(sys.argv[2]).write_text(json.dumps({'scope':'Standalone internal-source hinge energy and derivative tests; no simulation or accepted garment','snapshotDirectory':str(root),'fixtureHashesVerified':True,'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/HingeBending.swift" -o "$test_dir/hinge-bending"
"$test_dir/hinge-bending" "$fixture_dir" "$output_dir"
"$python_bin" "$snapshot_dir/Tests/NativePattern/HingeBendingOracle.py" --fixture-dir "$fixture_dir" \
 --swift-summary "$output_dir/hinge-summary.json" --output "$output_dir/independent-oracle-summary.json" > "$output_dir/independent-oracle.log"
