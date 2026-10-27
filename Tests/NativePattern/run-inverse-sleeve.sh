#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssInverseSleeveBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_INVERSE_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_INVERSE_OUTPUT-/private/tmp/TailorAssInverseSleeve}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodePanelMesher.swift GarmentCodePanelPlacement.swift GarmentCodeUpperPlacement.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
cp "$script_dir/InverseSleeve.swift" "$script_dir/GenerateInverseSleeveGoldens.py" "$script_dir/ReplayUpperPlacement.py" "$snapshot_dir/Tests/NativePattern/"
cp "$script_dir/Fixtures/inverse-sleeve-oracles.json" "$snapshot_dir/Tests/NativePattern/Fixtures/"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]); files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Frozen inverse sleeve source and exact original upstream redistribution regression','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/InverseSleeve.swift" -o "$test_dir/inverse-sleeve"
"$test_dir/inverse-sleeve"
