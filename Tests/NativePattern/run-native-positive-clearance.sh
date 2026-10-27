#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssNativePositiveClearanceBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_NATIVE_POSITIVE_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
if [ -n "${GARMENTCODE_NATIVE_OUTPUT-}" ]; then
 output_dir="$GARMENTCODE_NATIVE_OUTPUT"
else
 output_dir=$(mktemp -d /private/tmp/TailorAssNativePositiveClearanceResults.XXXXXX)
fi
export GARMENTCODE_NATIVE_OUTPUT="$output_dir"
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
for fixture in meta-grid-defaults meta-grid-female upper-placement-oracles composition-rise-oracles native-assembly-levels-oracles native-initialization-three-mode-goldens; do
 cp "$script_dir/Fixtures/$fixture.json" "$snapshot_dir/Tests/NativePattern/Fixtures/$fixture.json"
done
cp "$script_dir/GenerateNativeAssemblyLevelsGoldens.py" "$script_dir/NativeInitializationState.swift" "$script_dir/NativePositiveClearanceChecks.swift" "$script_dir/BodySurfaceContact.swift" "$snapshot_dir/Tests/NativePattern/"
cp "$script_dir/PositiveClearanceOracle.cpp" "$script_dir/ValidatePositiveClearance.py" "$snapshot_dir/Tests/NativePattern/"
python3 - "$script_dir" "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
source,root=Path(sys.argv[1]),Path(sys.argv[2]);tests=root/'Tests/NativePattern'
s=(source/'NativeAssembly.swift').read_text();needle='            var row=try check(prepared,document:document);row["case"]=id';assert s.count(needle)==1
s=s.replace(needle,needle+'\n            row["positiveGapInitialization"]=try NativePositiveClearanceChecks.run(id:id,document:document,body:body,design:design,native:prepared)',1)
s=s.replace('native-assembly-summary.json','native-positive-clearance-summary.json');(tests/'NativeAssembly.swift').write_text(s)
s=(source/'RigidBodyClearance.swift').read_text();token='@main @MainActor struct RigidBodyClearanceRegression';assert token in s;(tests/'RigidBodyClearance.swift').write_text(s.replace(token,token.replace('@main ',''),1))
files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[3]).write_text(json.dumps({'scope':'Full211 explicit positive-gap initialization; all633 old three-mode exact-value checks, source/plan/body/self oracle; no dynamics','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -D BODY_SURFACE_INTEGRATION \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/NativeAssembly.swift" \
 "$snapshot_dir/Tests/NativePattern/NativeInitializationState.swift" "$snapshot_dir/Tests/NativePattern/NativePositiveClearanceChecks.swift" \
 "$snapshot_dir/Tests/NativePattern/BodySurfaceContact.swift" "$snapshot_dir/Tests/NativePattern/RigidBodyClearance.swift" -o "$test_dir/native-positive-clearance"
"$test_dir/native-positive-clearance"

xcrun clang++ -std=c++17 -O2 -Wall -Wextra -Werror "$snapshot_dir/Tests/NativePattern/PositiveClearanceOracle.cpp" -o "$test_dir/positive-distance-oracle"
python3 "$snapshot_dir/Tests/NativePattern/ValidatePositiveClearance.py" "$output_dir" "$test_dir/positive-distance-oracle"
