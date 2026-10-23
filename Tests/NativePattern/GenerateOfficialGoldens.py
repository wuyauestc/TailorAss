#!/usr/bin/env python3
"""Regenerate pinned GarmentCode JSON fixtures for the Swift pattern ports.

Requires the exact upstream checkout at GARMENTCODE_SOURCE and its Python
dependencies. CairoSVG is stubbed only because fixture generation uses JSON,
not PNG/PDF rendering.
"""
import json
import os
import subprocess
import sys
import types
from pathlib import Path

source = Path(os.environ["GARMENTCODE_SOURCE"]).resolve()
if not (source / "assets/garment_programs/meta_garment.py").is_file():
    raise SystemExit("GARMENTCODE_SOURCE is not a GarmentCode checkout")
pinned_commit = "d449629979028123a5c4dc9e732a2ec19b7fce31"
actual_commit = subprocess.check_output(
    ["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
if actual_commit != pinned_commit:
    raise SystemExit(f"Expected GarmentCode {pinned_commit}, got {actual_commit}")
changed = subprocess.check_output(
    ["git", "-C", str(source), "diff", "--name-only", "-z", "HEAD"], text=True)
for filename in filter(None, changed.split("\0")):
    # The downloaded SVG may have a terminal newline absent in the Git blob.
    # Permit only that byte-level difference; reject any geometry/code changes.
    original = subprocess.check_output(["git", "-C", str(source), "show", f"HEAD:{filename}"])
    local = (source / filename).read_bytes()
    if filename == "assets/img/siggraph_logo_thick_connection.svg" and local.removesuffix(b"\n") == original.removesuffix(b"\n"):
        continue
    raise SystemExit(f"Official oracle source differs from pinned commit: {filename}")
# GarmentCode's SIGGRAPH SVG loader uses a repository-root-relative asset path.
# Run generation from the pinned checkout regardless of the caller's cwd.
os.chdir(source)
os.environ.setdefault("MPLCONFIGDIR", "/private/tmp/tailorass-matplotlib")
sys.path.insert(0, str(source))

cairosvg = types.ModuleType("cairosvg")
cairosvg.svg2png = lambda *args, **kwargs: None
cairosvg.svg2pdf = lambda *args, **kwargs: None
sys.modules["cairosvg"] = cairosvg

import yaml  # noqa: E402
from assets.bodies.body_params import BodyParameters  # noqa: E402
from assets.garment_programs.meta_garment import MetaGarment  # noqa: E402


def apply_parameter_overrides(design, overrides):
    for section, values in (overrides or {}).items():
        for key, value in values.items():
            if isinstance(value, dict):
                apply_parameter_overrides({section: design[section][key]}, {section: value})
            else:
                design[section][key]["v"] = value


def generate_skirt(bottom, panel_curve=None, bottom_cut=None, add_circle_cut=False,
                   parameter_overrides=None):
    body = BodyParameters(str(source / "assets/bodies/mean_all.yaml"))
    with (source / "assets/design_params/default.yaml").open() as stream:
        design = yaml.safe_load(stream)["design"]
    if bottom in ("StraightWB", "FittedWB"):
        design["meta"]["wb"]["v"] = bottom
    else:
        design["meta"]["bottom"]["v"] = bottom
    if panel_curve is not None:
        design["flare-skirt"]["skirt-many-panels"]["panel_curve"]["v"] = panel_curve
    if bottom_cut is not None:
        design["skirt"]["bottom_cut"]["v"] = bottom_cut
    if add_circle_cut:
        design["flare-skirt"]["cut"]["add"]["v"] = True
    apply_parameter_overrides(design, parameter_overrides)
    garment = MetaGarment(bottom, body, design)
    return garment.assembly().spec


def generate_skirt_with_waistband(bottom, waistband, bottom_cut=None, panel_curve=None, n_panels=None,
                                  add_circle_cut=False, cut_place=None, parameter_overrides=None):
    body = BodyParameters(str(source / "assets/bodies/mean_all.yaml"))
    with (source / "assets/design_params/default.yaml").open() as stream:
        design = yaml.safe_load(stream)["design"]
    design["meta"]["bottom"]["v"] = bottom
    design["meta"]["wb"]["v"] = waistband
    if bottom_cut is not None:
        design["skirt"]["bottom_cut"]["v"] = bottom_cut
    if panel_curve is not None:
        design["flare-skirt"]["skirt-many-panels"]["panel_curve"]["v"] = panel_curve
    if n_panels is not None:
        design["flare-skirt"]["skirt-many-panels"]["n_panels"]["v"] = n_panels
    if add_circle_cut:
        design["flare-skirt"]["cut"]["add"]["v"] = True
    if cut_place is not None:
        design["flare-skirt"]["cut"]["place"]["v"] = cut_place
    apply_parameter_overrides(design, parameter_overrides)
    garment = MetaGarment("comparison", body, design)
    return garment.assembly().spec


def generate_upper(upper, overrides=None):
    body = BodyParameters(str(source / "assets/bodies/mean_all.yaml"))
    with (source / "assets/design_params/default.yaml").open() as stream:
        design = yaml.safe_load(stream)["design"]
    design["meta"]["upper"]["v"] = upper
    apply_parameter_overrides(design, overrides)
    garment = MetaGarment(upper, body, design)
    return garment.assembly().spec


def generate_combination(upper, bottom, waistband=None, overrides=None,
                         body_file="mean_all.yaml", body_overrides=None):
    body = BodyParameters(str(source / "assets/bodies" / body_file))
    for key, value in (body_overrides or {}).items():
        body[key] = value
    with (source / "assets/design_params/default.yaml").open() as stream:
        design = yaml.safe_load(stream)["design"]
    design["meta"]["upper"]["v"] = upper
    design["meta"]["bottom"]["v"] = bottom
    design["meta"]["wb"]["v"] = waistband
    apply_parameter_overrides(design, overrides)
    garment = MetaGarment("comparison", body, design)
    return garment.assembly().spec


fixtures = Path(__file__).parent / "Fixtures"
fixtures.mkdir(parents=True, exist_ok=True)
if "--tangent-sensitivity" in sys.argv:
    import numpy as np
    import pygarment as pyg
    from svgpathtools import CubicBezier
    cases = json.loads((fixtures / "tangent-fit-oracles.json").read_text())
    results = []
    for index in (1, 9):
        case = cases[index]
        expected = CubicBezier(*[complex(*p) for p in case["expected"]])
        # Establish that this interpreter reproduces the captured oracle before
        # attributing any difference to a one-ULP perturbation. Otherwise a
        # dependency/platform change could be mistaken for input sensitivity.
        baseline_points = pyg.ops.curve_match_tangents(
            CubicBezier(*[complex(*p) for p in case["source"]]),
            np.array(case["start_tangent"]), np.array(case["end_tangent"]),
            target_len=case["length"])
        baseline = CubicBezier(*[complex(*p) for p in baseline_points])
        baseline_error = max(abs(baseline.point(t) - expected.point(t))
                             for t in np.linspace(0, 1, 101))
        if baseline_error > 1e-8:
            raise RuntimeError(f"Case {index}: baseline no longer reproduces oracle: {baseline_error} cm")
        for control_index in (1, 2):
            for axis in (0, 1):
                for sign in (-1, 1):
                    points = np.array(case["source"], dtype=float)
                    original = points[control_index, axis]
                    points[control_index, axis] = np.nextafter(original, sign * np.inf)
                    curve = CubicBezier(*[complex(*p) for p in points])
                    output = pyg.ops.curve_match_tangents(curve, np.array(case["start_tangent"]),
                        np.array(case["end_tangent"]), target_len=case["length"])
                    fitted = CubicBezier(*[complex(*p) for p in output])
                    error = max(abs(fitted.point(t) - expected.point(t)) for t in np.linspace(0, 1, 101))
                    results.append({"case": index, "control": control_index, "axis": axis,
                                    "baseline_contour_error_cm": float(baseline_error),
                                    "delta": float(points[control_index, axis] - original),
                                    "max_sampled_contour_error_cm": float(error)})
    destination = fixtures / "tangent-upstream-sensitivity.json"
    destination.write_text(json.dumps(results, indent=2, allow_nan=False) + "\n")
    print(destination)
    print("Largest upstream-only perturbation response (cm):", max(r["max_sampled_contour_error_cm"] for r in results))
    raise SystemExit(0)
if "--deep-neck" in sys.argv:
    spec = generate_upper("FittedShirt", {"collar": {"f_collar": "VNeckHalf", "b_collar": "VNeckHalf",
                                                   "fc_depth": 2, "bc_depth": 2}})
    destination = fixtures / "fitted-shirt-deep-neck.json"
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)
    raise SystemExit(0)
if "--tangent-oracles" in sys.argv:
    import pygarment as pyg
    original_match = pyg.ops.curve_match_tangents
    records = []
    def capture_match(curve, target_tan0, target_tan1, target_len=None,
                      return_as_edge=False, verbose=False):
        original_minimize = pyg.ops.minimize
        optimizer_result = {}
        def capture_minimize(*args, **kwargs):
            from scipy.optimize._numdiff import approx_derivative
            initial_value = args[0](args[1], *kwargs.get("args", ()))
            initial_gradient = approx_derivative(args[0], args[1], method="2-point", abs_step=1e-8,
                                                 args=kwargs.get("args", ()))
            trajectory = []
            def capture_iteration(x):
                trajectory.append([float(v) for v in x])
            output = original_minimize(*args, **kwargs, callback=capture_iteration)
            optimizer_result.update(iterations=int(output.nit), objective=float(output.fun),
                                    gradient=[float(v) for v in output.jac],
                                    shift=[float(v) for v in output.x], message=str(output.message),
                                    initial_objective=float(initial_value),
                                    initial_gradient=[float(v) for v in initial_gradient.ravel()],
                                    trajectory=trajectory)
            return output
        pyg.ops.minimize = capture_minimize
        try:
            result = original_match(curve, target_tan0, target_tan1, target_len,
                                    return_as_edge, verbose)
        finally:
            pyg.ops.minimize = original_minimize
        expected = result.as_curve().bpoints() if return_as_edge else [complex(*p) for p in result]
        records.append({"source": [[p.real, p.imag] for p in curve.bpoints()],
                        "start_tangent": [float(v) for v in target_tan0],
                        "end_tangent": [float(v) for v in target_tan1],
                        "length": curve.length() if target_len is None else target_len,
                        "expected": [[p.real, p.imag] for p in expected],
                        "optimizer": optimizer_result})
        return result
    pyg.ops.curve_match_tangents = capture_match
    generate_upper("Shirt", {"sleeve": {"sleeveless": False}})
    generate_upper("FittedShirt", {"collar": {"component": {"style": "Hood2Panels"}}})
    generate_upper("Shirt", {"collar": {"component": {"style": "Hood2Panels"}}})
    destination = fixtures / "tangent-fit-oracles.json"
    destination.write_text(json.dumps(records, indent=2, allow_nan=False) + "\n")
    print(destination)
    raise SystemExit(0)
if "--body-dependencies" in sys.argv:
    body = BodyParameters(str(source / "assets/bodies/mean_all.yaml"))
    cases = []
    for key, value in (("height", 175), ("head_l", 25), ("waist_line", 43),
                       ("hips_line", 22), ("shoulder_w", 42), ("bust_line", 28),
                       ("vert_bust_line", 25), ("hip_inclination", 12),
                       ("shoulder_incl", 0), ("armscye_depth", 19)):
        body[key] = value
        cases.append({"key": key, "value": value, "expected": dict(body.params)})
    destination = fixtures / "body-dependency-edits.json"
    destination.write_text(json.dumps(cases, indent=2, allow_nan=False) + "\n")
    print(destination)
    raise SystemExit(0)
if "--neckline-variants" in sys.argv:
    for upper in ("Shirt", "FittedShirt"):
        for style in ("CircleNeckHalf", "CurvyNeckHalf", "VNeckHalf", "SquareNeckHalf",
                      "TrapezoidNeckHalf", "CircleArcNeckHalf", "Bezier2NeckHalf"):
            spec = generate_upper(upper, {"collar": {
                "f_collar": style, "b_collar": style, "width": -0.2,
                "fc_depth": 0.6, "bc_depth": 0.3, "fc_angle": 75, "bc_angle": 110,
                "f_bezier_x": 0.6, "f_bezier_y": 0.3,
                "b_bezier_x": 0.4, "b_bezier_y": 0.7,
                "f_flip_curve": True, "b_flip_curve": True}})
            destination = fixtures / f"{upper}-neck-varied-{style}.json"
            destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
            print(destination)
    raise SystemExit(0)
if "--asymmetric-components" in sys.argv:
    for upper in ("Shirt", "FittedShirt"):
        for tag in ("left-sleeve", "right-sleeve", "left-band-skirt", "right-band-skirt", "left-strapless"):
            overrides = {"left": {"enable_asym": True}}
            if tag == "left-sleeve":
                overrides["left"]["sleeve"] = {"sleeveless": False, "cuff": {"type": "CuffBand"}}
            elif tag == "right-sleeve":
                overrides["sleeve"] = {"sleeveless": False, "cuff": {"type": "CuffSkirt"}}
            elif tag.endswith("band-skirt"):
                target = overrides["left"] if tag.startswith("left") else overrides
                target["sleeve"] = {"sleeveless": False, "cuff": {"type": "CuffBandSkirt"}}
            else:
                overrides["left"]["shirt"] = {"strapless": True}
            spec = generate_upper(upper, overrides)
            destination = fixtures / f"{upper}-asym-{tag}.json"
            destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
            print(destination)
    raise SystemExit(0)
if "--pencil-shape-variants" in sys.argv:
    for tag, flare, angle, rise in (("narrow-low", 0.8, 20, 0.7),
                                    ("wide-low", 1.2, -15, 0.8),
                                    ("wide-high", 1.4, 20, 1.0)):
        spec = generate_skirt("PencilSkirt", parameter_overrides={"pencil-skirt": {
            "flare": flare, "low_angle": angle, "rise": rise}})
        destination = fixtures / f"pencil-skirt-{tag}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)
if "--pencil-flare" in sys.argv:
    for flare in (0.8, 1.2):
        spec = generate_skirt("PencilSkirt", parameter_overrides={"pencil-skirt": {"flare": flare}})
        destination = fixtures / f"pencil-skirt-flare-{flare}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)
if "--undarted-back" in sys.argv:
    changes = {"waist": 94.0, "waist_back_width": 49.0}
    body = BodyParameters(str(source / "assets/bodies/mean_all.yaml"))
    for key, value in changes.items():
        body[key] = value
    patterns = {}
    for tag, bottom, belt, overrides in (
        ("torso", None, None, {}),
        ("strapless", None, None, {"shirt": {"strapless": True}}),
        ("skirt", "Skirt2", None, {}),
        ("belt", None, "StraightWB", {}),
        ("sleeved", None, None, {"sleeve": {"sleeveless": False}}),
    ):
        patterns[tag] = generate_combination("FittedShirt", bottom, belt, overrides,
                                             body_overrides=changes)
    destination = fixtures / "fitted-shirt-undarted-back.json"
    destination.write_text(json.dumps({"body": body.params, "patterns": patterns},
                                      indent=2, allow_nan=False) + "\n")
    print(destination)
    raise SystemExit(0)
if "--siggraph-shape" in sys.argv:
    import pygarment as pyg

    svg_file = source / "assets/img/siggraph_logo_thick_connection.svg"
    if not svg_file.is_file():
        raise SystemExit(f"Missing pinned SIGGRAPH SVG: {svg_file}")
    reference_body = BodyParameters(str(source / "assets/bodies/mean_all.yaml"))
    reference_depth = 0.7 * (reference_body["hips"] / 4 - reference_body["bust_points"] / 2)
    reference_height = reference_depth * 1.5
    left, right = pyg.EdgeSeqFactory.halfs_from_svg(str(svg_file), target_height=reference_height)

    def records(sequences):
        return [[{
            "start": [float(value) / reference_height for value in edge.start],
            "end": [float(value) / reference_height for value in edge.end],
            "controls": [[float(value) for value in point]
                         for point in edge.control_points],
        } for edge in sequence] for sequence in sequences]

    shape = {
        "source_commit": "d449629979028123a5c4dc9e732a2ec19b7fce31",
        "target_height_cm": 1,
        "normalization_reference_height_cm": reference_height,
        "left": records(left),
        "right": records(right),
    }
    destination = Path(__file__).parents[2] / "TrailorAss/Resources/GarmentCodeSiggraphShape.json"
    destination.write_text(json.dumps(shape, indent=2, allow_nan=False) + "\n")
    print(destination)
    raise SystemExit(0)

if "--siggraph-variants" in sys.argv:
    for tag, hips, bust_points in (("wide", 109.0, 18.0),
                                   ("narrow", 96.0, 16.0)):
        body = BodyParameters(str(source / "assets/bodies/mean_all.yaml"))
        body["hips"] = hips
        body["bust_points"] = bust_points
        with (source / "assets/design_params/default.yaml").open() as stream:
            design = yaml.safe_load(stream)["design"]
        design["meta"]["bottom"]["v"] = "PencilSkirt"
        design["pencil-skirt"]["style_side_cut"]["v"] = "SIGGRAPH_logo"
        spec = MetaGarment("PencilSkirt", body, design).assembly().spec
        destination = fixtures / f"pencil-skirt-SIGGRAPH_logo-{tag}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    for tag, slits in (("left-slit", {"left_slit": 0.1}),
                       ("deep-left-slit", {"left_slit": 0.5}),
                       ("skip-left-slit", {"left_slit": 0.8}),
                       ("all-slits", {"left_slit": 0.1, "right_slit": 0.1,
                                      "front_slit": 0.1, "back_slit": 0.1})):
        spec = generate_skirt("PencilSkirt", parameter_overrides={
            "pencil-skirt": {"style_side_cut": "SIGGRAPH_logo", **slits}
        })
        destination = fixtures / f"pencil-skirt-SIGGRAPH_logo-{tag}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)

if "--sun-slit-variants" in sys.argv:
    for tag, slits in (("left-slit", {"left_slit": 0.1}),
                       ("deep-left-slit", {"left_slit": 0.5}),
                       ("boundary-left-slit", {"left_slit": 0.6}),
                       ("skip-left-slit", {"left_slit": 0.8}),
                       ("all-slits", {"left_slit": 0.1, "right_slit": 0.1,
                                      "front_slit": 0.1, "back_slit": 0.1})):
        spec = generate_skirt("PencilSkirt", parameter_overrides={
            "pencil-skirt": {"style_side_cut": "Sun", **slits}
        })
        destination = fixtures / f"pencil-skirt-Sun-{tag}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)

if "--levels-side-cuts" in sys.argv:
    for style in ("Sun", "SIGGRAPH_logo"):
        spec = generate_skirt("SkirtLevels", parameter_overrides={
            "levels-skirt": {"base": "PencilSkirt"},
            "pencil-skirt": {"style_side_cut": style},
        })
        destination = fixtures / f"skirt-levels-PencilSkirt-{style}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)

if "--godet-side-cuts" in sys.argv:
    for style in ("Sun", "SIGGRAPH_logo"):
        spec = generate_skirt("GodetSkirt", parameter_overrides={
            "godet-skirt": {"base": "PencilSkirt"},
            "pencil-skirt": {"style_side_cut": style},
        })
        destination = fixtures / f"godet-skirt-PencilSkirt-{style}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)

if "--composition-variants" in sys.argv:
    variants = (
        ("Shirt", "PencilSkirt", "StraightWB", "sun", {
            "pencil-skirt": {"style_side_cut": "Sun"}}),
        ("FittedShirt", "SkirtLevels", "FittedWB", "logo", {
            "levels-skirt": {"base": "PencilSkirt"},
            "pencil-skirt": {"style_side_cut": "SIGGRAPH_logo"}}),
        ("Shirt", "Pants", None, "asymmetric", {
            "left": {"enable_asym": True}}),
        ("FittedShirt", "Skirt2", None, "strapless", {
            "shirt": {"strapless": True}}),
    )
    for upper, bottom, waistband, tag, overrides in variants:
        spec = generate_combination(upper, bottom, waistband, overrides)
        destination = fixtures / f"combo-{upper}-{bottom}-{waistband or 'None'}-{tag}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)

if "--upper-belt" in sys.argv:
    for upper, waistband, tag, overrides in (
        ("Shirt", "StraightWB", "default", {}),
        ("FittedShirt", "FittedWB", "default", {}),
        ("Shirt", "FittedWB", "asymmetric", {"left": {"enable_asym": True}}),
        ("FittedShirt", "StraightWB", "strapless", {"shirt": {"strapless": True}}),
    ):
        spec = generate_combination(upper, None, waistband, overrides)
        suffix = "" if tag == "default" else f"-{tag}"
        destination = fixtures / f"combo-{upper}-None-{waistband}{suffix}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)

if "--meta-grid" in sys.argv or "--meta-grid-female" in sys.argv:
    female = "--meta-grid-female" in sys.argv
    body_file = "mean_female.yaml" if female else "mean_all.yaml"
    uppers = (None, "Shirt", "FittedShirt")
    waistbands = (None, "StraightWB", "FittedWB")
    bottoms = (None, "SkirtCircle", "AsymmSkirtCircle", "GodetSkirt",
               "Pants", "Skirt2", "SkirtManyPanels", "PencilSkirt", "SkirtLevels")
    records = {}
    skipped = []
    for upper in uppers:
        for waistband in waistbands:
            for bottom in bottoms:
                if upper is None and waistband is None and bottom is None:
                    continue
                key = "|".join(item or "None" for item in (upper, waistband, bottom))
                try:
                    records[key] = generate_combination(upper, bottom, waistband,
                                                        body_file=body_file)
                except BaseException as error:
                    skipped.append((key, type(error).__name__, str(error)))
    destination = fixtures / ("meta-grid-female.json" if female else "meta-grid-defaults.json")
    payload = {"body": BodyParameters(str(source / "assets/bodies" / body_file)).params,
               "patterns": records} if female else records
    destination.write_text(json.dumps(payload, separators=(",", ":"), allow_nan=False) + "\n")
    print(f"{destination}: {len(records)} official patterns")
    for key, kind, reason in skipped:
        print(f"SKIPPED {key}: {kind}: {reason}")
    raise SystemExit(0)

if "--upper-variants" in sys.argv:
    # This mode keeps existing fixture files untouched while extending the
    # matrix of official upper-garment parameter cases.
    variants = (
        ("Shirt", "shirt-sleeved-varied", {"sleeve": {
            "sleeveless": False, "length": 0.75, "end_width": 1.25,
            "sleeve_angle": 40, "opening_dir_mix": 0.3}}),
        ("FittedShirt", "fitted-shirt-sleeved-varied", {"sleeve": {
            "sleeveless": False, "length": 0.6, "end_width": 1.3}}),
        ("Shirt", "shirt-sleeved-CuffBand", {"sleeve": {
            "sleeveless": False, "cuff": {"type": "CuffBand"}}}),
        ("Shirt", "shirt-sleeved-CuffSkirt", {"sleeve": {
            "sleeveless": False, "cuff": {"type": "CuffSkirt"}}}),
        ("Shirt", "shirt-sleeved-CuffBandSkirt", {"sleeve": {
            "sleeveless": False, "cuff": {"type": "CuffBandSkirt"}}}),
        ("Shirt", "shirt-sleeved-connect-ruffle", {"sleeve": {
            "sleeveless": False, "connect_ruffle": 1.4}}),
        ("Shirt", "shirt-sleeved-standing", {"sleeve": {
            "sleeveless": False, "standing_shoulder": True,
            "sleeve_angle": 50}}),
        ("Shirt", "shirt-collar-Hood2Panels-varied", {"collar": {
            "component": {"style": "Hood2Panels", "hood_length": 1.25,
                          "hood_depth": 1.3}}}),
        ("Shirt", "shirt-collar-SimpleLapel-back-VNeckHalf", {"collar": {
            "component": {"style": "SimpleLapel"}, "b_collar": "VNeckHalf"}}),
        ("FittedShirt", "fitted-shirt-collar-SimpleLapel-back-VNeckHalf", {"collar": {
            "component": {"style": "SimpleLapel"}, "b_collar": "VNeckHalf"}}),
    )
    for upper, filename, overrides in variants:
        spec = generate_upper(upper, overrides)
        destination = fixtures / f"{filename}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)
    raise SystemExit(0)

for program, filename in (("SkirtCircle", "skirt-circle.json"),
                          ("AsymmSkirtCircle", "skirt-asymmetric-circle.json"),
                          ("Skirt2", "skirt-two-panel.json"),
                          ("SkirtManyPanels", "skirt-many-panels.json"),
                          ("Pants", "pants.json"),
                          ("StraightWB", "waistband-straight.json"),
                          ("FittedWB", "waistband-fitted.json")):
    spec = generate_skirt(program)
    destination = fixtures / filename
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

# Broaden the oracle set beyond the initially ported skirt subset. These
# fixtures are intentionally upstream-authored; Swift implementations must
# match them before a style is marked supported in the app.
for program, filename in (("GodetSkirt", "godet-skirt.json"),
                          ("PencilSkirt", "pencil-skirt.json"),
                          ("SkirtLevels", "skirt-levels.json")):
    spec = generate_skirt(program)
    destination = fixtures / filename
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

for program, overrides, filename in (
    ("Pants", {"pants": {"rise": 0.75, "length": 0.55, "width": 1.2, "flare": 1.1}}, "pants-varied.json"),
    ("GodetSkirt", {"godet-skirt": {"num_inserts": 8, "insert_w": 20, "insert_depth": 25}}, "godet-skirt-varied.json"),
    ("SkirtLevels", {"levels-skirt": {"num_levels": 3, "level_ruffle": 1.3}}, "skirt-levels-varied.json"),
    ("SkirtLevels", {"levels-skirt": {"rise": 0.75}}, "skirt-levels-rise.json"),
):
    spec = generate_skirt(program, parameter_overrides=overrides)
    destination = fixtures / filename
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

for base_style in ("Skirt2", "PencilSkirt", "SkirtCircle", "AsymmSkirtCircle"):
    for level_style in ("Skirt2", "SkirtCircle", "AsymmSkirtCircle"):
        if base_style == "PencilSkirt" and level_style == "Skirt2":
            continue  # covered by skirt-levels.json and skirt-levels-varied.json
        spec = generate_skirt("SkirtLevels", parameter_overrides={
            "levels-skirt": {"base": base_style, "level": level_style}
        })
        destination = fixtures / f"skirt-levels-{base_style}-{level_style}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)

spec = generate_skirt("GodetSkirt", parameter_overrides={"godet-skirt": {"base": "Skirt2"}})
destination = fixtures / "godet-skirt-Skirt2.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

for cuff_type in ("CuffBand", "CuffSkirt", "CuffBandSkirt"):
    spec = generate_skirt("Pants", parameter_overrides={"pants": {"cuff": {"type": cuff_type}}})
    destination = fixtures / f"pants-{cuff_type}.json"
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

for upper, overrides, filename in (
    ("Shirt", None, "shirt.json"),
    ("Shirt", {"shirt": {"width": 1.2, "length": 1.5, "flare": 1.15}}, "shirt-varied.json"),
    ("FittedShirt", None, "fitted-shirt.json"),
):
    spec = generate_upper(upper, overrides)
    destination = fixtures / filename
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

for neckline in ("VNeckHalf", "SquareNeckHalf", "TrapezoidNeckHalf",
                 "CurvyNeckHalf", "CircleArcNeckHalf", "Bezier2NeckHalf"):
    for upper, prefix in (("Shirt", "shirt"), ("FittedShirt", "fitted-shirt")):
        spec = generate_upper(upper, {"collar": {"f_collar": neckline, "b_collar": neckline}})
        destination = fixtures / f"{prefix}-neckline-{neckline}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)

for armhole in ("ArmholeSquare", "ArmholeAngle"):
    for upper, prefix in (("Shirt", "shirt"), ("FittedShirt", "fitted-shirt")):
        spec = generate_upper(upper, {"sleeve": {"armhole_shape": armhole}})
        destination = fixtures / f"{prefix}-armhole-{armhole}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)

for upper, prefix in (("Shirt", "shirt"), ("FittedShirt", "fitted-shirt")):
    spec = generate_upper(upper, {"sleeve": {"sleeveless": False}})
    destination = fixtures / f"{prefix}-sleeved.json"
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

for collar_style in ("Turtle", "SimpleLapel", "Hood2Panels"):
    for upper, prefix in (("Shirt", "shirt"), ("FittedShirt", "fitted-shirt")):
        spec = generate_upper(upper, {"collar": {"component": {"style": collar_style}}})
        destination = fixtures / f"{prefix}-collar-{collar_style}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)

for upper, prefix in (("Shirt", "shirt"), ("FittedShirt", "fitted-shirt")):
    for overrides, variant in (
        ({"collar": {"component": {"style": "SimpleLapel", "lapel_standing": True}}},
         "SimpleLapel-standing"),
        ({"collar": {"component": {"style": "SimpleLapel"}, "f_collar": "VNeckHalf"}},
         "SimpleLapel-VNeckHalf"),
    ):
        spec = generate_upper(upper, overrides)
        destination = fixtures / f"{prefix}-collar-{variant}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)

spec = generate_upper("FittedShirt", {"shirt": {"strapless": True}})
destination = fixtures / "fitted-shirt-strapless.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

spec = generate_upper("Shirt", {"left": {"enable_asym": True}})
destination = fixtures / "shirt-asymmetric.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

spec = generate_upper("FittedShirt", {"left": {"enable_asym": True}})
destination = fixtures / "fitted-shirt-asymmetric.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

for upper, bottom, waistband in (("Shirt", "Skirt2", None),
                                  ("FittedShirt", "PencilSkirt", None),
                                  ("Shirt", "Skirt2", "StraightWB"),
                                  ("Shirt", "Skirt2", "FittedWB"),
                                  ("FittedShirt", "PencilSkirt", "StraightWB"),
                                  ("Shirt", "SkirtCircle", None),
                                  ("Shirt", "AsymmSkirtCircle", "FittedWB"),
                                  ("Shirt", "GodetSkirt", None),
                                  ("Shirt", "SkirtLevels", None),
                                  ("Shirt", "SkirtManyPanels", None),
                                  ("Shirt", "SkirtManyPanels", "StraightWB"),
                                  ("Shirt", "Pants", None),
                                  ("FittedShirt", "Pants", "FittedWB"),
                                  ("FittedShirt", "SkirtLevels", None)):
    spec = generate_combination(upper, bottom, waistband)
    filename = "-".join(part for part in (upper, bottom, waistband) if part) + ".json"
    destination = fixtures / filename
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

spec = generate_skirt("SkirtManyPanels", panel_curve=0.25)
destination = fixtures / "skirt-many-panels-curved.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

for program, filename in (("SkirtCircle", "skirt-circle-cut.json"),
                          ("AsymmSkirtCircle", "skirt-asymmetric-circle-cut.json")):
    spec = generate_skirt(program, add_circle_cut=True)
    destination = fixtures / filename
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

spec = generate_skirt("Skirt2", bottom_cut=0.5)
destination = fixtures / "skirt-two-panel-cut.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

for slit, ratio in (("left_slit", 0.25), ("right_slit", 0.25),
                    ("front_slit", 0.25), ("back_slit", 0.25)):
    spec = generate_skirt("PencilSkirt", parameter_overrides={
        "pencil-skirt": {slit: ratio}
    })
    destination = fixtures / f"pencil-skirt-{slit}.json"
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

spec = generate_skirt("PencilSkirt", parameter_overrides={
    "pencil-skirt": {"left_slit": 0.2, "right_slit": 0.2,
                     "front_slit": 0.2, "back_slit": 0.2}
})
destination = fixtures / "pencil-skirt-all-slits.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

for style_cut in ("Sun", "SIGGRAPH_logo"):
    if style_cut == "SIGGRAPH_logo" and not (source / "assets/img/siggraph_logo_thick_connection.svg").is_file():
        print("SKIP SIGGRAPH_logo: the upstream sparse checkout is missing its referenced SVG asset")
        continue
    spec = generate_skirt("PencilSkirt", parameter_overrides={
        "pencil-skirt": {"style_side_cut": style_cut}
    })
    destination = fixtures / f"pencil-skirt-{style_cut}.json"
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

for bottom in ("SkirtCircle", "AsymmSkirtCircle", "Skirt2", "SkirtManyPanels"):
    for waistband in ("StraightWB", "FittedWB"):
        filename = f"{bottom}-{waistband}.json"
        spec = generate_skirt_with_waistband(bottom, waistband)
        destination = fixtures / filename
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)

for waistband in ("StraightWB", "FittedWB"):
    spec = generate_skirt_with_waistband("SkirtLevels", waistband)
    destination = fixtures / f"SkirtLevels-{waistband}.json"
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

for base_style in ("Skirt2", "SkirtCircle", "AsymmSkirtCircle"):
    for waistband in ("StraightWB", "FittedWB"):
        spec = generate_skirt_with_waistband("SkirtLevels", waistband,
            parameter_overrides={"levels-skirt": {"base": base_style}})
        destination = fixtures / f"SkirtLevels-{base_style}-{waistband}.json"
        destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
        print(destination)

for bottom in ("PencilSkirt", "GodetSkirt"):
    base_styles = ("PencilSkirt", "Skirt2") if bottom == "GodetSkirt" else (None,)
    for base_style in base_styles:
        for waistband in ("StraightWB", "FittedWB"):
            overrides = {"godet-skirt": {"base": base_style}} if base_style else None
            spec = generate_skirt_with_waistband(bottom, waistband,
                                                  parameter_overrides=overrides)
            suffix = f"-{base_style}" if base_style else ""
            destination = fixtures / f"{bottom}{suffix}-{waistband}.json"
            destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
            print(destination)

spec = generate_skirt_with_waistband("Skirt2", "StraightWB", bottom_cut=0.5)
destination = fixtures / "Skirt2-StraightWB-cut.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

spec = generate_skirt_with_waistband("SkirtManyPanels", "FittedWB", panel_curve=0.25)
destination = fixtures / "SkirtManyPanels-FittedWB-curved.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

spec = generate_skirt_with_waistband("SkirtManyPanels", "StraightWB", n_panels=6)
destination = fixtures / "SkirtManyPanels-6-StraightWB.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)

for bottom, waistband in (("SkirtCircle", "StraightWB"), ("AsymmSkirtCircle", "FittedWB")):
    spec = generate_skirt_with_waistband(bottom, waistband, add_circle_cut=True)
    destination = fixtures / f"{bottom}-{waistband}-cut.json"
    destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
    print(destination)

spec = generate_skirt_with_waistband("SkirtCircle", "FittedWB", add_circle_cut=True, cut_place=0.5)
destination = fixtures / "SkirtCircle-FittedWB-front-cut.json"
destination.write_text(json.dumps(spec, indent=2, allow_nan=False) + "\n")
print(destination)
