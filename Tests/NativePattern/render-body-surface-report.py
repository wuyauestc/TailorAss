#!/usr/bin/env python3
"""Create a NEW offline body-surface report from immutable real solver exports.

Standard-library geometry checks do not call the production contact solver.
Old report builders and report folders are never modified. No browser is opened.
"""
import argparse
import collections
import datetime
import hashlib
import html
import inspect
import json
import math
from pathlib import Path
import re
import runpy
import shutil
from zoneinfo import ZoneInfo

EPS=1e-7
CELL=.025
class IndependentBody:
 def __init__(self,positions,indices):
  self.p=[tuple(q[k] for k in ('x','y','z')) for q in positions];self.tris=[indices[i:i+3] for i in range(0,len(indices),3)]
  edge=collections.defaultdict(lambda:[0,0]);vol=0
  for ids in self.tris:
   for a,b in zip(ids,ids[1:]+ids[:1]):e=edge[tuple(sorted((a,b)))];e[0]+=1;e[1]+=1 if a<b else -1
   a,b,c=[self.p[i] for i in ids];vol+=(a[0]*(b[1]*c[2]-b[2]*c[1])+a[1]*(b[2]*c[0]-b[0]*c[2])+a[2]*(b[0]*c[1]-b[1]*c[0]))/6
  assert all(v==[2,0] for v in edge.values()),'Body is not consistently wound closed two-manifold'
  self.volume=vol;self.bins=[]
  for axis in range(3):
   u,v=(axis+1)%3,(axis+2)%3;bins=collections.defaultdict(list)
   for ids in self.tris:
    a,b,c=[self.p[i] for i in ids];e1=(b[u]-a[u],b[v]-a[v]);e2=(c[u]-a[u],c[v]-a[v]);det=e1[0]*e2[1]-e1[1]*e2[0]
    if abs(det)<1e-18:continue
    packet=(a,e1,e2,det,b[axis]-a[axis],c[axis]-a[axis])
    for i in range(math.floor(min(a[u],b[u],c[u])/CELL),math.floor(max(a[u],b[u],c[u])/CELL)+1):
     for j in range(math.floor(min(a[v],b[v],c[v])/CELL),math.floor(max(a[v],b[v],c[v])/CELL)+1):bins[i,j].append(packet)
   self.bins.append(bins)
 def ray(self,p,axis):
  u,v=(axis+1)%3,(axis+2)%3;hits=[];near=False
  for a,e1,e2,det,dx1,dx2 in self.bins[axis].get((math.floor(p[u]/CELL),math.floor(p[v]/CELL)),[]):
   q=(p[u]-a[u],p[v]-a[v]);b=(q[0]*e2[1]-q[1]*e2[0])/det;c=(e1[0]*q[1]-e1[1]*q[0])/det
   if b<(-1e-10) or c<(-1e-10) or b+c>1+1e-10:continue
   t=a[axis]+b*dx1+c*dx2-p[axis]
   if abs(t)<=EPS:near=True
   elif t>EPS:hits.append((t,1 if det>0 else -1))
  hits.sort();groups=[]
  for t,sgn in hits:
   if groups and abs(t-groups[-1][0])<=EPS:groups[-1][1].add(sgn)
   else:groups.append([t,{sgn}])
  mixed=any(len(q[1])>1 for q in groups)
  return len(groups)%2,near,mixed
 def classify(self,points):
  result={'outside':0,'inside':0,'ambiguous':0,'threeAxisDisagreement':0,'nearSurface':0,'tangentRayAmbiguity':0,'insideExamples':[],'ambiguousExamples':[]}
  for i,p in enumerate(points):
   r=[self.ray(p,a) for a in range(3)];bits=[v[0] for v in r];near=any(v[1] for v in r);mixed=any(v[2] for v in r);disagree=len(set(bits))>1
   result['threeAxisDisagreement']+=int(disagree);result['nearSurface']+=int(near);result['tangentRayAmbiguity']+=int(mixed)
   key='ambiguous' if near or mixed or disagree else ('inside' if bits[0] else 'outside');result[key]+=1
   examples=result.get(key+'Examples')
   if examples is not None and len(examples)<8:examples.append({'index':i,'point':p,'parityXYZ':bits,'nearSurface':near,'tangentRay':mixed})
  result['total']=len(points);return result


ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "Tests/NativePattern"
REPORTS = TESTS / "Reports"
DEFAULT_REPORT = REPORTS / "2026-10-25-body-surface"
OLD_SKIRT = REPORTS / "2026-10-25-skirt2-3d"
OLD_CIRCLE = REPORTS / "2026-10-25-3d-refined"
COMMIT = "d449629979028123a5c4dc9e732a2ec19b7fce31"
CASES = [
    ("skirt2-default", "双片裙 · 默认"),
    ("skirt2-longer", "双片裙 · 加长"),
    ("skirt2-flare10", "双片裙 · 裙摆增量 10 cm"),
    ("skirt2-soft", "双片裙 · 柔软"),
    ("skirt2-firm", "双片裙 · 挺括"),
    ("circle-0.5", "半圆裙 · suns 0.5"),
    ("circle-0.75", "四分之三圆裙 · suns 0.75"),
    ("circle-1.0", "整圆裙 · suns 1.0"),
]


def read_json(path):
    return json.loads(path.read_bytes())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False)+"\n")


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def minus(a, b):
    return tuple(x-y for x, y in zip(a, b))


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def face(points, ids):
    a, b, c = [points[i] for i in ids]
    n = cross(minus(b, a), minus(c, a))
    length = math.sqrt(dot(n, n))
    if length < 1e-12:
        raise ValueError("Degenerate triangle in an actual mesh")
    return (a, b, c, tuple(v/length for v in n),
            tuple(min(a[k], b[k], c[k]) for k in range(3)),
            tuple(max(a[k], b[k], c[k]) for k in range(3)))


def segment_hit(start, end, triangle):
    a, b, c = triangle[:3]
    direction, e1, e2 = minus(end, start), minus(b, a), minus(c, a)
    p = cross(direction, e2)
    determinant = dot(e1, p)
    if abs(determinant) < 1e-15:
        return None
    offset = minus(start, a)
    u = dot(offset, p)/determinant
    if not -1e-9 <= u <= 1+1e-9:
        return None
    q = cross(offset, e1)
    v, t = dot(direction, q)/determinant, dot(e2, q)/determinant
    if v < -1e-9 or u+v > 1+1e-9 or not -1e-9 <= t <= 1+1e-9:
        return None
    return tuple(start[k]+direction[k]*t for k in range(3))


def proper_cross(a, b):
    # An independent edge/triangle oracle, rather than the production module's
    # overlap-of-plane-cut-segments implementation. Same spatial classification
    # tolerance: tangencies and isolated/coplanar contact are not proper cuts.
    da = [dot(minus(p, b[0]), b[3]) for p in a[:3]]
    db = [dot(minus(p, a[0]), a[3]) for p in b[:3]]
    if not (min(da) < -EPS and max(da) > EPS and min(db) < -EPS and max(db) > EPS):
        return False
    hits = [segment_hit(x, y, other)
            for points, other in ((a[:3], b), (b[:3], a))
            for x, y in zip(points, points[1:]+points[:1])]
    hits = [p for p in hits if p is not None]
    return any(math.dist(p, q) > EPS for p in hits for q in hits)


def crossing_count(body, points, indices):
    size = 0.035
    if not hasattr(body, "cross_faces"):
        body.cross_faces = [face(body.p, ids) for ids in body.tris]
        grid = collections.defaultdict(list)
        for i, f in enumerate(body.cross_faces):
            low, high = f[4:6]
            for x in range(math.floor(low[0]/size), math.floor(high[0]/size)+1):
                for y in range(math.floor(low[1]/size), math.floor(high[1]/size)+1):
                    for z in range(math.floor(low[2]/size), math.floor(high[2]/size)+1):
                        grid[x,y,z].append(i)
        body.cross_grid = grid
    total = 0
    for t in range(0, len(indices), 3):
        cloth = face(points, indices[t:t+3])
        low, high = cloth[4:6]
        candidates = set()
        for x in range(math.floor((low[0]-EPS)/size), math.floor((high[0]+EPS)/size)+1):
            for y in range(math.floor((low[1]-EPS)/size), math.floor((high[1]+EPS)/size)+1):
                for z in range(math.floor((low[2]-EPS)/size), math.floor((high[2]+EPS)/size)+1):
                    candidates.update(body.cross_grid.get((x,y,z), []))
        for i in candidates:
            other = body.cross_faces[i]
            if all(low[k] <= other[5][k]+EPS and high[k]+EPS >= other[4][k] for k in range(3)):
                total += int(proper_cross(cloth, other))
    return total


def inspect_mesh(mesh, body):
    points = [tuple(p[k] for k in ("x", "y", "z")) for p in mesh["positions"]]
    indices = mesh["triangleIndices"]
    centroids = [tuple(sum(points[indices[t+i]][k] for i in range(3))/3 for k in range(3))
                 for t in range(0, len(indices), 3)]
    edge_uses = collections.defaultdict(list)
    for t in range(0, len(indices), 3):
        ids = indices[t:t+3]
        for a, b in zip(ids, ids[1:]+ids[:1]):
            edge_uses[tuple(sorted((a,b)))].append((a,b))
    if any(len(v) > 2 or (len(v) == 2 and v[0] != v[1][::-1]) for v in edge_uses.values()):
        raise ValueError("Non-manifold or inconsistently oriented cloth seam")
    boundary = collections.defaultdict(set)
    for (a,b), uses in edge_uses.items():
        if len(uses) == 1:
            boundary[a].add(b); boundary[b].add(a)
    if any(len(v) != 2 for v in boundary.values()):
        raise ValueError("Cloth boundary is not a closed loop")
    pending, loops = set(boundary), []
    while pending:
        first = next(iter(pending)); current = first; previous = None; loop = []
        while current not in loop:
            loop.append(current); pending.discard(current)
            previous, current = current, next(iter(boundary[current]-{previous}))
        loops.append(loop)
    if len(loops) != 2:
        raise ValueError("Expected the skirt's waist and hem boundaries")
    waist = max(loops, key=lambda ids: sum(points[i][1] for i in ids)/len(ids))
    waist_length = sum(math.dist(points[a], points[b]) for a, b in zip(waist, waist[1:]+waist[:1]))
    return {"properBodyTrianglePairs": crossing_count(body, points, indices),
            "vertices": body.classify(points), "triangleCentroids": body.classify(centroids),
            "waistBoundaryPolylineMeters": waist_length,
            "clothEdgesManifoldAndOriented": True, "boundaryLoops": 2}


def source_metrics(document):
    if document.get("properties", {}).get("units_in_meter", 100) != 100:
        raise ValueError("This source comparison requires explicit centimetre pattern units")
    panels = document["pattern"]["panels"]
    has_arcs = any(e.get("curvature") for p in panels.values() for e in p["edges"])
    waist = hem = area = 0.0
    lengths = []
    for p in panels.values():
        vertices = p["vertices"]
        if has_arcs:
            arcs = [e for e in p["edges"] if e.get("curvature", {}).get("type") == "circle"]
            if len(arcs) != 2:
                raise ValueError("Expected two annular-sector boundary arcs")
            arcs.sort(key=lambda e: e["curvature"]["params"][0])
            measured = []
            for edge in arcs:
                a, b = [vertices[i] for i in edge["endpoints"]]
                radius, large, _ = edge["curvature"]["params"]
                angle = 2*math.asin(min(1, math.dist(a,b)/(2*radius)))
                if large:
                    angle = 2*math.pi-angle
                measured.append((radius, angle))
            (inner, angle), (outer, other_angle) = measured
            if abs(angle-other_angle) > 1e-7:
                raise ValueError("Annular arcs are not concentric sector measures")
            waist += inner*angle; hem += outer*angle
            area += 0.5*angle*(outer*outer-inner*inner)
            lengths.append(outer-inner)
        else:
            low, high = min(v[1] for v in vertices), max(v[1] for v in vertices)
            lengths.append(high-low)
            for edge in p["edges"]:
                a, b = [vertices[i] for i in edge["endpoints"]]
                if edge.get("label") == "lower_interface": waist += math.dist(a,b)
                if abs(a[1]-low)<1e-8 and abs(b[1]-low)<1e-8: hem += math.dist(a,b)
            area += abs(sum(a[0]*b[1]-a[1]*b[0]
                            for a,b in zip(vertices,vertices[1:]+vertices[:1])))/2
    if max(lengths)-min(lengths) > 1e-7:
        raise ValueError("Source front/back lengths differ")
    return {"garmentStyle": "SkirtCircle" if has_arcs else "Skirt2",
            "lengthLabel": "径向裙长" if has_arcs else "垂直裙长",
            "waistCM": waist, "hemCM": hem, "lengthCM": lengths[0], "analyticAreaCM2": area}


def compare_geometry(actual, expected):
    a, b = actual["pattern"], expected["pattern"]
    if set(a["panels"]) != set(b["panels"]) or a["stitches"] != b["stitches"]:
        raise ValueError("Source panel or stitch identities changed")
    differences = [0.0]
    for name in b["panels"]:
        p, q = a["panels"][name], b["panels"][name]
        if len(p["vertices"]) != len(q["vertices"]) or len(p["edges"]) != len(q["edges"]):
            raise ValueError("Source boundary topology changed")
        differences += [abs(x-y) for v,w in zip(p["vertices"],q["vertices"]) for x,y in zip(v,w)]
        for e,f in zip(p["edges"],q["edges"]):
            if e["endpoints"] != f["endpoints"] or e.get("label") != f.get("label"):
                raise ValueError("Source edge role changed")
            c, d = e.get("curvature"), f.get("curvature")
            if c is None or d is None:
                if c != d: raise ValueError("Source curve type changed")
            else:
                if c["type"] != d["type"] or c["params"][1:] != d["params"][1:]:
                    raise ValueError("Source circle orientation changed")
                differences.append(abs(c["params"][0]-d["params"][0]))
    maximum = max(differences)
    if maximum >= 1e-7:
        raise ValueError(f"Source geometry changed by {maximum} cm")
    return maximum


def field_proof():
    resources = ROOT / "TrailorAss/Resources"
    provenance = read_json(resources/"GarmentCodeStandardBodySource.json")
    asset = read_json(resources/"GarmentCodeStandardBody.json")
    grid = asset["collisionGrid"]
    if grid["dimensions"] != [128,181,65] or grid["origin"] != [-0.6337,-1.1137,-0.3037] or grid["spacing"] != 0.01:
        raise ValueError("Full-body collision-grid assumptions changed")
    field = (resources/grid["filename"]).read_bytes()
    if len(field) != 128*181*65*4:
        raise ValueError("Unexpected full-body field byte count")
    high = [grid["origin"][k]+grid["spacing"]*(grid["dimensions"][k]-1) for k in range(3)]
    if not all(all(grid["origin"][k] < p[k] < high[k] for k in range(3)) for p in asset["positions"]):
        raise ValueError("A visible body vertex lies outside the declared full grid")
    if hashlib.sha256(field).hexdigest() != provenance["collisionFieldSHA256"]:
        raise ValueError("Full-body field provenance hash mismatch")
    if digest(resources/"GarmentCodeStandardBody.json") != provenance["derivedMeshSHA256"]:
        raise ValueError("Body resource provenance hash mismatch")
    legacy = b"".join(field[((z*181+y)*128)*4:((z*181+y)*128+128)*4]
                       for z in range(65) for y in range(133))
    expected = "81251419a12a69de9946e8d85237a5ff77fe8c5775c992360e8b8878ca9d9172"
    if hashlib.sha256(legacy).hexdigest() != expected or provenance["collisionCoverage"]["oddRayRows"] != 0:
        raise ValueError("Legacy lower-grid or full-grid sign preprocessing changed")
    return {"dimensions": grid["dimensions"], "origin": grid["origin"], "spacingMeters": 0.01,
            "sampleMaximumY": 0.6863, "visibleHeadMaximumY": max(p[1] for p in asset["positions"]),
            "fieldBytes": len(field), "fieldSHA256": provenance["collisionFieldSHA256"],
            "legacyLowerFloatCount": 128*133*65, "legacyLowerSHA256": expected,
            "legacyLowerHashMatches": True, "oddRayRows": 0,
            "allVisibleVerticesInsideGridBounds": True,
            "bodyResourceSHA256": provenance["derivedMeshSHA256"],
            "provenanceSHA256": digest(resources/"GarmentCodeStandardBodySource.json")}


def replace_once(page, old, new):
    if page.count(old) != 1:
        raise ValueError("Existing viewer marker changed: "+old[:70])
    return page.replace(old, new)


def make_html(template, cases, proof, stamp):
    page = template.replace("圆裙离线 3D · 实际输出与官方参照", "人体表面接触 · 实际结果与旧版对照")
    page = page.replace("圆裙，从裁片到成衣", "把人体面片穿插纳入检查")
    page = page.replace("圆裙试验方案", "实际输出与旧版对照").replace("实际圆裙三维网格", "实际裙装三维网格")
    page = page.replace("腰弧总长", "原纸样腰口总长").replace("裁片径向裙长", '<span id="length-label">裁片长度</span>').replace("下摆弧长", "原纸样下摆总长")
    page = replace_once(page, '<p class="intro">左侧显示当前计算链实际导出的三维网格，可以旋转检查接缝和垂坠；右侧是官方公开效果图。这里记录的是实验结果，尚未证明与 GarmentCode 的三维仿真一致。</p>',
        '<p class="intro">8 组当前真实输出通过原有质量门槛，并增加可见人体三角面检查。旧版双片裙的 130 对人体交叉已降为 0；下方保留原始旧网格，可切换检查。三维效果仍是数值实验，尚未证明与 GarmentCode 仿真等价。</p>')
    page = page.replace("下列腰弧、下摆与面积来自裁片参考几何，不能当作垂坠后投影测量。",
        "腰口、裁片长度、下摆和面积来自原纸样；模拟腰口折线长是另一项三维测量，可能包含支撑预应变。")
    page = replace_once(page, '<p class="sub" id="source"></p>',
        '<div class="metric-grid"><div><div class="metric-value" id="support-waist"></div><div class="metric-label">参考人体腰围<small>cm</small></div></div><div><div class="metric-value" id="gather"></div><div class="metric-label">原纸样抽褶倍率</div></div><div><div class="metric-value" id="waist-polyline"></div><div class="metric-label">模拟腰口折线长<small>cm · 含支撑预应变</small></div></div></div><p class="sub" id="source"></p>')
    page = replace_once(page, '<li><span>末态近距离面接触对数</span><strong id="surface-near-pairs"></strong></li>',
        '<li><span>末态近距离布片接触对数</span><strong id="surface-near-pairs"></strong></li><li><span>独立复核：布片／人体真实交叉对数</span><strong id="body-crossings"></strong></li><li><span>实际人体体积内的顶点／面中心</span><strong id="volume-inside"></strong></li><li><span>三轴体积检查模糊点</span><strong id="volume-ambiguous"></strong></li><li><span>人体三角面接触目标间隙</span><strong id="mesh-target"></strong></li><li><span>SDF 顶点投影目标间隙</span><strong id="sdf-target"></strong></li><li><span>固定腰口支撑目标间隙</span><strong id="waist-target"></strong></li>')
    page = replace_once(page, '<a class="download" id="download" href="#" download>下载当前网格 JSON ↗</a>',
        '<span><a class="download" id="download" href="#" download>网格 JSON ↗</a> · <a class="download" id="pattern-download" href="#" download>原纸样 JSON ↗</a></span>')
    page = replace_once(page, "el('status').textContent=d.converged?'达到当前收敛门槛 · 实验仿真':'未达到收敛门槛 · 仅供检查装配';",
        "const current=item.kind==='current';el('status').textContent=current?'达到当前复合门槛 · 实验仿真':'历史结果 · 新增人体面检查不通过';")
    page = replace_once(page, "el('status').classList.toggle('good',d.converged);el('download').href='generated/'+item.filename;",
        "el('status').classList.toggle('good',current&&d.converged);el('download').href='generated/'+item.filename;el('pattern-download').href='generated/'+item.filename.replace('-mesh.json','-pattern.json');")
    page = replace_once(page, "el('length').textContent=fmt(d.radialLengthMeters*100);",
        "el('length').textContent=fmt(d.patternLengthMeters*100);el('length-label').textContent='裁片'+d.patternLengthLabel;el('support-waist').textContent=fmt(d.supportWaistCircumferenceMeters*100);el('gather').textContent=fmt(d.waistGatherRatio,2)+' 倍';el('waist-polyline').textContent=fmt(item.analysis.waistBoundaryPolylineMeters*100);")
    page = replace_once(page, "el('converged').textContent=d.converged?'是':'否';el('converged').classList.toggle('danger',!d.converged);",
        "el('converged').textContent=current&&d.converged?'是':'历史旧门槛通过；新增检查失败';el('converged').classList.toggle('danger',!current||!d.converged);")
    page = replace_once(page, "el('strain').textContent=fmt(d.maxEdgeStrain*100)+'%';",
        "el('strain').textContent=fmt(d.maxEdgeStrain*100,4)+'%';")
    page = replace_once(page, "el('source').textContent='数据：'+item.filename+' · SHA-256 '+item.sha256.slice(0,16)+'…';",
        "const a=item.analysis;el('body-crossings').textContent=fmt(a.properBodyTrianglePairs,0);el('body-crossings').classList.toggle('danger',a.properBodyTrianglePairs>0);el('volume-inside').textContent=a.vertices.inside+' / '+a.triangleCentroids.inside;el('volume-ambiguous').textContent=a.vertices.ambiguous+a.triangleCentroids.ambiguous;el('mesh-target').textContent=current?mm(d.bodySurfaceClearanceMeters):'旧版未启用';el('sdf-target').textContent='2.50 mm';el('waist-target').textContent=current?mm(d.waistSupportClearanceMeters):'旧版无此目标';el('source').textContent='数据：'+item.filename+' · SHA-256 '+item.sha256.slice(0,16)+'…';")
    baseline = re.compile(r'<p>可复现的官方圆裙基线：.*?</p>')
    if len(baseline.findall(page)) != 1: raise ValueError("Existing baseline paragraph changed")
    page = baseline.sub('<p>二维输入对照固定 GarmentCode 提交 d4496299：默认双片裙和默认四分之三圆裙均与官方 fixture 对照，端点、圆弧半径及接缝语义通过。其他方案另与各自旧源纸样比较。源数据未因新增接触而改写；这不构成官方最终三维成衣的误差比较。</p>', page)
    rows = []
    for tag, _ in CASES:
        item = cases[tag]; d = item["mesh"]["diagnostics"]; a = item["analysis"]
        rows.append(f'<tr><td>{html.escape(item["label"])}</td><td>{d["maxEdgeStrain"]*100:.4f}%</td><td>{a["properBodyTrianglePairs"]}</td><td>{a["vertices"]["inside"]} / {a["triangleCentroids"]["inside"]}</td><td>{d["computationSeconds"]:.2f} s</td></tr>')
    section = '''<section class="panel method"><h3>同一人体、同一原纸样：旧版与本版</h3>
<p>独立三角面复核：旧版 <strong>130 对</strong>真实人体交叉 → 本版默认双片裙 <strong>0 对</strong>。旧版所有顶点都在人体外，但有 <strong>4 个面中心在人体内</strong>；本版 8 组的顶点和面中心均在外，三轴无分歧或模糊点。这是离散几何复核，不是连续碰撞或真实合体度保证。</p>
<div style="display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px"><figure style="margin:0"><img style="width:100%" src="generated/before-skirt2-focus.png" alt="旧版实际网格，同一固定相机的正侧背放大"><figcaption class="sub">旧版 · 真实网格 · 130 对人体交叉，4 个面中心在内</figcaption></figure><figure style="margin:0"><img style="width:100%" src="generated/skirt2-default-focus.png" alt="新版实际网格，同一固定相机的正侧背放大"><figcaption class="sub">本版 · 真实网格 · 人体交叉为 0，采样体积内点为 0</figcaption></figure></div>
<p>放大图共用相机、米制坐标与绘制方式，只改变观察范围；没有改写、缩放或修补网格。可在上方方案中切换旧版进行三维检查。</p>
<h3>本批 8 组当前输出</h3><table><thead><tr><th>方案</th><th>最大源边应变</th><th>人体交叉</th><th>体积内顶点／面中心</th><th>Mac 导出耗时</th></tr></thead><tbody>'''+"".join(rows)+'''</tbody></table>
<p>全部保持原门槛：应变 &lt;8%，持续运动检查 &lt;0.025 m/s，SDF 顶点穿入估计 &lt;3 mm，布片自交与真实人体三角面交叉均为 0。接缝间距为 0 来自共享自由度，不是对照官方模型的精度。</p>
<h3>三个数值目标，不能混作物理精度</h3><p>人体网格接触目标 <strong>0.50 mm</strong>；SDF 顶点投影目标 <strong>2.50 mm</strong>；腰口支撑目标 <strong>5.00 mm</strong>。它们是不同约束的数值间隙目标，未标定为面料厚度，也不保证末态所有位置均达到相同最小间隙。交叉分类容差为 <strong>1e−7 m</strong>，只用于区分真实穿过、切触与共面接触，不能解释为物理精度。</p>
<p>人体场扩展为 <strong>128×181×65</strong>，覆盖完整可见人体；全部 <strong>1,106,560</strong> 个旧下半身浮点样本的字节哈希保持一致。可见人体形状未改变。关闭新功能的旧圆裙与旧双片裙通过顶点数组完全相等回归，最大位置差为 0。</p>
<p>本页是经过验证的分支快照合并：五组双片裙沿用圆裙专属支撑修复前已经通过的数据；圆裙三组及旧版对照在该修复后重新通过。没有宣称 8 组来自同一次最终运行；各文件来源见原始合并汇总。</p>
<p>实际三视图：<a href="generated/skirt2-default-views.png">默认双片裙 ↗</a> · <a href="generated/skirt2-flare10-views.png">裙摆增量 10 cm ↗</a> · <a href="generated/circle-0.75-views.png">四分之三圆裙 ↗</a>。<a href="comparison.json">几何与文件校验 ↗</a> · <a href="generated/body-surface-summary.json">合并运行来源 ↗</a> · <a href="generated/independent-geometry.json">独立几何复核 ↗</a> · <a href="generated/field-coverage-proof.json">全身场与旧样本证明 ↗</a></p></section>'''
    page = replace_once(page, '<section class="panel method"><h3>如何读这份对比</h3>', section+'<section class="panel method"><h3>如何读这份对比</h3>')
    options = "".join(f'<option value="{html.escape(k)}">{html.escape(v["label"])}</option>' for k,v in cases.items())
    payload = json.dumps(cases, ensure_ascii=False, separators=(",",":"), allow_nan=False)
    payload = payload.replace("<","\\u003c").replace("\u2028","\\u2028").replace("\u2029","\\u2029")
    return (page.replace("__CASE_OPTIONS__",options).replace("__DATA__",payload)
            .replace("__GENERATED_AT__",stamp.strftime("%Y-%m-%d %H:%M:%S（北京时间，UTC+08:00）")))


def source_note(proof):
    return f'''# 人体表面接触：证据、数值目标与限制

此报告为私有离线研究预览；所有网格、JSON 和 OBJ 均为实际求解输出。图片为网格栅格化，不是 App 截图。当前八组数据逐项通过源尺寸、质量门槛与独立几何复核。

## 真实改变与独立对照

人体闭合网格和源纸样不变。新增检查覆盖布片与可见人体三角面的真实穿过，补足原先仅检查布片顶点的不足。旧默认双片裙有 130 对人体三角面交叉；其 624 个顶点均在人体外，仍有 4 个三角面中心在人体内。本版同款为 0 对交叉、0 个采样体积内点。

独立交叉复核使用六条边与对面三角形的 Möller–Trumbore 求交，与生产模块的两平面切线区间方法不同。双方使用 1e−7 m 的空间分类容差区分 proper crossing 与切触／孤立接触；共面接触不计为真实穿过。该容差不是物理误差界。

独立体积复核使用实际闭合人体三角形，分别沿 +X、+Y、+Z 射线计数；不读取 SDF，也不调用生产接触代码。轴向分歧、原点近表面与混合方向切触射线分别标为模糊，不强行归为外部。本批八组顶点和面中心均在外，模糊点为 0。有限采样不能单独证明整张连续曲面无穿插，因此与完整三角面求交联合报告，且仍不保证整个运动过程无穿透。

## 三个明确的数值假设

| 约束 | 目标 |
| --- | ---: |
| 可见人体三角面接触 | 0.50 mm |
| SDF 顶点投影 | 2.50 mm |
| 固定腰口支撑 | 5.00 mm |

这些是数值间隙目标，不是实测面料厚度或末态最小间隙证书。腰口有固定支撑；圆裙清距轮廓按弧长重采样以避免非均匀支撑预应变，仍以原平面纸样作为静止尺寸。双片裙保留原腰口总边长、抽褶与真实三角网格边约束；没有通过改小衣服、放大人体或降低 8% 源边应变门槛取得通过。

## 全身场与不可变证据

同一 MakeHuman CC0 标准人体保留 13,380 顶点、26,756 三角形。全场 128×181×65，共 {proof['fieldCoverage']['fieldBytes']} 字节；采样上界 Y=0.6863 m，高于可见头顶 Y=0.632175 m。全部旧 128×133×65 下半身样本按新 Z 跨距提取后哈希仍为 `81251419a12a69de9946e8d85237a5ff77fe8c5775c992360e8b8878ca9d9172`；预处理奇数射线数为 0。人体场增加覆盖，没有新增个人人体拟合。

完整新场 SHA-256：`{proof['fieldCoverage']['fieldSHA256']}`。旧版与所有当前输出中的可见人体坐标、三角面完全相同；各原始网格哈希与独立体积数据见 `comparison.json`、`generated/independent-geometry.json`。关闭新功能时，旧圆裙与旧双片裙的顶点数组完全相等，相关回归断言及源文件哈希列于对照记录。

当前报告来自经过验证的分支快照合并。五组双片裙在圆裙专属支撑修复前已经通过并保留原文件；该修复未改动双片裙分支。三组圆裙与关闭新功能的两项原始位置对照在修复后重跑通过。`generated/body-surface-summary.json` 保留真实来源、原运行中的排除失败项及逐案例证明，未伪称一次全量最终运行。

## 官方二维输入与视觉参照

二维源对照锁定 [GarmentCode 提交 d4496299](https://github.com/maria-korosteleva/GarmentCode/tree/{COMMIT})，默认人体与设计。默认 Skirt2 与默认 SkirtCircle 的端点／圆弧半径最大差分别为 {proof['officialSourceOracles']['Skirt2']['maximumDeltaCM']:.3g}／{proof['officialSourceOracles']['SkirtCircle']['maximumDeltaCM']:.3g} cm，接缝语义一致。其余方案逐项与此前相同参数的源纸样比较。圆弧网格参考面积允许小于 0.1% 的离散化差，直线双片裙面积直接对照多边形解析面积；布料质量按实际参考三角面积计算。

保留的两张原图来自既有报告，未裁切或改绘：GarmentCode [官方款式群像](https://github.com/maria-korosteleva/GarmentCode/blob/main/assets/img/header.png)，Maria Korosteleva 等，仓库 MIT；Design2GarmentCode [官方文字生成结果](https://style3d.github.io/design2garmentcode/static/images/result_text.png)，Feng Zhou 等，官网 CC BY-SA 4.0。后者左侧是该方法、右侧是 DressCode 对照，不能误标。来源、素材许可另见项目 `THIRD_PARTY_NOTICES.md`。

两张公开图的人体、款式、面料、相机均未与本批对齐；[Design2GarmentCode 的实现](https://github.com/Style3D/design2garmentcode-impl#3-optional-enable-3-d-simulation)使用 GarmentCode 的定制 Warp 仿真器，并非第二个独立物理后端。尚缺同输入官方最终三维网格，不能声明三维等价。本项目没有引入受限 Warp 代码作为产品依赖。

三档面料仍为未标定实验预设；人体仍为标准模板的有限尺寸拟合，不能判断个人真实合体度。耗时来自 Mac 命令行而非 iPhone 实测。本次只做数据、源码、哈希、JavaScript 与实际 PNG 检查；遵守内置浏览器本地文件安全限制，没有自动打开或改走其他浏览器／服务。
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir",type=Path,default=Path("/private/tmp/TailorAssBodySurfaceFinal"))
    parser.add_argument("--output-dir",type=Path,default=DEFAULT_REPORT)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if output in {p.resolve() for p in (OLD_SKIRT,OLD_CIRCLE,REPORTS/"2026-10-25-3d")}:
        raise SystemExit("Use a NEW body-surface report folder; old snapshots are immutable")
    summary = read_json(args.input_dir/"body-surface-summary.json")
    required = {tag for tag,_ in CASES}|{"flag-off-reference"}
    if summary.get("passed") is not True or not required.issubset(summary.get("executed",[])):
        raise ValueError("All eight cases and the exact flag-off control must pass before publication")
    if not summary.get("sourceRuns") or len(summary.get("caseProvenance",[])) != 8:
        raise ValueError("Merged snapshot needs explicit source-run provenance")
    if summary.get("numericalMarginsMeters") != {"exactMesh":0.0005,"sampledSDF":0.0025,"fixedWaistSupport":0.005}:
        raise ValueError("Numerical contact assumptions changed; update report deliberately")
    viewer = runpy.run_path(str(TESTS/"render-cloth-report.py"))
    old_path = OLD_SKIRT/"generated/skirt2-default-mesh.json"
    old = read_json(old_path)
    body = IndependentBody(old["mannequinPositions"],old["mannequinTriangleIndices"])
    old_analysis = inspect_mesh(old,body)
    if old_analysis["properBodyTrianglePairs"] != 130 or old_analysis["triangleCentroids"]["inside"] != 4:
        raise ValueError("Historical 130-pair / four-centroid evidence changed")
    cases = {}; analyses = {}; sources = {}
    for tag,title in CASES:
        path = args.input_dir/f"{tag}-mesh.json"; mesh=read_json(path); d=mesh["diagnostics"]
        viewer["validate_mesh"](mesh,path.name)
        if mesh["mannequinPositions"] != old["mannequinPositions"] or mesh["mannequinTriangleIndices"] != old["mannequinTriangleIndices"]:
            raise ValueError("Visible body changed; cannot call this a same-body comparison")
        if d != read_json(args.input_dir/f"{tag}-diagnostics.json"):
            raise ValueError("Raw diagnostic snapshot does not match the mesh")
        if not (d["converged"] and d["maxEdgeStrain"]<.08 and d["maxSpeedMetersPerSecond"]<.025 and d["maxBodyPenetrationMeters"]<.003 and d["surfaceIntersectionCount"]==0 and d["bodySurfaceIntersectionCount"]==0 and d["maxSeamGapMeters"]==0):
            raise ValueError(f"{tag}: unchanged quality gates did not pass")
        if d.get("bodySurfaceClearanceMeters") != .0005 or d.get("waistSupportClearanceMeters") != .005:
            raise ValueError(f"{tag}: missing explicit clearance targets")
        document = read_json(args.input_dir/f"{tag}-pattern.json"); measured=source_metrics(document)
        if d.get("garmentStyle") != measured["garmentStyle"] or d.get("patternLengthLabel") != measured["lengthLabel"]:
            raise ValueError("Mixed styles lost radial/vertical length semantics")
        for key,value in (("waistCircumferenceMeters",measured["waistCM"]/100),("hemCircumferenceMeters",measured["hemCM"]/100),("patternLengthMeters",measured["lengthCM"]/100)):
            if abs(d[key]-value)>1e-8:raise ValueError(f"{tag}: source measure {key} changed")
        area_error=abs(d["referenceAreaSquareMeters"]*10000-measured["analyticAreaCM2"])/measured["analyticAreaCM2"]
        if area_error >= (.001 if measured["garmentStyle"]=="SkirtCircle" else 1e-8):
            raise ValueError("Reference area no longer agrees with source geometry")
        density=.12 if tag.endswith("soft") else (.28 if tag.endswith("firm") else .18)
        if abs(d["totalFabricMassKg"]-d["referenceAreaSquareMeters"]*density)>1e-10:
            raise ValueError("Reference area mass changed")
        baseline=(OLD_CIRCLE if tag.startswith("circle") else OLD_SKIRT)/"generated"/f"{tag}-pattern.json"
        delta=compare_geometry(document,read_json(baseline))
        analysis=inspect_mesh(mesh,body)
        if analysis["properBodyTrianglePairs"] != d["bodySurfaceIntersectionCount"]:
            raise ValueError("Independent proper-crossing oracle disagrees")
        if any(analysis[k]["inside"] or analysis[k]["ambiguous"] for k in ("vertices","triangleCentroids")):
            raise ValueError("Volume verification needs review; do not silently call ambiguous samples outside")
        analyses[tag]=analysis
        sources[tag]={"sourceMetrics":measured,"flatAreaRelativeError":area_error,"previousSourceMaximumDeltaCM":delta,"patternSHA256":digest(args.input_dir/f"{tag}-pattern.json")}
        cases[tag]={"kind":"current","label":title+" · "+d["materialName"],"filename":path.name,"sha256":digest(path),"mesh":mesh,"analysis":analysis}
        print(f"Verified {tag}: independent body cuts 0, volume samples outside, source area/rest metadata and gates pass",flush=True)
    cases["before-skirt2"]={"kind":"historical","label":"旧版双片裙 · 130 对人体交叉","filename":"before-skirt2-default-mesh.json","sha256":digest(old_path),"mesh":old,"analysis":old_analysis}
    oracles={}
    for style,tag,fixture in (("Skirt2","skirt2-default","skirt-two-panel.json"),("SkirtCircle","circle-0.75","skirt-circle.json")):
        path=TESTS/"Fixtures"/fixture
        oracles[style]={"fixtureSHA256":digest(path),"maximumDeltaCM":compare_geometry(read_json(args.input_dir/f"{tag}-pattern.json"),read_json(path)),"stitchSemanticsEqual":True}
    kernel_path=ROOT/"TrailorAss/Models/GarmentCodeCircleDrape.swift"
    if "let dt=1.0/120, thickness=0.0025" not in kernel_path.read_text():
        raise ValueError("SDF vertex-target assumption needs an explicit report update")
    proof={"sourceCommit":COMMIT,"mergedSnapshotProvenance":summary,"sourceChecks":sources,"officialSourceOracles":oracles,"fieldCoverage":field_proof(),"properCrossClassificationEpsilonMeters":EPS,"numericalTargetsMeters":summary["numericalMarginsMeters"],"beforeAfter":{"oldProperBodyPairs":130,"newProperBodyPairs":0,"oldInsideCentroids":4,"newInsideCentroids":0,"oldMeshSHA256":digest(old_path),"newDefaultMeshSHA256":cases["skirt2-default"]["sha256"]},"flagOffControl":{"exactPositionEqualityPassed":True,"maximumPositionDeltaMeters":0,"evidence":"Latest passed flag-off-reference selector asserts complete vertex-array equality for both old circle and standard-body Skirt2; no separate current raw flag-off mesh was exported.","harnessSHA256":digest(TESTS/"ClothBodySurface.swift"),"circleBaselineSHA256":digest(REPORTS/"2026-10-25-3d/generated/circle-0.75-mesh.json"),"skirtBaselineSHA256":digest(old_path)},"sourceCodeSHA256":{p.name:digest(p) for p in (kernel_path,ROOT/"TrailorAss/Models/GarmentCodeSkirtDrape.swift",ROOT/"TrailorAss/Models/GarmentCodeBodySurfaceContact.swift",Path(__file__))},"officialFinal3DMeshAvailable":False}
    body_bytes=json.dumps({"p":body.p,"t":old["mannequinTriangleIndices"]},separators=(",",":")).encode()
    proof["sameVisibleBodyGeometry"]={"exactlyEqualAcrossBeforeAndAllCurrent":True,"canonicalGeometrySHA256":hashlib.sha256(body_bytes).hexdigest(),"vertexCount":len(body.p),"triangleCount":len(body.tris),"closedManifoldVerified":True,"signedVolumeM3":body.volume}
    output.mkdir(parents=True,exist_ok=True); generated=output/"generated";generated.mkdir(exist_ok=True)
    for tag,_ in CASES:
        for suffix in ("-mesh.json","-pattern.json","-diagnostics.json",".obj"):
            shutil.copyfile(args.input_dir/(tag+suffix),generated/(tag+suffix))
    shutil.copyfile(args.input_dir/"body-surface-summary.json",generated/"body-surface-summary.json")
    shutil.copyfile(old_path,generated/"before-skirt2-default-mesh.json")
    shutil.copyfile(OLD_SKIRT/"generated/skirt2-default-pattern.json",generated/"before-skirt2-default-pattern.json")
    write_json(generated/"independent-geometry.json",{"method":"Actual closed-body +X/+Y/+Z parity and independent six-edge/triangle proper-crossing oracle; no production contact or SDF calls.","epsilonMeters":EPS,"before":old_analysis,"current":analyses})
    write_json(generated/"field-coverage-proof.json",proof["fieldCoverage"])
    for name,expected in (("garmentcode-header.png","e3cd112937455057f16e3405d5f6c67380d6622cb2ee4b6d978c1c16d284855c"),("design2garmentcode-result-text.png","3332c598b4901683d1b197a60bd6721946b4b7c8df34f351dca4658c5fc7c787")):
        source=OLD_CIRCLE/"references"/name
        if digest(source)!=expected:raise ValueError("Unmodified official reference image hash changed")
        (output/"references").mkdir(exist_ok=True);shutil.copyfile(source,output/"references"/name)
    renderer=runpy.run_path(str(TESTS/"render-cloth-preview.py"))
    for tag in ("skirt2-default","skirt2-flare10","circle-0.75"):
        renderer["render"](generated/f"{tag}-mesh.json",generated/f"{tag}-views.png")
    focus=inspect.getsource(renderer["render"])
    focus=replace_once(focus,"def render(mesh_path, output_path):","def render_focus(mesh_path, output_path):")
    focus=replace_once(focus,"center_y = (low+high)/2","center_y = -0.22")
    focus=replace_once(focus,"scale = min(520, (height-90)/max(0.1, high-low))","scale = 1200.0")
    exec(focus,renderer)
    renderer["render_focus"](generated/"before-skirt2-default-mesh.json",generated/"before-skirt2-focus.png")
    renderer["render_focus"](generated/"skirt2-default-mesh.json",generated/"skirt2-default-focus.png")
    stamp=datetime.datetime.now(ZoneInfo("Asia/Shanghai"));proof["generatedAt"]=stamp.isoformat(timespec="seconds")
    proof["generatedFileSHA256"]={p.name:digest(p) for p in sorted(generated.iterdir()) if p.is_file()}
    write_json(output/"comparison.json",proof)
    (output/"reference-sources.md").write_text(source_note(proof))
    (output/"index.html").write_text(make_html(viewer["HTML"],cases,proof,stamp))
    print(f"Built NEW eight-case body-surface report: {output/'index.html'}")


if __name__=="__main__":
    main()

