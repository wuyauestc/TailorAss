#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssSewnDrapeBuild.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -O -D SEWN_INPUT_INTEGRATION -D BODY_SURFACE_INTEGRATION -module-cache-path "$test_dir/module-cache" \
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
  "$repo_dir/TrailorAss/Models/GarmentCodeWaistbandDrape.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeWaistbandAssembly.swift" \
  "$script_dir/BodySurfaceContact.swift" "$script_dir/SewnInput.swift" \
  "$script_dir/SewnDrape.swift" -o "$test_dir/sewn-drape"
"$test_dir/sewn-drape"
