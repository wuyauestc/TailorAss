#!/usr/bin/env python3
"""Render a private offline report from an already terminal JointResult run.

No solver, subprocess, network request, or state promotion is performed. A run
root needs its terminal summary.json; a single case directory needs its terminal
case-summary.json. Incomplete runs are refused. Existing output is not replaced.
"""
import argparse
import datetime
import hashlib
import html
import importlib.util
import json
import math
from pathlib import Path
import re
from zoneinfo import ZoneInfo


HERE = Path(__file__).resolve().parent
TERMINAL_REASONS = {"requestedPrefixEnded", "stepRejected", "stepThrew",
                    "physicalAttemptBudget", "validationRejected", "stableValidated"}
ARTIFACTS = ("validated-output.json", "validated-output.obj",
             "validated-proof.json", "validated-metrics.json",
             "validated-seam-group-ids.json")


def check(condition, message):
    if not condition:
        raise ValueError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


class Inputs:
    def __init__(self, root):
        self.root, self.records, self.terminal_results = root, {}, {}

    def raw(self, path):
        path = path.resolve()
        check(path.is_relative_to(self.root), f"Input escapes run root: {path}")
        raw = path.read_bytes()
        self.records[str(path.relative_to(self.root))] = {
            "sha256": digest(raw), "bytes": len(raw)}
        return raw

    def json(self, path):
        return json.loads(self.raw(path), parse_constant=lambda x: (_ for _ in ()).throw(
            ValueError(f"Non-finite JSON value {x} in {path}")))

    def unchanged(self):
        return all(digest((self.root / name).read_bytes()) == record["sha256"]
                   for name, record in self.records.items())


def vector(point):
    check(isinstance(point, dict), "Vertex must have x/y/z fields")
    values = tuple(point[k] for k in ("x", "y", "z"))
    check(all(type(x) in (int, float) and math.isfinite(x) for x in values),
          "Non-finite or non-numeric vertex")
    return values


def mesh(points, indices, name):
    check(isinstance(points, list) and points, f"Missing {name} vertices")
    for p in points:
        vector(p)
    check(isinstance(indices, list) and indices and len(indices) % 3 == 0,
          f"Invalid {name} triangles")
    check(all(type(i) is int and 0 <= i < len(points) for i in indices),
          f"Out-of-bounds {name} triangle index")


def distance(a, b):
    return math.dist(vector(a), vector(b))


def attached(attachment, points):
    ids, weights = attachment["vertexIDs"], attachment["weights"]
    check(ids and len(ids) == len(weights), "Invalid barycentric seam attachment")
    check(all(type(i) is int and 0 <= i < len(points) for i in ids),
          "Out-of-bounds seam attachment")
    check(all(type(w) in (int, float) and math.isfinite(w) for w in weights)
          and abs(sum(weights) - 1) < 1e-10, "Invalid seam weights")
    return {k: sum(points[i][k] * w for i, w in zip(ids, weights))
            for k in ("x", "y", "z")}


def measure(source, plan, points):
    """Display-only Float64 measurements; no collision or acceptance test."""
    reference = source["referencePositions"]
    mapping = source["referenceToSimulation"]
    check(len(mapping) == len(reference) and len(set(mapping)) == len(points)
          and set(mapping) == set(range(len(points))), "Incomplete source mapping")
    triangles = source["referenceTriangles"]
    edges = set()
    area = 0.0
    for start in range(0, len(triangles), 3):
        ids = triangles[start:start + 3]
        a, b, c = (vector(reference[i]) for i in ids)
        u, v = ([b[k] - a[k] for k in range(3)], [c[k] - a[k] for k in range(3)])
        area += math.hypot(u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2],
                           u[0]*v[1]-u[1]*v[0]) / 2
        edges.update(tuple(sorted((ids[k], ids[(k+1) % 3]))) for k in range(3))
    strains = []
    for a, b in edges:
        rest = distance(reference[a], reference[b])
        check(rest > 0, "Zero source edge")
        strains.append(abs(distance(points[mapping[a]], points[mapping[b]]) / rest - 1))
    gaps = [distance(attached(row["a"], points), attached(row["b"], points))
            for row in plan["constraints"]]
    return {"sourceAreaSquareMeters": area, "fabricMassKg": sum(source["massesKg"]),
            "sourceEdges": len(edges), "sewingConstraints": len(gaps),
            "maximumSourceEdgeRelativeChange": max(strains, default=0),
            "gapMeasurementScope": "anchorConstraintsOnly",
            "maximumActualSeamGapMeters": max(gaps, default=0),
            "rmsActualSeamGapMeters": math.sqrt(sum(x*x for x in gaps) / len(gaps)) if gaps else 0}


def groups(source):
    seen_vertices, seen_faces, names = set(), set(), set()
    for group in source["panelGroups"]:
        name, vertices, faces = group["panelID"], group["vertexIDs"], group["triangleIDs"]
        check(name and name not in names and vertices and faces, "Invalid panel membership")
        check(len(set(vertices)) == len(vertices) and not seen_vertices.intersection(vertices),
              "Overlapping panel vertices")
        check(len(set(faces)) == len(faces) and not seen_faces.intersection(faces),
              "Overlapping panel faces")
        check(all(type(i) is int and 0 <= i < len(source["positions"]) for i in vertices),
              "Out-of-bounds panel vertex")
        for face in faces:
            check(type(face) is int and 0 <= face < len(source["triangleIndices"]) // 3,
                  "Out-of-bounds panel face")
            check(set(source["triangleIndices"][3*face:3*face+3]) <= set(vertices),
                  "Panel face crosses membership")
        names.add(name)
        seen_vertices.update(vertices)
        seen_faces.update(faces)
    check(len(seen_vertices) == len(source["positions"])
          and len(seen_faces) * 3 == len(source["triangleIndices"]), "Dropped source panel data")


def source_svg(paper):
    """Render original paper curves directly as SVG; never substitute cloth faces."""
    mode = paper.get("properties", {}).get("curvature_coords", "relative")
    check(mode in ("relative", "absolute"), "Unknown paper curvature coordinates")
    relative = mode == "relative"
    cards = []
    for name, panel in paper["pattern"]["panels"].items():
        vertices, bounds, paths = panel["vertices"], [], []
        for edge in panel["edges"]:
            a, b = (tuple(vertices[i]) for i in edge["endpoints"])
            check(len(a) == len(b) == 2 and all(math.isfinite(v) for v in (*a, *b)),
                  "Invalid original paper edge")
            bounds.extend((a, b))
            def xy(point):
                return ' '.join(format(v, '.17g') for v in point)
            command = 'M ' + xy(a)
            curve = edge.get("curvature")
            if not curve:
                command += ' L ' + xy(b)
            elif curve["type"] in ("quadratic", "cubic"):
                controls = curve["params"]
                check(len(controls) == (1 if curve["type"] == "quadratic" else 2),
                      "Invalid original Bezier controls")
                chord = (b[0]-a[0], b[1]-a[1])
                points = [(a[0]+chord[0]*p[0]-chord[1]*p[1],
                           a[1]+chord[1]*p[0]+chord[0]*p[1]) if relative else tuple(p)
                          for p in controls]
                check(all(len(p) == 2 and all(math.isfinite(v) for v in p) for p in points),
                      "Non-finite original Bezier control")
                bounds.extend(points)  # Beziers are contained in their control hull.
                command += (' Q ' if len(points) == 1 else ' C ') + ' '.join(xy(p) for p in points+[b])
            elif curve["type"] == "circle":
                radius, large, sweep = curve["params"]
                check(math.isfinite(radius) and radius > 0 and large in (0, 1) and sweep in (0, 1),
                      "Invalid original circular arc")
                dx, dy = b[0]-a[0], b[1]-a[1]
                length = math.hypot(dx, dy)
                check(length > 0, "Zero-chord paper arc")
                corrected = max(radius, length/2)
                height = math.sqrt(max(0, corrected*corrected-length*length/4))
                sign = -1 if large == sweep else 1
                center = ((a[0]+b[0])/2-dy/length*height*sign,
                          (a[1]+b[1])/2+dx/length*height*sign)
                angle = math.atan2(a[1]-center[1], a[0]-center[0])
                end = math.atan2(b[1]-center[1], b[0]-center[0])
                delta = (end-angle) % (2*math.pi) if sweep else -((angle-end) % (2*math.pi))
                # At an exact diameter either large-arc flag describes the same sweep.
                for k in range(4):
                    test = k*math.pi/2
                    distance_on_arc = (test-angle) % (2*math.pi) if sweep else (angle-test) % (2*math.pi)
                    if distance_on_arc <= abs(delta):
                        bounds.append((center[0]+corrected*math.cos(test), center[1]+corrected*math.sin(test)))
                command += ' A ' + xy((radius, radius)) + f' 0 {int(large)} {int(sweep)} ' + xy(b)
            else:
                raise ValueError("Unsupported original paper curvature: " + str(curve["type"]))
            paths.append('<path d="' + command + '"/>')
        low = [min(p[k] for p in bounds) for k in (0, 1)]
        high = [max(p[k] for p in bounds) for k in (0, 1)]
        margin = max(high[0]-low[0], high[1]-low[1], 1e-12)*.06
        viewbox = f'{low[0]-margin:.17g} {-high[1]-margin:.17g} {high[0]-low[0]+2*margin:.17g} {high[1]-low[1]+2*margin:.17g}'
        cards.append('<figure><svg role="img" aria-label="' + html.escape(name, quote=True)
                     + ' 原始纸样曲线" viewBox="' + viewbox + '"><g transform="scale(1 -1)">'
                     + ''.join(paths) + '</g></svg><figcaption>' + html.escape(name)
                     + f' · {len(panel["edges"])} 条原始边</figcaption></figure>')
    return ''.join(cards)


def seam_paths(plan, points):
    sewn = {(anchor[side]["edge"]["panelID"], anchor[side]["edge"]["edgeIndex"])
            for anchor in plan["anchors"] for side in ("a", "b")}
    paths = []
    for boundary in plan["allBoundaryPaths"]:
        edge = boundary["edge"]
        if (edge["panelID"], edge["edgeIndex"]) not in sewn:
            continue
        segments = boundary["segments"]
        if not segments:
            continue
        path = [segments[0]["vertexIDs"][0]] + [s["vertexIDs"][1] for s in segments]
        check(all(type(i) is int and 0 <= i < len(points) for i in path), "Invalid seam path")
        paths.append(path)
    return paths


def obj_matches(raw, output):
    """Read the complete export: cloth groups followed by the offset mannequin."""
    vertices, faces = [], []
    for line in raw.decode("utf-8").splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            check(len(parts) == 4, "Invalid OBJ vertex")
            vertices.append(tuple(map(float, parts[1:])))
        elif parts[0] == "f":
            check(len(parts) == 4, "Non-triangle OBJ face")
            faces.append(tuple(int(p.split('/')[0]) - 1 for p in parts[1:]))
    cloth_count = len(output["positions"])
    check(vertices == [vector(p) for p in output["positions"] + output["mannequinPositions"]],
          "OBJ cloth/mannequin vertices differ from output")
    expected = [tuple(output["triangleIndices"][i:i+3])
                for i in range(0, len(output["triangleIndices"]), 3)]
    expected += [tuple(cloth_count + j for j in output["mannequinTriangleIndices"][i:i+3])
                 for i in range(0, len(output["mannequinTriangleIndices"]), 3)]
    check(sorted(faces) == sorted(expected), "OBJ does not contain every cloth/mannequin face")


def acceptance(inputs, directory, summary, source, final):
    """Read the saved R acceptance receipt; never create or re-run acceptance."""
    reasons = []
    if summary["resultAccepted"] is not True:
        return None, ["本次 R 未返回正式验收结果。"]
    try:
        check(inputs.terminal_results.get(directory.name) is not False,
              "Terminal wrapper reports this case unaccepted")
        check(summary.get("outputProduced") is True and summary["stopReason"] == "stableValidated",
              "Accepted summary lacks stableValidated/outputProduced")
        check(all((directory / name).is_file() for name in ARTIFACTS), "Missing validated artifact")
        output = inputs.json(directory / ARTIFACTS[0])
        proof = inputs.json(directory / "validated-proof.json")
        metrics = inputs.json(directory / "validated-metrics.json")
        seam_ids = inputs.json(directory / "validated-seam-group-ids.json")
        mesh(output["positions"], output["triangleIndices"], "validated cloth")
        mesh(output["mannequinPositions"], output["mannequinTriangleIndices"], "validated body")
        check(output["positions"] == final["positions"]
              and output["triangleIndices"] == source["triangleIndices"]
              and output["mannequinPositions"] == source["bodyPositions"]
              and output["mannequinTriangleIndices"] == source["bodyTriangleIndices"],
              "Validated mesh differs from terminal source/state")
        check(output["diagnostics"].get("converged") is True, "Output is not converged")
        check(proof["sourceSHA256"] == source["sourceSHA256"] == summary["sourceSHA256"]
              and proof["bodyGeometrySHA256"] == summary["bodyGeometrySHA256"]
              == source["bodyClearanceProof"]["bodyGeometrySHA256"]
              and proof["linearizationSourceIdentity"] == source["linearizationSourceIdentity"]
              == summary["linearizationSourceIdentity"], "Foreign validated provenance")
        check(len(proof["frames"]) == 24 and proof["frames"][-1]["step"] == final["completedSteps"]
              and metrics["completedSteps"] == final["completedSteps"]
              and metrics["verifiedQuietFrames"] == 24, "Incomplete stable validation window")
        check(type(seam_ids) is list and len(seam_ids) == len(output["seamPaths"]),
              "Invalid validated seam groups")
        check(output.get("panelGroups") == source["panelGroups"], "Changed validated panel membership")
        obj_matches(inputs.raw(directory / "validated-output.obj"), output)
        return {"output": output, "proof": proof, "metrics": metrics}, reasons
    except (ValueError, KeyError, TypeError, IndexError, UnicodeError) as error:
        return None, ["保存的验收产物不完整或不一致：" + str(error)]


def paper_style_label(paper, fallback):
    names = {"StraightWB": "直条腰头", "FittedWB": "贴体弧形腰头",
             "Shirt": "宽松上衣", "FittedShirt": "合体上衣", "Pants": "裤装",
             "SkirtCircle": "圆裙", "AsymmSkirtCircle": "不对称圆裙",
             "Skirt2": "双片裙", "SkirtManyPanels": "多片拼接裙",
             "PencilSkirt": "铅笔裙", "GodetSkirt": "三角插片裙", "SkirtLevels": "层叠裙"}
    meta = paper.get("parameters", {}).get("design", {}).get("meta", {})
    selected = [meta.get(key, {}).get("v") for key in ("upper", "wb", "bottom")]
    labels = [names[value] for value in selected if isinstance(value, str) and value in names]
    return "＋".join(labels) or fallback


def case_data(inputs, directory):
    summary = inputs.json(directory / "case-summary.json")
    check(summary.get("mode") == "simulate" and summary.get("stopReason") in TERMINAL_REASONS,
          f"Not a terminal simulation case: {directory}")
    check(type(summary.get("resultAccepted")) is bool, "Missing actual R resultAccepted")
    source = inputs.json(directory / "complete-initial-input.json")
    paper = inputs.json(directory / "complete-paper-source.json")
    plan = inputs.json(directory / "complete-sewing-plan.json")
    initial = inputs.json(directory / "initial-state.json")
    final = inputs.json(directory / "last-accepted-state.json")
    settings = inputs.json(directory / "numerical-settings.json")
    mesh(source["positions"], source["triangleIndices"], "initial cloth")
    mesh(source["referencePositions"], source["referenceTriangles"], "reference cloth")
    mesh(source["bodyPositions"], source["bodyTriangleIndices"], "body")
    mesh(final["positions"], source["triangleIndices"], "last accepted cloth")
    check(initial["positions"] == source["positions"] and initial["completedSteps"] == 0,
          "Initial state differs from source")
    check(len(final["positions"]) == len(initial["positions"])
          and final["completedSteps"] == summary["actualCompletedSteps"], "Terminal state mismatch")
    check(source["sourceSHA256"] == plan["sourceSHA256"] == summary["sourceSHA256"],
          "Source/plan/summary identity mismatch")
    check(source["bodyClearanceProof"]["bodyGeometrySHA256"] == summary["bodyGeometrySHA256"],
          "Body identity mismatch")
    check(source["linearizationSourceIdentity"] == summary["linearizationSourceIdentity"],
          "Linearization instance mismatch")
    groups(source)
    check(set(paper["pattern"]["panels"]) == {g["panelID"] for g in source["panelGroups"]},
          "Paper/source panel set mismatch")
    check(len(source["massesKg"]) == len(initial["positions"])
          and all(math.isfinite(m) and m > 0 for m in source["massesKg"]), "Invalid mass array")
    check(len(source["pinMask"]) == len(initial["positions"]), "Invalid pin array")
    report = None
    if final["completedSteps"]:
        frame = inputs.json(directory / "last-accepted-frame.json")
        check(frame["accepted"] == final and frame["report"]["accepted"] is True
              and frame["report"]["attemptedStep"] == final["completedSteps"],
              "Last accepted report differs from actual saved state")
        report = frame["report"]
    accepted, warnings = acceptance(inputs, directory, summary, source, final)
    # Historical R outputs measured tacks only. Do not present their saved
    # numerical acceptance as a new continuous-boundary closure certificate.
    continuous = (accepted["proof"]["frames"][-1].get("sewing", {}).get("continuousBoundary")
                  if accepted else (report or {}).get("continuousSeamQuality"))
    complete_boundary = False
    if continuous is not None:
        check(continuous.get("sourceSHA256") == source["sourceSHA256"], "Foreign continuous seam quality")
        bound = continuous.get("maximumGapUpperBoundMeters")
        check(bound is None or (type(bound) in (int, float) and math.isfinite(bound) and bound >= 0),
              "Invalid continuous seam gap bound")
        seams = continuous.get("seams", [])
        check(len(seams) == continuous.get("measuredContinuousSeams"), "Incomplete saved seam records")
        check(all(type(s.get("maximumGapUpperBoundMeters")) in (int, float)
                  and math.isfinite(s["maximumGapUpperBoundMeters"])
                  and 0 <= s["maximumGapUpperBoundMeters"] <= bound for s in seams) if bound is not None else not seams,
              "Inconsistent per-seam upper bounds")
        seam_indices = {s["stitchIndex"] for s in seams}
        complete_boundary = (continuous.get("completedAllContinuousSeams") is True
                             and continuous.get("gatheredSeamsUnproven") == 0
                             and continuous.get("declaredSeams") == len(paper["pattern"]["stitches"])
                             and continuous.get("measuredContinuousSeams") == continuous.get("declaredSeams")
                             and len(seam_indices) == len(seams)
                             and seam_indices == set(range(len(paper["pattern"]["stitches"])))
                             and (bound is not None and bound < 0.0005 or not seams and bound is None))
    if accepted and not complete_boundary:
        warnings.append("此数值输出没有完整整边闭合验收记录；钉点间隙不能证明整条接缝闭合。")
    paths = seam_paths(plan, initial["positions"])
    views = {"initial": initial["positions"], "final": final["positions"]}
    common = {"triangleIndices": source["triangleIndices"], "mannequinPositions": source["bodyPositions"],
              "mannequinTriangleIndices": source["bodyTriangleIndices"], "seamPaths": paths}
    return {"id": directory.name, "directory": str(directory.relative_to(inputs.root)),
            "label": paper_style_label(paper, directory.name),
            "accepted": accepted is not None, "warnings": warnings,
            "recordedContinuousSeamQuality": continuous,
            "recordedWholeSeamClosurePassed": complete_boundary,
            "summary": {k: v for k, v in summary.items() if k != "lastStep"},
            "sourceSHA256": source["sourceSHA256"], "bodyGeometrySHA256": summary["bodyGeometrySHA256"],
            "linearizationSourceIdentity": source["linearizationSourceIdentity"],
            "failurePhase": (summary.get("lastStep") or {}).get("phase", summary["stopReason"]),
            "failure": summary.get("failure"), "report": {k: v for k, v in (report or {}).items() if k not in ("newton", "path")},
            "measurements": {name: measure(source, plan, points) for name, points in views.items()},
            "pins": sum(source["pinMask"]), "panelCount": len(source["panelGroups"]),
            "settings": settings, "sourceSVG": source_svg(paper), "commonMesh": common,
            "initialPositions": views["initial"], "finalPositions": views["final"],
            "recordedValidatedMetrics": accepted["metrics"] if accepted else None}


def discover(inputs):
    root = inputs.root
    if (root / "case-summary.json").is_file():
        return [root]
    summary = inputs.json(root / "summary.json")
    check(type(summary.get("driverPassed")) is bool and not summary.get("buildOnly"),
          "Run has no terminal driver summary")
    base = root / "requested2400" if (root / "requested2400").is_dir() else root
    candidates = sorted(base.glob("*/case-summary.json")) + sorted(base.glob("*/*/case-summary.json"))
    directories = [p.parent for p in candidates]
    check(directories and len({p.name for p in directories}) == len(directories),
          "No unique terminal cases found")
    expected = set(summary["cases"]) if isinstance(summary.get("cases"), dict) else (
        {summary["case"]} if summary.get("case") not in (None, "all") else {"circle-straight-band", "shirt-sleeved"})
    check({p.name for p in directories} == expected, "Incomplete terminal case set; run may still be active")
    for name in expected:
        if isinstance(summary.get("cases"), dict):
            row = summary["cases"][name]
            if isinstance(row, dict) and type(row.get("resultAccepted")) is bool:
                inputs.terminal_results[name] = row["resultAccepted"]
        elif isinstance(summary.get("acceptedCases"), list):
            inputs.terminal_results[name] = name in summary["acceptedCases"]
    return directories


def template():
    # Reuse the project's established offline WebGL/CPU viewer and visual style.
    path = HERE / "render-cloth-report.py"
    spec = importlib.util.spec_from_file_location("cloth_report_viewer", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    style = re.search(r"<style>(.*?)</style>", module.HTML, re.S).group(1)
    viewer = module.HTML.split("const canvas=el('viewer');", 1)[1].split("</script>", 1)[0]
    return style, "const canvas=el('viewer');" + viewer, path


PAGE = r'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>整衣 3D · 真实终态报告</title><style>__STYLE__
.workspace{grid-template-columns:minmax(0,1fr) minmax(0,1fr)}.source-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;padding:14px;max-height:640px;overflow:auto}.source-grid figure{margin:0;border:1px solid #eee5e0;border-radius:8px;padding:8px;min-width:0}.source-grid svg{width:100%;max-height:235px;display:block}.source-grid path{fill:none;stroke:#aa6a81;stroke-width:1.6;vector-effect:non-scaling-stroke}.source-grid figcaption{font-size:11px;overflow-wrap:anywhere;color:var(--muted);text-align:center}.mono{font-family:ui-monospace,monospace;font-size:11px;overflow-wrap:anywhere}#download[hidden]{display:none}.metric-grid{grid-template-columns:repeat(4,minmax(0,1fr))}.status{line-height:1.7}.historical{background:#eee7dd;padding:12px 16px;border-radius:8px;color:#725f46;font-size:13px;margin:16px 0}.method code{overflow-wrap:anywhere}.data-box dt{font-size:12px;color:var(--muted)}.data-box dd{margin:6px 0 14px;font-size:13px;overflow-wrap:anywhere}.checks li span{min-width:0}@media(max-width:960px){.workspace{grid-template-columns:1fr}}@media(max-width:520px){.metric-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
</style></head><body><main><div class="eyebrow">TAILORASS · 私有离线报告 · 已终止的真实运行</div><h1>裁片与整衣三维状态</h1><p class="intro">同一份源裁片与实际保存的初态、末次接受状态。正式结果需要运行记录中 R 验收通过且全套产物一致；失败或只运行到指定前缀时，三维展示标为诊断。</p>__HISTORICAL__
<div class="topline"><span id="status" class="status"></span><a class="download" id="download" hidden download>下载已验收 OBJ ↗</a></div>
<div class="controls"><label for="case">款式</label><select id="case">__OPTIONS__</select><label for="state">查看状态</label><select id="state"><option value="final">末次接受状态</option><option value="initial">真实初始状态</option></select></div>
<div class="workspace"><section class="panel"><div class="panel-head"><h2>源 2D 裁片</h2><p class="sub">直接保留原纸样的直线、二次／三次贝塞尔与圆弧，按原 panel 分开排列；每片独立缩放以便检查，不能比较此图中的相对大小，也不能作为 1:1 打印图。</p></div><div class="source-grid" id="source-panels"></div></section>
<section class="panel"><div class="panel-head"><h2 id="mesh-title">实际三维状态</h2><p class="sub" id="mesh-note"></p></div><div class="canvas-wrap"><canvas id="viewer" aria-label="实际整衣三维网格，可拖动旋转和缩放"></canvas><div class="canvas-hint" id="hint">拖动旋转 · 滚轮／双指缩放</div><div class="canvas-error" id="canvas-error"></div></div><div class="view-tools"><div class="view-buttons"><button data-view="front">正面</button><button data-view="side">侧面</button><button data-view="back">背面</button><button data-view="reset">重置</button></div><div class="toggles"><label><input id="body" type="checkbox" checked>人体</label><label><input id="seams" type="checkbox" checked>缝合边</label><label><input id="wire" type="checkbox">网格</label></div></div></section></div>
<section class="panel data-box" style="margin-top:22px"><h3>实际记录与网格测量</h3><div class="metric-grid"><div><div class="metric-value" id="steps"></div><div class="metric-label">已接受步 / 请求步</div></div><div><div class="metric-value" id="gravity"></div><div class="metric-label">已接受帧的重力比例</div></div><div><div class="metric-value" id="gap"></div><div class="metric-label">有限钉点的最大间距</div></div><div><div class="metric-value" id="strain"></div><div class="metric-label">最大源边相对长度变化</div></div><div><div class="metric-value" id="time"></div><div class="metric-label">实际动力学时间</div></div><div><div class="metric-value" id="geometry"></div><div class="metric-label">布料顶点 / 三角面</div></div><div><div class="metric-value" id="area"></div><div class="metric-label">源面积 / 面料质量</div></div><div><div class="metric-value" id="panels"></div><div class="metric-label">完整裁片 / 固定顶点</div></div></div><ul class="checks"><li><span>保存的完整接缝间隙上界</span><strong id="whole-gap"></strong></li><li><span>终止原因</span><strong id="stop"></strong></li><li><span>失败阶段</span><strong id="phase"></strong></li><li><span>真实失败信息</span><strong id="failure"></strong></li><li><span>缝合约束数 / RMS 间距</span><strong id="sewing"></strong></li><li><span id="rate-label">末次接受帧速率</span><strong id="rate"></strong></li><li><span>已接受步骤计算 / 工作者墙钟</span><strong id="wall"></strong></li></ul><ul id="warnings" class="warnings"></ul></section>
<div class="data-grid"><section class="panel data-box"><h3>输入身份</h3><dl><dt>运行目录</dt><dd class="mono" id="run"></dd><dt>源裁片身份 SHA-256</dt><dd class="mono" id="source-sha"></dd><dt>实际人体身份 SHA-256</dt><dd class="mono" id="body-sha"></dd><dt>源线性化实例</dt><dd class="mono" id="identity"></dd></dl></section><section class="panel data-box"><h3>怎样理解这份报告</h3><p class="sub">“已接受步”表示求解器提交了这一帧，不代表整衣已通过最终验收。装配阶段是配置变化，未计作真实动力学时间。失败的候选位置没有用于三维展示。</p><p class="sub">缝合间距由全部保存的重心坐标约束重新计算；应变取全部源三角网格边长度的绝对相对变化。两者使用 Python Float64，仅用于报告，不会重新执行碰撞检查或 R 验收。</p><p class="sub">2D 直接读取原纸样曲线，用 SVG 原生 L／Q／C／A 绘制，没有用布料网格替代轮廓；3D 是未经平滑或补洞的原始保存顶点及完整面索引。显示时 WebGL 使用 Float32；测量与文件仍保留原 Float64 数据。</p><p class="sub">正式验收标签依据已保存的 R 记录、24 帧窗口与一致产物，不等于本报告重新证明了物理正确性或个人合体效果。<a href="report-manifest.json">查看所有输入与报告文件 SHA-256 ↗</a></p></section></div><div class="footer">生成时间：__TIME__。全页面离线，无外部资源、网络请求或上传。报告不启动求解器，不更改原始运行。__HISTORY_NOTE__</div></main>
<script id="joint-data" type="application/json">__DATA__</script><script>
'use strict';const report=JSON.parse(document.getElementById('joint-data').textContent);const el=id=>document.getElementById(id);const cases={};for(const c of report.cases){for(const state of ['initial','final'])cases[c.id+'/'+state]={mesh:{...c.commonMesh,positions:c[state+'Positions']}}}
const fmt=(n,d=2)=>Number.isFinite(n)?n.toLocaleString('zh-CN',{maximumFractionDigits:d,minimumFractionDigits:d}):'未记录';const mm=n=>fmt(n*1000,5)+' mm';
function choose(){const c=report.cases.find(c=>c.id===el('case').value),initial=el('state').value==='initial',m=c.measurements[initial?'initial':'final'],s=c.summary,r=c.report;el('status').textContent=c.accepted?(c.recordedWholeSeamClosurePassed?'R 数值验收与整边闭合检查通过':'历史 R 数值输出 · 整边闭合未确认'):'诊断状态 · 未通过整衣最终验收';el('status').classList.toggle('good',c.accepted&&c.recordedWholeSeamClosurePassed);el('mesh-title').textContent=initial?'实际初态 · 独立裁片':c.accepted?(c.recordedWholeSeamClosurePassed?'实际已验收整衣':'历史数值输出 · 整边未确认'):'末次接受帧 · 失败诊断';el('mesh-note').textContent=initial?'初始刚性放置位置；尚未开始缝合和重力过程。':'第 '+s.actualCompletedSteps+' 步的真实保存状态；没有使用未提交的失败候选。';el('source-panels').innerHTML=c.sourceSVG;el('download').hidden=!c.accepted;if(c.accepted)el('download').href='artifacts/'+encodeURIComponent(c.id)+'/validated-output.obj';el('steps').textContent=(initial?'0':s.actualCompletedSteps)+' / '+s.requestedSteps;el('gravity').textContent=initial?'0%':Number.isFinite(r.gravityFraction)?fmt(100*r.gravityFraction,2)+'%':'未记录';el('gap').textContent=mm(m.maximumActualSeamGapMeters);el('whole-gap').textContent=initial?'尚未缝合':c.recordedContinuousSeamQuality&&c.recordedContinuousSeamQuality.declaredSeams===0?'无配对接缝':c.recordedContinuousSeamQuality&&c.recordedContinuousSeamQuality.maximumGapUpperBoundMeters!=null?mm(c.recordedContinuousSeamQuality.maximumGapUpperBoundMeters)+(c.recordedWholeSeamClosurePassed?'':'（覆盖不完整或未达标）'):'未记录，不能由钉点指标代替';el('strain').textContent=fmt(m.maximumSourceEdgeRelativeChange*100,4)+'%';el('time').textContent=fmt(initial?0:s.dynamicSimulatedSeconds,4)+' s';el('geometry').textContent=c.initialPositions.length+' / '+c.commonMesh.triangleIndices.length/3;el('area').textContent=fmt(m.sourceAreaSquareMeters,4)+' m² / '+fmt(m.fabricMassKg*1000,2)+' g';el('panels').textContent=c.panelCount+' / '+c.pins;el('stop').textContent=s.stopReason;el('phase').textContent=c.accepted?'—':c.failurePhase;el('failure').textContent=c.failure||'没有记录异常（可能仅运行到请求前缀）';el('sewing').textContent=m.sewingConstraints+' / '+mm(m.rmsActualSeamGapMeters);el('rate-label').textContent=r.trajectoryMode==='physicalLinearStep'?'末次接受帧最大物理速度':'末次接受帧配置变化率（非物理速度）';el('rate').textContent=Number.isFinite(r.maximumSpeedMetersPerSecond)?fmt(r.maximumSpeedMetersPerSecond,6)+' m/s':'未记录';el('wall').textContent=fmt(s.acceptedStepComputationSeconds,2)+' s / '+fmt(s.totalWorkerWallSeconds,2)+' s';el('run').textContent=report.runRoot+' / '+c.directory;el('source-sha').textContent=c.sourceSHA256;el('body-sha').textContent=c.bodyGeometrySHA256;el('identity').textContent=c.linearizationSourceIdentity;el('warnings').replaceChildren(...c.warnings.map(t=>{const li=document.createElement('li');li.textContent=t;return li}));loadMesh(cases[c.id+'/'+el('state').value].mesh)}
__VIEWER__
el('state').addEventListener('change',choose);
</script></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path, help="New private report directory")
    parser.add_argument("--historical", action="store_true", help="Label an immutable earlier run as historical")
    args = parser.parse_args()
    root, output = args.run_root.resolve(), args.output.resolve()
    check(root.is_dir(), "Run root does not exist")
    check(not output.exists(), "Output must be a new directory; existing reports are preserved")
    check(not output.is_relative_to(root) and not root.is_relative_to(output),
          "Output and source run must be separate directories")
    inputs = Inputs(root)
    directories = discover(inputs)
    for name in ("delivery-manifest.json", "source-manifest.json", "build/source-manifest.json",
                 "final-native-proof-binding.json", "native-dependencies.json"):
        if (root / name).is_file():
            inputs.raw(root / name)
    data = [case_data(inputs, directory) for directory in directories]
    style, viewer, reused = template()
    now = datetime.datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds")
    payload = {"runRoot": str(root), "historical": args.historical, "cases": data}
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    encoded = encoded.replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    replacements = {"STYLE": style, "VIEWER": viewer, "DATA": encoded, "TIME": now,
                    "OPTIONS": ''.join('<option value="'+html.escape(c["id"], quote=True)+'">'+html.escape(c["label"])+'</option>' for c in data),
                    "HISTORICAL": '<div class="historical">历史冻结运行 · 用于报告开发与失败检查，不代表当前版本效果。</div>' if args.historical else '',
                    "HISTORY_NOTE": "此页明确展示历史版本。" if args.historical else ''}
    # A source label containing a template marker must remain plain data.
    content = re.sub(r"__(STYLE|VIEWER|DATA|OPTIONS|TIME|HISTORICAL|HISTORY_NOTE)__",
                     lambda match: replacements[match.group(1)], PAGE)
    check(inputs.unchanged(), "Input changed while report was generated")
    output.mkdir(parents=True)
    (output / "index.html").write_text(content)
    for c, directory in zip(data, directories):
        if c["accepted"]:
            target = output / "artifacts" / c["id"]
            target.mkdir(parents=True)
            for name in ARTIFACTS:
                # Copy exactly the bytes consumed and hashed above.
                (target / name).write_bytes(inputs.raw(directory / name))
    check(inputs.unchanged(), "Input changed while artifacts were copied")
    records = {str(p.relative_to(output)): {"sha256": digest(p.read_bytes()), "bytes": p.stat().st_size}
               for p in sorted(output.rglob('*')) if p.is_file()}
    manifest = {"schemaVersion": 1, "generatedAt": now, "historical": args.historical,
                "runRoot": str(root), "generatorSHA256": digest(Path(__file__).read_bytes()),
                "reusedViewer": {"path": str(reused), "sha256": digest(reused.read_bytes())},
                "actualSourceInputs": inputs.records, "inputBytesUnchanged": True,
                "cases": [{"case": c["id"], "acceptedOutputShown": c["accepted"],
                           "actualCompletedSteps": c["summary"]["actualCompletedSteps"],
                           "recordedWholeSeamClosurePassed": c["recordedWholeSeamClosurePassed"],
                           "recordedContinuousSeamQuality": c["recordedContinuousSeamQuality"],
                           "stopReason": c["summary"]["stopReason"], "warnings": c["warnings"],
                           "sourceSHA256": c["sourceSHA256"], "bodyGeometrySHA256": c["bodyGeometrySHA256"],
                           "measurements": c["measurements"]} for c in data],
                "newSimulationStarted": False, "acceptanceReexecuted": False,
                "diagnosticOBJWritten": False, "externalAssets": False, "reportFiles": records}
    (output / "report-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2, allow_nan=False)+'\n')
    print(json.dumps({"report": str(output / 'index.html'), "cases": len(data),
                      "accepted": sum(c["accepted"] for c in data), "historical": args.historical,
                      "manifestSHA256": digest((output / 'report-manifest.json').read_bytes())}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, IndexError) as error:
        raise SystemExit("Report refused: " + str(error))
