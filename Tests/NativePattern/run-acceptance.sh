#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -n "${GARMENTCODE_CASE_FILTER-}" ]; then
  echo "Full acceptance requires GARMENTCODE_CASE_FILTER to be unset" >&2
  exit 1
fi
GARMENTCODE_NATIVE_ACCEPTANCE=1 sh "$script_dir/run.sh"
sh "$script_dir/run-tangent.sh" --quality-only
sh "$script_dir/run-tangent.sh" --stability-only
sh "$script_dir/run-import.sh"
sh "$script_dir/run-localization.sh"
sh "$script_dir/run-seams.sh"
sh "$script_dir/run-pdf-plan.sh"
sh "$script_dir/run-pdf.sh"
sh "$script_dir/run-allowance.sh"
sh "$script_dir/run-marks.sh"
sh "$script_dir/run-manufacturing-pdf.sh"
sh "$script_dir/run-basic.sh"
sh "$script_dir/run-lower-branches.sh"
python3 "$script_dir/run-levels-hem.py"
python3 "$script_dir/run-contour-diagnostics.py"
