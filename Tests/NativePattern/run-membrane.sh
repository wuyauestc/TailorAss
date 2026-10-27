#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssMembraneBuild.XXXXXX)
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_MEMBRANE_OUTPUT-/private/tmp/TailorAssMembrane}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift GarmentCodeCircleDrape.swift GarmentCodeMembrane.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
  cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
done
cp "$script_dir/Membrane.swift" "$snapshot_dir/Tests/NativePattern/Membrane.swift"
cp "$script_dir/GenerateMembraneOracle.py" "$snapshot_dir/Tests/NativePattern/GenerateMembraneOracle.py"
cp -R "$script_dir/Fixtures/3d-membrane" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-membrane"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
fixture=root/'Tests/NativePattern/Fixtures/3d-membrane';proof=json.loads((fixture/'manifest.json').read_text())
for name,digest in proof['files'].items():assert hashlib.sha256((fixture/name).read_bytes()).hexdigest()==digest,name
oracle=json.loads((fixture/'numpy-svd-oracle.json').read_text());assert hashlib.sha256((root/'Tests/NativePattern/GenerateMembraneOracle.py').read_bytes()).hexdigest()==oracle['generatorSHA256'],'Independent oracle source hash changed'
Path(sys.argv[2]).write_text(json.dumps({'scope':'Frozen source membrane metric/energy/derivative inputs; rejected simulation capture is not an accepted garment','snapshotDirectory':str(root),'fixtureHashesVerified':True,'sha256':files},indent=2)+'\n')
MANIFEST
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -module-cache-path "$test_dir/module-cache" \
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
  "$snapshot_dir/TrailorAss/Models/GarmentCodeMembrane.swift" \
  "$snapshot_dir/Tests/NativePattern/Membrane.swift" -o "$test_dir/membrane"
GARMENTCODE_MEMBRANE_OUTPUT="$output_dir" "$test_dir/membrane"
