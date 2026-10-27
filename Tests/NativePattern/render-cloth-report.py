#!/usr/bin/env python3
"""Build a private, offline report from actual exported cloth meshes.

Python standard library only. This is a viewer/report builder, not a cloth solver.
Run again after solver changes to replace the report with the latest mesh output.
"""
import argparse
import datetime
import hashlib
import html
import json
import math
from pathlib import Path
import shutil
from zoneinfo import ZoneInfo


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REPORT = ROOT / "Tests/NativePattern/Reports/2026-10-25-3d"


def validate_mesh(data, filename):
    for position_key, index_key in (
        ("positions", "triangleIndices"),
        ("mannequinPositions", "mannequinTriangleIndices"),
    ):
        positions, indices = data[position_key], data[index_key]
        if not positions or not indices or len(indices) % 3:
            raise ValueError(f"{filename}: invalid {position_key}/{index_key}")
        for point in positions:
            if any(not math.isfinite(point[axis]) for axis in ("x", "y", "z")):
                raise ValueError(f"{filename}: non-finite vertex")
        if any(type(index) is not int or index < 0 or index >= len(positions)
               for index in indices):
            raise ValueError(f"{filename}: triangle vertex out of bounds")
    for seam in data["seamPaths"]:
        if any(type(index) is not int or not 0 <= index < len(data["positions"])
               for index in seam):
            raise ValueError(f"{filename}: seam vertex out of bounds")
    if type(data["diagnostics"].get("converged")) is not bool:
        raise ValueError(f"{filename}: missing convergence result")
    for key in ("surfaceIntersectionCount", "closeSurfacePairCount"):
        value = data["diagnostics"].get(key)
        if value is not None and (type(value) is not int or value < 0):
            raise ValueError(f"{filename}: invalid {key}")
    mass = data["diagnostics"].get("totalFabricMassKg")
    if mass is not None and (not math.isfinite(mass) or mass <= 0):
        raise ValueError(f"{filename}: invalid fabric mass")


HTML = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>圆裙离线 3D · 实际输出与官方参照</title>
<style>
:root{font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Microsoft YaHei",sans-serif;color:#302b2b;background:#f7f4ef;font-synthesis:none;--muted:#766d6b;--accent:#954864;--line:#dfd6d1;--paper:#fffdfa}
*{box-sizing:border-box}body{margin:0}button,select,input{font:inherit}button,select{border:1px solid var(--line);background:#fffdfa;color:#423839;border-radius:8px;padding:8px 12px}button{cursor:pointer}button:hover,select:hover{border-color:var(--accent)}button:focus-visible,select:focus-visible,a:focus-visible{outline:3px solid #d7b3c0;outline-offset:2px}a{color:var(--accent)}button.active{background:#f4e3e9;border-color:#bc7f96}main{max-width:1440px;margin:auto;padding:36px 36px 48px}.eyebrow{font-size:12px;letter-spacing:.15em;color:var(--accent);font-weight:650}h1{font-size:clamp(28px,3.6vw,46px);line-height:1.2;margin:14px 0}h2{font-size:21px;margin:0}h3{font-size:16px;margin:0 0 12px}.intro{line-height:1.8;color:var(--muted);max-width:850px;margin:0}.topline{display:flex;justify-content:space-between;gap:20px;align-items:center;margin-top:24px}.status{font-size:13px;padding:8px 12px;border-radius:6px;background:#fff0d8;color:#825711;border:1px solid #e5c99a}.status.good{background:#edf3ec;color:#486447;border-color:#c5d6c1}.workspace{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(0,1fr);gap:22px;margin-top:18px}.panel{background:var(--paper);border:1px solid var(--line);border-radius:14px;overflow:hidden}.panel-head{padding:18px 20px 14px;border-bottom:1px solid var(--line)}.sub{font-size:13px;color:var(--muted);line-height:1.65;margin:8px 0 0}.controls{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:14px}.controls label{font-size:13px;color:#655a59;display:flex;gap:6px;align-items:center}.controls select{max-width:100%}.canvas-wrap{position:relative;height:480px;background:#f1ece7;overflow:hidden}.canvas-wrap canvas{width:100%;height:100%;display:block;touch-action:none;cursor:grab}.canvas-wrap canvas:active{cursor:grabbing}.canvas-hint{position:absolute;left:16px;bottom:12px;color:#6b6462;font-size:12px;background:#fffdf9dc;padding:7px 9px;border-radius:5px;pointer-events:none}.canvas-error{position:absolute;inset:0;display:none;align-items:center;justify-content:center;padding:30px;color:#8f3c37;text-align:center;background:#fff3ed}.view-tools{display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap;padding:12px 16px;border-top:1px solid var(--line)}.view-buttons{display:flex;gap:5px;flex-wrap:wrap}.view-buttons button{font-size:12px;padding:6px 10px}.toggles{display:flex;gap:12px;align-items:center;font-size:12px;color:#6d605e}.toggles label{display:flex;gap:4px;align-items:center}.reference-body{padding:16px 20px}.reference-image{height:373px;display:flex;align-items:center;justify-content:center;margin:0;background:#eee9e3;border-radius:8px;overflow:hidden}.reference-image img{display:block;max-width:100%;max-height:100%;object-fit:contain;cursor:zoom-in}.ref-caption{font-size:12px;color:var(--muted);line-height:1.8;margin:12px 0 0;min-height:65px}.mismatch{background:#f4eee3;border-left:3px solid #bf9a57;padding:10px 12px;font-size:12px;line-height:1.75;color:#705e42;margin-top:12px}.data-grid{display:grid;grid-template-columns:1.05fr 1fr;gap:22px;margin-top:22px}.data-box{padding:20px}.metric-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:16px 12px;margin-top:18px}.metric-value{font-variant-numeric:tabular-nums;font-size:23px;letter-spacing:-.03em;line-height:1.3}.metric-label{font-size:12px;color:var(--muted);line-height:1.7;margin-top:4px}.metric-label small{display:block;color:#8c817e;font-size:11px}.checks{list-style:none;padding:0;margin:14px 0 0}.checks li{display:flex;justify-content:space-between;gap:16px;padding:10px 0;border-bottom:1px solid #eee5e0;font-size:13px}.checks strong{font-weight:600;font-variant-numeric:tabular-nums}.danger{color:#a44b32}.warnings{margin:14px 0 0;padding-left:20px;font-size:13px;line-height:1.9;color:#75655e}.method{margin-top:22px;padding:22px}.method p{font-size:13px;color:var(--muted);line-height:1.9;margin:10px 0}.method table{width:100%;border-collapse:collapse;font-size:13px;margin:14px 0}.method th,.method td{text-align:left;border-bottom:1px solid #e7ded8;padding:10px 12px;line-height:1.7}.method th{background:#f4eee8;color:#695b58}.footer{font-size:11px;color:#8c807b;line-height:1.9;margin-top:20px;overflow-wrap:anywhere}dialog{border:1px solid #d6cac3;border-radius:12px;background:#fffdfa;padding:16px;max-width:95vw;max-height:94vh}dialog::backdrop{background:#29221ee0}dialog img{display:block;max-width:88vw;max-height:80vh;object-fit:contain;background:#eee9e3}dialog button{display:block;margin:10px 0 0 auto}.download{font-size:12px;white-space:nowrap}
@media(max-width:960px){main{padding:26px 18px}.workspace,.data-grid{grid-template-columns:1fr}.reference-image{height:400px}.canvas-wrap{height:470px}.topline{align-items:flex-start}.metric-grid{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:520px){main{padding:22px 12px}.canvas-wrap{height:390px}.panel-head,.reference-body,.data-box{padding:16px}.reference-image{height:330px}.topline{display:block}.download{display:block;margin-top:12px}.metric-value{font-size:20px}.method{padding:16px}.method table{font-size:12px}.method th,.method td{padding:8px}.toggles{width:100%}}
</style></head><body><main>
<div class="eyebrow">TAILORASS · 私有离线研究预览 · 2026.10.25</div>
<h1>圆裙，从裁片到成衣</h1>
<p class="intro">左侧显示当前计算链实际导出的三维网格，可以旋转检查接缝和垂坠；右侧是官方公开效果图。这里记录的是实验结果，尚未证明与 GarmentCode 的三维仿真一致。</p>
<div class="topline"><span id="status" class="status">读取实际计算结果…</span><a class="download" id="download" href="#" download>下载当前网格 JSON ↗</a></div>
<div class="workspace">
<section class="panel"><div class="panel-head"><h2>本项目 · 实际输出</h2><p class="sub">使用同一初始视野比较实际导出方案；模型单位为米。红橙与靛蓝线标出两组侧缝。</p><div class="controls"><label for="case">圆裙试验方案</label><select id="case">__CASE_OPTIONS__</select></div></div>
<div class="canvas-wrap"><canvas id="viewer" aria-label="实际圆裙三维网格，可拖动旋转，滚轮或双指缩放"></canvas><div class="canvas-hint" id="hint">拖动旋转 · 滚轮／双指缩放</div><div class="canvas-error" id="canvas-error"></div></div>
<div class="view-tools"><div class="view-buttons"><button type="button" data-view="front">正面</button><button type="button" data-view="side">侧面</button><button type="button" data-view="back">背面</button><button type="button" data-view="garment">放大裙身</button><button type="button" data-view="reset">重置</button></div><div class="toggles"><label><input type="checkbox" id="body" checked>人台</label><label><input type="checkbox" id="seams" checked>接缝</label><label><input type="checkbox" id="wire">网格</label></div></div></section>
<section class="panel"><div class="panel-head"><h2>官方效果 · 定性参照</h2><p class="sub">保留官方原图。点击图片可放大查看。</p><div class="controls"><select id="reference" aria-label="选择官方参考图"><option value="gc">GarmentCode · 款式与垂坠示例</option><option value="d2g">Design2GarmentCode · 图文生成结果</option></select></div></div><div class="reference-body"><figure class="reference-image"><img id="ref-image" src="references/garmentcode-header.png" alt="GarmentCode 官方多款成衣垂坠示例" tabindex="0"></figure><p class="ref-caption" id="ref-caption"></p><div class="mismatch"><strong>比较条件不同：</strong>官方图片的人体、设计参数、面料与相机未完全对齐，只可比较轮廓、褶皱和明显装配问题，不能据此计算三维误差或认定效果相同。</div></div></section>
</div>
<div class="data-grid"><section class="panel data-box"><h3>当前裁片的参考尺寸</h3><p class="sub">下列腰弧、下摆与面积来自裁片参考几何，不能当作垂坠后投影测量。</p><div class="metric-grid"><div><div class="metric-value" id="waist"></div><div class="metric-label">腰弧总长<small>cm</small></div></div><div><div class="metric-value" id="length"></div><div class="metric-label">裁片径向裙长<small>cm</small></div></div><div><div class="metric-value" id="hem"></div><div class="metric-label">下摆弧长<small>cm</small></div></div><div><div class="metric-value" id="area"></div><div class="metric-label">裁片面积<small>m²</small></div></div><div><div class="metric-value" id="vertices"></div><div class="metric-label">布料顶点数</div></div><div><div class="metric-value" id="triangles"></div><div class="metric-label">布料三角面数</div></div></div><p class="sub" id="source"></p></section>
<section class="panel data-box"><h3>技术质量与实际限制</h3><ul class="checks"><li><span>人台模型</span><strong id="body-model"></strong></li><li><span>材料设置</span><strong id="material-name"></strong></li><li><span>裁片总质量（按参考面积）</span><strong id="fabric-mass"></strong></li><li><span>达到当前收敛门槛</span><strong id="converged"></strong></li><li><span>计算耗时（导出环境）</span><strong id="seconds"></strong></li><li><span>共享侧缝间距</span><strong id="gap"></strong></li><li><span>网格边最大应变</span><strong id="strain"></strong></li><li><span>人体距离场顶点穿入估计</span><strong id="penetration"></strong></li><li><span>末态最大速度</span><strong id="speed"></strong></li><li><span>末态三角面交叉对数</span><strong id="surface-intersections"></strong></li><li><span>末态近距离面接触对数</span><strong id="surface-near-pairs"></strong></li></ul><ul class="warnings" id="warnings"></ul></section></div>
<section class="panel method"><h3>如何读这份对比</h3><table><thead><tr><th>检查层次</th><th>当前证据</th><th>可以判断什么</th></tr></thead><tbody><tr><td>裁片与网格</td><td>真实导出顶点、三角面与接缝索引</td><td>是否按当前裁片生成，装配是否出现明显问题</td></tr><tr><td>本项目仿真</td><td>收敛、应变、接缝、碰撞诊断</td><td>当前实验质量；仍需真机性能与完整穿插检查</td></tr><tr><td>官方公开图</td><td>本页两个官方原图及来源</td><td>外观定性参照，不证明相同参数或物理等价</td></tr><tr><td>严格三维对比</td><td>尚缺同输入官方最终成衣网格</td><td>目前不能给出表面距离或“已匹配”结论</td></tr></tbody></table><p>Design2GarmentCode 的公开实现使用 GarmentCode 的定制 Warp 仿真后端；它们不能算作两个独立物理求解器的验证。在线 GarmentCode 帮助说明三维预览使用默认人体，修改人体尺寸不会改变预览人台。</p><p>可复现的官方圆裙基线：固定提交 d4496299、mean_all 人体、默认设计，suns = 0.75，腰弧 84.3338 cm、径向裙长 40.54146 cm、下摆 275.380929 cm、平面面积 0.729168 m²。只有当前输入也相同时才可与这些数值比较；本页各方案的真实尺寸列在上方。</p><p><a href="reference-sources.md">查看来源、许可与完整对比条件 ↗</a> · <a href="https://garmentcode.ethz.ch/" target="_blank" rel="noreferrer">GarmentCode 在线配置器 ↗</a> · <a href="https://style3d.github.io/design2garmentcode/" target="_blank" rel="noreferrer">Design2GarmentCode 官网 ↗</a></p></section>
<div class="footer">生成时间：__GENERATED_AT__。此页面完全离线显示本地数据，无外部脚本、字体或网络请求。计算耗时来自原始导出诊断，不代表 iPhone 17 Pro 实测。<br>GarmentCode 图片：Maria Korosteleva 等，原仓库 MIT 许可见项目 THIRD_PARTY_NOTICES.md。Design2GarmentCode 图片：Feng Zhou 等，官网标注 CC BY-SA 4.0。保留原图；未进行裁切或重绘。</div>
</main><dialog id="image-dialog"><img id="large-image" alt="官方原图放大"><button id="close-dialog" type="button">关闭</button></dialog>
<script id="mesh-data" type="application/json">__DATA__</script>
<script>
'use strict';
const cases=JSON.parse(document.getElementById('mesh-data').textContent);
const el=id=>document.getElementById(id);
const refs={gc:{src:'references/garmentcode-header.png',alt:'GarmentCode 官方多款成衣垂坠示例',caption:'GarmentCode 官方款式群像：可以观察裙摆形态、腰部支撑与褶皱。图中各款输入未与本项目对齐。',url:'https://github.com/maria-korosteleva/GarmentCode/blob/main/assets/img/header.png'},d2g:{src:'references/design2garmentcode-result-text.png',alt:'Design2GarmentCode 文字生成裁片及正背面垂坠结果',caption:'Design2GarmentCode 官方文字生成结果。左栏为该方法，右栏为其对照方法 DressCode。图 (b) 含环扇形裙片与 A 字连衣裙正背面；具体参数未知。',url:'https://style3d.github.io/design2garmentcode/static/images/result_text.png'}};
function reference(){const r=refs[el('reference').value];el('ref-image').src=r.src;el('ref-image').alt=r.alt;el('ref-caption').textContent=r.caption+' ';const a=document.createElement('a');a.href=r.url;a.textContent='官方来源 ↗';a.target='_blank';a.rel='noreferrer';el('ref-caption').append(a)}
el('reference').addEventListener('change',reference);reference();
function enlarge(){el('large-image').src=el('ref-image').src;el('large-image').alt=el('ref-image').alt;el('image-dialog').showModal()}
el('ref-image').addEventListener('click',enlarge);el('ref-image').addEventListener('keydown',e=>{if(e.key==='Enter')enlarge()});el('close-dialog').addEventListener('click',()=>el('image-dialog').close());
function fmt(n,d=2){return Number.isFinite(n)?n.toLocaleString('zh-CN',{minimumFractionDigits:d,maximumFractionDigits:d}):'未记录'}
function mm(n){return n===0?'0.00 mm':(Math.abs(n*1000)<.01?'< 0.01 mm':fmt(n*1000)+' mm')}
function choose(){
 const item=cases[el('case').value],d=item.mesh.diagnostics;
 el('status').textContent=d.converged?'达到当前收敛门槛 · 实验仿真':'未达到收敛门槛 · 仅供检查装配';
 el('status').classList.toggle('good',d.converged);el('download').href='generated/'+item.filename;
 el('waist').textContent=fmt(d.waistCircumferenceMeters*100);el('length').textContent=fmt(d.radialLengthMeters*100);
 el('hem').textContent=fmt(d.hemCircumferenceMeters*100);el('area').textContent=fmt(d.referenceAreaSquareMeters,4);
 el('vertices').textContent=fmt(item.mesh.positions.length,0);el('triangles').textContent=fmt(item.mesh.triangleIndices.length/3,0);
 el('body-model').textContent=d.bodyModel||'未记录（旧格式）';el('material-name').textContent=d.materialName||'未记录（旧格式）';
 el('fabric-mass').textContent=Number.isFinite(d.totalFabricMassKg)?fmt(d.totalFabricMassKg*1000,1)+' g':'未记录';
 el('converged').textContent=d.converged?'是':'否';el('converged').classList.toggle('danger',!d.converged);
 el('seconds').textContent=fmt(d.computationSeconds)+' s';el('gap').textContent=mm(d.maxSeamGapMeters);
 el('strain').textContent=fmt(d.maxEdgeStrain*100)+'%';el('penetration').textContent=mm(d.maxBodyPenetrationMeters)+'（仅顶点）';
 el('speed').textContent=fmt(d.maxSpeedMetersPerSecond*100,3)+' cm/s';
 el('surface-intersections').textContent=Number.isInteger(d.surfaceIntersectionCount)?fmt(d.surfaceIntersectionCount,0)+'（离散末态）':'未检查（旧格式）';
 el('surface-intersections').classList.toggle('danger',Number.isInteger(d.surfaceIntersectionCount)&&d.surfaceIntersectionCount>0);
 el('surface-near-pairs').textContent=Number.isInteger(d.closeSurfacePairCount)?fmt(d.closeSurfacePairCount,0):'未记录';
 el('source').textContent='数据：'+item.filename+' · SHA-256 '+item.sha256.slice(0,16)+'…';
 el('warnings').replaceChildren(...(d.warnings||[]).map(t=>{const li=document.createElement('li');li.textContent=t;return li}));loadMesh(item.mesh)
}
const canvas=el('viewer');let gl=canvas.getContext('webgl2',{antialias:true,alpha:false}),ctx=null,program,geometry=null;
let yaw=.5,pitch=.12,zoom=1,raf=0,showBody=true,showSeams=true,showWire=false;
const allPoints=Object.values(cases).flatMap(c=>[...c.mesh.positions,...c.mesh.mannequinPositions]);
const low=[Infinity,Infinity,Infinity],high=[-Infinity,-Infinity,-Infinity];for(const p of allPoints){[p.x,p.y,p.z].forEach((v,k)=>{low[k]=Math.min(low[k],v);high[k]=Math.max(high[k],v)})}
const center=low.map((v,k)=>(v+high[k])/2),radius=Math.max(...low.map((v,k)=>high[k]-v))*.66;
function flat(points){return new Float32Array(points.flatMap(p=>[p.x,p.y,p.z]))}
function normals(points,indices){const n=new Float32Array(points.length*3);for(let i=0;i<indices.length;i+=3){const a=points[indices[i]],b=points[indices[i+1]],c=points[indices[i+2]],u=[b.x-a.x,b.y-a.y,b.z-a.z],v=[c.x-a.x,c.y-a.y,c.z-a.z],q=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]];for(let j=0;j<3;j++)for(let k=0;k<3;k++)n[indices[i+j]*3+k]+=q[k]}for(let i=0;i<n.length;i+=3){const l=Math.hypot(n[i],n[i+1],n[i+2])||1;n[i]/=l;n[i+1]/=l;n[i+2]/=l}return n}
function edges(indices){const seen=new Set(),out=[];for(let i=0;i<indices.length;i+=3)for(let k=0;k<3;k++){const a=indices[i+k],b=indices[i+(k+1)%3],key=Math.min(a,b)+':'+Math.max(a,b);if(!seen.has(key)){seen.add(key);out.push(a,b)}}return new Uint32Array(out)}
function make(points,indices,isLine=false){const g={points,indices,normals:isLine?new Float32Array(points.length*3):normals(points,indices)};if(gl){g.vao=gl.createVertexArray();gl.bindVertexArray(g.vao);g.buffers=[];for(const [at,data] of [[0,flat(points)],[1,g.normals]]){const b=gl.createBuffer();g.buffers.push(b);gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,data,gl.STATIC_DRAW);gl.enableVertexAttribArray(at);gl.vertexAttribPointer(at,3,gl.FLOAT,false,0,0)}g.index=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,g.index);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,new Uint32Array(indices),gl.STATIC_DRAW);g.edgeData=isLine?new Uint32Array():edges(indices);g.edge=gl.createBuffer();gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,g.edge);gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,g.edgeData,gl.STATIC_DRAW);gl.bindVertexArray(null)}return g}
function dispose(g){if(!gl||!g)return;for(const m of [g.cloth,g.body,...g.seams]){for(const b of m.buffers)gl.deleteBuffer(b);gl.deleteBuffer(m.index);gl.deleteBuffer(m.edge);gl.deleteVertexArray(m.vao)}}
function loadMesh(mesh){dispose(geometry);geometry={cloth:make(mesh.positions,mesh.triangleIndices),body:make(mesh.mannequinPositions,mesh.mannequinTriangleIndices),seams:mesh.seamPaths.map(path=>make(path.map(i=>mesh.positions[i]),path.map((_,i)=>i),true))};requestDraw()}
function shader(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s}
if(gl){try{program=gl.createProgram();gl.attachShader(program,shader(gl.VERTEX_SHADER,`#version 300 es
precision highp float;layout(location=0)in vec3 position;layout(location=1)in vec3 normal;uniform mat4 mvp;uniform mat3 rotation;out vec3 n;void main(){gl_Position=mvp*vec4(position,1.);n=rotation*normal;}`));gl.attachShader(program,shader(gl.FRAGMENT_SHADER,`#version 300 es
precision highp float;in vec3 n;uniform vec3 color;uniform float unlit;out vec4 result;void main(){if(unlit>.5){result=vec4(color,1.);return;}vec3 nn=normalize(n);if(!gl_FrontFacing)nn=-nn;float light=.58+.31*max(dot(nn,normalize(vec3(-.4,.8,1.))),0.)+.11*max(dot(nn,normalize(vec3(.9,.2,-.3))),0.);result=vec4(color*mix(light,1.,unlit),1.);}`));gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(program));gl.enable(gl.DEPTH_TEST);gl.clearColor(.945,.925,.906,1);gl.disable(gl.CULL_FACE)}catch(e){el('canvas-error').textContent='三维显示初始化失败：'+e.message;el('canvas-error').style.display='flex';gl=null}}
if(!gl){const replacement=canvas.cloneNode(false);canvas.replaceWith(replacement);const fallback=replacement.getContext('2d');ctx=fallback;if(ctx)el('canvas-error').style.display='none';el('hint').textContent='CPU 兼容显示 · 拖动旋转 · 滚轮／双指缩放'}
const surface=()=>el('viewer');
function rotation(){const cy=Math.cos(yaw),sy=Math.sin(yaw),cp=Math.cos(pitch),sp=Math.sin(pitch);return [cy,sp*sy,-cp*sy,0,cp,sp,sy,-sp*cy,cp*cy]}
function transform(p,r){const a=[p.x-center[0],p.y-center[1],p.z-center[2]];return [r[0]*a[0]+r[3]*a[1]+r[6]*a[2],r[1]*a[0]+r[4]*a[1]+r[7]*a[2],r[2]*a[0]+r[5]*a[1]+r[8]*a[2]]}
function requestDraw(){if(!raf)raf=requestAnimationFrame(()=>{raf=0;draw()})}
function drawGL(w,h,r,scale){gl.viewport(0,0,w,h);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.useProgram(program);const sx=1/(scale*w/h),sy=1/scale,sz=-1/20;const tx=-(r[0]*center[0]+r[3]*center[1]+r[6]*center[2]),ty=-(r[1]*center[0]+r[4]*center[1]+r[7]*center[2]),tz=-(r[2]*center[0]+r[5]*center[1]+r[8]*center[2]);gl.uniformMatrix4fv(gl.getUniformLocation(program,'mvp'),false,new Float32Array([sx*r[0],sy*r[1],sz*r[2],0,sx*r[3],sy*r[4],sz*r[5],0,sx*r[6],sy*r[7],sz*r[8],0,sx*tx,sy*ty,sz*tz,1]));gl.uniformMatrix3fv(gl.getUniformLocation(program,'rotation'),false,new Float32Array(r));function mesh(g,color,mode=gl.TRIANGLES,wire=false){gl.bindVertexArray(g.vao);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,wire?g.edge:g.index);gl.uniform3fv(gl.getUniformLocation(program,'color'),color);gl.uniform1f(gl.getUniformLocation(program,'unlit'),mode===gl.TRIANGLES?0:1);if(mode===gl.TRIANGLES){gl.enable(gl.POLYGON_OFFSET_FILL);gl.polygonOffset(1,1)}else gl.disable(gl.POLYGON_OFFSET_FILL);gl.drawElements(mode,wire?g.edgeData.length:g.indices.length,gl.UNSIGNED_INT,0)}if(showBody)mesh(geometry.body,[.51,.55,.56]);mesh(geometry.cloth,[.79,.37,.52]);if(showWire)mesh(geometry.cloth,[.42,.22,.29],gl.LINES,true);if(showSeams)geometry.seams.forEach((g,i)=>mesh(g,i%2?[.19,.30,.61]:[.96,.43,.13],gl.LINE_STRIP));gl.bindVertexArray(null)}
function drawCanvas(w,h,r,scale){ctx.fillStyle='#f1ece7';ctx.fillRect(0,0,w,h);const unit=h/(2*scale),project=p=>{const v=transform(p,r);return [w/2+v[0]*unit,h/2-v[1]*unit,v[2]]};let tris=[];for(const [g,col]of [[geometry.body,[130,140,143]],[geometry.cloth,[201,94,133]]]){if(g===geometry.body&&!showBody)continue;const pp=g.points.map(project);for(let i=0;i<g.indices.length;i+=3){const a=pp[g.indices[i]],b=pp[g.indices[i+1]],c=pp[g.indices[i+2]],u=b.map((v,k)=>v-a[k]),v=c.map((v,k)=>v-a[k]),n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],l=Math.hypot(...n)||1,brightness=.6+.4*Math.abs((-.35*n[0]+.5*n[1]+.79*n[2])/l);tris.push({p:[a,b,c],z:(a[2]+b[2]+c[2])/3,color:'rgb('+col.map(v=>Math.round(v*brightness)).join(',')+')',wire:g===geometry.cloth&&showWire})}}tris.sort((a,b)=>a.z-b.z);for(const t of tris){ctx.beginPath();ctx.moveTo(t.p[0][0],t.p[0][1]);ctx.lineTo(t.p[1][0],t.p[1][1]);ctx.lineTo(t.p[2][0],t.p[2][1]);ctx.closePath();ctx.fillStyle=t.color;ctx.fill();if(t.wire){ctx.lineWidth=.5;ctx.strokeStyle='#713c52';ctx.stroke()}}if(showSeams)geometry.seams.forEach((g,i)=>{ctx.beginPath();g.points.map(project).forEach((p,j)=>j?ctx.lineTo(p[0],p[1]):ctx.moveTo(p[0],p[1]));ctx.strokeStyle=i%2?'#344c9c':'#ed6b22';ctx.lineWidth=2;ctx.stroke()})}
function draw(){if(!geometry)return;const c=surface(),bounds=c.getBoundingClientRect(),dpr=Math.min(window.devicePixelRatio||1,2),w=Math.max(1,Math.round(bounds.width*dpr)),h=Math.max(1,Math.round(bounds.height*dpr));if(c.width!==w||c.height!==h){c.width=w;c.height=h}const r=rotation(),scale=radius/zoom;if(gl)drawGL(w,h,r,scale);else if(ctx)drawCanvas(w,h,r,scale)}
const pointers=new Map();let pinchDistance=0;
surface().addEventListener('pointerdown',e=>{pointers.set(e.pointerId,[e.clientX,e.clientY]);surface().setPointerCapture(e.pointerId);if(pointers.size===2){const p=[...pointers.values()];pinchDistance=Math.hypot(p[0][0]-p[1][0],p[0][1]-p[1][1])}});
surface().addEventListener('pointermove',e=>{if(!pointers.has(e.pointerId))return;const old=pointers.get(e.pointerId);pointers.set(e.pointerId,[e.clientX,e.clientY]);if(pointers.size===1){yaw+=(e.clientX-old[0])*.008;pitch=Math.max(-1.35,Math.min(1.35,pitch+(e.clientY-old[1])*.006))}else{const p=[...pointers.values()],d=Math.hypot(p[0][0]-p[1][0],p[0][1]-p[1][1]);if(pinchDistance>0)zoom=Math.max(.45,Math.min(4,zoom*d/pinchDistance));pinchDistance=d}requestDraw()});
for(const t of ['pointerup','pointercancel','lostpointercapture'])surface().addEventListener(t,e=>{pointers.delete(e.pointerId);pinchDistance=0});surface().addEventListener('wheel',e=>{e.preventDefault();zoom=Math.max(.45,Math.min(4,zoom*Math.exp(-e.deltaY*.001)));requestDraw()},{passive:false});
document.querySelectorAll('[data-view]').forEach(b=>b.addEventListener('click',()=>{const v=b.dataset.view;yaw=v==='side'?Math.PI/2:v==='back'?Math.PI:v==='front'?0:.5;pitch=v==='reset'?.12:0;zoom=v==='garment'?2:1;requestDraw()}));for(const id of ['body','seams','wire'])el(id).addEventListener('change',()=>{showBody=el('body').checked;showSeams=el('seams').checked;showWire=el('wire').checked;requestDraw()});el('case').addEventListener('change',choose);new ResizeObserver(requestDraw).observe(surface());choose();
</script></body></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path,
                        default=Path("/private/tmp/TailorAssClothResults"))
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # A new report is self-contained. Copy reference sources only when missing;
    # never replace an existing report's prose or change the original v1 folder.
    for image in ("garmentcode-header.png", "design2garmentcode-result-text.png"):
        target = output / "references" / image
        if not target.is_file():
            source_image = DEFAULT_REPORT / "references" / image
            if not source_image.is_file():
                raise SystemExit(f"Missing official reference image: {image}")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_image, target)
    source_note = output / "reference-sources.md"
    if not source_note.is_file() and output != DEFAULT_REPORT:
        shutil.copyfile(DEFAULT_REPORT / "reference-sources.md", source_note)
    cases = {}
    specifications = [
        ("0.5", "circle-0.5", "半圆裙 · suns 0.5", True),
        ("0.75", "circle-0.75", "四分之三圆裙 · suns 0.75", True),
        ("1.0", "circle-1.0", "整圆裙 · suns 1.0", True),
        ("0.75-length-0.35", "circle-0.75-length-0.35", "加长四分之三圆裙", False),
        ("0.75-material-soft", "circle-0.75-material-soft", "四分之三圆裙", False),
        ("0.75-material-firm", "circle-0.75-material-firm", "四分之三圆裙", False),
    ]
    for key, tag, title, required in specifications:
        source = args.input_dir / f"{tag}-mesh.json"
        if not source.is_file() and not required:
            continue
        raw = source.read_bytes()
        data = json.loads(raw)
        validate_mesh(data, source.name)
        material = data["diagnostics"].get("materialName")
        if material:
            title += " · " + material
        cases[key] = {
            "label": title,
            "filename": source.name,
            "sha256": hashlib.sha256(raw).hexdigest(),
            "mesh": data,
        }
    generated = output / "generated"
    generated.mkdir(parents=True, exist_ok=True)
    for item in cases.values():
        shutil.copyfile(args.input_dir / item["filename"], generated / item["filename"])
        pattern_name = item["filename"].replace("-mesh.json", "-pattern.json")
        if (args.input_dir / pattern_name).is_file():
            shutil.copyfile(args.input_dir / pattern_name, generated / pattern_name)
    # User-facing report time follows the task's client timezone, independently
    # of the process host's local clock configuration.
    generated_at = datetime.datetime.now(ZoneInfo("Asia/Shanghai"))
    stamp = generated_at.isoformat(timespec="seconds")
    display_stamp = generated_at.strftime("%Y-%m-%d %H:%M:%S（北京时间，UTC+08:00）")
    payload = json.dumps(cases, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    # JSON is placed in a data script, so an embedded </script> must not end it.
    payload = payload.replace("<", "\\u003c").replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")
    comparison_path = output / "comparison.json"
    if comparison_path.is_file():
        comparison = json.loads(comparison_path.read_text())
        if comparison.get("native_mesh_sha256") == cases["0.75"]["sha256"]:
            delta = comparison["maximum_source_coordinate_or_radius_delta_cm"]
            error = comparison["flat_area_relative_error"] * 100
            quantitative = f'''<section class="panel method"><h3>默认圆裙：与官方二维输入的自动对照</h3>
<p>锁定提交 d4496299、示例人体与默认参数。裁片端点及圆弧半径最大差为 {delta:.3g} cm；平面三角网格面积相对解析圆弧面积误差为 {error:.5f}%；两条侧缝已通过流形与三角面方向检查。</p>
<p>这些检查验证二维输入及网格化，不是官方最终三维成衣的误差。<a href="comparison.json">查看原始对照记录与文件校验值 ↗</a></p></section>'''
        else:
            quantitative = '<section class="panel method"><h3>二维对照需要更新</h3><p>对照记录与当前网格的校验值不同。请重新运行 compare-cloth-reference.py，不使用旧记录判断当前结果。</p></section>'
    else:
        quantitative = '<section class="panel method"><h3>尚未载入二维对照记录</h3><p>请先运行 compare-cloth-reference.py。</p></section>'
    anatomical = any("makehuman" in (item["mesh"]["diagnostics"].get("bodyModel") or "").lower()
                     for item in cases.values())
    checked_surface = all(item["mesh"]["diagnostics"].get("surfaceIntersectionCount") is not None
                          for item in cases.values())
    all_converged = all(item["mesh"]["diagnostics"]["converged"] for item in cases.values())
    stability = (f"本页 {len(cases)} 份实际输出均达到当前持续稳定检查。" if all_converged else
                 "本页部分输出尚未达到持续稳定检查，请按各方案的原始诊断判断。")
    body_observation = (
        "本批输出已使用 MakeHuman CC0 标准人体及同源碰撞场，包含腹部、臀部与双腿轮廓；量体数据仅用于有限尺寸拟合，不能还原个人真实体型。"
        if anatomical else
        "本批输出的人台仍是旋转对称的实验碰撞体，缺少腹部、臀部和双腿的真实接触差异。")
    contact_observation = (
        "已加入点面与边边的离散表面接触，并记录最终三角面交叉对数；末态计数为零不代表整个运动过程都没有穿透，也不等于连续碰撞检测。"
        if checked_surface else
        "本批旧格式输出未记录完整表面交叉检查；顶点间距处理不能排除边／三角面穿插。")
    material_observations = []
    base = cases["0.75"]["mesh"]
    for key in ("0.75-material-soft", "0.75-material-firm"):
        if key not in cases:
            continue
        variant = cases[key]["mesh"]
        if (variant["triangleIndices"] == base["triangleIndices"] and
                len(variant["positions"]) == len(base["positions"]) and
                variant["mannequinPositions"] == base["mannequinPositions"] and
                variant["mannequinTriangleIndices"] == base["mannequinTriangleIndices"]):
            squared = sum(sum((a[axis]-b[axis])**2 for axis in ("x", "y", "z"))
                          for a, b in zip(variant["positions"], base["positions"]))
            rms_mm = math.sqrt(squared/len(base["positions"]))*1000
            name = html.escape(variant["diagnostics"].get("materialName") or key)
            material_observations.append(f"{name}相对默认方案的最终顶点 RMS 变化为 {rms_mm:.2f} mm")
    material_observation = ("；".join(material_observations) + "。这些预设使用面积质量和数值柔顺度，没有实物面料标定。"
                            if material_observations else "本批固定数值材料尚未做实物标定。")
    observation = f'''<section class="panel method"><h3>这次效果对比的结论</h3>
<p>{stability}{body_observation}</p><p>{contact_observation}</p><p>{material_observation}</p>
<p>仍不能标记为达到 GarmentCode／Design2GarmentCode 的完整仿真质量：尚缺同人体、同参数、同材料的官方最终网格，连续碰撞、真实面料标定及跨片弯曲仍需完善。</p></section>'''
    options = "".join(f'<option value="{html.escape(key)}"{" selected" if key == "0.75" else ""}>{html.escape(item["label"])}</option>'
                      for key, item in cases.items())
    page = HTML.replace("__DATA__", payload).replace("__GENERATED_AT__", display_stamp).replace("__CASE_OPTIONS__", options)
    page = page.replace('.checks strong{font-weight:600;', '.checks strong{text-align:right;max-width:65%;overflow-wrap:anywhere;font-weight:600;')
    page = page.replace('<section class="panel method"><h3>如何读这份对比</h3>', quantitative + observation + '<section class="panel method"><h3>如何读这份对比</h3>')
    (output / "index.html").write_text(page, encoding="utf-8")
    manifest = {"generated_at": stamp,
                "cases": {k: {"file": v["filename"], "sha256": v["sha256"], "label": v["label"],
                              "converged": v["mesh"]["diagnostics"]["converged"],
                              "bodyModel": v["mesh"]["diagnostics"].get("bodyModel"),
                              "materialName": v["mesh"]["diagnostics"].get("materialName"),
                              "surfaceIntersectionCount": v["mesh"]["diagnostics"].get("surfaceIntersectionCount")}
                          for k, v in cases.items()}}
    (generated / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
        encoding="utf-8")
    print(output / "index.html")
    print(f"Embedded {len(cases)} actual meshes; source JSON and SHA-256 manifest copied.")


if __name__ == "__main__":
    main()
