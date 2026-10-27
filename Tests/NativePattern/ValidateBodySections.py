#!/usr/bin/env python3
"""Independent scalar horizontal triangle slicing and source-edge provenance."""
from pathlib import Path
import sys,json,math,hashlib,struct,html
root=Path(sys.argv[1]);rows=[];cards=[]
for name in ['default','female']:
    data=json.loads((root/(name+'-sections.json')).read_text());p=[(x['x'],x['y'],x['z']) for x in data['sourcePositions']];ids=data['sourceTriangleIndices']
    raw=b'rigid-clearance-visible-body-v1\0'+struct.pack('<QQ',len(p),len(ids))+b''.join(struct.pack('<ddd',*x) for x in p)+b''.join(struct.pack('<I',x) for x in ids);sha=hashlib.sha256(raw).hexdigest()
    for item in data['sections']:
        s=item['section'];y=item['heightMeters'];assert s['status']=='complete' and s['bodyGeometrySHA256']==sha
        points={};segments=[];adj={}
        for face in range(len(ids)//3):
            tri=ids[3*face:3*face+3];keys=[]
            for a,b in zip(tri,tri[1:]+tri[:1]):
                if (p[a][1]<y)==(p[b][1]<y):continue
                a,b=sorted((a,b));key=(a,b);keys.append(key)
                t=(y-p[a][1])/(p[b][1]-p[a][1]);points[key]=tuple(p[a][k]+t*(p[b][k]-p[a][k]) for k in range(3))
            if keys:
                assert len(keys)==2;idx=len(segments);segments.append((keys[0],keys[1],face))
                for k in keys:adj.setdefault(k,[]).append(idx)
        assert all(len(x)==2 for x in adj.values());seen=set();expected={}
        for start in sorted(points):
            if all(x in seen for x in adj[start]):continue
            current=start;nodes=[];faces=[]
            while True:
                nodes.append(current);edge=next(e for e in adj[current] if e not in seen);seen.add(edge)
                a,b,f=segments[edge];faces.append(f);current=b if current==a else a
                if current==start:break
            poly=[points[k] for k in nodes]
            perimeter=math.fsum(math.dist(a,b) for a,b in zip(poly,poly[1:]+poly[:1]));origin=poly[0]
            area=abs(math.fsum((a[0]-origin[0])*(b[2]-origin[2])-(a[2]-origin[2])*(b[0]-origin[0]) for a,b in zip(poly,poly[1:]+poly[:1]))/2)
            expected[frozenset(nodes)]=(perimeter,area,set(faces))
        assert len(expected)==len(s['loops']) and len(segments)==s['sourceSegmentCount']
        loop_rows=[]
        for loop in s['loops']:
            vertices=loop['vertices'];keys=[(v['sourceEdge']['a'],v['sourceEdge']['b']) for v in vertices];perimeter,area,faces=expected.pop(frozenset(keys))
            assert abs(loop['perimeterMeters']-perimeter)<1e-10 and abs(loop['areaSquareMeters']-area)<1e-10
            assert {x['sourceTriangleID'] for x in loop['boundary']}==faces
            for i,v in enumerate(vertices):
                edge=keys[i];t=v['edgeParameter'];actual=tuple(v['position'][k] for k in ['x','y','z'])
                assert 0<t<1 and math.dist(actual,points[edge])<1e-12 and abs(actual[1]-y)<1e-12
                boundary=loop['boundary'][i];assert boundary['fromVertex']==i and boundary['toVertex']==(i+1)%len(vertices)
                source=ids[3*boundary['sourceTriangleID']:3*boundary['sourceTriangleID']+3]
                assert all(x in source for x in edge) and all(x in source for x in keys[(i+1)%len(keys)])
            loop_rows.append(dict(perimeterMeters=perimeter,areaSquareMeters=area,sourceSegments=len(vertices)))
        rows.append(dict(body=name,label=item['label'],heightMeters=y,geometrySHA256=sha,loops=loop_rows,configuredCircumferenceMeters=item['configuredCircumferenceMeters'],selection='none',fitApplied=False))
        allp=[v['position'] for l in s['loops'] for v in l['vertices']];svg=''
        if allp:
            xmin=min(v['x'] for v in allp);xmax=max(v['x'] for v in allp);zmin=min(v['z'] for v in allp);zmax=max(v['z'] for v in allp);scale=240/max(xmax-xmin,zmax-zmin,1e-9)
            palette=['#1976d2','#d94841','#2d9761','#9d4cc6','#b2791a']
            for i,l in enumerate(s['loops']):
                pts=' '.join(f"{10+(v['position']['x']-xmin)*scale:.5f},{10+(zmax-v['position']['z'])*scale:.5f}" for v in l['vertices'])
                svg+=f'<polygon points="{pts}" fill="none" stroke="{palette[i%len(palette)]}" stroke-width="1.5"/>'
        desc='; '.join(f"环{i+1}: {x['perimeterMeters']*100:.3f} cm / {x['areaSquareMeters']*10000:.3f} cm²" for i,x in enumerate(loop_rows))
        cards.append(f'<article><h3>{name} · {html.escape(item["label"])}</h3><p>Y = {y:.8f} m · {len(loop_rows)} 个独立环</p><svg viewBox="0 0 265 265">{svg}</svg><p>{desc}</p><small>{html.escape(item["heightSource"])}</small><p>所有环保留；没有选择躯干/腿环、没有拟合。</p></article>')
assert len(rows)==10
summary=dict(passed=True,caseCount=10,independent='Python scalar triangle-plane intersections, identity-by-source-edge graph, math.fsum polygon lengths/areas, exact binary source hash and complete source triangle boundary provenance',loopsRetained=True,anatomicalSelection=False,bodyFittingApplied=False,cases=rows)
(root/'independent-summary.json').write_text(json.dumps(summary,indent=2)+'\n')
(root/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>真实人体表面截面核验</title><style>body{font:16px system-ui;margin:35px;background:#f4f5f7;color:#243145}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(310px,1fr));gap:20px}article{background:white;border-radius:12px;padding:20px}svg{width:100%;height:260px}small{display:block;line-height:1.5}p{line-height:1.5}</style><h1>真实可见人体表面：截面环与来源</h1><p>三角面和平面直接求交，单位为米；不取凸包、不合并、不猜最大环。每个有色环单独给出周长和面积。胸线是参数垂直参考，未验证解剖点。本结果没有拟合26项量体数据。</p><main>'+''.join(cards)+'</main>')
print('PASS independent body sections:',len(rows),'planes; all loops, perimeter/area, exact hash, edge and triangle provenance verified; no body fit')
