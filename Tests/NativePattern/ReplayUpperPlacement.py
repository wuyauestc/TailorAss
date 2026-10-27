#!/usr/bin/env python3
"""Replay official rigid assembly operations on exact native source paper.

This isolates placement from existing 2D sleeve-fit differences. It never calls
the Swift placement module, changes paper dimensions, or copies official
fixture offsets onto sleeves. Daily regression only reads its saved results.
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
parser.add_argument("--native-exports", type=Path, required=True)
parser.add_argument("--fixture", type=Path, default=SCRIPT.parent / "Fixtures/upper-placement-oracles.json")
args = parser.parse_args()
source, exports, fixture_path = args.upstream_dir.resolve(), args.native_exports.resolve(), args.fixture.resolve()
fixture = json.loads(fixture_path.read_text())
assert fixture["source"]["commit"] == "d449629979028123a5c4dc9e732a2ec19b7fce31"
for name, expected in fixture["source"]["sourceFileSHA256"].items():
    assert hashlib.sha256((source / name).read_bytes()).hexdigest() == expected, name
os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/tailorass-upper-replay-matplotlib")
os.chdir(source)
sys.path.insert(0, str(source))
cairo = types.ModuleType("cairosvg")
cairo.svg2png = lambda *a, **k: None
cairo.svg2pdf = lambda *a, **k: None
sys.modules["cairosvg"] = cairo
import numpy as np
from scipy.spatial.transform import Rotation as R
import pygarment as pyg
from assets.garment_programs.bodice import Shirt, BodiceFrontHalf, BodiceBackHalf
from assets.garment_programs.tee import TorsoFrontHalfPanel, TorsoBackHalfPanel

def native_panel(name, raw, left):
    panel = pyg.Panel(name)
    vertices = [list(v) for v in raw["vertices"]]
    edges = []
    for item in raw["edges"]:
        a, b = (vertices[i] for i in item["endpoints"])
        curve = item.get("curvature")
        if curve is None:
            edge = pyg.Edge(a, b)
        elif curve["type"] == "circle":
            p = curve["params"]
            edge = (pyg.CircleEdge(a, b, cy=p[0]) if len(p) == 1 else
                    pyg.CircleEdgeFactory.from_points_radius(a, b, radius=p[0], large_arc=bool(p[1]), right=bool(p[2])))
        else:
            edge = pyg.CurveEdge(a, b, control_points=curve["params"])
        edges.append(edge)
    panel.edges = pyg.EdgeSequence(*edges)
    if left:
        panel.mirror()
        panel.edges.reverse()
    return panel

def interface(panels, ids):
    return pyg.Interface.from_multiple(*[pyg.Interface(panels[name], pyg.EdgeSequence(*[panels[name].edges[i] for i in indices]))
                                         for name, indices in sorted(ids.items())])

def top_edges(panels):
    result = {}
    for name, panel in panels.items():
        top = max(v[1] for v in panel.edges.verts())
        result[name] = [i for i, e in enumerate(panel.edges) if abs(e.start[1]-top)<1e-7 and abs(e.end[1]-top)<1e-7]
        assert result[name], name
    return result

export_data = json.loads((exports / "exports.json").read_text())
export_rows = {x["id"]: x for x in export_data["exports"]}
failures = list(export_data["failures"])
checked = 0
for case in fixture["cases"]:
    if case["id"] not in export_rows:
        continue
    entry = export_rows[case["id"]]
    data = (exports / "native" / entry["file"]).read_bytes()
    assert hashlib.sha256(data).hexdigest() == entry["sourceSHA256"]
    native = json.loads(data)
    body = native["parameters"]["body"]
    design = native["parameters"]["design"]
    # Invoke the real upstream asymmetric parameter sharing/suppression.
    adjusted = Shirt.eval_dep_params(None, copy.deepcopy(design))
    fitted = design["meta"]["upper"]["v"] == "FittedShirt"
    expected = {name: {"translation": panel["translation"], "rotation": panel["rotation"]}
                for name, panel in case["expected"]["pattern"]["panels"].items()}
    try:
        for side in ("right", "left"):
            left = side == "left"
            half_design = adjusted["left"] if left and adjusted["left"]["enable_asym"]["v"] else adjusted
            if fitted and half_design["shirt"]["strapless"]["v"]:
                continue
            if half_design["sleeve"]["sleeveless"]["v"]:
                continue
            raw = native["pattern"]["panels"]
            torsos = {}
            for front in (True, False):
                name = side + ("_ftorso" if front else "_btorso")
                cls = (BodiceFrontHalf if front else BodiceBackHalf) if fitted else (TorsoFrontHalfPanel if front else TorsoBackHalfPanel)
                seed = cls(name, body, half_design).translate_by([0, 0, 30 if front else -25])
                panel = native_panel(name, raw[name], left)
                # Restore the integer pivot already serialized in native XY.
                pivot = np.trunc(np.asarray(seed.edges[0].start))
                for vertex in panel.edges.verts():
                    vertex[0] += pivot[0]
                    vertex[1] += pivot[1]
                panel.translation = seed.translation.copy()
                torsos[name] = panel
            panels = {}
            for front in (True, False):
                name = side + ("_sleeve_f" if front else "_sleeve_b")
                panel = native_panel(name, raw[name], left)
                closing = panel.edges[-1].start if front else panel.edges[0].end
                panel.set_pivot(closing)
                panel.translate_to([-body["shoulder_w"]/2, body["height"]-body["head_l"], 15 if front else -15])
                panels[name] = panel
            sleeve = pyg.Component("replay_sleeve")
            sleeve.subs = list(panels.values())
            cuff = half_design["sleeve"]["cuff"]["type"]["v"]
            if cuff:
                bands, skirts = {}, {}
                for front in (True, False):
                    for kind, enabled in (("cuff", cuff != "CuffSkirt"), ("cuff_skirt", cuff != "CuffBand")):
                        if not enabled:
                            continue
                        name = "sl_"+side+"_"+kind+("_f" if front else "_b")
                        panel = native_panel(name, raw[name], left)
                        panel.top_center_pivot()
                        panel.center_x()
                        panel.translate_by([0, 0, 15 if front else -15])
                        (bands if kind == "cuff" else skirts)[name] = panel
                band_comp, skirt_comp = pyg.Component("bands"), pyg.Component("skirts")
                band_comp.subs, skirt_comp.subs = list(bands.values()), list(skirts.values())
                if cuff == "CuffBandSkirt":
                    skirt_comp.place_below(band_comp)
                cuff_comp = pyg.Component("cuff")
                cuff_comp.subs = [part for part in (band_comp, skirt_comp) if part.subs]
                # Identify actual top edges before construction pivots shift Y.
                top = {}
                for name, panel in (bands or skirts).items():
                    high = max(v[1] for v in panel.edges.verts())
                    top[name] = [i for i,e in enumerate(panel.edges) if abs(e.start[1]-high)<1e-7 and abs(e.end[1]-high)<1e-7]
                cuff_top = interface(bands or skirts, top)
                sleeve_out = interface(panels, {side+"_sleeve_f":[0],side+"_sleeve_b":[len(panels[side+"_sleeve_b"].edges)-1]})
                cuff_comp.rotate_by(R.from_euler("XYZ", [0,0,-90], degrees=True))
                cuff_comp.place_by_interface(cuff_top, sleeve_out, gap=2, alignment="top")
                sleeve.subs.append(cuff_comp)
                panels.update(bands)
                panels.update(skirts)
            sleeve.rotate_by(R.from_euler("XYZ", [0,0,body["arm_pose_angle"]], degrees=True))
            own_ids, torso_ids = {}, {}
            actual_sleeves = {side+"_sleeve_f",side+"_sleeve_b"}
            for stitch in native["pattern"]["stitches"]:
                a,b = stitch[:2]
                if a["panel"] in actual_sleeves and b["panel"] in torsos:
                    own, target = a,b
                elif b["panel"] in actual_sleeves and a["panel"] in torsos:
                    own, target = b,a
                else:
                    continue
                for value, ids in ((own,own_ids),(target,torso_ids)):
                    count = len(raw[value["panel"]]["edges"])
                    index = count-1-value["edge"] if left else value["edge"]
                    ids.setdefault(value["panel"],set()).add(index)
            own_ids = {key:sorted(value) for key,value in own_ids.items()}
            torso_ids = {key:sorted(value) for key,value in torso_ids.items()}
            sleeve.place_by_interface(interface(panels,own_ids), interface(torsos,torso_ids),
                                      gap=-1-body["arm_pose_angle"]/10, alignment="top")
            if left:
                sleeve.mirror()
            for name,panel in panels.items():
                assembled = panel.assembly().pattern["panels"][name]
                expected[name] = {"translation": assembled["translation"], "rotation": assembled["rotation"]}
        assert set(expected) == set(native["pattern"]["panels"])
        case["nativeReplay"] = {"sourceSHA256": entry["sourceSHA256"], "transforms": expected,
            "method": "Unmodified upstream Panel.set_pivot/top_center_pivot/center_x, Component.rotate_by/place_below/place_by_interface/mirror/assembly on exact native sleeve/cuff paper. Torso/collar anchors retain the independent original MetaGarment oracle; no fixed fixture offset is used for sleeves."}
        checked += 1
        print("REPLAYED",case["id"],flush=True)
    except BaseException as error:
        failures.append({"id":case["id"],"error":repr(error)})
        print("FAILED REPLAY",case["id"],repr(error),flush=True)
fixture["source"]["nativeReplayGeneratorSHA256"] = hashlib.sha256(SCRIPT.read_bytes()).hexdigest()
fixture["nativeReplayFailures"] = failures
fixture_path.write_text(json.dumps(fixture,ensure_ascii=False,indent=2,allow_nan=False)+"\n")
print("REPLAY COMPLETE",checked,"cases",len(failures),"failures",flush=True)
if failures:
    raise SystemExit(1)
