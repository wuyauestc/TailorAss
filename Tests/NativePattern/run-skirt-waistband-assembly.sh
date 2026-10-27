#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssSkirtWaistbandBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_SKIRT_WAISTBAND_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_SKIRT_WAISTBAND_OUTPUT-/private/tmp/TailorAssSkirtWaistbandAssembly}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern" "$output_dir"
set --
for native_model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift \
  GarmentCodeNativeGenerator.swift GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift \
  GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift GarmentCodeCircleDrape.swift \
  GarmentCodePanelMesher.swift GarmentCodeSewing.swift GarmentCodeSewnDrape.swift GarmentCodeContinuousBodyContact.swift \
  GarmentCodeSewnBodyContact.swift GarmentCodeSewnPointBlock.swift GarmentCodeSourceTethers.swift GarmentCodeSewnInput.swift \
  GarmentCodeWaistbandDrape.swift GarmentCodeWaistbandAssembly.swift GarmentCodeCircleAssembly.swift \
  GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeFixedBody.swift GarmentCodeAssemblyBuilder.swift GarmentCodeSkirtWaistbandAssembly.swift; do
  cp "$repo_dir/TrailorAss/Models/$native_model" "$snapshot_dir/TrailorAss/Models/$native_model"
  set -- "$@" "$snapshot_dir/TrailorAss/Models/$native_model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
cp "$script_dir/BodySurfaceContact.swift" "$snapshot_dir/Tests/NativePattern/BodySurfaceContact.swift"
cp "$script_dir/SkirtWaistbandAssembly.swift" "$snapshot_dir/Tests/NativePattern/SkirtWaistbandAssembly.swift"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1])
files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Exact isolated compilation inputs; not a success claim','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
swiftc -O -D BODY_SURFACE_INTEGRATION -module-cache-path "$test_dir/module-cache" \
  "$@" "$snapshot_dir/Tests/NativePattern/BodySurfaceContact.swift" \
  "$snapshot_dir/Tests/NativePattern/SkirtWaistbandAssembly.swift" -o "$test_dir/skirt-waistband-assembly"
if [ -n "${GARMENTCODE_SKIRT_WAISTBAND_BINARY-}" ]; then cp "$test_dir/skirt-waistband-assembly" "$GARMENTCODE_SKIRT_WAISTBAND_BINARY"; fi
"$test_dir/skirt-waistband-assembly"
