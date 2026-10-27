#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssRecoveryCompatibilityBuild.XXXXXX)
trap 'if [ "${GARMENTCODE_RECOVERY_COMPATIBILITY_KEEP_SNAPSHOT-0}" != "1" ]; then rm -rf "$test_dir"; fi' EXIT
snapshot_dir="$test_dir/source"
output_dir="${GARMENTCODE_RECOVERY_COMPATIBILITY_OUTPUT-/private/tmp/TailorAssRecoveryCompatibility}"
mkdir -p "$snapshot_dir/TrailorAss/Models" "$snapshot_dir/Tests/NativePattern" "$output_dir"
set --
for model in PatternDesignModels.swift GarmentCodeGeometry.swift GarmentCodePrograms.swift GarmentCodeNativeGenerator.swift \
 GarmentCodeClothMaterial.swift GarmentCodeClothContact.swift GarmentCodeBodySurfaceContact.swift GarmentCodeStandardBody.swift \
 GarmentCodeCircleDrape.swift GarmentCodePanelMesher.swift \
 GarmentCodeBodyRig.swift GarmentCodeBodyMeshQueries.swift GarmentCodeBodySurfaceMeasurements.swift GarmentCodeFitDeformationReplay.swift GarmentCodeBodySurfaceFitter.swift GarmentCodeBodySurfaceValidator.swift GarmentCodeFittedBody.swift; do
 cp "$repo_dir/TrailorAss/Models/$model" "$snapshot_dir/TrailorAss/Models/$model"
 set -- "$@" "$snapshot_dir/TrailorAss/Models/$model"
done
cp -R "$repo_dir/TrailorAss/Resources" "$snapshot_dir/TrailorAss/Resources"
cp -R "$script_dir/Fixtures" "$snapshot_dir/Tests/NativePattern/Fixtures"
cp "$script_dir/PanelMesher.swift" "$snapshot_dir/Tests/NativePattern/"
cp "$script_dir/SourceMeshCoverage.swift" "$snapshot_dir/Tests/NativePattern/SourceMeshCoverage.original.swift"
python3 - "$snapshot_dir" "$output_dir/build-input-manifest.json" <<'MANIFEST'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);tests=root/'Tests/NativePattern'
s=(tests/'SourceMeshCoverage.original.swift').read_text();assert '@main @MainActor' in s
s=s.replace('@main @MainActor','@MainActor',1)
needle='                    panels.append(try Oracle.check(mesh,panel:panel,target:target,flatness:flatness))'
assert s.count(needle)==1
s=s.replace(needle,'                    try encoder.encode(mesh).write(to:directory.appendingPathComponent(spec.id+"-"+id+"-mesh.json"))\n'+needle,1)
(tests/'SourceMeshCoverage.swift').write_text(s)
(tests/'RecoveryCompatibilityDriver.swift').write_text('import Foundation\n@main @MainActor struct RecoveryCompatibilityDriver { static func main() throws { try PanelMesherRegression.main(); try SourceMeshCoverage.main() } }\n')
files={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file()}
Path(sys.argv[2]).write_text(json.dumps({'scope':'Current complete meshes compared byte-for-byte with permanent pre-recovery 189-mesh goldens; isolated main-entrypoint and complete mesh-export adaptation only, identical to baseline instrumentation','snapshotDirectory':str(root),'sha256':files},indent=2)+'\n')
MANIFEST
printf '%s\n' "Snapshot: $snapshot_dir"
swiftc -O -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -D PANEL_MESHER_INTEGRATION \
 -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature InferSendableFromCaptures \
 -enable-upcoming-feature GlobalActorIsolatedTypesUsability -enable-upcoming-feature MemberImportVisibility \
 -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature NonisolatedNonsendingByDefault \
 -module-cache-path "$test_dir/module-cache" "$@" "$snapshot_dir/Tests/NativePattern/PanelMesher.swift" \
 "$snapshot_dir/Tests/NativePattern/SourceMeshCoverage.swift" "$snapshot_dir/Tests/NativePattern/RecoveryCompatibilityDriver.swift" -o "$test_dir/compatibility"
GARMENTCODE_PANEL_MESH_OUTPUT_DIR="$output_dir/panel-output" GARMENTCODE_SOURCE_MESH_OUTPUT="$output_dir/coverage-output" "$test_dir/compatibility"
python3 - "$snapshot_dir/Tests/NativePattern/Fixtures/panel-mesher-pre-recovery-goldens.json" "$output_dir" <<'COMPARE'
import hashlib,json,sys
from pathlib import Path
fixture=json.loads(Path(sys.argv[1]).read_text());root=Path(sys.argv[2]);rows=[]
assert fixture['format']=='GarmentCodePreBoundaryRecoveryMeshGoldens/v1'
for folder,expected in fixture['sha256'].items():
 actual={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root/folder).glob('*.json'))}
 diffs=[name for name in sorted(actual.keys()|expected.keys()) if actual.get(name)!=expected.get(name)]
 rows.append({'folder':folder,'fileCount':len(actual),'completeMeshCount':sum(name.endswith('-mesh.json') for name in actual),'differences':diffs,'allBytesIdentical':not diffs})
passed=all(row['allBytesIdentical'] for row in rows)
summary={'passed':passed,'baselineMesherSHA256':fixture['baselineMesherSHA256'],'comparedJSONCount':sum(r['fileCount'] for r in rows),'completeMeshCount':sum(r['completeMeshCount'] for r in rows),'comparisons':rows,'scope':'Exact saved original source/mesh JSON bytes, not a tolerance comparison. No physical or App acceptance claimed.'}
(root/'compatibility-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print(json.dumps(summary,indent=2));assert passed,'Existing successful mesh bytes changed'
COMPARE
