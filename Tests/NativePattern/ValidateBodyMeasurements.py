#!/usr/bin/env python3
"""Independent scalar slice/perimeter and exact-Fraction loop selection oracle."""
from fractions import Fraction as F
from pathlib import Path
import json,sys,hashlib,struct,math
out=Path(sys.argv[1]);rows=[]
for name in ['default','female']:
 j=json.loads((out/(name+'-measurements.json')).read_text());s=j['source'];p=[tuple(v[a] for a in ['x','y','z']) for v in s['positions']];tri=s['triangleIndices'];values=s['bodyValues']
 raw=b'rigid-clearance-visible-body-v1\0'+struct.pack('<QQ',len(p),len(tri))+b''.join(struct.pack('<ddd',*v) for v in p)+b''.join(struct.pack('<I',x) for x in tri)
 assert hashlib.sha256(raw).hexdigest()==s['geometrySHA256']
 params=b'body-reference-measurements-parameters-v1\0'+b''.join(k.encode()+b'\0'+struct.pack('<d',values[k]) for k in sorted(values))
 assert len(values)==33 and hashlib.sha256(params).hexdigest()==s['parameterSHA256']
 assert j['height']['observedMeters']==max(v[1] for v in p)-min(v[1] for v in p)
 for m in j['measurements']:
  section=m['section'];y=m['request']['plane']['origin']['y'];points={};exact={};segments=[];adj={}
  assert section['status']=='complete' and section['bodyGeometrySHA256']==s['geometrySHA256']
  for fi in range(len(tri)//3):
   ids=tri[3*fi:3*fi+3];keys=[]
   for ia,ib in zip(ids,ids[1:]+ids[:1]):
    if (p[ia][1]<y)==(p[ib][1]<y):continue
    a,b=sorted((ia,ib));key=(a,b);keys.append(key);t=(y-p[a][1])/(p[b][1]-p[a][1]);points[key]=tuple(p[a][k]+t*(p[b][k]-p[a][k]) for k in range(3))
    ta=(F(y)-F(p[a][1]))/(F(p[b][1])-F(p[a][1]));exact[key]=tuple(F(p[a][k])+ta*(F(p[b][k])-F(p[a][k])) for k in range(3))
   if keys:
    assert len(keys)==2;idx=len(segments);segments.append((keys[0],keys[1],fi))
    for key in keys:adj.setdefault(key,[]).append(idx)
  assert all(len(a)==2 for a in adj.values());seen=set();expected={}
  for start in sorted(points):
   if all(a in seen for a in adj[start]):continue
   cur=start;nodes=[];faces=[]
   while True:
    nodes.append(cur);edge=next(e for e in adj[cur] if e not in seen);seen.add(edge);a,b,f=segments[edge];faces.append(f);cur=b if cur==a else a
    if cur==start:break
   poly=[points[k] for k in nodes];perimeter=math.fsum(math.dist(a,b) for a,b in zip(poly,poly[1:]+poly[:1]))
   # The declared axis is (0,Y,0). Strict winding uses exact intersections of
   # original Float64 triangles, not the rounded Swift contour or max loop.
   winding=0
   e=[exact[k] for k in nodes]
   for aa,bb in zip(e,e[1:]+e[:1]):
    ax,ay=aa[0],aa[2];bx,by=bb[0],bb[2];orient=(bx-ax)*(-ay)-(by-ay)*(-ax)
    assert not(orient==0 and min(ax,bx)<=0<=max(ax,bx) and min(ay,by)<=0<=max(ay,by))
    if ay<=0<by and orient>0:winding+=1
    if by<=0<ay and orient<0:winding-=1
   expected[frozenset(nodes)]=(perimeter,set(faces),winding!=0)
  assert len(expected)==len(section['loops'])
  containing=[]
  for i,l in enumerate(section['loops']):
   keys=[(v['sourceEdge']['a'],v['sourceEdge']['b']) for v in l['vertices']];perimeter,faces,inside=expected[frozenset(keys)]
   assert abs(perimeter-l['perimeterMeters'])<1e-10
   assert faces=={v['sourceTriangleID'] for v in l['boundary']}
   if inside:containing.append(i)
   for v,key in zip(l['vertices'],keys):assert math.dist(tuple(v['position'][a] for a in ['x','y','z']),points[key])<1e-12
  assert len(containing)==1 and m['selectedLoopIndex']==containing[0]
  selected=section['loops'][containing[0]]['perimeterMeters'];assert m['observedMeters']==selected
  assert m['observedMinusRequestedMeters']==selected-values[m['request']['targetKey']]/100
  assert m['anatomicalComparisonStatus']=='unsupported' and m['anatomicalComparisonIssue']=='uncertifiedAnatomicalRegion'
  rows.append({'profile':name,'reference':m['request']['id'],'geometrySHA256':s['geometrySHA256'],'loops':len(section['loops']),'selected':containing[0],'perimeterMeters':selected,'referenceResidualMeters':m['observedMinusRequestedMeters'],'exactFractionUniqueInterior':True})
 assert j['bodyFittingApplied'] is False and j['anatomicalDefinitionsEstablished'] is False
summary={'passed':True,'measurements':rows,'method':'Independent scalar source-edge slicing, math.fsum perimeters, original-binary exact-Fraction triangle-plane points and strict winding, independent source/parameter SHA; no body fit'}
(out/'independent-summary.json').write_text(json.dumps(summary,indent=2)+'\n');print('PASS independent measurements',len(rows))
