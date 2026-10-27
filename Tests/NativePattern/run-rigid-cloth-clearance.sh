#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssRigidClothBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_RIGID_CLOTH_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_RIGID_CLOTH_OUTPUT-/private/tmp/TailorAssRigidClothClearance}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodeContinuousBodyContact.swift GarmentCodePanelMesher.swift GarmentCodePanelPlacement.swift GarmentCodeUpperPlacement.swift \
 GarmentCodeLowerPlacement.swift GarmentCodeCompositionPlacement.swift GarmentCodeSewing.swift GarmentCodeSewnDrape.swift \
 GarmentCodeSewnInput.swift GarmentCodeSewnPointBlock.swift GarmentCodeSewnBodyContact.swift GarmentCodeSourceTethers.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeFixedBody.swift GarmentCodeAssemblyBuilder.swift GarmentCodeNativeAssembly.swift GarmentCodeRigidBodyClearance.swift GarmentCodeRigidClothClearance.swift \
 GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
cp "$script_dir/BodySurfaceContact.swift" "$script_dir/RigidClothClearance.swift" "$snapshot_dir/Tests/NativePattern/"
python3 - "$script_dir" "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
source,root=Path(sys.argv[1]),Path(sys.argv[2]);tests=root/'Tests/NativePattern'
for name,token in [('NativeAssembly.swift','@main @MainActor struct NativeAssemblyRegression'),('RigidBodyClearance.swift','@main @MainActor struct RigidBodyClearanceRegression')]:
 s=(source/name).read_text();assert token in s;(tests/name).write_text(s.replace(token,token.replace('@main ',''),1))
files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[3]).write_text(json.dumps({'scope':'Analytic rigid cloth initializer only; independent original surface oracle and no physics','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -D BODY_SURFACE_INTEGRATION \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/NativeAssembly.swift" \
 "$snapshot_dir/Tests/NativePattern/BodySurfaceContact.swift" "$snapshot_dir/Tests/NativePattern/RigidBodyClearance.swift" \
 "$snapshot_dir/Tests/NativePattern/RigidClothClearance.swift" -o "$test_dir/rigid-cloth"
"$test_dir/rigid-cloth"
