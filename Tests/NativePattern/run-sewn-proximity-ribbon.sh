#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssSewnProximityBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_SEWN_PROXIMITY_KEEP_SNAPSHOT:-0}" != 1 ]; then rm -rf "$test_dir"; fi' EXIT
mkdir -p "$test_dir/source/TrailorAss/Models" "$test_dir/source/Tests/NativePattern"
models='PatternDesignModels GarmentCodeGeometry GarmentCodePrograms GarmentCodeNativeGenerator GarmentCodeClothMaterial GarmentCodeClothContact GarmentCodeBodySurfaceContact GarmentCodeStandardBody GarmentCodeCircleDrape GarmentCodePanelMesher GarmentCodeSewing GarmentCodeSewnDrape GarmentCodeSewnInput GarmentCodeSewnBodyContact GarmentCodeSourceTethers'
for model in $models; do
  cp "$repo_dir/TrailorAss/Models/$model.swift" "$test_dir/source/TrailorAss/Models/$model.swift"
done
cp "$script_dir/SewnProximityRibbon.swift" "$test_dir/source/Tests/NativePattern/SewnProximityRibbon.swift"
python3 - "$test_dir/source" "$test_dir/build-input-manifest.json" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1])
paths=sorted(root.rglob('*.swift'))
manifest={'kind':'sewn_proximity_snapshot','files':[
  {'path':str(path.relative_to(root)),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()} for path in paths]}
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
PY
set --
for model in $models; do set -- "$@" "$test_dir/source/TrailorAss/Models/$model.swift"; done
swiftc -O -warnings-as-errors -default-isolation MainActor -module-cache-path "$test_dir/module-cache" \
  "$@" "$test_dir/source/Tests/NativePattern/SewnProximityRibbon.swift" -o "$test_dir/sewn-proximity-ribbon"
if [ -n "${GARMENTCODE_SEWN_PROXIMITY_OUTPUT:-}" ]; then
  mkdir -p "$GARMENTCODE_SEWN_PROXIMITY_OUTPUT"
  cp "$test_dir/build-input-manifest.json" "$GARMENTCODE_SEWN_PROXIMITY_OUTPUT/build-input-manifest.json"
fi
"$test_dir/sewn-proximity-ribbon"
