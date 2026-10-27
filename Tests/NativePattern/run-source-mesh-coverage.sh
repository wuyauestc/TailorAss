#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssSourceMeshCoverageBuild.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -O -swift-version 5 -default-isolation MainActor -warnings-as-errors -D PANEL_MESHER_INTEGRATION -module-cache-path "$test_dir/module-cache" \
  "$repo_dir/TrailorAss/Models/PatternDesignModels.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeGeometry.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodePrograms.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeNativeGenerator.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeClothMaterial.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeClothContact.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeBodySurfaceContact.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeStandardBody.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeCircleDrape.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeBodyRig.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeBodyMeshQueries.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeBodySurfaceMeasurements.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeFitDeformationReplay.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeBodySurfaceFitter.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeBodySurfaceValidator.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeFittedBody.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodePanelMesher.swift" \
  "$script_dir/PanelMesher.swift" "$script_dir/SourceMeshCaseDefinitions.swift" "$script_dir/SourceMeshCoverage.swift" -o "$test_dir/source-mesh-coverage"
"$test_dir/source-mesh-coverage"
