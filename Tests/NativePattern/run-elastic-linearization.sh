#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssElasticLinearizationBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_ELASTIC_LINEARIZATION_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_ELASTIC_LINEARIZATION_OUTPUT-/private/tmp/TailorAssElasticLinearization}"
mkdir -p "$snapshot_dir/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift \
 GarmentCodeStandardBody.swift GarmentCodeCircleDrape.swift GarmentCodeHingeBending.swift GarmentCodeMembrane.swift \
 GarmentCodeElasticEnergyDelta.swift GarmentCodeElasticLinearization.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/Models/$model"
 set -- "$@" "$snapshot_dir/Models/$model"
done
for fixture in 3d-hinge 3d-elastic-linearization; do
 cp -R "$script_dir/Fixtures/$fixture" "$snapshot_dir/Tests/NativePattern/Fixtures/$fixture"
done
for test in ElasticLinearization.swift GenerateElasticLinearizationFixture.py; do
 cp "$script_dir/$test" "$snapshot_dir/Tests/NativePattern/$test"
done
python3 "$snapshot_dir/Tests/NativePattern/GenerateElasticLinearizationFixture.py" \
 --verify-dir "$snapshot_dir/Tests/NativePattern/Fixtures/3d-elastic-linearization" > "$output_dir/fixture-verification.json"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'PY'
from pathlib import Path
import hashlib,json,sys
p=Path(sys.argv[1]);d={str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(p.rglob('*')) if f.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Exact immutable fixed-x elastic Hv only; no simulation or garment acceptance','snapshotDirectory':str(p),'sha256':d},indent=2)+'\n')
PY
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/ElasticLinearization.swift" -o "$test_dir/elastic-linearization"
"$test_dir/elastic-linearization" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
printf '%s\n' "Snapshot: $snapshot_dir"
