#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssNativeRigidClothBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_NATIVE_RIGID_CLOTH_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_NATIVE_OUTPUT-/private/tmp/TailorAssNativeRigidCloth}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
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
for fixture in meta-grid-defaults meta-grid-female upper-placement-oracles composition-rise-oracles native-assembly-levels-oracles native-initialization-old-mode-goldens; do
 cp "$script_dir/Fixtures/$fixture.json" "$snapshot_dir/Tests/NativePattern/Fixtures/$fixture.json"
done
cp "$script_dir/GenerateNativeAssemblyLevelsGoldens.py" "$script_dir/NativeInitializationState.swift" "$script_dir/NativeRigidClothChecks.swift" "$script_dir/BodySurfaceContact.swift" "$snapshot_dir/Tests/NativePattern/"
python3 - "$script_dir" "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
source,root=Path(sys.argv[1]),Path(sys.argv[2]);tests=root/'Tests/NativePattern'
s=(source/'NativeAssembly.swift').read_text();needle='            var row=try check(prepared,document:document);row["case"]=id';assert s.count(needle)==1
s=s.replace(needle,needle+'\n            row["rigidClothInitialization"]=try NativeRigidClothChecks.run(id:id,document:document,body:body,design:design,native:prepared)',1)
s=s.replace('native-assembly-summary.json','native-rigid-cloth-summary.json');(tests/'NativeAssembly.swift').write_text(s)
s=(source/'RigidBodyClearance.swift').read_text();token='@main @MainActor struct RigidBodyClearanceRegression';assert token in s;(tests/'RigidBodyClearance.swift').write_text(s.replace(token,token.replace('@main ',''),1))
files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[3]).write_text(json.dumps({'scope':'Full211 new rigid body+cloth initialization, original two-option exact-value goldens, rebuilt plans/tethers and independent body/self oracle; no dynamics','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -D BODY_SURFACE_INTEGRATION \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/NativeAssembly.swift" \
 "$snapshot_dir/Tests/NativePattern/NativeInitializationState.swift" "$snapshot_dir/Tests/NativePattern/NativeRigidClothChecks.swift" \
 "$snapshot_dir/Tests/NativePattern/BodySurfaceContact.swift" "$snapshot_dir/Tests/NativePattern/RigidBodyClearance.swift" -o "$test_dir/native-rigid-cloth"
"$test_dir/native-rigid-cloth"
