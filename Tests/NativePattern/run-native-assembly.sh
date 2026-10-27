#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssNativeAssemblyBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_NATIVE_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_NATIVE_OUTPUT-/private/tmp/TailorAssNativeAssembly}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodeContinuousBodyContact.swift GarmentCodePanelMesher.swift GarmentCodePanelPlacement.swift GarmentCodeUpperPlacement.swift \
 GarmentCodeLowerPlacement.swift GarmentCodeCompositionPlacement.swift GarmentCodeSewing.swift GarmentCodeSewnDrape.swift \
 GarmentCodeSewnInput.swift GarmentCodeSewnPointBlock.swift GarmentCodeSewnBodyContact.swift GarmentCodeSourceTethers.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeFixedBody.swift GarmentCodeAssemblyBuilder.swift GarmentCodeRigidBodyClearance.swift GarmentCodeRigidClothClearance.swift GarmentCodeNativeAssembly.swift \
 GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
for fixture in meta-grid-defaults meta-grid-female upper-placement-oracles composition-rise-oracles native-assembly-levels-oracles; do
 cp "$script_dir/Fixtures/$fixture.json" "$snapshot_dir/Tests/NativePattern/Fixtures/$fixture.json"
done
cp "$script_dir/NativeAssembly.swift" "$snapshot_dir/Tests/NativePattern/NativeAssembly.swift"
cp "$script_dir/GenerateNativeAssemblyLevelsGoldens.py" "$snapshot_dir/Tests/NativePattern/GenerateNativeAssemblyLevelsGoldens.py"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Exact rigid native source-to-strict-PreparedInput compile inputs; not cloth physics','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/NativeAssembly.swift" -o "$test_dir/native-assembly"
"$test_dir/native-assembly"
