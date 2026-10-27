#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssWaistbandBuild.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -O -D BODY_SURFACE_INTEGRATION -module-cache-path "$test_dir/module-cache" \
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
  "$repo_dir/TrailorAss/Models/GarmentCodeWaistbandDrape.swift" \
  "$script_dir/BodySurfaceContact.swift" "$script_dir/WaistbandDrape.swift" -o "$test_dir/waistband"
if [ "${GARMENTCODE_WAISTBAND_SENSITIVITY:-0}" = "1" ]; then
  output_base=${GARMENTCODE_WAISTBAND_OUTPUT_DIR:-/private/tmp/TailorAssWaistbandSensitivity}
  for passes in 20 40 80; do
    env GARMENTCODE_WAISTBAND_CASE_FILTER=straight-default,fitted-default \
      GARMENTCODE_WAISTBAND_STRAIN_PASSES="$passes" \
      GARMENTCODE_WAISTBAND_OUTPUT_DIR="$output_base/passes-$passes" "$test_dir/waistband"
  done
else
  "$test_dir/waistband"
fi
