#!/bin/sh
set -eu
# Preserve the original 860-panel/one-failure oracle. This independent run
# aliases the post-fix 108-case replay fixture only inside its isolated copy.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssUpperCompleteBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_UPPER_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_UPPER_OUTPUT-/private/tmp/TailorAssUpperPlacementComplete}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodePanelMesher.swift GarmentCodePanelPlacement.swift GarmentCodeUpperPlacement.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
cp -R "$script_dir/Fixtures" "$snapshot_dir/Tests/NativePattern/Fixtures"
cp "$script_dir/Fixtures/upper-placement-complete-oracles.json" "$snapshot_dir/Tests/NativePattern/Fixtures/upper-placement-oracles.json"
cp "$script_dir/UpperPlacement.swift" "$script_dir/GenerateUpperPlacementGoldens.py" "$script_dir/ReplayUpperPlacement.py" "$snapshot_dir/Tests/NativePattern/"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Post-fix complete upper placement. Original fixture remains unchanged; only isolated snapshot aliases the complete replay to the legacy harness filename. Not physical drape acceptance.','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/UpperPlacement.swift" -o "$test_dir/upper-placement"
"$test_dir/upper-placement"
