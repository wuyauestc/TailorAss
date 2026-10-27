#!/usr/bin/env python3
"""Pinned official full-outfit Levels rise oracles; never invokes Swift."""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import types

COMMIT = "d449629979028123a5c4dc9e732a2ec19b7fce31"
p = argparse.ArgumentParser(description=__doc__)
p.add_argument("--upstream-dir", type=Path, required=True)
p.add_argument("--source-tree-proof", type=Path, required=True)
p.add_argument("--body-input", type=Path, required=True)
p.add_argument("--female-fixture", type=Path, required=True)
p.add_argument("--output", type=Path, required=True)
a = p.parse_args()
source = a.upstream_dir.resolve()
output = a.output.resolve()
tree = json.loads(a.source_tree_proof.read_text())
assert tree["commit"] == COMMIT and tree["treeSHA"] == "fd422f0e3708f4d67f169cb2553fa38182601d44"
source_hashes = {}
for path in sorted(source.rglob("*")):
    if path.is_file() and path.suffix in (".py", ".yaml"):
        relative = str(path.relative_to(source))
        data = path.read_bytes()
        oid = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
        assert oid == tree["blobSHA"][relative], "Modified upstream source: " + relative
        source_hashes[relative] = hashlib.sha256(data).hexdigest()
body_raw = json.loads(a.body_input.read_text())
bodies = {"default": body_raw.get("values", body_raw), "female": json.loads(a.female_fixture.read_text())["body"]}
os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/TailorAssOfficialMatplotlib")
os.chdir(source)
sys.path.insert(0, str(source))
cairo = types.ModuleType("cairosvg")
cairo.svg2png = lambda *args, **kwargs: None
cairo.svg2pdf = lambda *args, **kwargs: None
sys.modules["cairosvg"] = cairo
import numpy as np
import scipy
import yaml
from assets.garment_programs import meta_garment as meta
with (source / "assets/design_params/default.yaml").open() as stream:
    base = yaml.safe_load(stream)["design"]
cases = []
for body_name, body in bodies.items():
    for rise in (0.5, 0.75):
        for band in (None, "StraightWB", "FittedWB"):
            design = copy.deepcopy(base)
            design["meta"]["upper"]["v"] = "FittedShirt"
            design["meta"]["bottom"]["v"] = "SkirtLevels"
            design["meta"]["wb"]["v"] = band
            design["levels-skirt"]["rise"]["v"] = rise
            case_id = f"{body_name}-FittedShirt-SkirtLevels-{band}-rise{rise}"
            expected = meta.MetaGarment(case_id, copy.deepcopy(body), copy.deepcopy(design)).assembly().spec
            cases.append({"id": case_id, "bodyName": body_name,
                          "overrides": [{"path": ["meta", "upper"], "value": "FittedShirt"},
                                        {"path": ["meta", "bottom"], "value": "SkirtLevels"},
                                        {"path": ["meta", "wb"], "value": band},
                                        {"path": ["levels-skirt", "rise"], "value": rise}],
                          "designRise": rise, "constructionRiseOverride": 1.0,
                          "expected": expected})
            print("GENERATED", case_id, len(expected["pattern"]["panels"]), flush=True)
payload = {"format": "GarmentCodeNativeAssemblyLevelsOracles/v1", "source": {
    "repository": "https://github.com/maria-korosteleva/GarmentCode", "commit": COMMIT,
    "verifiedGitTreeSHA": tree["treeSHA"], "allImportedFilesMatchPinnedGitObjects": True,
    "sourceFileSHA256": source_hashes, "numpyVersion": np.__version__, "scipyVersion": scipy.__version__,
    "generatorSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "scope": "Official full MetaGarment native construction, including Levels designRise base length with fitted requestedRise1. Swift and previous default placement fixtures are not called."},
    "bodies": bodies, "cases": cases}
output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
print("PASS official independent NativeAssembly Levels cases", len(cases), flush=True)
