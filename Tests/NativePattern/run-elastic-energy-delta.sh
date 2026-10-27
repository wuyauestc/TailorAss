#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssElasticDeltaBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_ELASTIC_DELTA_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_ELASTIC_DELTA_OUTPUT-/private/tmp/TailorAssElasticDelta}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodeMembrane.swift GarmentCodeHingeBending.swift GarmentCodeElasticEnergyDelta.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
for test in ElasticEnergyDelta.swift GenerateElasticEnergyDeltaFixture.py; do cp "$script_dir/$test" "$snapshot_dir/Tests/NativePattern/$test"; done
cp -R "$script_dir/Fixtures/3d-elastic-delta" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-elastic-delta"
cp -R "$script_dir/Fixtures/3d-hinge" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-hinge"
python3 "$snapshot_dir/Tests/NativePattern/GenerateElasticEnergyDeltaFixture.py" --verify-dir "$snapshot_dir/Tests/NativePattern/Fixtures/3d-elastic-delta" > "$output_dir/fixture-verification.json"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys,gzip
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
fixture=root/'Tests/NativePattern/Fixtures';h=json.loads((fixture/'3d-hinge/manifest.json').read_text())
for name,digest in h['files'].items():assert hashlib.sha256((fixture/'3d-hinge'/name).read_bytes()).hexdigest()==digest,name
(fixture/'3d-elastic-delta/controls.json').write_bytes(gzip.decompress((fixture/'3d-elastic-delta/controls.json.gz').read_bytes()))
Path(sys.argv[2]).write_text(json.dumps({'scope':'Standalone stable elastic delta estimates; no new physics or accepted update','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/ElasticEnergyDelta.swift" -o "$test_dir/elastic-energy-delta"
"$test_dir/elastic-energy-delta" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-hinge/native-source-topology.json" \
 "$snapshot_dir/Tests/NativePattern/Fixtures/3d-elastic-delta/controls.json" "$output_dir"
