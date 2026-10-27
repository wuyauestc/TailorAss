#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
test_dir=$(mktemp -d /private/tmp/TailorAssClothMaterial.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
swiftc -O -module-cache-path "$test_dir/module-cache" \
  "$repo_dir/TrailorAss/Models/GarmentCodeClothMaterial.swift" \
  "$script_dir/ClothMaterial.swift" -o "$test_dir/material"
"$test_dir/material"
