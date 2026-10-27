#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssLowerBranchesBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_LOWER_BRANCH_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_LOWER_BRANCH_OUTPUT-/private/tmp/TailorAssLowerBranches}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodePanelMesher.swift GarmentCodePanelPlacement.swift GarmentCodeLowerPlacement.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
cp "$script_dir/Fixtures/lower-branch-oracles.json" "$snapshot_dir/Tests/NativePattern/Fixtures/lower-branch-oracles.json"
cp "$script_dir/GenerateLowerBranchGoldens.py" "$snapshot_dir/Tests/NativePattern/GenerateLowerBranchGoldens.py"
cp "$script_dir/LowerBranches.swift" "$snapshot_dir/Tests/NativePattern/LowerBranches.swift"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Exact frozen inputs for official lower 2D branch and placement checks','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
swiftc -O -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/LowerBranches.swift" -o "$test_dir/lower-branches"
"$test_dir/lower-branches"
