#!/usr/bin/env python3
"""Exercise report export checks against an actual terminal simulation case."""
import argparse
import importlib.util
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--case", required=True, type=Path)
args = parser.parse_args()
path = Path(__file__).with_name("render-joint-report.py")
spec = importlib.util.spec_from_file_location("joint_report", path)
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)
output = json.loads((args.case / "validated-output.json").read_text())
raw = (args.case / "validated-output.obj").read_bytes()
report.obj_matches(raw, output)

def rejects(data):
    try:
        report.obj_matches(data, output)
    except ValueError:
        return
    raise AssertionError("Corrupted OBJ was accepted")

lines = raw.decode().splitlines()
body_object = next(i for i, line in enumerate(lines)
                   if line in ("o standard_mannequin", "o analytic_collision_proxy"))
rejects(("\n".join(lines[:body_object]) + "\n").encode())
body_face = next(i for i in range(body_object, len(lines)) if lines[i].startswith("f "))
wrong_offset = list(lines)
wrong_offset[body_face] = "f " + " ".join(str(int(v) - len(output["positions"]))
                                        for v in lines[body_face].split()[1:])
rejects(("\n".join(wrong_offset) + "\n").encode())
rejects(("\n".join(lines[:body_face] + lines[body_face + 1:]) + "\n").encode())
body_vertex = next(i for i in range(body_object, len(lines)) if lines[i].startswith("v "))
wrong_vertex = list(lines)
values = wrong_vertex[body_vertex].split()
values[1] = str(float(values[1]) + 0.001)
wrong_vertex[body_vertex] = " ".join(values)
rejects(("\n".join(wrong_vertex) + "\n").encode())
inputs = report.Inputs(args.case.resolve())
case = report.case_data(inputs, args.case.resolve())
assert case["accepted"] and inputs.unchanged()
if case["recordedContinuousSeamQuality"] is None:
    assert not case["recordedWholeSeamClosurePassed"]
    assert any("钉点间隙不能证明整条接缝闭合" in warning for warning in case["warnings"])
assert case["measurements"]["final"]["gapMeasurementScope"] == "anchorConstraintsOnly"
print(json.dumps({"passed": True, "actualCompleteOBJ": True,
                  "missingBodyWrongOffsetMissingFaceChangedBodyRejected": 4,
                  "actualReportAccepted": True, "label": case["label"]}, ensure_ascii=False))
