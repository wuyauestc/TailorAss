#!/usr/bin/env python3
"""Compare an exported native .75-sun input to the pinned official 2D oracle.

This deliberately does not manufacture a GarmentCode final 3D mesh. The mesh
quality section is our solver's measurement, not an upstream simulation score.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path


def compare(source_dir: Path, destination: Path):
    here = Path(__file__).resolve().parent
    oracle_path = here / "Fixtures/skirt-circle.json"
    pattern_path = source_dir / "circle-0.75-pattern.json"
    mesh_path = source_dir / "circle-0.75-mesh.json"
    oracle = json.loads(oracle_path.read_text())
    native = json.loads(pattern_path.read_text())
    mesh = json.loads(mesh_path.read_text())
    assert oracle["properties"]["units_in_meter"] == native["properties"]["units_in_meter"] == 100
    expected, actual = oracle["pattern"], native["pattern"]
    assert set(expected["panels"]) == set(actual["panels"]) == {"skirt_front", "skirt_back"}
    assert expected["stitches"] == actual["stitches"], "Stitch identity or direction changed"
    coordinate_deltas = []
    curve_deltas = []
    for name, panel in expected["panels"].items():
        other = actual["panels"][name]
        assert len(panel["vertices"]) == len(other["vertices"])
        for a, b in zip(panel["vertices"], other["vertices"]):
            coordinate_deltas += [abs(x-y) for x, y in zip(a, b)]
        assert len(panel["edges"]) == len(other["edges"])
        for a, b in zip(panel["edges"], other["edges"]):
            assert a["endpoints"] == b["endpoints"], "Boundary topology changed"
            ca, cb = a.get("curvature"), b.get("curvature")
            if ca is None or cb is None:
                assert ca is cb
                continue
            assert ca["type"] == cb["type"] == "circle"
            assert ca["params"][1:] == cb["params"][1:], "Arc orientation changed"
            curve_deltas.append(abs(ca["params"][0]-cb["params"][0]))
    maximum_delta = max(coordinate_deltas + curve_deltas)
    assert maximum_delta < 1e-7, f"Native 2D input differs from official oracle: {maximum_delta} cm"

    # Independent analytic annular-sector measurement from the official JSON.
    waist = hem = area = 0.0
    radial = []
    for panel in expected["panels"].values():
        arcs = [e for e in panel["edges"] if e.get("curvature", {}).get("type") == "circle"]
        arcs.sort(key=lambda e: e["curvature"]["params"][0])
        lengths, radii = [], []
        for edge in arcs:
            a, b = (panel["vertices"][index] for index in edge["endpoints"])
            radius, large, _ = edge["curvature"]["params"]
            angle = 2*math.asin(min(1, math.dist(a, b)/(2*radius)))
            if large:
                angle = 2*math.pi-angle
            lengths.append(radius*angle)
            radii.append(radius)
        waist += lengths[0]
        hem += lengths[1]
        angle = lengths[0]/radii[0]
        area += 0.5*angle*(radii[1]**2-radii[0]**2)
        radial.append(radii[1]-radii[0])
    d = mesh["diagnostics"]
    assert abs(d["waistCircumferenceMeters"]*100-waist) < 1e-7
    assert abs(d["hemCircumferenceMeters"]*100-hem) < 1e-7
    assert abs(d["radialLengthMeters"]*100-radial[0]) < 1e-7
    mesh_area = d["referenceAreaSquareMeters"]*10000
    area_error = abs(mesh_area-area)/area
    assert area_error < 0.001, "Flat mesh area discretization error exceeds 0.1%"
    # Topology is checked independently on the final indexed triangle mesh.
    edges = {}
    indices = mesh["triangleIndices"]
    assert len(indices) % 3 == 0
    assert all(isinstance(i, int) and 0 <= i < len(mesh["positions"]) for i in indices)
    for offset in range(0, len(indices), 3):
        a, b, c = indices[offset:offset+3]
        assert len({a, b, c}) == 3
        for x, y in [(a, b), (b, c), (c, a)]:
            key = tuple(sorted((x, y)))
            edges.setdefault(key, []).append((x, y))
    assert all(len(uses) <= 2 for uses in edges.values()), "Non-manifold seam"
    assert all(uses[0] == uses[1][::-1] for uses in edges.values() if len(uses) == 2), "Inconsistent triangle orientation"
    for path in mesh["seamPaths"]:
        for a, b in zip(path, path[1:]):
            assert len(edges[tuple(sorted((a, b)))]) == 2, "Unclosed side seam"
    result = {
        "source_commit": "d449629979028123a5c4dc9e732a2ec19b7fce31",
        "oracle_sha256": hashlib.sha256(oracle_path.read_bytes()).hexdigest(),
        "native_pattern_sha256": hashlib.sha256(pattern_path.read_bytes()).hexdigest(),
        "native_mesh_sha256": hashlib.sha256(mesh_path.read_bytes()).hexdigest(),
        "maximum_source_coordinate_or_radius_delta_cm": maximum_delta,
        "waist_cm": waist, "hem_cm": hem, "radial_length_cm": radial[0],
        "official_analytic_area_cm2": area, "mesh_flat_area_cm2": mesh_area,
        "flat_area_relative_error": area_error,
        "side_seams_manifold_and_oriented": True,
        "our_solver_diagnostics": d,
        "official_final_3d_mesh_available": False,
        "design2garmentcode_final_3d_mesh_available": False,
        "conclusion": "Official 2D input matches; 3D equality is NOT established."
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"PASS: official 2D delta {maximum_delta:.3g} cm; flat area error {area_error:.5%}; manifold oriented side seams")
    print("No matched official final 3D mesh: no 3D parity claim.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("/private/tmp/TailorAssClothResults"))
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parent / "Reports/2026-10-25-3d/comparison.json")
    args = parser.parse_args()
    compare(args.input, args.output)
