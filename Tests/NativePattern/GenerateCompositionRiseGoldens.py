#!/usr/bin/env python3
"""Regenerate fitted-upper/lower-rise oracles from unmodified GarmentCode.

This script is not needed by Swift regression. A pinned source checkout or a
read-only Git object repository must independently verify every imported file.
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
parser.add_argument("--upstream-dir", type=Path, required=True)
parser.add_argument("--git-dir", type=Path)
parser.add_argument("--source-tree-proof", type=Path)
parser.add_argument("--body-input", type=Path, required=True)
parser.add_argument("--female-fixture", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
source = args.upstream_dir.resolve()
body_raw = json.loads(args.body_input.read_text())
bodies = {"default": body_raw.get("values", body_raw),
          "female": json.loads(args.female_fixture.read_text())["body"]}
git = ["git", "--git-dir=" + str(args.git_dir.resolve())] if args.git_dir else ["git", "-C", str(source)]
tree = json.loads(args.source_tree_proof.read_text()) if args.source_tree_proof else None
if tree:
    assert tree["commit"] == COMMIT and tree["treeSHA"] == "fd422f0e3708f4d67f169cb2553fa38182601d44"
else:
    subprocess.check_output(git + ["cat-file", "-e", COMMIT + "^{commit}"])
source_hashes = {}
for path in sorted(source.rglob("*")):
    if path.is_file() and path.suffix in (".py", ".yaml"):
        relative = str(path.relative_to(source))
        original = path.read_bytes()
        if tree:
            oid = hashlib.sha1(b"blob " + str(len(original)).encode() + b"\0" + original).hexdigest()
            assert oid == tree["blobSHA"][relative], "Modified upstream input: " + relative
        else:
            assert original == subprocess.check_output(git + ["cat-file", "blob", COMMIT + ":" + relative]), "Modified upstream input: " + relative
        source_hashes[relative] = hashlib.sha256(original).hexdigest()
os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/TailorAssCompositionOracleMatplotlib")
os.chdir(source)
sys.path.insert(0, str(source))
cairo = types.ModuleType("cairosvg")
cairo.svg2png = lambda *a, **k: None
cairo.svg2pdf = lambda *a, **k: None
sys.modules["cairosvg"] = cairo
import numpy as np
import scipy
import yaml
from assets.garment_programs import meta_garment as meta

with (source / "assets/design_params/default.yaml").open() as stream:
    base = yaml.safe_load(stream)["design"]

def isolated(name, body, design, kind):
    d = copy.deepcopy(design)
    if kind == "upper":
        d["meta"]["wb"]["v"] = d["meta"]["bottom"]["v"] = None
    elif kind == "lower":
        fitted = d["meta"]["upper"]["v"] == "FittedShirt"
        d["meta"]["upper"]["v"] = d["meta"]["wb"]["v"] = None
        if fitted:
            d["flare-skirt"]["rise"]["v"] = 1.0
    else:
        d["meta"]["upper"]["v"] = d["meta"]["bottom"]["v"] = None
    return meta.MetaGarment(name, copy.deepcopy(body), d).assembly().spec

cases = []
for body_name, body in bodies.items():
    for upper in ("FittedShirt", "Shirt"):
        for bottom in ("SkirtCircle", "AsymmSkirtCircle", "SkirtManyPanels"):
            for rise in (0.5, 0.75):
                for belt in ((None, "StraightWB", "FittedWB") if upper == "FittedShirt" else (None,)):
                    name = f"{body_name}-{upper}-{bottom}-{belt}-rise{rise}"
                    d = copy.deepcopy(base)
                    d["meta"]["upper"]["v"] = upper
                    d["meta"]["bottom"]["v"] = bottom
                    d["meta"]["wb"]["v"] = belt
                    d["flare-skirt"]["rise"]["v"] = rise
                    expected = meta.MetaGarment(name, copy.deepcopy(body), copy.deepcopy(d)).assembly().spec
                    components = [{"kind": "upper", "pattern": isolated(name, body, d, "upper")}]
                    if belt:
                        components.append({"kind": "waistband", "pattern": isolated(name, body, d, "waistband")})
                    components.append({"kind": "lower", "pattern": isolated(name, body, d, "lower")})
                    cases.append({"id": name, "bodyName": body_name,
                        "overrides": [{"path": ["meta", "upper"], "value": upper},
                                      {"path": ["meta", "bottom"], "value": bottom},
                                      {"path": ["meta", "wb"], "value": belt},
                                      {"path": ["flare-skirt", "rise"], "value": rise}],
                        "expected": expected, "initialComponents": components})
                    print("GENERATED", name, len(expected["pattern"]["panels"]), flush=True)
payload = {"format": "GarmentCodeCompositionRiseOracles/v1", "source": {
    "repository": "https://github.com/maria-korosteleva/GarmentCode", "commit": COMMIT,
    "sourceFileSHA256": source_hashes,
    "allImportedFilesMatchPinnedGitObjects": True,
    "verifiedGitTreeSHA": tree["treeSHA"] if tree else None,
    "numpyVersion": np.__version__, "scipyVersion": scipy.__version__,
    "generatorSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "scope": "Official full patterns and independent isolated components; Swift is never called."},
    "bodies": bodies, "cases": cases}
args.output.resolve().write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
print("PASS composition-rise official cases", len(cases), flush=True)
