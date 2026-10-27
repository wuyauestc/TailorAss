#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssMembranePathBuild.XXXXXX)
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_MEMBRANE_PATH_OUTPUT-/private/tmp/TailorAssMembranePath}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift \
 GarmentCodeStandardBody.swift GarmentCodeCircleDrape.swift GarmentCodeMembrane.swift GarmentCodeMembranePath.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp "$script_dir/MembranePath.swift" "$snapshot_dir/Tests/NativePattern/MembranePath.swift"
cp -R "$script_dir/Fixtures/3d-membrane-path-r63" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-membrane-path-r63"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
fixture=root/'Tests/NativePattern/Fixtures/3d-membrane-path-r63';m=json.loads((fixture/'manifest.json').read_text())
for f in m['files']:
 assert hashlib.sha256((fixture/f['path']).read_bytes()).hexdigest()==f['sha256'],f['path']
assert hashlib.sha256((fixture/'source-pattern.json').read_bytes()).hexdigest()==m['sourcePatternSHA256']
Path(sys.argv[2]).write_text(json.dumps({'scope':'Exact source path certificate, not a physical time step','snapshotDirectory':str(root),'fixtureHashesVerified':True,'sha256':files},indent=2)+'\n')
MANIFEST
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/MembranePath.swift" -o "$test_dir/membrane-path"
"$test_dir/membrane-path" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-membrane-path-r63" "$output_dir"
