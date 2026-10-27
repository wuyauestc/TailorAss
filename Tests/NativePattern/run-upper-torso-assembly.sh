#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssUpperTorsoBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_UPPER_TORSO_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_UPPER_TORSO_OUTPUT-/private/tmp/TailorAssUpperTorso}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/TrailorAss/Resources" "$snapshot_dir/Tests/NativePattern" "$output_dir"
cp "$repo_dir/TrailorAss/Models/PatternDesignModels.swift" "$snapshot_dir/TrailorAss/Models/PatternDesignModels.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeGeometry.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeGeometry.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodePrograms.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodePrograms.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeNativeGenerator.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeNativeGenerator.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeClothMaterial.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeClothMaterial.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeClothContact.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeClothContact.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeBodySurfaceContact.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeBodySurfaceContact.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeStandardBody.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeStandardBody.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeCircleDrape.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeCircleDrape.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeBodySurfaceMeasurements.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeBodySurfaceMeasurements.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeFitDeformationReplay.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeFitDeformationReplay.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeBodySurfaceFitter.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeBodySurfaceFitter.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeBodySurfaceValidator.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeBodySurfaceValidator.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeFittedBody.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeFittedBody.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodePanelMesher.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodePanelMesher.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeSewing.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeSewing.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeSewnDrape.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnDrape.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeContinuousBodyContact.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeContinuousBodyContact.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeSewnBodyContact.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnBodyContact.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeSewnPointBlock.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnPointBlock.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeSourceTethers.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeSourceTethers.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeSewnInput.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnInput.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeBodyRig.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeBodyRig.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeBodyMeshQueries.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeBodyMeshQueries.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeFixedBody.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeFixedBody.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeAssemblyBuilder.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeAssemblyBuilder.swift"
cp "$repo_dir/TrailorAss/Models/GarmentCodeUpperTorsoAssembly.swift" "$snapshot_dir/TrailorAss/Models/GarmentCodeUpperTorsoAssembly.swift"
cp "$repo_dir/Tests/NativePattern/BodySurfaceContact.swift" "$snapshot_dir/Tests/NativePattern/BodySurfaceContact.swift"
cp "$repo_dir/Tests/NativePattern/UpperTorsoAssembly.swift" "$snapshot_dir/Tests/NativePattern/UpperTorsoAssembly.swift"
cp "$repo_dir/TrailorAss/Resources/GarmentCodeParameterCatalog.json" "$snapshot_dir/TrailorAss/Resources/GarmentCodeParameterCatalog.json"
cp "$repo_dir/TrailorAss/Resources/GarmentCodeStandardBody.json" "$snapshot_dir/TrailorAss/Resources/GarmentCodeStandardBody.json"
cp "$repo_dir/TrailorAss/Resources/GarmentCodeStandardBodySource.json" "$snapshot_dir/TrailorAss/Resources/GarmentCodeStandardBodySource.json"
cp "$repo_dir/TrailorAss/Resources/GarmentCodeStandardBodySDF.bin" "$snapshot_dir/TrailorAss/Resources/GarmentCodeStandardBodySDF.bin"
if [ -n "${GARMENTCODE_UPPER_TORSO_REJECTED_FRAME_FILE-}" ]; then
python3 - "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnDrape.swift" <<'REJECTION_TRACE'
from pathlib import Path
import hashlib,sys
p=Path(sys.argv[1]);source=p.read_text()
needle='        guard maximumStrain.isFinite,maximumStrain<0.40 else { throw Kernel.DrapeError.unstable }'
assert source.count(needle)==1,'Rejected-frame diagnostic requires the unchanged source-strain guard'
trace=r'''
        // TEST SNAPSHOT ONLY: retain rejection evidence; original guard follows.
        if !(maximumStrain.isFinite && maximumStrain<0.40),
           let debugPath=ProcessInfo.processInfo.environment["GARMENTCODE_UPPER_TORSO_REJECTED_FRAME_FILE"] {
            let debug:[String:Any] = [
                "kind":"rejected_upper_torso_debug_frame","convergenceClaimed":false,
                "positions":positions.map{[$0.x,$0.y,$0.z]},"triangleIndices":input.triangleIndices,
                "referencePositions":input.referencePositions.map{[$0.x,$0.y,$0.z]},
                "referenceTriangles":input.referenceTriangles,"pinned":input.pinned,
                "mannequinPositions":input.mannequinPositions.map{[$0.x,$0.y,$0.z]},
                "mannequinTriangleIndices":input.mannequinTriangleIndices,
                "sourceSHA256":prepared.sourceSHA256,"maximumSourceStrain":maximumStrain,
                "lastSpeedMetersPerSecond":lastSpeed,"completedSteps":completedSteps,
                "staticFrames":schedule.staticFrames,"gravityRampFrames":schedule.gravityRampFrames]
            if let bytes=try? JSONSerialization.data(withJSONObject:debug,options:[.sortedKeys]) {
                try? bytes.write(to:URL(fileURLWithPath:debugPath))
            }
        }
'''
p.with_suffix('.original-sha256').write_text(hashlib.sha256(source.encode()).hexdigest()+'\n')
p.write_text(source.replace(needle,trace+'\n'+needle))
REJECTION_TRACE
fi
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1])
files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Exact isolated files copied before this compilation; no active worktree model file compiled','snapshotDirectory':str(root),'rejectionTraceInstrumentation':bool(list(root.rglob('*.original-sha256'))),'sha256':files},indent=2)+'\n')
MANIFEST
swiftc -O -D BODY_SURFACE_INTEGRATION -module-cache-path "$test_dir/module-cache" \
  "$snapshot_dir/TrailorAss/Models/PatternDesignModels.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeGeometry.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodePrograms.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeNativeGenerator.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeClothMaterial.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeClothContact.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeBodySurfaceContact.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeStandardBody.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeCircleDrape.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeBodyRig.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeBodyMeshQueries.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeBodySurfaceMeasurements.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeFitDeformationReplay.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeBodySurfaceFitter.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeBodySurfaceValidator.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeFittedBody.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodePanelMesher.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeSewing.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnDrape.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeContinuousBodyContact.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnBodyContact.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnPointBlock.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeSourceTethers.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeSewnInput.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeAssemblyBuilder.swift" \
  "$snapshot_dir/TrailorAss/Models/GarmentCodeUpperTorsoAssembly.swift" \
  "$snapshot_dir/Tests/NativePattern/BodySurfaceContact.swift" \
  "$snapshot_dir/Tests/NativePattern/UpperTorsoAssembly.swift" -o "$test_dir/upper-torso"
if [ -n "${GARMENTCODE_UPPER_TORSO_BINARY-}" ]; then cp "$test_dir/upper-torso" "$GARMENTCODE_UPPER_TORSO_BINARY"; fi
"$test_dir/upper-torso"
