#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssSewingBuild.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -O -module-cache-path "$test_dir/module-cache" \
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
  "$repo_dir/TrailorAss/Models/GarmentCodeSkirtDrape.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodePanelMesher.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeSewing.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeSewnDrape.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeContinuousBodyContact.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeSewnBodyContact.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeSewnPointBlock.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeSourceTethers.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeSewnInput.swift" \
  "$script_dir/Sewing.swift" -o "$test_dir/sewing"
"$test_dir/sewing"
