#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/tailorass-import-test.XXXXXX")"
swift_module_cache="${TMPDIR:-/tmp}/tailorass-swift-module-cache"
trap 'rm -f "$test_directory/GarmentCodeImportSmoke"; rmdir "$test_directory"' EXIT

swiftc \
  -module-cache-path "$swift_module_cache" \
  "$repository_root/TrailorAss/Models/PatternDesignModels.swift" \
  "$repository_root/Tests/GarmentCodeImportSmoke.swift" \
  -o "$test_directory/GarmentCodeImportSmoke"
"$test_directory/GarmentCodeImportSmoke" \
  "$repository_root/TrailorAss/Resources/GarmentCodeTShirtSample.json"
swiftc -frontend -parse "$repository_root/TrailorAss/Views/Garment/PatternDesignView.swift"
