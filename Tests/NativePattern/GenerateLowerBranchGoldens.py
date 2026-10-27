#!/usr/bin/env python3
"""Generate independent lower-branch JSON using unmodified pinned GarmentCode.

Normal regression consumes the checked-in JSON and needs no Python packages or
upstream checkout. Regeneration requires upstream dependencies, an explicit
resolved body input, and either an exact Git checkout or a recorded read-only
extraction proof from that commit. Only unused Cairo rendering is stubbed.
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
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--upstream-dir", required=True, type=Path)
parser.add_argument("--body-input", required=True, type=Path)
parser.add_argument("--extracted-source-proof", type=Path)
parser.add_argument("--output", type=Path, default=Path(__file__).parent / "Fixtures/lower-branch-oracles.json")
args = parser.parse_args()
source = args.upstream_dir.resolve()
if args.extracted_source_proof:
    proof = json.loads(args.extracted_source_proof.read_text())
    assert proof["commit"] == COMMIT and proof.get("missing") == []
    provenance = {"method": proof["method"], "extractionProofSHA256": hashlib.sha256(args.extracted_source_proof.read_bytes()).hexdigest()}
else:
    actual = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
    assert actual == COMMIT, actual
    assert not subprocess.check_output(["git", "-C", str(source), "diff", "--name-only", "HEAD"], text=True).strip()
    provenance = {"method": "Unmodified exact Git checkout"}
source_files = {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in sorted(source.rglob("*")) if p.is_file() and p.suffix in (".py", ".yaml")}
assert "assets/garment_programs/godet.py" in source_files
assert "assets/garment_programs/pants.py" in source_files
body_raw = json.loads(args.body_input.read_text())
body = body_raw.get("values", body_raw)
assert all(key in body for key in ("_waist_level", "_leg_length", "_hip_inclination"))
os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/tailorass-lower-oracle-matplotlib")
os.chdir(source)
sys.path.insert(0, str(source))
cairo = types.ModuleType("cairosvg")
cairo.svg2png = lambda *a, **k: None
cairo.svg2pdf = lambda *a, **k: None
sys.modules["cairosvg"] = cairo
import numpy as np
import scipy
import yaml
import svgpathtools
from assets.garment_programs.meta_garment import MetaGarment

with (source / "assets/design_params/default.yaml").open() as stream:
    base_design = yaml.safe_load(stream)["design"]

cases = []
def generate(name, changes):
    design = copy.deepcopy(base_design)
    for key in ("upper", "bottom", "wb"):
        design["meta"][key]["v"] = None
    for path, value in changes:
        node = design
        for key in path:
            node = node[key]
        node["v"] = value
    garment = MetaGarment(name, copy.deepcopy(body), design)
    spec = garment.assembly().spec
    cases.append({"id": name, "overrides": [{"path": path, "value": value} for path, value in changes], "expected": spec})
    print("GENERATED", name, len(spec["pattern"]["panels"]), "panels", flush=True)

for wb in ("StraightWB", "FittedWB"):
    for rise in (0.5, 0.75, 1.0):
        for unrelated in (0.5, 1.0):
            generate(f"pants-{wb}-rise{rise}-skirt{unrelated}", [
                (["meta", "bottom"], "Pants"), (["meta", "wb"], wb),
                (["pants", "rise"], rise), (["skirt", "rise"], unrelated)])

slits = ("front_slit", "back_slit", "left_slit", "right_slit")
for subset in ((), ("front_slit",), ("back_slit",), ("left_slit",), ("right_slit",), slits):
    generate("godet-" + ("-".join(subset) or "no-slits"), [
        (["meta", "bottom"], "GodetSkirt"), (["godet-skirt", "base"], "PencilSkirt")
    ] + [(["pencil-skirt", key], 0.2) for key in subset])
for wb in ("StraightWB", "FittedWB"):
    generate("godet-all-slits-" + wb, [
        (["meta", "bottom"], "GodetSkirt"), (["meta", "wb"], wb),
        (["godet-skirt", "base"], "PencilSkirt")
    ] + [(["pencil-skirt", key], 0.2) for key in slits])
for subset in (("front_slit",), ("back_slit",), ("left_slit",), ("right_slit",), slits):
    generate("pencil-" + "-".join(subset), [(["meta", "bottom"], "PencilSkirt")]
             + [(["pencil-skirt", key], 0.2) for key in subset])

payload = {"format": "GarmentCodeNativeLowerBranchOracles/v1", "source": {
    "repository": "https://github.com/maria-korosteleva/GarmentCode", "commit": COMMIT,
    "provenance": provenance, "sourceFileSHA256": source_files,
    "numpyVersion": np.__version__, "scipyVersion": scipy.__version__,
    "generatorSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "scope": "Unmodified official MetaGarment and 2D geometry; explicit resolved input body. No Swift generator called."},
    "body": body, "cases": cases}
args.output.resolve().write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
print("PASS official lower-branch oracles", len(cases), flush=True)
