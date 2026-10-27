#!/usr/bin/env python3
"""Build a separate, offline Skirt2 report from real exported solver meshes.

Reuses the existing local mesh viewer without changing the circle-skirt report.
Only Python's standard library is required. This script never opens a browser.
"""
import argparse
import datetime
import hashlib
import html
import json
import math
from pathlib import Path
import re
import runpy
import shutil
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "Tests/NativePattern"
DEFAULT_REPORT = TESTS / "Reports/2026-10-25-skirt2-3d"
REFERENCE_REPORT = TESTS / "Reports/2026-10-25-3d-refined"
COMMIT = "d449629979028123a5c4dc9e732a2ec19b7fce31"
CASES = [
    ("skirt2-default", "默认双片裙 · 抽褶 1.3 倍"),
    ("skirt2-longer", "加长双片裙 · 长度比例 0.35"),
    ("skirt2-flare10", "双片裙 · 每片每侧裙摆增加 10 cm"),
    ("skirt2-soft", "默认双片裙"),
    ("skirt2-firm", "默认双片裙"),
]


def read_json(path):
    return json.loads(path.read_bytes())


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_metrics(document):
    """Independent polygon measurements in the source JSON's centimeter units."""
    waist = hem = area = 0.0
    heights = []
    for panel in document["pattern"]["panels"].values():
        vertices, edges = panel["vertices"], panel["edges"]
        if len(vertices) != 4 or len(edges) != 4 or any(e.get("curvature") for e in edges):
            raise ValueError("Expected complete, straight four-edge Skirt2 panels")
        low, high = min(p[1] for p in vertices), max(p[1] for p in vertices)
        heights.append(high-low)
        for edge in edges:
            a, b = [vertices[i] for i in edge["endpoints"]]
            length = math.dist(a, b)
            if edge.get("label") == "lower_interface":
                waist += length
            if abs(a[1]-low) < 1e-8 and abs(b[1]-low) < 1e-8:
                hem += length
        area += abs(sum(a[0]*b[1]-b[0]*a[1]
                        for a, b in zip(vertices, vertices[1:]+vertices[:1])))/2
    if len(heights) != 2 or abs(heights[0]-heights[1]) > 1e-8:
        raise ValueError("Skirt2 front/back source heights differ")
    return {"waist_cm": waist, "hem_cm": hem, "height_cm": heights[0], "area_cm2": area}


def compare_source(actual, oracle):
    a, b = actual["pattern"], oracle["pattern"]
    if set(a["panels"]) != set(b["panels"]) or a["stitches"] != b["stitches"]:
        raise ValueError("Default Skirt2 source panel or stitch identities differ from the official fixture")
    maximum = 0.0
    for name in b["panels"]:
        left, right = a["panels"][name], b["panels"][name]
        if left["edges"] != right["edges"] or len(left["vertices"]) != len(right["vertices"]):
            raise ValueError("Default Skirt2 source boundary semantics differ from the official fixture")
        maximum = max(maximum, *(abs(x-y) for p, q in zip(left["vertices"], right["vertices"])
                                 for x, y in zip(p, q)))
    if maximum >= 1e-7:
        raise ValueError(f"Default source coordinate error is {maximum} cm")
    return maximum


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError(f"Shared viewer marker changed: {old[:75]}")
    return source.replace(old, new)


def make_html(template, cases, comparison, generated_at):
    page = template.replace("圆裙", "双片裙")
    page = page.replace("下列腰弧、下摆与面积来自裁片参考几何，不能当作垂坠后投影测量。",
                        "腰口、裙长、下摆与面积来自原始裁片；人体腰围是抽褶支撑的参考尺寸。二者不能混用。")
    page = page.replace("腰弧总长", "原纸样腰口总长").replace("裁片径向裙长", "裁片垂直裙长").replace("下摆弧长", "原纸样下摆总长")
    page = replace_once(page, '<p class="sub" id="source"></p>',
        '<div class="metric-grid"><div><div class="metric-value" id="support-waist"></div><div class="metric-label">支撑参考腰围<small>cm</small></div></div><div><div class="metric-value" id="gather-ratio"></div><div class="metric-label">腰口抽褶倍率</div></div></div>'
        '<p class="sub">抽褶支撑保留原纸样腰口边长，以外向褶皱绕人体装配；这是虚拟支撑环实验，尚未模拟真实腰头或松紧带。</p><p class="sub" id="source"></p>')
    page = replace_once(page, 'el(\'length\').textContent=fmt(d.radialLengthMeters*100);',
        "el('length').textContent=fmt(d.patternLengthMeters*100);el('support-waist').textContent=fmt(d.supportWaistCircumferenceMeters*100);el('gather-ratio').textContent=fmt(d.waistGatherRatio,2)+' 倍';")
    page = replace_once(page, '<a class="download" id="download" href="#" download>下载当前网格 JSON ↗</a>',
        '<span><a class="download" id="download" href="#" download>网格 JSON ↗</a> · <a class="download" id="download-pattern" href="#" download>原纸样 JSON ↗</a> · <a class="download" id="download-obj" href="#" download>OBJ ↗</a></span>')
    page = replace_once(page, "el('download').href='generated/'+item.filename;",
        "el('download').href='generated/'+item.filename;el('download-pattern').href='generated/'+item.filename.replace('-mesh.json','-pattern.json');el('download-obj').href='generated/'+item.filename.replace('-mesh.json','.obj');")
    page = replace_once(page, "el('strain').textContent=fmt(d.maxEdgeStrain*100)+'%';",
        "el('strain').textContent=fmt(d.maxEdgeStrain*100,4)+'%';")
    baseline = re.compile(r'<p>可复现的官方双片裙基线：.*?</p>')
    if len(baseline.findall(page)) != 1:
        raise ValueError("Shared viewer baseline paragraph changed")
    m = comparison["official_source_metrics"]
    page = baseline.sub(
        f'<p>官方双片裙二维基线：固定提交 d4496299、mean_all 人体、默认 Skirt2，抽褶 1.3 倍。原纸样腰口 {m["waist_cm"]:.5f} cm，垂直裙长 {m["height_cm"]:.5f} cm，原纸样下摆 {m["hem_cm"]:.5f} cm，平面面积 {m["area_cm2"]/10000:.6f} m²。默认方案端点最大差 {comparison["maximum_source_coordinate_delta_cm"]:.3g} cm、边及接缝语义一致。这验证二维输入；尚缺同输入的官方最终三维网格。</p>', page)
    all_converged = all(item["mesh"]["diagnostics"]["converged"] for item in cases.values())
    intersections = sum(item["mesh"]["diagnostics"].get("surfaceIntersectionCount", 0) for item in cases.values())
    observation = (f'本页 {len(cases)} 个真实输出均达到现有持续稳定门槛。' if all_converged else
                   '部分真实输出尚未达到持续稳定门槛，页面保留原始诊断，不作为通过验收的成衣。')
    observation += f'末态布片交叉对数总计 {intersections}。这些是离散末态检查，不能保证连续运动或所有布片面与人体都没有相交。'
    material_observations = []
    base = cases["skirt2-default"]["mesh"]
    for tag in ("skirt2-soft", "skirt2-firm"):
        mesh = cases[tag]["mesh"]
        if mesh["triangleIndices"] != base["triangleIndices"] or len(mesh["positions"]) != len(base["positions"]):
            raise ValueError("Material comparison requires the same source mesh topology")
        rms = math.sqrt(sum(sum((a[k]-b[k])**2 for k in ("x", "y", "z"))
                            for a, b in zip(mesh["positions"], base["positions"]))/len(base["positions"]))*1000
        name = html.escape(mesh["diagnostics"].get("materialName") or tag)
        material_observations.append(f"{name}相对中等面料的最终顶点 RMS 变化 {rms:.2f} mm")
    section = '<section class="panel method"><h3>本批实际结果与使用边界</h3><p>'+observation+'</p><p>'+"；".join(material_observations)+'。柔软、中等、挺括均为实验数值预设，尚未做样布标定；耗时为当前 Mac 导出数据。</p><p>本轮仅支持自然腰位、无腰头、无切口的双片裙及 1～1.5 倍统一抽褶；其他输入由 App 明确提示。标准人体按尺寸有限拟合，不能还原个人体型。共享侧缝间隙为零来自自由度焊接，不是与官方三维结果比较得到的精度。</p><p>实际网格三视图：<a href="generated/skirt2-default-views.png">默认双片裙 ↗</a> · <a href="generated/skirt2-flare10-views.png">裙摆增量 10 cm ↗</a>。<a href="comparison.json">二维对照与文件哈希 ↗</a> · <a href="generated/skirt2-summary.json">原始回归汇总 ↗</a></p></section>'
    page = replace_once(page, '<section class="panel method"><h3>如何读这份对比</h3>', section+'<section class="panel method"><h3>如何读这份对比</h3>')
    options = "".join(f'<option value="{html.escape(key)}">{html.escape(item["label"])}</option>'
                      for key, item in cases.items())
    payload = json.dumps(cases, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    payload = payload.replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    return (page.replace("__CASE_OPTIONS__", options).replace("__DATA__", payload)
            .replace("__GENERATED_AT__", generated_at.strftime("%Y-%m-%d %H:%M:%S（北京时间，UTC+08:00）")))


def source_note(comparison):
    m = comparison["official_source_metrics"]
    return f'''# 双片裙 3D：输入保真与官方参照

本报告仅为私有研究预览。交互页面显示本项目实际求解网格；官方公开图是不同输入的定性参照，**没有同输入官方最终三维网格，不能宣称三维效果等价**。

## 官方二维输入

锁定 [GarmentCode 提交 {COMMIT[:8]}](https://github.com/maria-korosteleva/GarmentCode/tree/{COMMIT})，使用 [mean_all 人体](https://github.com/maria-korosteleva/GarmentCode/blob/{COMMIT}/assets/bodies/mean_all.yaml)、[默认设计](https://github.com/maria-korosteleva/GarmentCode/blob/{COMMIT}/assets/design_params/default.yaml)，设 `meta.bottom=Skirt2`、关闭上装及腰头。官方 fixture 是项目 `Tests/NativePattern/Fixtures/skirt-two-panel.json`；生成器会先核对上游提交与工作区代码。

默认双片裙 `rise=1`、`length=0.2`、`ruffle=1.3`、`flare=0`、`bottom_cut=0`。腰围 84.3338 cm、后腰围 39.1358 cm、腰臀高 23.4837 cm、派生腿长 85.2888 cm。前片宽为 `(84.3338−39.1358)×1.3=58.7574 cm`，后片宽为 `39.1358×1.3=50.87654 cm`。垂直裙长为 `23.4837+0.2×85.2888=40.54146 cm`。

| 原纸样指标 | 官方 fixture 独立测量 |
| --- | ---: |
| 腰口总长 | {m['waist_cm']:.8f} cm |
| 下摆总长 | {m['hem_cm']:.8f} cm |
| 垂直裙长 | {m['height_cm']:.8f} cm |
| 两片总面积 | {m['area_cm2']:.8f} cm² |
| 默认生成端点最大差 | {comparison['maximum_source_coordinate_delta_cm']:.8g} cm |

`flare` 是每片每侧增加的厘米数：两片总下摆相对腰口增加 `4×flare`，侧缝长为 `sqrt(垂直裙长²+flare²)`。它不是尺寸倍率。接缝保持前片边 3 ↔ 后片边 0、前片边 1 ↔ 后片边 2；前后片的腰口为边 2／边 1。默认官方平移是初始摆片，不是最终垂坠。

原始纸样的长度、面积、静止约束均来自平面四边形，按 100 cm/m 转换成求解单位。标准人体上的外向褶皱支撑环保留原腰口各网格边长；支撑腰围和原纸样腰口总长分开记录。该支撑是实验装配，没有模拟真实腰头、松紧带或抽褶缝制过程。

双片裙的拉伸／剪切距离约束逐一对应真实三角网格边。一个四边网格单元只保留实际剖分使用的一条对角线，使两个三角形可以沿公共边折叠；同时约束两条对角线会把平面四边形锁成刚性单元，阻碍抽褶展开。二阶距离弯曲约束另行保留为软近似，没有用垂坠姿态改写静止边长。

有裙摆增量时，梯形裁片的侧缝需要向外倾斜；虚拟腰口支撑把两组侧缝放在外向褶峰，避免把侧缝压在贴人体的褶谷。各段仍严格按原纸样腰口边长构造；前后片宽度不相等也不会被重置为各一半。下方初始化包络来自标准人体的实际水平截面，排除远离躯干的手臂／手部后包住躯干或双腿；围度不足的输入明确拒绝，不靠修改原纸样通过。

## 官方三维图与许可

原图从已有研究报告复制，未裁切或改绘：

| 本地图片 | 来源与归属 | SHA-256 |
| --- | --- | --- |
| `references/garmentcode-header.png` | [GarmentCode 官方示例](https://github.com/maria-korosteleva/GarmentCode/blob/main/assets/img/header.png)，Maria Korosteleva 等；仓库 MIT | `e3cd112937455057f16e3405d5f6c67380d6622cb2ee4b6d978c1c16d284855c` |
| `references/design2garmentcode-result-text.png` | [Design2GarmentCode 官方文字生成结果](https://style3d.github.io/design2garmentcode/static/images/result_text.png)，Feng Zhou 等；官网 CC BY-SA 4.0 | `3332c598b4901683d1b197a60bd6721946b4b7c8df34f351dca4658c5fc7c787` |

GarmentCode 图是多款成衣群像。Design2GarmentCode 图左侧是该方法、右侧是 DressCode 对照，其中环扇形裙片与连衣裙不是当前 Skirt2 的同输入结果。人物、面料、设计与相机未对齐；不能计算三维表面误差，也不能把公开图用于本 App 的人体或成衣素材。

[Design2GarmentCode 的官方实现](https://github.com/Style3D/design2garmentcode-impl#3-optional-enable-3-d-simulation)使用 GarmentCode 的定制 Warp 仿真后端，因此它们不是两个独立的物理求解器验证。本项目未引入该受限 Warp 实现作为产品依赖。

标准人体来自 MakeHuman CC0 固定来源，详细来源、哈希与许可见 App `GarmentCodeStandardBodySource.json`、`MakeHuman-CC0-LICENSE.txt` 与项目 `THIRD_PARTY_NOTICES.md`。人体是有限尺寸拟合，不是个人身体重建。碰撞场覆盖脚底到腰线上方 20 cm，距离场顶点穿入估计和末态布片交叉检查不等于完整或连续人体碰撞保证。

## 实际证据与复核范围

`comparison.json` 记录默认源几何差值、独立平面测量及所展示数据的哈希。`generated/` 保留五个方案的原始网格、原纸样、诊断、OBJ、回归汇总，以及默认双片裙与裙摆增量 10 cm 的三视图。三视图由实际网格栅格化生成，是诊断渲染，不是 App 截图。

全部方案的收敛标志和质量数值来自各自原始诊断，未通过的输出不会被改为通过。源端点和边／接缝语义对照是二维保真证据；共享接缝残差为零来自拓扑构造。三档面料为未标定的实验数值预设，计算耗时来自 Mac，不代表 iPhone 17 Pro 真机结果。

本报告只进行源文件、JSON、哈希、JavaScript 语法与实际栅格图检查。内置浏览器此前明确拒绝自动打开本地文件 URL，因此本轮未使用其他浏览器或服务绕过限制；交互页面供用户手动打开复核。
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, default=Path("/private/tmp/TailorAssClothSkirt2"))
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    # Deliberately keep this extension separate from all existing reports.
    if output in ((TESTS/"Reports/2026-10-25-3d").resolve(), REFERENCE_REPORT.resolve()):
        raise SystemExit("Use a separate Skirt2 report folder; circle baselines must be preserved")
    summary = read_json(args.input_dir/"skirt2-summary.json")
    if not {tag for tag, _ in CASES}.issubset(summary.get("executed", [])):
        raise ValueError("Run the complete Skirt2 regression before publishing the five-case report")
    viewer = runpy.run_path(str(TESTS / "render-cloth-report.py"))
    cases = {}
    for tag, label in CASES:
        path = args.input_dir / f"{tag}-mesh.json"
        data = read_json(path)
        viewer["validate_mesh"](data, path.name)
        d = data["diagnostics"]
        if read_json(args.input_dir/f"{tag}-diagnostics.json") != d:
            raise ValueError(f"{tag}: exported diagnostics do not match the mesh")
        if d.get("garmentStyle") != "Skirt2" or d.get("patternLengthLabel") != "垂直裙长":
            raise ValueError(f"{tag}: missing explicit Skirt2/vertical-length semantics")
        for key in ("patternLengthMeters", "waistGatherRatio", "supportWaistCircumferenceMeters"):
            if not math.isfinite(d.get(key, math.nan)) or d[key] <= 0:
                raise ValueError(f"{tag}: invalid {key}")
        if d.get("surfaceIntersectionCount") is None:
            raise ValueError(f"{tag}: missing final surface intersection check")
        metrics = source_metrics(read_json(args.input_dir / f"{tag}-pattern.json"))
        for key, expected in (("waistCircumferenceMeters", metrics["waist_cm"]/100),
                              ("hemCircumferenceMeters", metrics["hem_cm"]/100),
                              ("patternLengthMeters", metrics["height_cm"]/100),
                              ("referenceAreaSquareMeters", metrics["area_cm2"]/10000)):
            if abs(d[key]-expected) > 1e-8:
                raise ValueError(f"{tag}: source metric mismatch: {key}")
        material = d.get("materialName")
        if material:
            label += " · " + material
        cases[tag] = {"label": label, "filename": path.name, "sha256": sha256(path), "mesh": data}
    fixture = TESTS / "Fixtures/skirt-two-panel.json"
    oracle = read_json(fixture)
    comparison = {"source_commit": COMMIT, "source_fixture_sha256": sha256(fixture),
                  "maximum_source_coordinate_delta_cm": compare_source(read_json(args.input_dir/"skirt2-default-pattern.json"), oracle),
                  "source_boundary_and_stitch_semantics_equal": True,
                  "official_source_metrics": source_metrics(oracle),
                  "official_final_3d_mesh_available": False,
                  "mesh_sha256": {key: item["sha256"] for key, item in cases.items()}}
    output.mkdir(parents=True, exist_ok=True)
    generated = output / "generated"
    generated.mkdir(exist_ok=True)
    for tag, _ in CASES:
        for suffix in ("-mesh.json", "-pattern.json", "-diagnostics.json", ".obj"):
            shutil.copyfile(args.input_dir/(tag+suffix), generated/(tag+suffix))
    shutil.copyfile(args.input_dir/"skirt2-summary.json", generated/"skirt2-summary.json")
    reference_hashes = {
        "garmentcode-header.png": "e3cd112937455057f16e3405d5f6c67380d6622cb2ee4b6d978c1c16d284855c",
        "design2garmentcode-result-text.png": "3332c598b4901683d1b197a60bd6721946b4b7c8df34f351dca4658c5fc7c787",
    }
    for image, expected in reference_hashes.items():
        if sha256(REFERENCE_REPORT/"references"/image) != expected:
            raise ValueError(f"Official reference image changed: {image}")
        target = output/"references"/image
        target.parent.mkdir(exist_ok=True)
        shutil.copyfile(REFERENCE_REPORT/"references"/image, target)
    renderer = runpy.run_path(str(TESTS / "render-cloth-preview.py"))
    renderer["render"](generated/"skirt2-default-mesh.json", generated/"skirt2-default-views.png")
    renderer["render"](generated/"skirt2-flare10-mesh.json", generated/"skirt2-flare10-views.png")
    timestamp = datetime.datetime.now(ZoneInfo("Asia/Shanghai"))
    comparison["generated_at"] = timestamp.isoformat(timespec="seconds")
    comparison["generated_file_sha256"] = {path.name: sha256(path) for path in sorted(generated.iterdir()) if path.is_file()}
    (output/"comparison.json").write_text(json.dumps(comparison, ensure_ascii=False, indent=2, allow_nan=False)+"\n")
    (output/"reference-sources.md").write_text(source_note(comparison))
    (output/"index.html").write_text(make_html(viewer["HTML"], cases, comparison, timestamp))
    print(f"Built separate Skirt2 report with {len(cases)} actual meshes: {output/'index.html'}")


if __name__ == "__main__":
    main()
