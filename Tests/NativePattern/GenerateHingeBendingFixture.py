#!/usr/bin/env python3
"""Archive/verify the actual 2000V/3472T native source; never infer production groups.

Generation: --input-dir captured-native-directory --output-dir fixture-directory
Daily verification: --verify-dir fixture-directory (no /tmp/upstream dependency).
The archived plan must have the SAME original global IDs as the captured mesh.
"""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import shutil

CANONICAL_SOURCE_SHA256 = '28eb56b2ec46feddde570c300896cd6422045e6d119d0a2af11f667ae7604a35'

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def check(ok, reason):
    if not ok: raise ValueError(reason)
def point(p): return (p['x'], p['y'], p['z'])
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def length(a): return math.sqrt(sum(x*x for x in a))
def paper_point(panel, edge, t):
    a,b=[tuple(v/100 for v in panel['vertices'][i])+ (0.,) for i in edge['endpoints']]
    curve=edge.get('curvature')
    if not curve: return tuple(a[i]+(b[i]-a[i])*t for i in range(3))
    check(curve['type']=='circle','This fixed fixture only uses line and circle source edges')
    radius,large,right=curve['params'];large=bool(large);right=bool(right)
    d=length(sub(b,a));radius=max(radius/100,d/2)
    height=math.sqrt(max(0,radius*radius-d*d/4));sign=-1 if large==right else 1
    center=((a[0]+b[0])/2-(b[1]-a[1])/d*height*sign,(a[1]+b[1])/2+(b[0]-a[0])/d*height*sign,0.)
    theta=math.atan2(a[1]-center[1],a[0]-center[0]);last=math.atan2(b[1]-center[1],b[0]-center[0]);delta=last-theta
    if right:
        while delta<0:delta+=2*math.pi
        while delta>=2*math.pi:delta-=2*math.pi
    else:
        while delta>0:delta-=2*math.pi
        while delta<=-2*math.pi:delta+=2*math.pi
    if (abs(delta)>math.pi)!=large:delta+= -2*math.pi if right else 2*math.pi
    return (center[0]+radius*math.cos(theta+delta*t),center[1]+radius*math.sin(theta+delta*t),0.)

def verify_topology(raw, plan, source):
    check(raw['sourceSHA256']==plan['sourceSHA256']==CANONICAL_SOURCE_SHA256,'Canonical source SHA mismatch')
    ref=list(map(point,raw['referencePositions']));tris=raw['referenceTriangles'];n=len(ref)
    check(n==2000 and len(tris)==3472*3 and len(raw['positions'])==n,'Actual native source dimensions changed')
    check(len(raw['pinned'])==n and not any(raw['pinned']),'Source must retain zero pins')
    check(all(all(math.isfinite(c) for c in v) and abs(v[2])<1e-12 for v in ref),'Finite flat reference required')
    check(all(all(math.isfinite(c) for c in point(v)) for v in raw['positions']),'Finite actual rigid source required')
    adj=[set() for _ in ref];edges=collections.defaultdict(list);seen=set()
    for ti in range(len(tris)//3):
        ids=tris[ti*3:ti*3+3]
        check(len(set(ids))==3 and all(isinstance(v,int) and 0<=v<n for v in ids),'Invalid source triangle IDs')
        key=tuple(sorted(ids));check(key not in seen,'Duplicate source triangle');seen.add(key)
        a,b,c=[ref[v] for v in ids]
        check(cross(sub(b,a),sub(c,a))[2]>1e-14,'Expected original source CCW reference triangles')
        for j in range(3):
            a,b=ids[j],ids[(j+1)%3];adj[a].add(b);adj[b].add(a);edges[tuple(sorted((a,b)))].append((ti,a,b))
    check(all(1<=len(f)<=2 for f in edges.values()),'Nonmanifold source')
    check(all(len(f)==1 or (f[0][1]==f[1][2] and f[0][2]==f[1][1]) for f in edges.values()),'Inconsistent source orientation')
    paths=plan['allBoundaryPaths'];seed=collections.defaultdict(set);path_edges=set();edge_keys=set();maximum_error=0.
    paper=source['pattern']['panels']
    for path in paths:
        panelID=path['edge']['panelID'];ei=path['edge']['edgeIndex'];key=(panelID,ei)
        check(panelID in paper and key not in edge_keys,'Unknown/duplicate actual panel source edge');edge_keys.add(key)
        check(0<=ei<len(paper[panelID]['edges']),'Source edge index outside exact panel')
        ids=path['vertexIDs'];params=path['sourceParameters']
        check(len(ids)==len(params) and len(ids)>=2,'Boundary source parameter count')
        for v,t in zip(ids,params):
            check(0<=v<n and math.isfinite(t) and 0<=t<=1,'Boundary global ID or source parameter')
            seed[v].add(panelID)
            expected=paper_point(paper[panelID],paper[panelID]['edges'][ei],t)
            error=length(sub(ref[v],expected));maximum_error=max(maximum_error,error)
            check(error<1e-12,'Captured plan/mesh global IDs do not map to this exact source curve')
        check(len(path['segments'])==len(ids)-1,'Actual boundary segments missing')
        for j,segment in enumerate(path['segments']):
            a,b=segment['vertexIDs'];check([a,b]==ids[j:j+2],'Boundary segment does not follow actual path')
            key=tuple(sorted((a,b)));check(key in edges and len(edges[key])==1,'Path is not an actual source boundary edge')
            check(edges[key][0][0]==segment['adjacentTriangleID'],'Wrong same-global-ID adjacent source triangle')
            check(key not in path_edges,'Duplicated actual boundary edge');path_edges.add(key)
    check(edge_keys=={(name,i) for name,panel in paper.items() for i in range(len(panel['edges']))},'Incomplete canonical source edges')
    check(path_edges=={e for e,f in edges.items() if len(f)==1},'Plan paths do not cover all exact source boundaries')
    check(all(len(names)==1 for names in seed.values()),'Ambiguous boundary ownership')
    # Fixture generation only: topology connected components are uniquely tied to
    # analytic, named source boundary curves above. Production receives these
    # archived explicit groups and DOES NOT perform this recovery algorithm.
    owner=[None]*n;groups=[];visited=set()
    for first in range(n):
        if first in visited:continue
        ids=[];todo=[first];visited.add(first)
        while todo:
            v=todo.pop();ids.append(v)
            for other in adj[v]:
                if other not in visited:visited.add(other);todo.append(other)
        names=set().union(*(seed[v] for v in ids));check(len(names)==1,'Missing/ambiguous source panel identity')
        name=next(iter(names))
        for v in ids:owner[v]=name
        groups.append({'panelID':name,'vertexIDs':sorted(ids),'triangleIDs':[]})
    check({g['panelID'] for g in groups}==set(paper) and len(groups)==len(paper),'Complete source panel membership required')
    by_name={g['panelID']:g for g in groups}
    for ti in range(len(tris)//3):
        names={owner[v] for v in tris[3*ti:3*ti+3]};check(len(names)==1,'Triangle crosses panel ownership')
        by_name[next(iter(names))]['triangleIDs'].append(ti)
    groups.sort(key=lambda g:g['panelID'])
    return groups,{'vertices':n,'triangles':len(tris)//3,'internalHinges':sum(len(f)==2 for f in edges.values()),'boundaryEdges':len(path_edges),
                   'actualSewingConstraints':len(plan['constraints']),'maximumExactSourceBoundaryPointErrorMeters':maximum_error,
                   'groupDerivation':'Fixture-only unchanged global reference triangle components uniquely seeded by complete actual plan boundaries, every boundary sample checked against canonical analytic source curves; production consumes explicit groups and never guesses ownership.'}

def main():
    p=argparse.ArgumentParser();p.add_argument('--input-dir',type=Path);p.add_argument('--output-dir',type=Path);p.add_argument('--verify-dir',type=Path);a=p.parse_args()
    if a.verify_dir:
        root=a.verify_dir;m=json.loads((root/'manifest.json').read_text())
        for f,h in m['files'].items():check(digest(root/f)==h,'Fixture hash changed: '+f)
        check(digest(root/'complete-source.json')==CANONICAL_SOURCE_SHA256,'Canonical complete source changed')
        raw=json.loads((root/'native-source-topology.json').read_text());plan=json.loads((root/'native-full-plan.json').read_text());source=json.loads((root/'complete-source.json').read_text())
        groups,proof=verify_topology(raw,plan,source)
        check(raw['panelGroups']==groups,'Archived explicit panel groups do not match actual source/plan topology')
        check(m['topologyProof']==proof,'Archived source/plan proof changed')
        print(json.dumps({'status':'pass','canonicalSourceSHA256':CANONICAL_SOURCE_SHA256,**proof},indent=2));return
    check(a.input_dir is not None and a.output_dir is not None,'Generation needs --input-dir and --output-dir')
    root=a.output_dir;root.mkdir(parents=True,exist_ok=True);inp=a.input_dir
    check(digest(inp/'native-full-source.json')==CANONICAL_SOURCE_SHA256,'Captured full source hash changed')
    raw=json.loads((inp/'native-initial-input.json').read_text());plan=json.loads((inp/'native-full-plan.json').read_text());source=json.loads((inp/'native-full-source.json').read_text())
    groups,proof=verify_topology(raw,plan,source)
    trimmed={k:raw[k] for k in ['positions','referencePositions','referenceTriangles','pinned','sourceSHA256']};trimmed['panelGroups']=groups
    (root/'native-source-topology.json').write_text(json.dumps(trimmed,separators=(',',':'))+'\n')
    shutil.copyfile(inp/'native-full-source.json',root/'complete-source.json');shutil.copyfile(inp/'native-full-plan.json',root/'native-full-plan.json')
    m={'scope':'Exact canonical native source and same-global-ID mesh/plan membership for derivative tests only; no dynamics or accepted garment',
       'canonicalSourceSHA256':CANONICAL_SOURCE_SHA256,'originalCapturedInputSHA256':digest(inp/'native-initial-input.json'),
       'originalCapturedPlanSHA256':digest(inp/'native-full-plan.json'),'topologyProof':proof,
       'generatorSHA256':digest(Path(__file__)),'files':{f:digest(root/f) for f in ['complete-source.json','native-source-topology.json','native-full-plan.json']}}
    (root/'manifest.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(m,indent=2))
if __name__=='__main__':main()
