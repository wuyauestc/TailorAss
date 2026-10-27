#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build a private STATIC waistband report from actual exported solver results.

A failed or unexecuted case remains visible as such. No template garment,
browser automation, network request, or modification of an old report is used.
"""
import argparse
import datetime
import hashlib
import html
import inspect
import json
import math
from pathlib import Path
import re
import runpy
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "Tests/NativePattern"
REPORTS = TESTS / "Reports"
DEFAULT_OUTPUT = REPORTS / "2026-10-25-waistband-3d"
SPECS = [
    ("straight-default", "直腰头 · 默认", "StraightWB", .2, .18),
    ("fitted-default", "弧形腰头 · 默认", "FittedWB", .2, .18),
    ("straight-narrow", "直腰头 · 窄版", "StraightWB", .1, .18),
    ("fitted-narrow", "弧形腰头 · 窄版", "FittedWB", .1, .18),
    ("straight-wide", "直腰头 · 宽版", "StraightWB", .35, .18),
    ("fitted-wide", "弧形腰头 · 宽版", "FittedWB", .35, .18),
    ("straight-wide-ease", "直腰头 · 宽版＋明确放量", "StraightWB", .35, .18),
    ("straight-soft", "直腰头 · 柔软", "StraightWB", .2, .12),
    ("fitted-firm", "弧形腰头 · 挺括", "FittedWB", .2, .28),
]


def read_json(path):
    return json.loads(path.read_bytes())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def body_geometry_hash(mesh):
    # Same encoding as the independent volume proof and earlier body report.
    canonical={"p":[[v[k] for k in ("x","y","z")] for v in mesh['mannequinPositions']],"t":mesh['mannequinTriangleIndices']}
    return hashlib.sha256(json.dumps(canonical,separators=(',',':')).encode()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+"\n")


def edge_length(panel, edge):
    a, b = [panel["vertices"][i] for i in edge["endpoints"]]
    curvature = edge.get("curvature")
    if not curvature:
        return math.dist(a,b)/100
    if curvature["type"] != "circle":
        raise ValueError("Current waistband report requires the actual line/circle source primitives")
    radius, large, _ = curvature["params"]
    angle = 2*math.asin(min(1,math.dist(a,b)/(2*radius)))
    if large:
        angle = 2*math.pi-angle
    return radius*angle/100


def source_metrics(document, style):
    if document.get("properties",{}).get("units_in_meter",100) != 100:
        raise ValueError("Unexpected pattern units; source centimetres must be explicit")
    panels = document["pattern"]["panels"]
    if set(panels) != {"wb_front","wb_back"}:
        raise ValueError("Snapshot is not a standalone two-panel waistband")
    fitted = style == "FittedWB"
    roles = {"wb_front": (3,1,[0,2]) if fitted else (2,0,[1,3]),
             "wb_back": (0,2,[1,3]) if fitted else (1,3,[0,2])}
    measured, perimeter = {}, 0.0
    for name, (top,bottom,sides) in roles.items():
        p=panels[name]
        if len(p["edges"]) != 4:
            raise ValueError("Unsupported decorated/cut waistband source")
        lengths=[edge_length(p,e) for e in p["edges"]]
        perimeter += sum(lengths)
        if fitted:
            inner=p["edges"][top].get("curvature"),p["edges"][bottom].get("curvature")
            if any(c is None or c["type"] != "circle" for c in inner):
                raise ValueError("FittedWB lost its two real annular-sector arcs")
            top_radius,bottom_radius=[c["params"][0]/100 for c in inner]
            depth=bottom_radius-top_radius
            if depth<=0 or abs(lengths[top]/top_radius-lengths[bottom]/bottom_radius)>1e-7:
                raise ValueError("FittedWB arcs are not one concentric annular sector")
        else:
            if any(e.get("curvature") for e in p["edges"]):
                raise ValueError("StraightWB must remain its real rectangular source")
            depth=lengths[sides[0]]
            if abs(lengths[top]-lengths[bottom])>1e-8:
                raise ValueError("StraightWB source is not a constant-width strip")
        if depth<=0 or any(abs(lengths[s]-depth)>1e-7 for s in sides):
            raise ValueError("Paper side/radial depth does not match its source edges")
        measured[name]={"topMeters":lengths[top],"bottomMeters":lengths[bottom],"paperDepthMeters":depth,
                        "analyticAreaSquareMeters":(lengths[top]+lengths[bottom])*depth/2}
    front,back=measured["wb_front"],measured["wb_back"]
    if abs(front["paperDepthMeters"]-back["paperDepthMeters"])>1e-7:
        raise ValueError("Front/back paper depth differs")
    return {"style":style,"topMeters":sum(p["topMeters"] for p in measured.values()),
            "bottomMeters":sum(p["bottomMeters"] for p in measured.values()),
            "paperDepthMeters":front["paperDepthMeters"],"paperDepthKind":"径向宽度" if fitted else "矩形宽度",
            "analyticAreaSquareMeters":sum(p["analyticAreaSquareMeters"] for p in measured.values()),
            "sourcePerimeterMeters":perimeter,"panels":measured}


def waist_renderer():
    """Reuse only the established z-buffer rasterizer with a shared camera.

    Camera changes do not alter any body/cloth coordinates or triangles.
    """
    namespace=runpy.run_path(str(TESTS/"render-cloth-preview.py"))
    source=inspect.getsource(namespace["render"])
    replacements={"def render(mesh_path, output_path):":"def render_waist(mesh_path, output_path):",
                  "view_width, height = 480, 750":"view_width, height = 420, 360",
                  "center_y = (low+high)/2":"center_y = -0.025",
                  "scale = min(520, (height-90)/max(0.1, high-low))":"scale = 900.0"}
    for a,b in replacements.items():
        if source.count(a)!=1:raise ValueError("Established renderer camera marker changed: "+a)
        source=source.replace(a,b)
    exec(source,namespace)
    return namespace["render_waist"]


def fmt(value, digits=2):
    return f"{value:.{digits}f}" if isinstance(value,(int,float)) and math.isfinite(value) else "未记录"


def mm(value):
    return fmt(value*1000)+" mm" if isinstance(value,(int,float)) else "未记录"


def metric(label,value):
    return '<div><dt>'+html.escape(label)+'</dt><dd>'+html.escape(value)+'</dd></div>'


def make_html(cases, summary, stamp, sensitivity=None):
    rows, cards = [], []
    for c in cases:
        tag,title=c["tag"],c["title"]
        badge="通过当前质量检查" if c["accepted"] else ("未达到质量门槛" if c["executed"] else "尚未执行")
        color="good" if c["accepted"] else "review"
        d=c.get("diagnostics",{});s=c.get("source");g=c.get("independent")
        procedure='通过（保留质量拒绝）' if c.get("harnessCasePassed") and not c["accepted"] else ('通过' if c.get("harnessCasePassed") else ('失败' if c.get("harnessCasePassed") is False else '未提供逐例记录'))
        rows.append('<tr><td><a href="#'+tag+'">'+html.escape(title)+'</a></td><td class="'+color+'">'+badge+'</td><td>'+procedure+'</td><td>'+('是' if d.get("converged") else ('否' if "converged" in d else '无网格'))+'</td><td>'+fmt(d.get("maxEdgeStrain",math.nan)*100,4)+'%</td><td>'+str(g["properBodyTrianglePairs"] if g else '未复核')+'</td></tr>')
        details=[]
        if s:
            details += [metric("原纸样上缘总弧长",fmt(s["topMeters"]*100)+" cm"),metric("原纸样下缘总弧长",fmt(s["bottomMeters"]*100)+" cm"),metric("纸样"+s["paperDepthKind"],fmt(s["paperDepthMeters"]*100)+" cm"),metric("原纸样解析面积",fmt(s["analyticAreaSquareMeters"],6)+" m²")]
            details.append(metric("源腰围倍率",fmt(c["declaredWaistMultiplier"],2)))
        if d:
            details += [metric("网格参考面积",fmt(d.get("referenceAreaSquareMeters"),6)+" m²"),metric("参考面积质量",fmt(d.get("totalFabricMassKg",math.nan)*1000)+" g"),metric("数值收敛标记",'是' if d.get("converged") else '否'),metric("最大源边应变",fmt(d.get("maxEdgeStrain",math.nan)*100,4)+"%"),metric("末态最大速度",fmt(d.get("maxSpeedMetersPerSecond",math.nan)*100,3)+" cm/s"),metric("SDF 顶点穿入估计",mm(d.get("maxBodyPenetrationMeters"))),metric("接缝间距诊断",mm(d.get("maxSeamGapMeters"))),metric("布片自交对数",str(d.get("surfaceIntersectionCount","未记录"))),metric("人体面交叉诊断",str(d.get("bodySurfaceIntersectionCount","未记录"))),metric("Mac 命令行耗时",fmt(d.get("computationSeconds"))+" s")]
            details += [metric("实验预设克重",fmt(c["declaredArealDensityKgPerM2"]*1000,0)+" g/m²"),metric("人体网格接触目标",mm(d.get("bodySurfaceClearanceMeters"))),metric("SDF 顶点投影目标", "2.50 mm（固定假设）"),metric("辅助上缘支撑目标",mm(d.get("waistSupportClearanceMeters")))]
            if "sourceStrainLimitFraction" in d:
                details += [metric("数值边长投影目标",fmt(d["sourceStrainLimitFraction"]*100,1)+"%"),metric("每步边长投影预算",str(d.get("sourceStrainLimitPassCount","未记录"))+" 次")]
        if "verticalProjectionRangeMeters" in c:
            details.append(metric("三维垂直投影范围（最高−最低）",fmt(c["verticalProjectionRangeMeters"]*100)+" cm"))
        if g:
            details += [metric("独立人体真实交叉对数",str(g["properBodyTrianglePairs"])),metric("体积内顶点／面中心",str(g["vertices"]["inside"])+" / "+str(g["triangleCentroids"]["inside"])),metric("三轴体积复核模糊点",str(g["vertices"]["ambiguous"]+g["triangleCentroids"]["ambiguous"]))]
        image=('<figure><img src="generated/'+c['image']+'" width="1260" height="360" loading="lazy" alt="'+html.escape(title)+'实际网格固定相机腰部三视图"><figcaption>左：正面；中：右侧；右：背面。相机中心 Y=−0.025 m，比例 900 px/m；所有方案共用相机，未改写或缩放网格坐标。</figcaption></figure>') if c.get("image") else '<p class="missing">本次没有可验证的三维网格图；没有用模板或临时原型补图。</p>'
        issues=''.join('<li>'+html.escape(v)+'</li>' for v in c["issues"])
        issue_block='<ul class="issues">'+issues+'</ul>' if issues else '<p class="sub">当前记录没有失败项。</p>'
        links=' · '.join('<a href="generated/'+html.escape(v)+'" download>'+html.escape(k)+'</a>' for k,v in c["files"].items())
        fixture='<p class="sub">默认源纸样与固定官方 fixture 的最大端点／圆弧半径差：'+fmt(c["officialFixtureMaximumDeltaCM"],10)+' cm；接缝语义一致。</p>' if "officialFixtureMaximumDeltaCM" in c else ''
        source_note='该对照明确把源腰围倍率改为 1.05；它是另一份较宽围度纸样，不能用于替代原倍率 1.00 的宽版失败结果。' if c["declaredWaistMultiplier"]!=1 else ''
        cards.append('<section id="'+tag+'"><header><h2>'+html.escape(title)+'</h2><span class="badge '+color+'">'+badge+'</span></header><p class="sub">'+html.escape(c["style"])+"；声明的宽度比例 "+fmt(c["declaredWidthRatio"],2)+'，源腰围倍率 '+fmt(c["declaredWaistMultiplier"],2)+'。'+source_note+'收敛标记、质量结论与回归流程结论分别记录，质量失败不会改写成通过。</p>'+image+'<dl class="metrics">'+''.join(details)+'</dl>'+fixture+issue_block+'<p>'+links+'</p></section>')
    accepted=sum(c["accepted"] for c in cases);executed=sum(c["executed"] for c in cases)
    sensitivity_html=''
    if sensitivity:
        data=sensitivity["summary"]
        legacy=sensitivity.get('legacyControl',{})
        legacy_html=('<p>本目录提供的原始关闭投影对照日志记录：既有圆裙和双片裙的最大位置差均为 0。本 Python 分析器只核对日志，没有重跑旧对照。<a href="generated/sensitivity-legacy-flag-off.log">对照日志</a></p>' if legacy.get('passed') else '<p>本次敏感性目录没有提供关闭投影的对照日志；旧对照未在本次分析中重跑，未据此宣称旧结果位置差为零。</p>')
        r=''.join('<tr><td>'+('直腰头' if item['style']=='straight-default' else '弧形腰头')+'</td><td>'+str(item['passes'])+'</td><td>'+fmt(item['maxActualEdgeStrain']*100,4)+'%</td><td>'+fmt(item['speedMetersPerSecond']*100,4)+' cm/s</td><td>通过</td></tr>' for item in data['rows'])
        comparison=next(c for c in data['positionComparisons'] if c['style']=='straight-default' and c['passesA']==40 and c['passesB']==80)
        sensitivity_html='<section><h2>有限投影预算的敏感性</h2><p>固定默认原纸样、标准人体和实验面料，只把每步边长投影预算改为 20／40／80 次。六例均达到原有质量门槛，体积复核的顶点和面中心均在人体外，未发现三轴分歧或模糊点。</p><table><thead><tr><th>原纸样</th><th>每步预算</th><th>实际最大应变</th><th>末态速度</th><th>原质量门槛</th></tr></thead><tbody>'+r+'</tbody></table><p>直腰头 40 与 80 次的对应顶点位移最大差 '+fmt(comparison['maximumPositionDifferenceMeters']*1000,3)+' mm'+'，均方根 '+fmt(comparison['rmsPositionDifferenceMeters']*1000,3)+' mm'+'。5% 是有限数值投影的目标；实际应变并非严格等于或低于 5%，本页仍按实际值与原 8% 门槛判断。这项检查不表示离散结果已严格收敛到唯一解，也不是标定后的面料物理精度。</p>'+legacy_html+'<p><a href="generated/sensitivity-summary.json">敏感性汇总</a> · <a href="generated/sensitivity-body-volume-parity.json">六例独立体积复核</a></p></section>'
    return '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>腰头 · 原纸样与 3D 验证</title><style>
:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#302c2b;background:#f6f2ed}*{box-sizing:border-box}body{margin:0}main{max-width:1280px;margin:auto;padding:28px 24px}h1{font-size:36px;margin:12px 0}h2{font-size:22px;margin:0}h3{font-size:17px}p{line-height:1.8}a{color:#96546a}section,.intro{background:#fffdf9;border:1px solid #ded4cd;border-radius:12px;margin:22px 0;padding:20px}header{display:flex;align-items:center;justify-content:space-between;gap:12px}.eyebrow,.sub,figcaption{font-size:13px;color:#786d67;line-height:1.8}.badge{font-size:13px;padding:7px 10px;border-radius:5px;white-space:nowrap}.good{color:#426744}.badge.good{background:#e8f0e5}.review{color:#9a5838}.badge.review{background:#f9ead7}table{border-collapse:collapse;width:100%;font-size:14px}td,th{text-align:left;padding:11px;border-bottom:1px solid #e6ddd7}figure{margin:16px 0}img{display:block;max-width:100%;height:auto;border-radius:7px;background:#f3efe7}.metrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:16px;margin:20px 0}.metrics div{padding:9px 0}dt{font-size:12px;color:#7f716a;line-height:1.7}dd{margin:5px 0 0;font-size:20px;font-variant-numeric:tabular-nums}.issues{color:#8d5439;line-height:1.9}.missing{padding:22px;background:#f4eee4;color:#806d5b}code{overflow-wrap:anywhere}.footer{font-size:12px;color:#887a71;line-height:1.8}@media(max-width:720px){main{padding:18px 10px}h1{font-size:29px}section,.intro{padding:15px}.metrics{grid-template-columns:repeat(2,minmax(0,1fr))}td,th{padding:8px;font-size:12px}header{align-items:flex-start}}
</style></head><body><main><div class="eyebrow">TAILORASS · 私有离线验证</div><h1>腰头，从原纸样到三维结果</h1><div class="intro"><p>本页只显示实际导出的腰头网格。已执行 '''+str(executed)+''' / '''+str(len(cases))+''' 组；本次达到质量门槛 '''+str(accepted)+''' 组。失败、未收敛或尚未执行的方案均保留明确状态。</p><p>直腰头来自矩形纸样；弧形腰头来自真实同心圆弧扇形。纸样宽度是原始侧边／径向距离，不能用三维最高点到最低点的垂直投影替代；源上、下缘长度也不能当作三维投影围度。</p><p>上缘采用辅助固定支撑，当前不是完整衣服或真实腰头合体度验证。源纸样和标准人体不得通过缩改来强行通过。较宽的直腰头可能在向臀部扩大的区域缺少围度；本模型失败时应保留失败结果，不能据此自动改小人体或判定现实裁缝方案绝对不可行。</p></div><section><h2>本批记录</h2><table><thead><tr><th>方案</th><th>质量状态</th><th>回归流程</th><th>数值收敛</th><th>最大应变</th><th>独立人体交叉</th></tr></thead><tbody>'''+''.join(rows)+'''</tbody></table><p class="sub">批次汇总 passed='''+html.escape(str(summary.get("passed")))+'''，它表示回归流程是否正确完成，可包含按原样保留的质量拒绝；不能当作全部三维结果通过。单项质量另按其诊断、原纸样和独立几何复核判断。<a href="generated/waistband-summary.json">原始汇总</a> · <a href="manifest.json">源文件与校验记录</a></p></section>'''+''.join(cards)+sensitivity_html+'''<section><h2>检查方式与边界</h2><p>可选边长投影只移动实际三维顶点，保留每条原始参考边长；其数值目标和迭代预算另列，不能当作已测得的物理伸长限制。保留原质量门槛：源边应变 &lt;8%，末态运动 &lt;0.025 m/s，SDF 顶点穿入估计 &lt;3 mm，布片自交和可见人体真实三角面交叉为 0，并达到持续收敛检查。侧缝若采用可接受的等长边共享自由度，间隙 0 是构造性质；若输出有限缝合点，则只报告实际点间距，不当作整条连续缝完全闭合的证书。</p><p>独立复核读取同一实际人体三角网格，使用边／三角形求交和三轴射线体积检查；不调用生产接触代码或 SDF。1e−7 m 是交叉／接触的数值分类容差，不是物理精度。三轴分歧与近表面模糊点另行报告；离散末态与有限采样不能保证整个运动过程或真实缝制效果。</p><p>人体网格接触目标、SDF 顶点投影与固定支撑属于不同数值假设，不能混作面料厚度或最小间隙证书。面料尚未样布标定，人体仍是有限拟合的标准模板。未取得同输入官方最终三维网格，不宣称与 GarmentCode 或 Design2GarmentCode 三维等价。耗时是 Mac 命令行记录，不是 iPhone 实测。</p><p><a href="https://github.com/maria-korosteleva/GarmentCode/tree/d449629979028123a5c4dc9e732a2ec19b7fce31">固定 GarmentCode 源版本</a>。人体为既有 MakeHuman CC0 素材；出处及许可见项目 THIRD_PARTY_NOTICES.md。</p></section><p class="footer">生成时间：'''+stamp.strftime("%Y-%m-%d %H:%M:%S（北京时间）")+'''。静态 HTML、实际网格 PNG 与本地原始数据；无外部脚本或字体。本次没有自动打开本地 HTML，也没有使用其他浏览器或 localhost 绕过安全限制。</p></main></body></html>'''


def self_check():
    for style,name in (("StraightWB","waistband-straight.json"),("FittedWB","waistband-fitted.json")):
        m=source_metrics(read_json(TESTS/"Fixtures"/name),style)
        if abs(m["topMeters"]-.843338)>1e-8 or abs(m["paperDepthMeters"]-.0469674)>1e-8:
            raise ValueError("Official default source self-check failed")
        if style=="FittedWB" and abs(m["bottomMeters"]-.8816264)>1e-8:
            raise ValueError("Fitted source arclength self-check failed")
    waist_renderer()
    print("PASS: official rectangle/annular-source measurements and fixed-camera renderer markers. No simulated result or report was manufactured.")


def legacy_control(directory):
    path=directory/'legacy-flag-off.log'
    if not path.is_file():
        return {'status':'not_rerun','passed':None,'rerunByAnalyzer':False,
                'message':'No flag-off log provided in this fresh directory; legacy controls were not rerun by this analysis.'}
    lines=[line.strip() for line in path.read_text().splitlines() if line.strip()]
    match=re.fullmatch(r'flag-off-reference: circle \+standard-body Skirt2 maximum_position_delta_m=([0-9.eE+\-]+)',lines[0]) if lines else None
    if not match or float(match.group(1))!=0 or lines[1:]!=['PASS: body-surface integration (flag-off-reference)']:
        raise ValueError('Provided flag-off log does not record the exact passing zero-delta controls')
    return {'status':'provided_exact_log','passed':True,'rerunByAnalyzer':False,
            'circleMaximumPositionDifferenceMeters':0,'standardBodySkirt2MaximumPositionDifferenceMeters':0,
            'log':str(path.resolve()),'logSHA256':digest(path),
            'message':'Validated the provided exact control log; the Python analyzer did not execute the legacy solver.'}


def analyze_sensitivity(directory):
    """Reproduce independent evidence from six checked-in runner exports.

    Only missing proof JSON files are written. Existing raw results, existing
    evidence and published reports are never modified by this analysis mode.
    """
    directory=directory.resolve();geometry=runpy.run_path(str(TESTS/'render-body-surface-report.py'))
    validate=runpy.run_path(str(TESTS/'render-cloth-report.py'))['validate_mesh']
    rows=[];parity=[];meshes={};source_hashes={};body_hash=None;body=None
    for passes in (20,40,80):
        base=directory/f'passes-{passes}'
        batch=base/'waistband-summary.json'
        if batch.is_file():
            q=read_json(batch)
            if not q.get('passed') or set(q.get('executed',[]))!={'straight-default','fitted-default'}:
                raise ValueError('Raw sensitivity runner batch did not pass both default cases')
        for tag,style,fixture in (('straight-default','StraightWB','waistband-straight.json'),('fitted-default','FittedWB','waistband-fitted.json')):
            path=base/f'{tag}-mesh.json';pattern=base/f'{tag}-pattern.json';mesh=read_json(path)
            validate(mesh,path.name);d=mesh['diagnostics'];paper=source_metrics(read_json(pattern),style)
            geometry['compare_geometry'](read_json(pattern),read_json(TESTS/'Fixtures'/fixture))
            source_hash=digest(pattern)
            if tag in source_hashes and source_hashes[tag]!=source_hash:raise ValueError('Sensitivity changed its original source file')
            source_hashes[tag]=source_hash
            if d.get('garmentStyle')!=style or d.get('sourceStrainLimitFraction')!=.05 or d.get('sourceStrainLimitPassCount')!=passes:
                raise ValueError('Sensitivity raw style/target/pass configuration differs')
            for field,value in (('waistCircumferenceMeters',paper['topMeters']),('hemCircumferenceMeters',paper['bottomMeters']),('patternLengthMeters',paper['paperDepthMeters'])):
                if abs(d[field]-value)>1e-8:raise ValueError('Sensitivity changed a declared source measurement')
            if abs(d['referenceAreaSquareMeters']-paper['analyticAreaSquareMeters'])>paper['sourcePerimeterMeters']*.00005+1e-9 or abs(d['totalFabricMassKg']-d['referenceAreaSquareMeters']*.18)>1e-10:
                raise ValueError('Sensitivity source area or fixed experimental material mass differs')
            key=body_geometry_hash(mesh)
            if body_hash is None:
                body_hash=key;body=geometry['IndependentBody'](mesh['mannequinPositions'],mesh['mannequinTriangleIndices'])
            elif key!=body_hash:raise ValueError('Sensitivity changed its actual body mesh')
            analysis=geometry['inspect_mesh'](mesh,body)
            if not (d.get('converged') and d['maxEdgeStrain']<.08 and d['maxSpeedMetersPerSecond']<.025 and d['maxBodyPenetrationMeters']<.003 and d.get('surfaceIntersectionCount')==0 and d.get('bodySurfaceIntersectionCount')==analysis['properBodyTrianglePairs']==0):
                raise ValueError('Sensitivity failed an unchanged source/motion/contact quality gate')
            if any(analysis[k]['inside'] or analysis[k]['ambiguous'] or analysis[k]['threeAxisDisagreement'] for k in ('vertices','triangleCentroids')):
                raise ValueError('Sensitivity independent volume check found inside or ambiguous samples')
            separate=base/f'{tag}-diagnostics.json'
            if separate.is_file() and read_json(separate)!=d:raise ValueError('Sensitivity diagnostic snapshots disagree')
            rows.append({'style':tag,'passes':passes,'targetAbsoluteStrain':.05,
                'maxActualEdgeStrain':d['maxEdgeStrain'],'meanActualEdgeStrain':d['meanEdgeStrain'],
                'speedMetersPerSecond':d['maxSpeedMetersPerSecond'],'converged':d['converged'],
                'selfIntersections':d['surfaceIntersectionCount'],'actualBodyIntersections':analysis['properBodyTrianglePairs'],
                'maxSDFPenetrationMeters':d['maxBodyPenetrationMeters'],'sourceAreaSquareMeters':d['referenceAreaSquareMeters'],
                'fabricMassKg':d['totalFabricMassKg'],'vertexCount':len(mesh['positions']),
                'sourcePatternSHA256':source_hash,'wallSecondsConcurrentMacCLI':d['computationSeconds']})
            parity.append({'input':str(path),'meshSHA256':digest(path),'bodyGeometrySHA256':key,
                'bodySignedVolumeM3':body.volume,'bodyClosedManifold':True,'rayAndSurfaceEpsilonMeters':1e-7,
                'method':'Independent +X/+Y/+Z ray parity and true triangle crossings against the actual closed body; no SDF. Ambiguity is reported separately; not physical-fit accuracy.',
                'productionDiagnostics':{k:d.get(k) for k in ('converged','maxEdgeStrain','maxBodyPenetrationMeters','bodySurfaceIntersectionCount','surfaceIntersectionCount','bodySurfaceClearanceMeters','waistSupportClearanceMeters')},
                'independentProperBodyTrianglePairs':analysis['properBodyTrianglePairs'],
                'vertices':analysis['vertices'],'triangleCentroids':analysis['triangleCentroids']})
            meshes[(tag,passes)]=mesh
    comparisons=[]
    for tag in ('straight-default','fitted-default'):
        for pa,pb in ((20,40),(40,80)):
            a,b=meshes[(tag,pa)],meshes[(tag,pb)]
            if len(a['positions'])!=len(b['positions']) or a['triangleIndices']!=b['triangleIndices']:raise ValueError('Sensitivity changed cloth topology')
            delta=[math.dist(tuple(x[k] for k in ('x','y','z')),tuple(y[k] for k in ('x','y','z'))) for x,y in zip(a['positions'],b['positions'])]
            comparisons.append({'style':tag,'passesA':pa,'passesB':pb,'maximumPositionDifferenceMeters':max(delta),
                'rmsPositionDifferenceMeters':math.sqrt(sum(v*v for v in delta)/len(delta))})
    summary={'kind':'Numerical pass-count sensitivity from raw runner exports; not calibrated physical or fit accuracy','passed':True,
        'settings':'Same actual body, immutable official-default source and medium experimental material; sourceStrainLimit .05; only pass count differs20/40/80; unchanged8%/.025m/s/3mm/zero-crossing gates.',
        'rows':rows,'positionComparisons':comparisons,'independentBodyVolumeParity':{
            'allSixMeshesAllVerticesAndTriangleCentroidsOutside':True,'inside':0,'ambiguous':0,'threeAxisDisagreement':0,
            'bodyGeometrySHA256':body_hash,'detailFile':str(directory/'body-volume-parity.json'),
            'method':'Independent three-axis ray parity against actual closed triangle geometry; no SDF.'},
        'disabledLimiterLegacySnapshotRegression':legacy_control(directory),
        'analyzerSHA256':digest(Path(__file__)),'privateHarnessRequired':False}
    summary_path=directory/'sensitivity-summary.json';parity_path=directory/'body-volume-parity.json'
    if summary_path.exists():
        saved=read_json(summary_path)
        old={(r['style'],r['passes']):r for r in saved['rows']}
        if len(old)!=6:raise ValueError('Existing sensitivity summary is incomplete')
        for row in rows:
            prior=old.get((row['style'],row['passes']))
            if prior is None or any(prior[k]!=row[k] for k in ('sourcePatternSHA256','converged','selfIntersections','actualBodyIntersections','vertexCount')):raise ValueError('Existing sensitivity summary does not match raw source/gates')
            if any(abs(prior[k]-row[k])>1e-12 for k in ('maxActualEdgeStrain','speedMetersPerSecond','sourceAreaSquareMeters','fabricMassKg')):raise ValueError('Existing sensitivity summary metrics are stale')
        for expected in comparisons:
            prior=next((c for c in saved['positionComparisons'] if all(c[k]==expected[k] for k in ('style','passesA','passesB'))),None)
            if prior is None or any(abs(prior[k]-expected[k])>1e-12 for k in ('maximumPositionDifferenceMeters','rmsPositionDifferenceMeters')):raise ValueError('Existing sensitivity position comparison is stale')
    if parity_path.exists():
        old={str(Path(r['input']).resolve()):r for r in read_json(parity_path)}
        if len(old)!=6:raise ValueError('Existing volume proof is incomplete')
        for expected in parity:
            prior=old.get(expected['input'])
            if prior is None or prior['meshSHA256']!=expected['meshSHA256'] or prior['bodyGeometrySHA256']!=expected['bodyGeometrySHA256']:raise ValueError('Existing volume proof hashes are stale')
            if any(prior[k]!=expected[k] for k in ('vertices','triangleCentroids')):raise ValueError('Existing volume proof classification is stale')
    # Existing evidence can be consumed by the renderer, which checks its raw
    # hashes. Reproduction must not silently replace a prior saved proof.
    if not summary_path.exists():write_json(summary_path,summary)
    if not parity_path.exists():write_json(parity_path,parity)
    print(f'PASS: independently analyzed six raw sensitivity cases; proof files available in {directory}; legacy={summary["disabledLimiterLegacySnapshotRegression"]["status"]}')
    return summary,parity


def sensitivity_proof(directory, generated, cases, geometry, body_cache):
    summary_path=directory/"sensitivity-summary.json"
    if not summary_path.is_file() or not (directory/'body-volume-parity.json').is_file():
        if all((directory/f'passes-{p}'/f'{tag}-mesh.json').is_file() for p in (20,40,80) for tag in ('straight-default','fitted-default')):analyze_sensitivity(directory)
        else:return None
    summary=read_json(summary_path);parity_path=directory/"body-volume-parity.json";parity=read_json(parity_path)
    rows=summary["rows"];expected={(style,p) for style in ("straight-default","fitted-default") for p in (20,40,80)}
    if len(rows)!=6 or {(r['style'],r['passes']) for r in rows}!=expected or len(parity)!=6:raise ValueError("Sensitivity requires all six fixed-source cases")
    result={"summary":summary,"originalFileSHA256":{},"snapshots":[]}
    meshes={};case_by_tag={c['tag']:c for c in cases}
    for row in rows:
        style,p=row['style'],row['passes'];base=directory/f"passes-{p}"
        mesh_path=base/f"{style}-mesh.json";pattern_path=base/f"{style}-pattern.json"
        mesh=read_json(mesh_path);d=mesh['diagnostics']
        record=next((r for r in parity if Path(r['input']).resolve()==mesh_path.resolve()),None)
        if record is None or record['meshSHA256']!=digest(mesh_path):raise ValueError("Sensitivity volume proof is stale")
        if digest(pattern_path)!=row['sourcePatternSHA256'] or digest(pattern_path)!=case_by_tag[style]['inputSHA256'][style+'-pattern.json']:raise ValueError("Sensitivity did not retain the identical original source")
        if not (row['converged'] and row['maxActualEdgeStrain']<.08 and row['speedMetersPerSecond']<.025 and row['maxSDFPenetrationMeters']<.003 and row['selfIntersections']==0 and row['actualBodyIntersections']==0):raise ValueError("Sensitivity case fails an unchanged numerical gate")
        if d.get('sourceStrainLimitFraction')!=.05 or d.get('sourceStrainLimitPassCount')!=p:raise ValueError("Sensitivity projection settings differ")
        for field,value in (("maxEdgeStrain",row['maxActualEdgeStrain']),("maxSpeedMetersPerSecond",row['speedMetersPerSecond']),("referenceAreaSquareMeters",row['sourceAreaSquareMeters']),("totalFabricMassKg",row['fabricMassKg'])):
            if abs(d[field]-value)>1e-12:raise ValueError("Sensitivity diagnostics differ from their summary")
        body_hash=body_geometry_hash(mesh)
        if body_hash!=case_by_tag[style]['bodyGeometrySHA256'] or body_hash!=record['bodyGeometrySHA256']:raise ValueError("Sensitivity body changed")
        for key,total in (('vertices',len(mesh['positions'])),('triangleCentroids',len(mesh['triangleIndices'])//3)):
            q=record[key]
            if q['total']!=total or q['outside']!=total or any(q[k] for k in ('inside','ambiguous','threeAxisDisagreement')):raise ValueError("Sensitivity volume proof has inside or ambiguous samples")
        points=[tuple(v[k] for k in ('x','y','z')) for v in mesh['positions']]
        if geometry['crossing_count'](body_cache[body_hash],points,mesh['triangleIndices'])!=0:raise ValueError("Sensitivity independent true-body crossing failed")
        meshes[(style,p)]=mesh
        name=f"sensitivity-p{p}-{style}-mesh.json";(generated/name).write_bytes(mesh_path.read_bytes())
        result['snapshots'].append({"style":style,"passes":p,"meshFile":name,"meshSHA256":digest(mesh_path),"sourcePatternSHA256":digest(pattern_path),"independentProperBodyCrossings":0})
        if p==40:(generated/f"sensitivity-{style}-pattern.json").write_bytes(pattern_path.read_bytes())
    for comparison in summary['positionComparisons']:
        a=meshes[(comparison['style'],comparison['passesA'])]['positions'];b=meshes[(comparison['style'],comparison['passesB'])]['positions']
        if len(a)!=len(b):raise ValueError("Sensitivity vertex topology differs")
        delta=[math.dist(tuple(x[k] for k in ('x','y','z')),tuple(y[k] for k in ('x','y','z'))) for x,y in zip(a,b)]
        if abs(max(delta)-comparison['maximumPositionDifferenceMeters'])>1e-12 or abs(math.sqrt(sum(v*v for v in delta)/len(delta))-comparison['rmsPositionDifferenceMeters'])>1e-12:raise ValueError("Sensitivity position comparison is not reproducible")
    legacy=legacy_control(directory);result['legacyControl']=legacy
    sources=[(summary_path,'sensitivity-summary.json'),(parity_path,'sensitivity-body-volume-parity.json')]
    if legacy['passed']:sources.append((directory/'legacy-flag-off.log','sensitivity-legacy-flag-off.log'))
    for source,name in sources:
        (generated/name).write_bytes(source.read_bytes());result['originalFileSHA256'][name]=digest(source)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir",type=Path,default=Path("/private/tmp/TailorAssWaistbandDrape"))
    parser.add_argument("--output-dir",type=Path,default=DEFAULT_OUTPUT)
    parser.add_argument("--sensitivity-dir",type=Path,default=Path("/private/tmp/TailorAssWaistbandSensitivity"))
    parser.add_argument("--analyze-sensitivity",type=Path,metavar="DIR",help="Independently analyze six raw passes-{20,40,80} cases; emit missing proof JSON, no browser or private harness")
    parser.add_argument("--self-check",action="store_true")
    args=parser.parse_args()
    if args.analyze_sensitivity:
        analyze_sensitivity(args.analyze_sensitivity);return
    if args.self_check:
        self_check();return
    summary_path=args.input_dir/"waistband-summary.json"
    if not summary_path.is_file():
        raise SystemExit("Waiting for real waistband-summary.json; renderer is ready. Use --self-check without generating fake results.")
    summary_bytes=summary_path.read_bytes();summary=json.loads(summary_bytes)
    known={s[0] for s in SPECS};executed=set(summary.get("executed",[]))
    if not executed or not executed.issubset(known):raise ValueError("Unknown or empty executed waistband cases")
    quality_rows=summary.get("caseQuality",[])
    if not isinstance(quality_rows,list):raise ValueError("caseQuality must contain explicit per-case records")
    quality={r["case"]:r for r in quality_rows}
    if len(quality)!=len(quality_rows) or not set(quality).issubset(executed):raise ValueError("Duplicate or unexecuted caseQuality record")
    output=args.output_dir.resolve()
    if output.parent!=REPORTS.resolve() or output.name in {"2026-10-25-3d","2026-10-25-3d-refined","2026-10-25-skirt2-3d","2026-10-25-body-surface"}:
        raise ValueError("Use a NEW report folder inside Tests/NativePattern/Reports")
    output.mkdir(parents=True,exist_ok=True);generated=output/"generated";generated.mkdir(exist_ok=True)
    if args.input_dir.resolve()==generated.resolve() or output in args.input_dir.resolve().parents:
        raise ValueError("Report output must be separate from its immutable raw input directory")
    # A rerun of this NEW report must not accidentally reuse a failed case's
    # earlier raw data or PNG. Never touch any older report or unknown file.
    own_names={tag+suffix for tag in known for suffix in ("-mesh.json","-pattern.json","-diagnostics.json",".obj","-waist-views.png")}
    own_names.add("waistband-summary.json")
    own_names.update({'sensitivity-summary.json','sensitivity-body-volume-parity.json','sensitivity-legacy-flag-off.log'})
    own_names.update(f'sensitivity-p{p}-{tag}-mesh.json' for p in (20,40,80) for tag in ('straight-default','fitted-default'))
    own_names.update(f'sensitivity-{tag}-pattern.json' for tag in ('straight-default','fitted-default'))
    for name in own_names:
        p=generated/name
        if p.is_file():p.unlink()
    geometry=runpy.run_path(str(TESTS/"render-body-surface-report.py"))
    viewer=runpy.run_path(str(TESTS/"render-cloth-report.py"));render=waist_renderer()
    baseline=read_json(TESTS/"Reports/2026-10-25-body-surface/generated/skirt2-default-mesh.json")
    expected_body={"positions":baseline["mannequinPositions"],"indices":baseline["mannequinTriangleIndices"]}
    body_cache={};cases=[]
    for tag,title,style,width,density in SPECS:
        waist_multiplier=1.05 if tag=="straight-wide-ease" else 1.0
        c={"tag":tag,"title":title,"style":style,"declaredWidthRatio":width,"declaredWaistMultiplier":waist_multiplier,"declaredArealDensityKgPerM2":density,"executed":tag in executed,"accepted":False,"issues":[],"files":{},"inputSHA256":{}}
        failures=[str(v) for v in summary.get("failures",[]) if str(v).startswith(tag+":")]
        c["issues"] += failures
        c["harnessCasePassed"]=(not failures) if tag in quality else None
        if tag in quality:
            row=quality[tag];c["sourceCaseQuality"]=row
            if abs(row.get("waistMultiplier",math.inf)-waist_multiplier)>1e-12 or abs(row.get("widthRatio",math.inf)-width)>1e-12:c["issues"].append("逐例记录的原纸样参数与声明对照不同。")
            if row.get("allowsQualityRejection")!=(tag in {"straight-wide","straight-wide-ease"}):c["issues"].append("逐例记录改变了允许保留质量拒绝的原宽版方案。")
        if not c["executed"]:
            c["issues"].append("该方案不在本次 executed 列表中；即使目录残留旧文件也不作为本次结果。")
            cases.append(c);continue
        for label,suffix in (("网格 JSON","-mesh.json"),("原纸样 JSON","-pattern.json"),("原诊断 JSON","-diagnostics.json"),("OBJ",".obj")):
            p=args.input_dir/(tag+suffix)
            if p.is_file():
                original=p.read_bytes();(generated/p.name).write_bytes(original)
                c["files"][label]=p.name;c["inputSHA256"][p.name]=hashlib.sha256(original).hexdigest()
        pattern=generated/f"{tag}-pattern.json"
        if pattern.is_file():
            try:
                c["source"]=source_metrics(read_json(pattern),style)
                if tag.endswith("default"):
                    fixture=TESTS/"Fixtures"/("waistband-fitted.json" if style=="FittedWB" else "waistband-straight.json")
                    c["officialFixtureMaximumDeltaCM"]=geometry["compare_geometry"](read_json(pattern),read_json(fixture))
            except Exception as error:c["issues"].append("源纸样复核失败："+str(error))
        mesh_path=generated/f"{tag}-mesh.json"
        if not mesh_path.is_file():
            c["issues"].append("本次未保存三维网格，可能在参数或装配预检查中停止。")
            cases.append(c);continue
        try:
            mesh=read_json(mesh_path);viewer["validate_mesh"](mesh,mesh_path.name)
            d=mesh["diagnostics"];c["diagnostics"]=d
            diag=generated/f"{tag}-diagnostics.json"
            if diag.is_file() and read_json(diag)!=d:c["issues"].append("独立诊断 JSON 与网格内诊断不一致。")
            if d.get("garmentStyle")!=style:c["issues"].append("输出衣服类型与本次声明的腰头类型不符。")
            actual_body={"positions":mesh["mannequinPositions"],"indices":mesh["mannequinTriangleIndices"]}
            c["sameVisibleBodyAsBaseline"]=actual_body==expected_body
            if not c["sameVisibleBodyAsBaseline"]:c["issues"].append("可见人体与固定基线不同，不能视为同人体的参数对照。")
            key=body_geometry_hash(mesh)
            if key not in body_cache:body_cache[key]=geometry["IndependentBody"](mesh["mannequinPositions"],mesh["mannequinTriangleIndices"])
            analysis=geometry["inspect_mesh"](mesh,body_cache[key])
            # The old helper's annular waist-loop length is not a universal
            # waistband measurement for separate sewn panel degrees of freedom.
            # Only the independent volume/intersection checks are consumed here.
            analysis.pop("waistBoundaryPolylineMeters",None)
            c["independent"]=analysis;c["bodyGeometrySHA256"]=key
            c["verticalProjectionRangeMeters"]=max(p["y"] for p in mesh["positions"])-min(p["y"] for p in mesh["positions"])
            if analysis["properBodyTrianglePairs"]!=d.get("bodySurfaceIntersectionCount"):c["issues"].append("独立人体三角面交叉计数与诊断不同。")
            if analysis["properBodyTrianglePairs"]!=0:c["issues"].append("仍检测到真实人体面片交叉。")
            if any(analysis[k]["inside"] or analysis[k]["ambiguous"] for k in ("vertices","triangleCentroids")):c["issues"].append("独立体积采样存在人体内点或模糊点，需进一步复核。")
            if s:=c.get("source"):
                for field,value in (("waistCircumferenceMeters",s["topMeters"]),("hemCircumferenceMeters",s["bottomMeters"]),("patternLengthMeters",s["paperDepthMeters"])):
                    if abs(d.get(field,math.inf)-value)>1e-8:c["issues"].append("诊断未保留原纸样量："+field)
                bound=s["sourcePerimeterMeters"]*0.00005+1e-9
                if abs(d["referenceAreaSquareMeters"]-s["analyticAreaSquareMeters"])>bound:c["issues"].append("参考三角面积超过源曲线离散误差界。")
                if abs(d.get("totalFabricMassKg",math.inf)-d["referenceAreaSquareMeters"]*density)>1e-10:c["issues"].append("参考面积质量与声明的实验面料克重不一致。")
                if abs(s["topMeters"]-d.get("supportWaistCircumferenceMeters",math.inf)*waist_multiplier)>1e-8:c["issues"].append("原纸样上缘总长不符合声明的独立腰围倍率。")
            else:c["issues"].append("缺少可验证的原纸样快照。")
            if not d.get("converged"):c["issues"].append("数值求解未达到持续收敛门槛。")
            if not d.get("maxEdgeStrain",math.inf)<.08:c["issues"].append("源边最大应变未低于 8%。")
            if not d.get("maxSpeedMetersPerSecond",math.inf)<.025:c["issues"].append("末态运动未低于 0.025 m/s。")
            if not d.get("maxBodyPenetrationMeters",math.inf)<.003:c["issues"].append("SDF 顶点穿入估计未低于 3 mm。")
            if not d.get("maxSeamGapMeters",math.inf)<.0005:c["issues"].append("实际接缝点间距未低于 0.5 mm。")
            if d.get("surfaceIntersectionCount")!=0:c["issues"].append("布片末态自交检查未通过。")
            numerical_quality=bool(d.get("converged") and d.get("maxEdgeStrain",math.inf)<.08 and d.get("maxSpeedMetersPerSecond",math.inf)<.025 and d.get("maxBodyPenetrationMeters",math.inf)<.003 and d.get("surfaceIntersectionCount")==0 and analysis["properBodyTrianglePairs"]==0)
            if tag in quality and quality[tag].get("qualityPassed")!=numerical_quality:c["issues"].append("逐例质量结论与实际诊断／独立人体交叉检查不同。")
            image=tag+"-waist-views.png";render(generated/mesh_path.name,generated/image);c["image"]=image
        except Exception as error:c["issues"].append("网格或独立复核未完成："+str(error))
        c["accepted"]=not c["issues"]
        cases.append(c)
    sensitivity=sensitivity_proof(args.sensitivity_dir,generated,cases,geometry,body_cache)
    (generated/summary_path.name).write_bytes(summary_bytes)
    stamp=datetime.datetime.now(ZoneInfo("Asia/Shanghai"))
    manifest={"generatedAt":stamp.isoformat(timespec="seconds"),"inputSummarySHA256":hashlib.sha256(summary_bytes).hexdigest(),
              "sourceRunSummary":summary,"camera":{"centerYMeters":-.025,"pixelsPerMeter":900,"views":"front/right/back","meshCoordinatesModified":False},
              "sourceLimiterSensitivity":sensitivity,
              "sourceFlatnessAreaBoundMeters":.00005,"properCrossClassificationEpsilonMeters":1e-7,
              "cases":cases,"generatedFileSHA256":{p.name:digest(p) for p in sorted(generated.iterdir()) if p.is_file()},
              "reportBuilderSHA256":digest(Path(__file__)),"regressionHarnessSHA256":digest(TESTS/"WaistbandDrape.swift"),
              "officialFinal3DMeshAvailable":False,"browserAutomationUsed":False}
    write_json(output/"manifest.json",manifest)
    (output/"index.html").write_text(make_html(cases,summary,stamp,sensitivity))
    print(f"Built static truthful waistband report: {output/'index.html'}; accepted {sum(c['accepted'] for c in cases)}/{len(executed)} executed")


if __name__=="__main__":
    main()
