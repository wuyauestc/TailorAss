#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build a NEW static report from actual separate-particle waistband solves.

No simulation, browser automation, network request, or old-report rewrite is
performed here. All geometry views rasterize the actual exported coordinates.
"""
import argparse
import collections
import datetime
import hashlib
import html
import json
import math
from pathlib import Path
import runpy
from zoneinfo import ZoneInfo

ROOT=Path(__file__).resolve().parents[2]
TESTS=ROOT/'Tests/NativePattern'
REPORTS=TESTS/'Reports'
DEFAULT_REPORT=REPORTS/'2026-10-25-waistband-sewn'
CASES=[('straightwb-default','直腰头 · 默认','StraightWB',0),
       ('straightwb-free-bottom-2mm','直腰头 · 下缘接缝扰动 2 mm','StraightWB',.002),
       ('fittedwb-default','弧形腰头 · 默认','FittedWB',0),
       ('fittedwb-free-bottom-2mm','弧形腰头 · 下缘接缝扰动 2 mm','FittedWB',.002)]
SUFFIXES=['-mesh.json','-diagnostics.json','-source.json','-plan.json','-reference.json','-acceptance.json']


def read(path):return json.loads(path.read_bytes())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write(path,value):path.write_text(json.dumps(value,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
def xyz(p):return tuple(p[k] for k in ('x','y','z'))
def close(a,b,tolerance=1e-12):
    if not math.isfinite(a) or not math.isfinite(b) or abs(a-b)>tolerance:raise ValueError(f'Measurement mismatch {a} versus {b}')
def fmt(v,digits=3):return f'{v:.{digits}f}'
def point(attachment,positions):
    ids,weights=attachment['vertexIDs'],attachment['weights']
    if not 1<=len(ids)<=2 or len(ids)!=len(weights) or len(set(ids))!=len(ids) or any(not 0<=i<len(positions) for i in ids) or any(not math.isfinite(w) or not 0<=w<=1 for w in weights):raise ValueError('Invalid actual seam attachment')
    close(sum(weights),1)
    return tuple(math.fsum(positions[i][k]*w for i,w in zip(ids,weights)) for k in ('x','y','z'))


def source_point(panel,edge,t):
    a,b=[panel['vertices'][i] for i in edge['endpoints']]
    c=edge.get('curvature')
    if not c:return tuple((a[k]+(b[k]-a[k])*t)/100 for k in range(2))+(0,)
    if c['type']!='circle':raise ValueError('This report only covers the real rectangle/annular-sector WB families')
    radius,large,right=c['params'];dx,dy=b[0]-a[0],b[1]-a[1];chord=math.hypot(dx,dy)
    radius=max(radius,chord/2);h=math.sqrt(max(0,radius*radius-chord*chord/4));sign=-1 if bool(large)==bool(right) else 1
    center=((a[0]+b[0])/2-dy/chord*h*sign,(a[1]+b[1])/2+dx/chord*h*sign)
    first=math.atan2(a[1]-center[1],a[0]-center[0]);last=math.atan2(b[1]-center[1],b[0]-center[0]);delta=last-first
    if right:
        while delta<0:delta+=2*math.pi
        while delta>=2*math.pi:delta-=2*math.pi
    else:
        while delta>0:delta-=2*math.pi
        while delta<=-2*math.pi:delta+=2*math.pi
    if (abs(delta)>math.pi)!=bool(large):delta+=-2*math.pi if right else 2*math.pi
    return ((center[0]+radius*math.cos(first+delta*t))/100,(center[1]+radius*math.sin(first+delta*t))/100,0)


def check_case(tag,style,perturb,mesh,reference,plan,source,acceptance,body,geometry,helpers):
    n=len(mesh['positions']);points=[xyz(p) for p in mesh['positions']];flat=[xyz(p) for p in reference['positions']]
    indices=mesh['triangleIndices'];rest_indices=reference['triangleIndices'];d=mesh['diagnostics']
    if n!=d['vertexCount'] or len(indices)//3!=d['triangleCount']:raise ValueError('Actual mesh counts differ from diagnostics')
    if reference['sourceToSimulation']!=list(range(n)) or len(flat)!=n or len(indices)!=len(rest_indices):raise ValueError('Source particles were welded or omitted')
    adjacency=collections.defaultdict(set);edge_uses=collections.Counter();edges=set();area=0.0
    for t in range(0,len(rest_indices),3):
        ids=rest_indices[t:t+3]
        if set(ids)!=set(indices[t:t+3]) or len(set(ids))!=3:raise ValueError('Actual face differs from its original paper face')
        a,b,c=[flat[i] for i in ids];cross=(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
        if cross<=0 or any(abs(p[2])>1e-12 for p in (a,b,c)):raise ValueError('Reference paper is flipped or non-planar')
        area+=cross/2
        for a,b in zip(ids,ids[1:]+ids[:1]):
            edges.add(tuple(sorted((a,b))));edge_uses[tuple(sorted((a,b)))]+=1;adjacency[a].add(b);adjacency[b].add(a)
    pending=set(range(n));components=[]
    while pending:
        todo=[min(pending)];component=set()
        while todo:
            i=todo.pop()
            if i not in pending:continue
            pending.remove(i);component.add(i);todo.extend(adjacency[i])
        components.append(component)
    if len(components)!=2:raise ValueError('Expected two independent source-panel particle components')
    panels=source['pattern']['panels'];panel_component={};seen_paths=set()
    for path in plan['allBoundaryPaths']:
        name,index=path['edge']['panelID'],path['edge']['edgeIndex'];key=(name,index)
        if key in seen_paths or name not in panels:raise ValueError('Missing or duplicate source boundary identity')
        seen_paths.add(key);component=next(c for c in components if path['vertexIDs'][0] in c)
        if not set(path['vertexIDs'])<=component:raise ValueError('Boundary crosses separate source particles')
        if name in panel_component and panel_component[name]!=component:raise ValueError('Panel particle component changed')
        panel_component[name]=component
        if len(path['vertexIDs'])!=len(path['sourceParameters']):raise ValueError('Invalid source parameter map')
        for i,t in zip(path['vertexIDs'],path['sourceParameters']):
            if math.dist(flat[i],source_point(panels[name],panels[name]['edges'][index],t))>1e-9:raise ValueError('Flat boundary is not the actual source curve')
    if seen_paths!={(name,i) for name,p in panels.items() for i in range(len(p['edges']))} or len(panel_component)!=2:raise ValueError('Incomplete original source boundaries')
    if panel_component['wb_front'] & panel_component['wb_back']:raise ValueError('Front/back source particles were merged')
    paper=helpers['source_metrics'](source,style)
    close(area,d['referenceAreaSquareMeters']);close(area*.18,d['totalFabricMassKg'])
    if abs(area-paper['analyticAreaSquareMeters'])>paper['sourcePerimeterMeters']*.00005+1e-9:raise ValueError('Paper area exceeds source curve flattening tolerance')
    strains=[abs(math.dist(points[a],points[b])/math.dist(flat[a],flat[b])-1) for a,b in edges]
    maximum=max(strains);close(maximum,d['maxEdgeStrain']);close(maximum,acceptance['maximumIndependentSourceEdgeStrain'])
    if plan['usesFiniteCoarseTacks'] or plan['foldIntervals']:raise ValueError('Default ordinary waistband was mislabeled as gathered')
    gaps=[]
    for c in plan['constraints']:
        if set(c['a']['vertexIDs']) & set(c['b']['vertexIDs']):raise ValueError('Seam zero was obtained by shared particles')
        if any('ordinary' not in origin['intent'] for origin in c['origins']):raise ValueError('Unsupported nonordinary seam intent')
        gaps.append(math.dist(point(c['a'],mesh['positions']),point(c['b'],mesh['positions'])))
    if len(gaps)!=6 or d['sewingConstraintCount']!=len(gaps):raise ValueError('Actual ordinary sewing constraints were omitted')
    gap=max(gaps);rms=math.sqrt(sum(v*v for v in gaps)/len(gaps))
    close(gap,d['maxSeamGapMeters']);close(rms,d['sewingRMSGapMeters']);close(gap,acceptance['finalActualAnchorGapMeters']);close(rms,acceptance['finalRMSAnchorGapMeters'])
    initial=max(c['initialGapMeters'] for c in plan['constraints']);close(initial,acceptance['initialActualAnchorGapMeters']);close(initial,perturb)
    if len(plan['ordinaryBoundaryIntervals'])!=4:raise ValueError('Ordinary side-seam polyline intervals are incomplete')
    interval_gap=0.0
    for interval in plan['ordinaryBoundaryIntervals']:
        for side in ('a','b'):
            segment=interval[side+'Segment'];a,b=segment['vertexIDs']
            if edge_uses[tuple(sorted((a,b)))]!=1:raise ValueError('Sewn contact interval is not on an actual source boundary')
            for end in ('Start','End'):
                if not set(interval[side+end]['attachment']['vertexIDs'])<=set(segment['vertexIDs']):raise ValueError('Ordinary interval leaves its declared segment')
        for end in ('Start','End'):
            interval_gap=max(interval_gap,math.dist(point(interval['a'+end]['attachment'],mesh['positions']),point(interval['b'+end]['attachment'],mesh['positions'])))
    close(interval_gap,gap)
    analysis=geometry['inspect_mesh'](mesh,body);analysis.pop('waistBoundaryPolylineMeters',None)
    if any(analysis[k]['inside'] or analysis[k]['ambiguous'] or analysis[k]['threeAxisDisagreement'] for k in ('vertices','triangleCentroids')):raise ValueError('Inside or ambiguous actual-body volume samples remain')
    if analysis['properBodyTrianglePairs']!=0 or acceptance['independentBodyTriangleCrossings']!=0 or d['bodySurfaceIntersectionCount']!=0:raise ValueError('Actual body face intersections remain')
    if not (d['converged'] and maximum<.08 and gap<.0005 and d['maxSpeedMetersPerSecond']<.025 and d['maxBodyPenetrationMeters']<.003 and d['surfaceIntersectionCount']==0):raise ValueError('A full unchanged quality gate failed')
    if acceptance['solverIterations']!=32 or d['sewingProjectionTravelBudgetMeters']!=.2 or d['sewingSingleProjectionLimitMeters']!=.02 or d['sewingUsesFiniteTacks']:raise ValueError('Actual recorded App configuration differs')
    if d['sourceStrainLimitFraction']!=.05 or d['sourceStrainLimitPassCount']!=40:raise ValueError('Source strain projection settings differ')
    for field,value in (('waistCircumferenceMeters',paper['topMeters']),('hemCircumferenceMeters',paper['bottomMeters']),('patternLengthMeters',paper['paperDepthMeters'])):close(d[field],value,1e-8)
    return {'source':paper,'independent':analysis,'separatePanelParticleComponents':2,'identitySourceMap':True,
        'sourceTriangleEdgeCount':len(edges),'referenceAreaSquareMeters':area,'independentMassKg':area*.18,
        'maximumIndependentSourceEdgeStrain':maximum,'actualInitialGapMeters':initial,'actualMaximumGapMeters':gap,
        'initialGapEvidence':'Swift initial-pose measurement in acceptance, cross-checked with the plan; full initial-pose coordinates are not exported',
        'finalGapEvidence':'Independently recomputed here from separate-particle barycentric attachments and final actual positions',
        'actualRMSGapMeters':rms,'ordinaryBoundaryIntervals':4,'polylineMaximumEndpointGapMeters':interval_gap,
        'sourcePanelParticleCounts':{name:len(c) for name,c in panel_component.items()},
        'sourceCase':{'solverIterations':32,'sourceStrainTarget':.05,'sourceStrainPasses':40,
                      'sewingAccumulatedConstraintPathPerVertexPerFrameMeters':.2,'sewingSingleCorrectionMeters':.02},
        'referenceToSimulationWelded':False,'verticalProjectionRangeMeters':max(p[1] for p in points)-min(p[1] for p in points)}


def obj(mesh,path,style):
    lines=['# Derived directly from the reported actual mesh; metres, +Y up; not a new simulation',
           'o '+('straight_waistband' if style=='StraightWB' else 'fitted_waistband')]
    for positions,indices,name in ((mesh['positions'],mesh['triangleIndices'],None),(mesh['mannequinPositions'],mesh['mannequinTriangleIndices'],'standard_mannequin')):
        if name:lines.append('o '+name)
        offset=0 if name is None else len(mesh['positions'])
        lines += ['v '+' '.join(repr(p[k]) for k in ('x','y','z')) for p in positions]
        lines += ['f '+' '.join(str(i+offset+1) for i in indices[t:t+3]) for t in range(0,len(indices),3)]
    path.write_text('\n'.join(lines)+'\n')


def page(cases,summary,stamp):
    rows=[];cards=[]
    def metric(label,value):return '<div><dt>'+html.escape(label)+'</dt><dd>'+html.escape(value)+'</dd></div>'
    for c in cases:
        d=c['diagnostics'];a=c['analysis'];s=a['source'];tag=c['tag']
        rows.append('<tr><td><a href="#'+tag+'">'+c['title']+'</a></td><td>通过</td><td>'+fmt(a['maximumIndependentSourceEdgeStrain']*100,4)+'%</td><td>'+f"{a['actualInitialGapMeters']*1000:.3f}"+' mm → '+f"{a['actualMaximumGapMeters']:.3e}"+' m</td><td>'+str(d['vertexCount'])+'</td><td>0 / 0</td></tr>')
        values=[('独立源颗粒',str(d['vertexCount'])),('实际缝合约束',str(d['sewingConstraintCount'])),('独立最大缝合点间距',f"{a['actualMaximumGapMeters']:.3e} m"),('独立缝合点均方根间距',f"{a['actualRMSGapMeters']:.3e} m"),
            ('最大原始边应变',fmt(a['maximumIndependentSourceEdgeStrain']*100,4)+'%'),('末态最大净速度',f"{d['maxSpeedMetersPerSecond']:.3e} m/s"),('原纸样上缘总弧长',fmt(s['topMeters']*100)+' cm'),('原纸样下缘总弧长',fmt(s['bottomMeters']*100)+' cm'),
            ('纸样'+s['paperDepthKind'],fmt(s['paperDepthMeters']*100)+' cm'),('三维垂直投影范围',fmt(a['verticalProjectionRangeMeters']*100)+' cm'),('参考裁片面积',fmt(a['referenceAreaSquareMeters'],6)+' m²'),('参考面积质量',fmt(a['independentMassKg']*1000)+' g'),
            ('独立人体真实交叉对数',str(a['independent']['properBodyTrianglePairs'])),('体积内顶点／面中心','0 / 0'),('三轴体积模糊／分歧','0 / 0'),('Mac 命令行计算耗时',fmt(d['computationSeconds'],2)+' s')]
        links=' · '.join('<a href="generated/'+name+'">'+html.escape(label)+'</a>' for label,name in c['files'].items())
        cards.append('<section id="'+tag+'"><h2>'+c['title']+'</h2><p class="sub">'+c['style']+'；原纸样与官方固定默认 fixture 的最大几何差 '+fmt(c['fixtureMaximumDeltaCM'],10)+' cm。'+('只扰动初始模拟接缝下缘，源纸样、参考网格及面料质量与同款默认例完全相同。' if c['perturbMeters'] else '侧缝从独立源颗粒开始；颗粒索引始终分开。')+'</p><figure><img src="generated/'+c['image']+'" width="1260" height="360" alt="'+c['title']+'实际网格腰部三视图"><figcaption>正面／右侧／背面，共用固定相机 Y=−0.025 m、900 px/m。PNG 是实际导出网格的深度缓冲栅格图；未修改模型坐标，不是 App 截图。</figcaption></figure><dl>'+''.join(metric(k,v) for k,v in values)+'</dl><p class="sub">实测极小间距是浮点数值残差，不代表纳米级物理精度。普通侧缝的 4 个匹配折线区间全部覆盖，端点距离独立复算；源颗粒没有通过焊接合并。</p><p class="downloads">'+links+'</p></section>')
    return '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>独立裁片 · 腰头实际缝合验证</title><style>
:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;background:#f6f2ed;color:#302e2c}*{box-sizing:border-box}body{margin:0}main{max-width:1280px;margin:auto;padding:32px 22px}h1{font-size:36px;margin:14px 0}h2{font-size:22px;margin:0 0 12px}p{line-height:1.85}.sub,figcaption{font-size:13px;color:#786e68;line-height:1.8}.eyebrow{font-size:12px;letter-spacing:.12em;color:#8c5b68}section,.intro{padding:22px;border:1px solid #dfd6ce;border-radius:12px;background:#fffdf9;margin:22px 0}a{color:#93566a}table{border-collapse:collapse;width:100%;font-size:14px}td,th{text-align:left;border-bottom:1px solid #e4dcd3;padding:11px;line-height:1.8}th{color:#756861}figure{margin:15px 0}img{display:block;max-width:100%;height:auto;background:#f3efe7;border-radius:8px}dl{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:20px 12px;margin:24px 0}dt{font-size:12px;color:#7b7069;line-height:1.7}dd{margin:5px 0 0;font-size:21px;font-variant-numeric:tabular-nums}.downloads{font-size:13px;line-height:2.1}.note{padding:12px 16px;background:#f3e8d7;border-left:3px solid #bc9253}.footer{font-size:12px;color:#857870;overflow-wrap:anywhere}@media(max-width:720px){main{padding:20px 10px}h1{font-size:28px}section,.intro{padding:15px}dl{grid-template-columns:repeat(2,minmax(0,1fr))}td,th{padding:7px;font-size:12px}table{display:block;overflow:auto;white-space:nowrap}}
</style></head><body><main><div class="eyebrow">TAILORASS · 私有离线验证</div><h1>独立裁片，实际缝合成腰头</h1><div class="intro"><p>本页验证当前腰头入口使用的独立裁片缝合后端。四例在与 App 一致的 32 次主求解迭代配置下通过原有质量门槛：两种默认腰头，以及各自的 2 mm 自由下缘接缝扰动。</p><p>前后片保留各自原始顶点、三角边长、面积与质量；缝合点通过约束逐步靠近。间距由两侧实际附着位置计算，未通过合并索引得到零值。固定上缘仍是约 5 mm 的辅助支撑，尚未缝合裙身、裤身或整件服装。</p><p class="note">本批覆盖默认尺寸的直腰头、弧形腰头；不保证全部宽度、围度或其他衣服都能生成有效结果。此前<a href="../2026-10-25-waistband-3d/index.html">九例共享侧缝旧后端报告（7/9 质量通过）</a>保留为历史对照，不代表当前 App 的缝合后端，也不替代本页的四例证据。</p></div><section><h2>四例实际结果</h2><table><thead><tr><th>方案</th><th>质量门槛</th><th>源边最大应变</th><th>独立实际缝合点间距</th><th>独立源颗粒</th><th>人体交叉／体积内点</th></tr></thead><tbody>'''+''.join(rows)+'''</tbody></table><p class="sub">初始间距取自 Swift 初态实测并与缝合计划核对，末态间距由 Python 从实际独立颗粒与权重复算。原始汇总 passed='''+str(summary['passed'])+'''；源数据、人体资源和取消检查的 Swift 回归断言均通过。Python 另外独立复算缝合间距、源边应变、参考面积质量、真实人体面交叉及三轴体积检查。<a href="generated/sewn-drape-summary.json">原始汇总</a> · <a href="manifest.json">全部数据与哈希</a></p></section>'''+''.join(cards)+'''<section><h2>如何理解数值预算与结果</h2><p>每个顶点每帧允许的 <strong>0.2 m 是缝合约束内部累计修正路径预算</strong>，统计反复数值投影的行程；它不是一帧移动 20 cm。每次约束修正另设 <strong>0.02 m 单次位移上限</strong>，共同缩放约束两侧以保留质量比例。末态净速度单独测量；本批最大约 6.764e−5 m/s，远低于原 0.025 m/s 门槛。累计预算与单次上限均在每例诊断 JSON 中公开。</p><p>原质量门槛保持：源边最大应变 &lt;8%，末态净速度 &lt;0.025 m/s，SDF 顶点穿入估计 &lt;3 mm，实际缝合点间距 &lt;0.5 mm，自交与真实人体面交叉为 0，并满足持续收敛检查。5% 只是有限边长投影的实验目标，本批实际最大源边应变约 5.00%～6.10%；不把目标当作已实现的严格材料伸长界限。</p><p>纸样侧边／径向宽度、原上／下缘弧长，以及三维的垂直投影属于不同量。面料克重为未标定的 180 g/m² 实验预设。人体网格接触目标 0.5 mm、SDF 顶点投影目标 2.5 mm、上缘支撑目标 5 mm 都是数值假设，不能当作真实厚度或最小间隙证书。</p><p>独立体积检查对实际闭合人体网格向 X／Y／Z 三轴发射射线，并将近表面、切线与轴向分歧另行报告。真实面交叉使用独立边／三角形检查；1e−7 m 为接触分类容差，不是物理精度。有限末态样本与普通侧缝折线对合不能证明连续运动无穿插、完整衣服可缝制或个人合体。Mac 命令行耗时不代表 iPhone 实测。</p><p>JSON 原始快照按字节保留；附带 OBJ 从同一实际网格派生，没有再次仿真。未获得同输入的官方最终三维网格，本页不宣称与 GarmentCode／Design2GarmentCode 三维等价。</p></section><p class="footer">生成：'''+stamp.isoformat(timespec='seconds')+'''。静态 HTML、实际网格 PNG、原始 JSON 与派生 OBJ；无外部脚本或字体。没有自动打开本地 HTML。人体来源及许可见项目 THIRD_PARTY_NOTICES.md。</p></main></body></html>'''


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input-dir',type=Path,default=Path('/private/tmp/TailorAssSewnDrapeCanonical32'));parser.add_argument('--output-dir',type=Path,default=DEFAULT_REPORT);args=parser.parse_args()
    output=args.output_dir.resolve()
    if output!=DEFAULT_REPORT.resolve():raise ValueError('Use the NEW sewn-waistband report folder; old reports must stay immutable')
    summary_path=args.input_dir/'sewn-drape-summary.json';summary=read(summary_path)
    if not all(summary.get(k) for k in ('passed','sourceUnchanged','bodyResourcesUnchanged','cancellationVerified')):raise ValueError('Original production regression did not pass')
    records={c['tag']:c for c in summary['cases']}
    if set(records)!={c[0] for c in CASES}:raise ValueError('Four exact production cases required')
    output.mkdir(parents=True,exist_ok=True);generated=output/'generated';generated.mkdir(exist_ok=True)
    if args.input_dir.resolve()==generated:raise ValueError('Raw input must be separate from report output')
    helpers=runpy.run_path(str(TESTS/'render-waistband-report.py'));geometry=runpy.run_path(str(TESTS/'render-body-surface-report.py'))
    validate=runpy.run_path(str(TESTS/'render-cloth-report.py'))['validate_mesh'];render=helpers['waist_renderer']();cases=[];body=None;body_hash=None
    for tag,title,style,perturb in CASES:
        copied={}
        for suffix in SUFFIXES:
            raw=args.input_dir/(tag+suffix);target=generated/raw.name;target.write_bytes(raw.read_bytes());copied[raw.name]=sha(raw)
        mesh,reference,plan,source,acceptance=[read(generated/(tag+s)) for s in ('-mesh.json','-reference.json','-plan.json','-source.json','-acceptance.json')]
        validate(dict(mesh,seamPaths=[]),tag)
        if read(generated/(tag+'-diagnostics.json'))!=mesh['diagnostics'] or records[tag]!=acceptance:raise ValueError('Separate diagnostic/acceptance snapshots disagree')
        source_hash=sha(generated/(tag+'-source.json'))
        if source_hash!=plan['sourceSHA256'] or source_hash!=acceptance['sourceSHA256']:raise ValueError('Canonical source document hash differs from verified plan')
        key=helpers['body_geometry_hash'](mesh)
        if body is None:body=geometry['IndependentBody'](mesh['mannequinPositions'],mesh['mannequinTriangleIndices']);body_hash=key
        elif key!=body_hash:raise ValueError('Actual visible/collision reference body differs between cases')
        if key!='6da810b8e3cd2c4cfe8886f7ce39bf0305973c380f4f804bef2fc31625927eb8':raise ValueError('Original standard visible body changed')
        analysis=check_case(tag,style,perturb,mesh,reference,plan,source,acceptance,body,geometry,helpers)
        fixture=TESTS/'Fixtures'/('waistband-straight.json' if style=='StraightWB' else 'waistband-fitted.json')
        delta=geometry['compare_geometry'](source,read(fixture))
        image=tag+'-waist-views.png';render(generated/(tag+'-mesh.json'),generated/image)
        derived=tag+'.obj';obj(mesh,generated/derived,style)
        files={'实际网格 JSON':tag+'-mesh.json','诊断':tag+'-diagnostics.json','源纸样':tag+'-source.json','缝合计划':tag+'-plan.json','平面参考网格':tag+'-reference.json','原始验收':tag+'-acceptance.json','实际网格派生 OBJ':derived}
        cases.append({'tag':tag,'title':title,'style':style,'perturbMeters':perturb,'passed':True,'diagnostics':mesh['diagnostics'],'analysis':analysis,'canonicalSourceSHA256':source_hash,'bodyGeometrySHA256':key,'fixtureMaximumDeltaCM':delta,'inputFileSHA256':copied,'image':image,'files':files})
    for style in ('StraightWB','FittedWB'):
        a,b=[c for c in cases if c['style']==style]
        for suffix in ('-source.json','-reference.json'):
            if (generated/(a['tag']+suffix)).read_bytes()!=(generated/(b['tag']+suffix)).read_bytes():raise ValueError('Perturbation changed original source paper or reference mesh')
    (generated/summary_path.name).write_bytes(summary_path.read_bytes())
    stamp=datetime.datetime.now(ZoneInfo('Asia/Shanghai'))
    code=['GarmentCodeSewing.swift','GarmentCodeSewnInput.swift','GarmentCodeSewnDrape.swift','GarmentCodeWaistbandAssembly.swift','GarmentCodeWaistbandDrape.swift','GarmentCodeClothContact.swift','GarmentCodeBodySurfaceContact.swift','GarmentCodePanelMesher.swift','GarmentCodeClothMaterial.swift']
    proof={'generatedAt':stamp.isoformat(timespec='seconds'),'scope':'Four actual current-production separate-particle WB cases at recorded App32; no all-width or complete-garment claim',
        'sourceRunSummarySHA256':sha(summary_path),'sourceRunSummary':summary,'cases':cases,'sameOriginalVisibleBody':True,'bodyGeometrySHA256':body_hash,'bodyClosedManifold':True,'bodySignedVolumeCubicMeters':body.volume,
        'numericalBudgets':{'sewingAccumulatedConstraintPathPerVertexPerFrameMeters':.2,'sewingSingleVertexCorrectionMeters':.02,'actualMainSolverIterations':32,'sourceStrainProjectionTarget':.05,'sourceStrainPasses':40},
        'camera':{'centerYMeters':-.025,'pixelsPerMeter':900,'views':'front/right/back','meshCoordinatesModified':False},
        'properCrossClassificationEpsilonMeters':1e-7,'harnessSHA256':sha(TESTS/'SewnDrape.swift'),'helperSHA256':sha(Path(__file__)),
        'codeSHA256':{name:sha(ROOT/'TrailorAss/Models'/name) for name in code},
        'supportingHelpersSHA256':{name:sha(TESTS/name) for name in ('render-waistband-report.py','render-body-surface-report.py','render-cloth-preview.py','render-cloth-report.py')},
        'generatedFileSHA256':{p.name:sha(p) for p in sorted(generated.iterdir()) if p.is_file()},'browserAutomationUsed':False,'officialFinal3DMeshEquivalenceClaimed':False,
        'previousWeldedBackendReport':{'relativeURL':'../2026-10-25-waistband-3d/index.html','qualityPassCount':7,'caseCount':9,'isCurrentAppBackend':False}}
    write(output/'manifest.json',proof);(output/'index.html').write_text(page(cases,summary,stamp))
    print(f'PASS: four actual separate-particle WB cases independently verified; report {output/"index.html"}')


if __name__=='__main__':main()
