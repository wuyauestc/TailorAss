#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssBoundaryRecoveryBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_BOUNDARY_RECOVERY_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_BOUNDARY_RECOVERY_OUTPUT-/private/tmp/TailorAssBoundaryRecovery}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodePanelMesher.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
cp "$script_dir/PanelMesher.swift" "$script_dir/PanelMesherBoundaryRecovery.swift" "$snapshot_dir/Tests/NativePattern/"
cp "$script_dir/Fixtures/female-standing-mesher-source.json" "$snapshot_dir/Tests/NativePattern/Fixtures/"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Exact female standing source recovery with frozen current production and independent mesh oracle','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -D PANEL_MESHER_INTEGRATION \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/PanelMesher.swift" \
 "$snapshot_dir/Tests/NativePattern/PanelMesherBoundaryRecovery.swift" -o "$test_dir/boundary-recovery"
"$test_dir/boundary-recovery"
