#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssJointObjectiveBuild.XXXXXX)
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_JOINT_OBJECTIVE_OUTPUT-/private/tmp/TailorAssJointObjective}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern/Fixtures" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift \
 GarmentCodeStandardBody.swift GarmentCodeCircleDrape.swift GarmentCodeSewing.swift \
 GarmentCodePanelMesher.swift GarmentCodeMembrane.swift GarmentCodeHingeBending.swift GarmentCodeElasticEnergyDelta.swift GarmentCodeElasticLinearization.swift GarmentCodeJointObjective.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp "$script_dir/JointObjective.swift" "$snapshot_dir/Tests/NativePattern/JointObjective.swift"
cp -R "$script_dir/Fixtures/3d-hinge" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-hinge"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]);files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
fixture=root/'Tests/NativePattern/Fixtures/3d-hinge';m=json.loads((fixture/'manifest.json').read_text())
for name,digest in m['files'].items():
 assert hashlib.sha256((fixture/name).read_bytes()).hexdigest()==digest,name
Path(sys.argv[2]).write_text(json.dumps({'scope':'Joint objective E/g/exact Hv only; no contact or accepted physics','snapshotDirectory':str(root),'fixtureHashesVerified':True,'sha256':files},indent=2)+'\n')
MANIFEST
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/JointObjective.swift" -o "$test_dir/joint-objective"
"$test_dir/joint-objective" "$snapshot_dir/Tests/NativePattern/Fixtures/3d-hinge" "$output_dir"
