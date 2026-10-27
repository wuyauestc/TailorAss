#!/usr/bin/env python3
"""Observe fixed unmodified upstream inverse fitting and opening redistribution.

The existing upper oracle anchors the exact upstream Python/YAML file hashes.
Only wrappers recording inputs/results are added; all calculations call the
unmodified upstream functions. Daily regression needs only the saved JSON.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import types

SCRIPT = Path(__file__).resolve()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--upstream-dir", type=Path, required=True)
parser.add_argument("--output", type=Path, default=SCRIPT.parent / "Fixtures/inverse-sleeve-oracles.json")
args = parser.parse_args()
source = args.upstream_dir.resolve()
fixture_path = SCRIPT.parent / "Fixtures/upper-placement-oracles.json"
fixture = json.loads(fixture_path.read_text())
commit = "d449629979028123a5c4dc9e732a2ec19b7fce31"
assert fixture["source"]["commit"] == commit
for name, expected in fixture["source"]["sourceFileSHA256"].items():
    assert hashlib.sha256((source / name).read_bytes()).hexdigest() == expected, name
os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/tailorass-inverse-sleeve-matplotlib")
os.chdir(source)
sys.path.insert(0, str(source))
cairo = types.ModuleType("cairosvg")
cairo.svg2png = lambda *a, **k: None
cairo.svg2pdf = lambda *a, **k: None
sys.modules["cairosvg"] = cairo
import numpy as np
import scipy
import svgpathtools as svg
import pygarment.garmentcode.operators as ops
from assets.garment_programs.meta_garment import MetaGarment

def point(value):
    return [float(value.real), float(value.imag)]

def controls(edge):
    return [point(z) for z in edge.as_curve().bpoints()]

fits, redistributions = [], []
actual_minimize = ops.minimize
def observe_minimize(fun, x0, *positional, **keywords):
    result = actual_minimize(fun, x0, *positional, **keywords)
    if fun.__name__ == "_bend_extend_2_tangent":
        cp, length, direction, t0, t1, samples = keywords["args"]
        shift = result.x
        final = [cp[0].tolist(), (cp[1] + shift[:2]).tolist(),
                 (cp[2] + shift[2:4]).tolist(), (cp[-1] + direction * shift[4]).tolist()]
        fits.append({"initialControl": cp.tolist(), "targetLength": float(length),
            "direction": direction.tolist(), "startTangent": point(t0), "endTangent": point(t1),
            "curvatureSamples": samples, "x0": list(x0), "bounds": keywords.get("bounds"),
            "method": keywords.get("method"), "success": bool(result.success),
            "status": int(result.status), "message": str(result.message),
            "iterations": int(result.nit), "functionEvaluations": int(result.nfev),
            "objective": float(result.fun), "shift": result.x.tolist(), "resultControl": final})
    return result

actual_even = ops.even_armhole_openings
def observe_even(front, back, *positional, **keywords):
    f, b = front.copy(), back.copy()
    b.reflect([0, 0], [1, 0]).reverse().snap_to(f[-1].end)
    slope = np.array([f[0].start, b[-1].end])
    vector = slope[1] - slope[0]
    perpendicular = np.array([-vector[1], vector[0]])
    middle = np.sum(slope, axis=0) / 2
    segment = svg.Line(complex(*(middle - 20 * perpendicular)), complex(*(middle + 20 * perpendicular)))
    before = {"front": [controls(e) for e in front], "back": [controls(e) for e in back],
              "slope": slope.tolist(), "intersections": f[-1].as_curve().intersect(segment),
              "tolerance": keywords.get("tol")}
    result = actual_even(front, back, *positional, **keywords)
    before["resultFront"] = [controls(e) for e in result[0]]
    before["resultBack"] = [controls(e) for e in result[1]]
    redistributions.append(before)
    return result

ops.minimize = observe_minimize
ops.even_armhole_openings = observe_even
cases = []
for body_name in ("all", "female"):
    body = next(c["body"] for c in fixture["cases"] if c["id"] == body_name + "-Shirt-default")
    for upper in ("Shirt", "FittedShirt"):
        for tag, changes in (("default", []),
                ("angle40-standing-false", [(["sleeve", "sleeve_angle"], 40), (["sleeve", "standing_shoulder"], False)]),
                ("angle40-standing-true", [(["sleeve", "sleeve_angle"], 40), (["sleeve", "standing_shoulder"], True)])):
            edits = [(["meta", "upper"], upper), (["meta", "bottom"], None),
                     (["meta", "wb"], None), (["sleeve", "sleeveless"], False)] + changes
            design = copy.deepcopy(fixture["baseDesign"])
            for path, value in edits:
                node = design
                for key in path:
                    node = node[key]
                node["v"] = value
            initial = copy.deepcopy(design)
            fits.clear()
            redistributions.clear()
            name = body_name + "-" + upper + "-" + tag
            garment = MetaGarment(name, copy.deepcopy(body), design)
            cases.append({"id": name, "body": body, "design": initial,
                "overrides": [{"path": p, "value": v} for p, v in edits],
                "fits": copy.deepcopy(fits), "redistributions": copy.deepcopy(redistributions),
                "expected": garment.assembly().spec})
            print("GENERATED", name, "intersections", [len(x["intersections"]) for x in redistributions], flush=True)

assert any(not r["intersections"] for c in cases for r in c["redistributions"])
assert any(r["intersections"] for c in cases for r in c["redistributions"])
result = {"format": "GarmentCodeInverseSleeveOracles/v1", "source": {
    "commit": commit, "sourceFileSHA256": fixture["source"]["sourceFileSHA256"],
    "anchoringUpperFixtureSHA256": hashlib.sha256(fixture_path.read_bytes()).hexdigest(),
    "generatorSHA256": hashlib.sha256(SCRIPT.read_bytes()).hexdigest(),
    "numpyVersion": np.__version__, "scipyVersion": scipy.__version__,
    "scope": "Actual unmodified upstream optimizer and redistribution. Observers record only, and do not change arguments, curves, tolerances, results or source validity."},
    "cases": cases}
args.output.resolve().write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
print("PASS", len(cases), "official inverse sleeve source cases", flush=True)
