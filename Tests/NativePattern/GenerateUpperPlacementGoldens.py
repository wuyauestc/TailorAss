#!/usr/bin/env python3
"""Generate independent upper initial placements with unmodified GarmentCode.

Daily Swift regression uses the saved JSON, without this Python environment.
An exact Git checkout or verified read-only extraction is required to regenerate.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import types

COMMIT = "d449629979028123a5c4dc9e732a2ec19b7fce31"
SCRIPT = Path(__file__).resolve()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--upstream-dir", required=True, type=Path)
parser.add_argument("--extracted-source-proof", type=Path)
parser.add_argument("--output", type=Path, default=SCRIPT.parent / "Fixtures/upper-placement-oracles.json")
args = parser.parse_args()
source, output = args.upstream_dir.resolve(), args.output.resolve()
if args.extracted_source_proof:
    proof = json.loads(args.extracted_source_proof.read_text())
    assert proof["commit"] == COMMIT and proof.get("missing") == []
    provenance = {"method": proof["method"], "extractionProofSHA256": hashlib.sha256(args.extracted_source_proof.read_bytes()).hexdigest()}
else:
    assert subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == COMMIT
    assert not subprocess.check_output(["git", "-C", str(source), "diff", "--name-only", "HEAD"], text=True).strip()
    provenance = {"method": "Unmodified exact Git checkout"}
source_files = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(source.rglob("*")) if p.is_file() and p.suffix in (".py", ".yaml")}
default_body = json.loads((SCRIPT.parent / "Fixtures/lower-branch-oracles.json").read_text())["body"]
female_body = json.loads((SCRIPT.parent / "Fixtures/meta-grid-female.json").read_text())["body"]
os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/tailorass-upper-oracle-matplotlib")
os.chdir(source)
sys.path.insert(0, str(source))
cairo = types.ModuleType("cairosvg")
cairo.svg2png = lambda *a, **k: None
cairo.svg2pdf = lambda *a, **k: None
sys.modules["cairosvg"] = cairo
import numpy as np
import scipy
import yaml
from assets.garment_programs.meta_garment import MetaGarment

base_design = yaml.safe_load((source / "assets/design_params/default.yaml").read_text())["design"]
cases = []
def generate(body_name, body, upper, tag, edits=(), pose=None):
    design = copy.deepcopy(base_design)
    changes = [(["meta", "upper"], upper), (["meta", "bottom"], None), (["meta", "wb"], None)] + list(edits)
    for path, value in changes:
        node = design
        for key in path:
            node = node[key]
        node["v"] = value
    body = copy.deepcopy(body)
    if pose is not None:
        body["arm_pose_angle"] = pose
    initial = copy.deepcopy(design)
    name = f"{body_name}-{upper}-{tag}"
    garment = MetaGarment(name, body, design)
    spec = garment.assembly().spec
    cases.append({"id": name, "body": body, "overrides": [{"path": p, "value": v} for p, v in changes],
                  "inputDesignSHA256": hashlib.sha256(json.dumps(initial, sort_keys=True, separators=(",", ":")).encode()).hexdigest(),
                  "expected": spec})
    print("GENERATED", name, len(spec["pattern"]["panels"]), "panels", flush=True)

for body_name, body in (("all", default_body), ("female", female_body)):
    for upper in ("Shirt", "FittedShirt"):
        generate(body_name, body, upper, "default")
        generate(body_name, body, upper, "sleeved", [(["sleeve", "sleeveless"], False)])
        generate(body_name, body, upper, "sleeve-varied", [(["sleeve", "sleeveless"], False),
            (["sleeve", "length"], 0.6), (["sleeve", "end_width"], 1.3), (["sleeve", "sleeve_angle"], 30),
            (["sleeve", "connecting_width"], 0.4), (["sleeve", "opening_dir_mix"], 0.3)])
        generate(body_name, body, upper, "standing", [(["sleeve", "sleeveless"], False),
            (["sleeve", "standing_shoulder"], True), (["sleeve", "standing_shoulder_len"], 7),
            (["sleeve", "sleeve_angle"], 40)])
        generate(body_name, body, upper, "connect-ruffle", [(["sleeve", "sleeveless"], False), (["sleeve", "connect_ruffle"], 1.4)])
        for cuff in ("CuffBand", "CuffSkirt", "CuffBandSkirt"):
            generate(body_name, body, upper, cuff, [(["sleeve", "sleeveless"], False),
                (["sleeve", "length"], 0.6), (["sleeve", "cuff", "type"], cuff),
                (["sleeve", "cuff", "top_ruffle"], 1.2), (["sleeve", "cuff", "cuff_len"], 0.15)])
        for collar in ("Turtle", "SimpleLapel", "Hood2Panels"):
            generate(body_name, body, upper, "sleeved-" + collar, [(["sleeve", "sleeveless"], False),
                (["collar", "component", "style"], collar)])
        generate(body_name, body, upper, "sleeved-standing-lapel", [(["sleeve", "sleeveless"], False),
            (["collar", "component", "style"], "SimpleLapel"), (["collar", "component", "lapel_standing"], True)])
        for neck in ("CircleNeckHalf", "CurvyNeckHalf", "VNeckHalf", "SquareNeckHalf", "TrapezoidNeckHalf", "CircleArcNeckHalf", "Bezier2NeckHalf"):
            generate(body_name, body, upper, neck, [(["collar", "f_collar"], neck), (["collar", "b_collar"], neck)])
        for armhole in ("ArmholeCurve", "ArmholeSquare", "ArmholeAngle"):
            generate(body_name, body, upper, armhole, [(["sleeve", "armhole_shape"], armhole)])
        generate(body_name, body, upper, "asym-left-band-skirt", [(["left", "enable_asym"], True),
            (["left", "sleeve", "sleeveless"], False), (["left", "sleeve", "cuff", "type"], "CuffBandSkirt"),
            (["left", "sleeve", "length"], 0.7), (["left", "shirt", "width"], 1.2)])
        generate(body_name, body, upper, "asym-right-skirt", [(["left", "enable_asym"], True),
            (["sleeve", "sleeveless"], False), (["sleeve", "cuff", "type"], "CuffSkirt"), (["sleeve", "length"], 0.6)])
        for pose in (30, 60):
            generate(body_name, body, upper, "pose" + str(pose), [(["sleeve", "sleeveless"], False),
                (["sleeve", "length"], 0.8), (["sleeve", "cuff", "type"], "CuffBandSkirt")], pose=pose)
        if upper == "FittedShirt":
            generate(body_name, body, upper, "strapless", [(["shirt", "strapless"], True), (["sleeve", "sleeveless"], False)])
            generate(body_name, body, upper, "asym-left-strapless", [(["left", "enable_asym"], True),
                (["left", "shirt", "strapless"], True), (["sleeve", "sleeveless"], False)])

payload = {"format": "GarmentCodeNativeUpperPlacementOracles/v1", "source": {
    "repository": "https://github.com/maria-korosteleva/GarmentCode", "commit": COMMIT,
    "provenance": provenance, "sourceFileSHA256": source_files,
    "designFileSHA256": source_files["assets/design_params/default.yaml"],
    "numpyVersion": np.__version__, "scipyVersion": scipy.__version__,
    "generatorSHA256": hashlib.sha256(SCRIPT.read_bytes()).hexdigest(),
    "scope": "Unmodified official MetaGarment with explicit resolved body inputs. No Swift geometry or placement called."},
    "baseDesign": base_design, "cases": cases}
output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
print("PASS official upper placement oracles", len(cases), flush=True)
