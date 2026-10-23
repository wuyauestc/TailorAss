#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssPDFPlan.XXXXXX)
swiftc -module-cache-path "$test_dir/module-cache" \
  "$repo_dir/TrailorAss/Models/PatternDesignModels.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeGeometry.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodePrograms.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeNativeGenerator.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeLocalization.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeSeamGuide.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeDraftingSettings.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeSeamAllowance.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodeManufacturingMarks.swift" \
  "$repo_dir/TrailorAss/Models/GarmentCodePrintPlan.swift" \
  "$script_dir/PDFPrintPlan.swift" -o "$test_dir/pdf-plan"
"$test_dir/pdf-plan"
