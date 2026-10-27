#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
build=$(mktemp -d /private/tmp/TailorAssGarmentViewerBuild.XXXXXX)
mkdir -p "$build/source/Models" "$build/source/Views" "$build/source/Tests"
output="${GARMENTCODE_VIEWER_EXPORT_OUTPUT-/private/tmp/TailorAssGarmentViewerExport}"
mkdir -p "$output"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift GarmentCodeCircleDrape.swift GarmentCodeMeshExport.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$build/source/Models/$model"
 set -- "$@" "$build/source/Models/$model"
done
cp "$repo_dir/TrailorAss/Views/Garment/GarmentCodeGarmentScene.swift" "$build/source/Views/"
cp "$script_dir/GarmentViewerExport.swift" "$build/source/Tests/"
python3 - "$build/source" "$output/build-input-manifest.json" <<'PY'
from pathlib import Path
import sys,json,hashlib
p=Path(sys.argv[1]);Path(sys.argv[2]).write_text(json.dumps({'scope':'Pure camera geometry and unchanged serializer tests, no UI or physics','snapshotDirectory':str(p),'files':{str(f.relative_to(p)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(p.rglob('*')) if f.is_file()}},indent=2)+'\n')
PY
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -module-cache-path "$build/module-cache" \
 "$@" "$build/source/Views/GarmentCodeGarmentScene.swift" "$build/source/Tests/GarmentViewerExport.swift" -o "$build/viewer-export"
"$build/viewer-export" "$output"
printf '%s\n' "Snapshot: $build/source"
