#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssSewnPointBlockBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_SEWN_POINT_BLOCK_KEEP_SNAPSHOT:-0}" != 1 ]; then rm -rf "$test_dir"; fi' EXIT
mkdir -p "$test_dir/source/TrailorAss/Models" "$test_dir/source/Tests/NativePattern"
models='PatternDesignModels GarmentCodeGeometry GarmentCodePrograms GarmentCodeNativeGenerator GarmentCodeClothMaterial GarmentCodeClothContact GarmentCodeBodySurfaceContact GarmentCodeStandardBody GarmentCodeCircleDrape GarmentCodePanelMesher GarmentCodeSewing GarmentCodeSewnPointBlock'
for model in $models; do cp "$repo_dir/TrailorAss/Models/$model.swift" "$test_dir/source/TrailorAss/Models/$model.swift"; done
cp "$script_dir/SewnPointBlock.swift" "$test_dir/source/Tests/NativePattern/SewnPointBlock.swift"
fixture_dir="${GARMENTCODE_SEWN_POINT_BLOCK_FIXTURE:-$script_dir/Fixtures/3d-sewn-point-block}"
if [ -n "$fixture_dir" ]; then
  if [ -f "$fixture_dir/manifest.json" ]; then
    python3 - "$fixture_dir" <<'FIXTURE_HASHES'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text())
for name,expected in manifest['sha256'].items():
 if hashlib.sha256((root/name).read_bytes()).hexdigest()!=expected:
  raise SystemExit('Point block fixture hash mismatch: '+name)
FIXTURE_HASHES
  fi
  mkdir -p "$test_dir/real-fixture"
  for file in straight-default-plan.json straight-default-reference.json straight-default-mesh.json; do cp "$fixture_dir/$file" "$test_dir/real-fixture/$file"; done
  GARMENTCODE_SEWN_POINT_BLOCK_FIXTURE="$test_dir/real-fixture"
  export GARMENTCODE_SEWN_POINT_BLOCK_FIXTURE
fi
python3 - "$test_dir" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);files={}
for folder in ['source','real-fixture']:
 for p in sorted((root/folder).rglob('*')):
  if p.is_file():files[str(p.relative_to(root))]=hashlib.sha256(p.read_bytes()).hexdigest()
(root/'build-input-manifest.json').write_text(json.dumps({'scope':'Exact independent final-point block inputs; no physical acceptance claim','sha256':files},indent=2,sort_keys=True)+'\n')
PY
set --
for model in $models; do set -- "$@" "$test_dir/source/TrailorAss/Models/$model.swift"; done
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$test_dir/module-cache" "$@" "$test_dir/source/Tests/NativePattern/SewnPointBlock.swift" -o "$test_dir/sewn-point-block"
if [ -n "${GARMENTCODE_SEWN_POINT_BLOCK_OUTPUT:-}" ]; then
  mkdir -p "$GARMENTCODE_SEWN_POINT_BLOCK_OUTPUT"
  cp "$test_dir/build-input-manifest.json" "$GARMENTCODE_SEWN_POINT_BLOCK_OUTPUT/build-input-manifest.json"
fi
"$test_dir/sewn-point-block"
