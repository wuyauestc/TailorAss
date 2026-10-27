#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssBodySectionsBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_BODY_SECTIONS_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
if [ -n "${GARMENTCODE_BODY_SECTIONS_OUTPUT-}" ]; then
 output_dir="$GARMENTCODE_BODY_SECTIONS_OUTPUT"
else
 output_dir=$(mktemp -d /private/tmp/TailorAssBodySectionsResults.XXXXXX)
fi
export GARMENTCODE_BODY_SECTIONS_OUTPUT="$output_dir"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodeBodySections.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
cp -R "$script_dir/Fixtures" "$snapshot_dir/Tests/NativePattern/Fixtures"
cp "$script_dir/BodySections.swift" "$script_dir/ValidateBodySections.py" "$snapshot_dir/Tests/NativePattern/"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Exact visible mesh sections, analytic geometry, full loop provenance; no body fit','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -target "$(uname -m)-apple-macos26.0" -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/BodySections.swift" -o "$test_dir/body-sections"
"$test_dir/body-sections"
python3 "$snapshot_dir/Tests/NativePattern/ValidateBodySections.py" "$output_dir"
