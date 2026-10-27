#!/usr/bin/env python3
"""Project-authored surface references from pinned CC0 assets only.

No MakeHuman application or measurement plugin/path data is read. Bones locate
regions during authoring; every saved measurement uses visible-surface points.
"""
from pathlib import Path
import hashlib,heapq,json,math
import sys

ROOT=None
T=R=P=F=VTO=STV=J=None
PACKAGES=None
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
add=lambda a,b:tuple(x+y for x,y in zip(a,b))
sub=lambda a,b:tuple(x-y for x,y in zip(a,b))
mul=lambda a,t:tuple(x*t for x in a)
dot=lambda a,b:sum(x*y for x,y in zip(a,b))
cross=lambda a,b:(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
norm=lambda a:math.sqrt(dot(a,a))
unit=lambda a:mul(a,1/norm(a))

def attachment(ids,weights):
    assert len(ids)==len(weights) and len(ids) in (1,2,3)
    return {'sourceVertexIDs':[VTO[i] for i in ids],'weights':list(weights)}
def point(a):
    return tuple(sum(P[STV[i]][k]*w for i,w in zip(a['sourceVertexIDs'],a['weights'])) for k in range(3))
def vertex(i):return attachment([i],[1.0])

def initialize(args):
    global ROOT,T,R,P,F,VTO,STV,J,EDGES,VF,ADJ,PACKAGES
    import shutil
    from PrepareBodyRig import prepare
    ROOT=args.output.resolve();ROOT.mkdir(parents=True,exist_ok=False)
    PACKAGES=args.python_packages
    shutil.copyfile(args.template,ROOT/'template.json');shutil.copyfile(args.rig,ROOT/'rig.json')
    shutil.copyfile(args.rig_provenance,ROOT/'rig-provenance.json');(ROOT/'assets').mkdir()
    # Four explicitly whitelisted pinned CC0 asset files; never scan plugins.
    for name in ['base.obj','default.mhskel','default_weights.mhw','LICENSE.ASSETS.md']:
        shutil.copyfile(args.source_dir/name,ROOT/'assets'/name)
    payload,_,_,_=prepare(ROOT/'assets',ROOT/'template.json')
    T=json.loads((ROOT/'template.json').read_text());R=json.loads((ROOT/'rig.json').read_text())
    # prepare() already requires exact reconstruction of every visible point
    # and triangle. Python3.12 changed sum() accumulation, so unrelated rig
    # metadata/weight means need not have the old Python3.9 JSON byte encoding.
    # Verify the source maps/table exactly and the locating joint means in the
    # original explicit scalar order; do not rewrite the pinned rig resource.
    assert payload['visibleToSource']==R['visibleToSource'] and payload['sourceToVisible']==R['sourceToVisible']
    assert payload['jointSourceVertexTable']==R['jointSourceVertexTable']
    assert len(payload['joints'])==len(R['joints'])
    for actual,record in zip(payload['joints'],R['joints']):
        assert all(actual[k]==record[k] for k in ['name','sourceVertexIDs','sourceVertexTableIndices'])
        expected=[]
        for axis in range(3):
            total=0.0
            for i in record['sourceVertexTableIndices']:total+=R['jointSourceVertexTable'][i]['templatePositionMeters'][axis]
            expected.append(total/len(record['sourceVertexTableIndices']))
        assert expected==record['templatePositionMeters'],'Locating proxy does not match its actual CC0 source surface/helper references'
    P=[tuple(p) for p in T['positions']];F=[tuple(T['triangleIndices'][i:i+3]) for i in range(0,len(T['triangleIndices']),3)]
    VTO=R['visibleToSource'];STV=R['sourceToVisible'];J={j['name']:tuple(j['templatePositionMeters']) for j in R['joints']}
    EDGES={};VF=[[] for _ in P];ADJ=[{} for _ in P]
    for i,f in enumerate(F):
        for v in f:VF[v].append(i)
        for a,b in zip(f,f[1:]+f[:1]):
            edge=tuple(sorted((a,b)));EDGES.setdefault(edge,[]).append(i)
            length=math.dist(P[a],P[b]);ADJ[a][b]=length;ADJ[b][a]=length
    assert all(len(ids)==2 for ids in EDGES.values())


def ray(origin,direction):
    d=unit(direction);hits=[]
    for i,f in enumerate(F):
        a,b,c=(P[v] for v in f);e1,e2=sub(b,a),sub(c,a)
        h=cross(d,e2);den=dot(e1,h)
        if abs(den)<1e-14:continue
        q=sub(origin,a);u=dot(q,h)/den
        if not -1e-12<=u<=1+1e-12:continue
        w=cross(q,e1);v=dot(d,w)/den;t=dot(e2,w)/den
        if v>=-1e-12 and u+v<=1+1e-12 and t>1e-9:
            weights=[1-u-v,u,v]
            if min(weights)<0:continue
            hits.append((t,i,attachment(f,weights)))
    assert hits,'No visible surface ray hit'
    hits.sort(key=lambda h:(h[0],h[1]));t,face,a=hits[0]
    return a,{'seed':origin,'direction':d,'distanceMeters':t,'triangleID':face,'allPositiveHitCount':len(hits)}

def supports(a):
    ids=[STV[i] for i in a['sourceVertexIDs']]
    return sorted(set.intersection(*(set(VF[i]) for i in ids)))

def route(start,end,side):
    a,b=point(start),point(end);start_node=-1;end_node=-2
    extra={start_node:{},end_node:{}};extra_faces={}
    for virtual,anchor in [(start_node,start),(end_node,end)]:
        for face in supports(anchor):
            for v in F[face]:
                extra[virtual][v]=math.dist(point(anchor),P[v]);extra_faces.setdefault((virtual,v),face)
    minimum_x=min(a[0]*side,b[0]*side)-0.07
    maximum_y=max(a[1],b[1])+0.05
    def allowed(v):return side*P[v][0]>=minimum_x and P[v][1]<=maximum_y
    distances={start_node:0};previous={};heap=[(0,start_node)]
    while heap:
        dist,u=heapq.heappop(heap)
        if dist!=distances.get(u):continue
        if u==end_node:break
        neighbors=dict(extra[u]) if u<0 else {v:w for v,w in ADJ[u].items() if allowed(v)}
        if u>=0 and u in extra[end_node]:neighbors[end_node]=extra[end_node][u]
        for v,w in sorted(neighbors.items()):
            nd=dist+w
            if nd<distances.get(v,math.inf):distances[v]=nd;previous[v]=u;heapq.heappush(heap,(nd,v))
    assert end_node in distances,'Surface route disconnected'
    nodes=[end_node]
    while nodes[-1]!=start_node:nodes.append(previous[nodes[-1]])
    nodes.reverse();samples=[start if v==start_node else end if v==end_node else vertex(v) for v in nodes]
    faces=[]
    for u,v in zip(nodes,nodes[1:]):
        face=extra_faces[(u,v)] if u<0 else extra_faces[(v,u)] if v<0 else min(EDGES[tuple(sorted((u,v)))])
        faces.append(face)
    # A virtual point equal to a vertex need not create a zero-length segment.
    compact=[samples[0]];compact_faces=[]
    for sample,face in zip(samples[1:],faces):
        if math.dist(point(compact[-1]),point(sample))>1e-14:compact.append(sample);compact_faces.append(face)
    return compact,compact_faces

def triangle_route(start,end,side,via=None,line_bias=0):
    """Optimize an actual piecewise-linear skin path within an authored strip.

    The search score only proposes a triangle corridor. Every final segment
    joins points of one ORIGINAL visible triangle. No 3D endpoint chord is
    substituted for a surface segment across different faces.
    """
    if PACKAGES:sys.path.insert(0,str(PACKAGES))
    import numpy as np
    from scipy.optimize import minimize
    a,b=point(start),point(end)
    centers=[mul(add(add(P[f[0]],P[f[1]]),P[f[2]]),1/3) for f in F]
    dual=[{} for _ in F]
    for edge,faces in EDGES.items():
        left,right=faces;dual[left][right]=edge;dual[right][left]=edge
    low=min(a[0]*side,b[0]*side)-.07;high=max(a[1],b[1])+.05
    def allowed(face):return side*centers[face][0]>=low and centers[face][1]<=high
    def corridor(first_anchor,last_anchor):
        first_point,last_point=point(first_anchor),point(last_anchor)
        goals=set(supports(last_anchor));distances={f:math.dist(first_point,centers[f]) for f in supports(first_anchor)}
        previous={};heap=[(d,f) for f,d in distances.items()];heapq.heapify(heap)
        best=math.inf;finish=None
        while heap:
            dist,u=heapq.heappop(heap)
            if dist!=distances.get(u):continue
            if dist>=best:break
            if u in goals:
                value=dist+math.dist(centers[u],last_point)
                if value<best:best,finish=value,u
            for v in sorted(dual[u]):
                if not allowed(v):continue
                delta=sub(b,a);t=max(0,min(1,dot(sub(centers[v],a),delta)/dot(delta,delta)))
                offset=math.dist(centers[v],add(a,mul(delta,t)))
                nd=dist+math.dist(centers[u],centers[v])*(1+line_bias*offset)
                if nd<distances.get(v,math.inf):distances[v]=nd;previous[v]=u;heapq.heappush(heap,(nd,v))
        assert finish is not None
        strip=[finish]
        while strip[-1] in previous:strip.append(previous[strip[-1]])
        strip.reverse();return strip
    if via is None:strip=corridor(start,end)
    else:
        one,two=corridor(start,via),corridor(via,end);assert one[-1]==two[0]
        raw=one+two[1:];strip=[]
        for face in raw:
            if face in strip:strip=strip[:strip.index(face)+1]
            else:strip.append(face)
    portals=[dual[x][y] for x,y in zip(strip,strip[1:])]
    first=np.asarray([P[e[0]] for e in portals]);directions=np.asarray([sub(P[e[1]],P[e[0]]) for e in portals])
    def objective(t,epsilon=0.0):
        points=np.vstack([np.asarray(a),first+directions*t[:,None],np.asarray(b)])
        differences=points[1:]-points[:-1];lengths=np.sqrt(np.sum(differences*differences,axis=1)+epsilon*epsilon)
        units=differences/np.maximum(lengths[:,None],1e-30)
        gradient=np.sum(directions*(units[:-1]-units[1:]),axis=1)
        return float(np.sum(lengths)),gradient
    initial=np.full(len(portals),.5)
    current=initial;continuation=[]
    # Smooth only the AUTHORING optimizer's norm at coincident portal points.
    # Final length is always the actual unsmoothed original-surface path.
    # At epsilon each total approximation error is <= segmentCount*epsilon.
    for epsilon in [1e-4,1e-5,1e-6,1e-7,1e-8,1e-9]:
        result=minimize(lambda t:objective(t,epsilon),current,jac=True,method='L-BFGS-B',bounds=[(0,1)]*len(portals),
                        options={'ftol':1e-15,'gtol':1e-11,'maxiter':5000,'maxls':80})
        current=result.x
        continuation.append({'epsilonMeters':epsilon,'smoothedLengthMeters':float(result.fun),
            'actualLengthMeters':objective(current)[0],'iterations':int(result.nit),'termination':str(result.message)})
    assert math.isfinite(objective(result.x)[0]) and objective(result.x)[0]<=objective(initial)[0]
    samples=[start]
    for edge,t in zip(portals,result.x):
        # Authoring only: canonicalize numerical active bounds to a source
        # vertex (at most 1e-9 edge length); the source mesh never moves.
        if t<1e-9:samples.append(vertex(edge[0]))
        elif t>1-1e-9:samples.append(vertex(edge[1]))
        else:samples.append(attachment(edge,[1-float(t),float(t)]))
    samples.append(end);compact=[samples[0]];faces=[]
    for sample,face in zip(samples[1:],strip):
        if math.dist(point(compact[-1]),point(sample))<=1e-13:continue
        assert set(compact[-1]['sourceVertexIDs'])|set(sample['sourceVertexIDs']) <= {VTO[v] for v in F[face]}
        compact.append(sample);faces.append(face)
    trace={'triangleCorridor':strip,'portals':portals,'optimizer':'SciPy1.13.1 L-BFGS-B; authored fixed triangle corridor',
           'termination':str(result.message),'iterations':int(result.nit),'success':bool(result.success),
           'initialStripMidpointLengthMeters':objective(initial)[0],'optimizedLengthMeters':objective(result.x)[0],
           'smoothAuthoringContinuation':continuation,
           'canonicalizedLengthMeters':length({'samples':compact},False),'chordLowerBoundMeters':math.dist(a,b),
           'notGlobalGeodesicClaim':True,'corridorLineBiasPerMeter':line_bias}
    return compact,faces,trace

def section(origin,normal):
    n=unit(normal);signed=[dot(sub(p,origin),n) for p in P]
    points={};segments={};isolated=[]
    for face,f in enumerate(F):
        if all(signed[v]==0 for v in f):raise ValueError(f'Coplanar source face {face}')
        keys=[]
        for a,b in zip(f,f[1:]+f[:1]):
            da,db=signed[a],signed[b]
            if da==0:
                key=('v',a);points[key]=vertex(a);keys.append(key)
            if da*db<0:
                a,b=sorted((a,b));t=signed[a]/(signed[a]-signed[b]);key=('e',a,b)
                points[key]=attachment([a,b],[1-t,t]);keys.append(key)
        keys=list(dict.fromkeys(keys))
        if len(keys)==2:
            edge=tuple(sorted(keys));segments.setdefault(edge,[]).append(face)
        elif len(keys)==1:isolated.append({'triangleID':face,'point':keys[0]})
        else:assert len(keys)==0,(face,keys)
    adj={}
    for edge in segments:
        a,b=edge;adj.setdefault(a,[]).append(b);adj.setdefault(b,[]).append(a)
    assert all(len(v)==2 for v in adj.values()),'Section has non-manifold/touching contour'
    remaining=set(segments);loops=[]
    while remaining:
        start=min(remaining)[0];nodes=[start];faces=[];previous=None;current=start
        while True:
            candidates=sorted(adj[current]);nxt=candidates[0] if candidates[0]!=previous else candidates[1]
            edge=tuple(sorted((current,nxt)));assert edge in remaining
            remaining.remove(edge);faces.append(min(segments[edge]));previous,current=current,nxt
            if current==start:break
            assert current not in nodes;nodes.append(current)
        loops.append({'samples':[points[k] for k in nodes],'sourceTriangleIDs':faces})
    return loops,{'normal':n,'origin':origin,'isolatedTangentTriangleCount':len(isolated),'loopCount':len(loops)}

def contains(loop,origin,normal):
    drop=max(range(3),key=lambda i:abs(normal[i]));axes=[i for i in range(3) if i!=drop]
    p=[origin[i] for i in axes];poly=[[point(a)[i] for i in axes] for a in loop['samples']]
    winding=0
    for a,b in zip(poly,poly[1:]+poly[:1]):
        orient=(b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])
        if a[1]<=p[1]<b[1] and orient>0:winding+=1
        elif b[1]<=p[1]<a[1] and orient<0:winding-=1
    return winding!=0

def selected_section(origin,normal,region):
    loops,meta=section(origin,normal);selected=[i for i,l in enumerate(loops) if contains(l,origin,normal)]
    assert len(selected)==1,('Not a unique containing loop',selected)
    loop=loops[selected[0]]
    assert all(region(point(a)) for a in loop['samples']),'Selected loop leaves authored surface region'
    meta['selectedLoopIndex']=selected[0];meta['allLoops']=[{'perimeterMeters':length(l,True),'sourceTriangleIDs':l['sourceTriangleIDs'],'points':[point(a) for a in l['samples']]} for l in loops]
    return loop,meta

def length(path,closed):
    points=[point(a) for a in path['samples']]
    return sum(math.dist(a,b) for a,b in zip(points,points[1:]+(points[:1] if closed else [])))

def main():
    provenance=json.loads((ROOT/'rig-provenance.json').read_text())
    for asset in provenance['assets']:
        assert sha(ROOT/'assets'/asset['filename'])==asset['sha256'] and asset['license']=='CC0-1.0'
    assert sha(ROOT/'template.json')==provenance['templateResourceSHA256'] and sha(ROOT/'rig.json')==provenance['rigResourceSHA256']
    landmarks={};measurements=[];authoring={}
    # Source-owned visible breast rig endpoints are only geometric chest seeds.
    for side,label in [(1,'L'),(-1,'R')]:
        joint=next(j for j in R['joints'] if j['name']==f'breast.{label}____tail')
        assert len(joint['sourceVertexIDs'])==1 and STV[joint['sourceVertexIDs'][0]]>=0
        landmarks[f'chestSurfaceReference.{label}']=vertex(STV[joint['sourceVertexIDs'][0]])
        shoulder,trace=ray(J[f'upperarm01.{label}____head'],(0,1,0))
        landmarks[f'shoulderSurfaceReference.{label}']=shoulder;authoring[f'shoulder.{label}']=trace
        elbow=J[f'lowerarm01.{label}____head'];upper=J[f'upperarm01.{label}____head'];wrist=J[f'wrist.{label}____head']
        outward=mul(add(unit(sub(upper,elbow)),unit(sub(wrist,elbow))),-1)
        elbow_surface,trace=ray(elbow,outward)
        landmarks[f'outerElbowSurfaceReference.{label}']=elbow_surface;authoring[f'elbow.{label}']=trace
        axis=unit(sub(wrist,elbow))
        wrist_loop,trace=selected_section(wrist,axis,lambda p:side*p[0]>.40 and -.15<p[1]<.08)
        authoring[f'wrist.{label}']=trace
        measurements.append({'id':f'wristSurfaceLoop.{label}','targetKey':'wrist','kind':'surfacePath','closed':True,**wrist_loop,
            'definition':'Project wrist reference: visible-surface closed intersection of the authored forearm-normal plane; the rig center was only an authoring seed.'})
        radial=sub(outward,mul(axis,dot(outward,axis)))
        end=max(wrist_loop['samples'],key=lambda a:dot(sub(point(a),wrist),radial))
        landmarks[f'wristArmRouteEnd.{label}']=end
        old_first,old_faces1=route(shoulder,elbow_surface,side);old_second,old_faces2=route(elbow_surface,end,side)
        old_path={'samples':old_first+old_second[1:],'sourceTriangleIDs':old_faces1+old_faces2}
        guide,guide_trace=ray(mul(add(upper,elbow),.5),(0,0,-1))
        landmarks[f'posteriorUpperArmGuide.{label}']=guide;authoring[f'upperArmGuide.{label}']=guide_trace
        alternatives=[triangle_route(shoulder,elbow_surface,side,line_bias=bias) for bias in [0,25,100,400]]
        alternatives.append(triangle_route(shoulder,elbow_surface,side,via=guide))
        first,faces1,trace1=min(alternatives,key=lambda p:length({'samples':p[0]},False))
        trace1={**trace1,'candidateSurfaceLengthsMeters':[length({'samples':trial[0]},False) for trial in alternatives]}
        second,faces2,trace2=triangle_route(elbow_surface,end,side)
        path={'samples':first+second[1:],'sourceTriangleIDs':faces1+faces2}
        authoring[f'armRoute.{label}']={'originalEdgeWalkLengthMeters':length(old_path,False),'originalEdgeWalk':old_path,
            'surfaceTriangleRouteLengthMeters':length(path,False),'upperStrip':trace1,'lowerStrip':trace2}
        chord=math.dist(point(shoulder),point(elbow_surface))+math.dist(point(elbow_surface),point(end))
        measurements.append({'id':f'outerArmSurfaceRoute.{label}','targetKey':'arm_length','kind':'surfacePath','closed':False,**path,
            'viaLandmark':f'outerElbowSurfaceReference.{label}','chordLowerBoundMeters':chord,
            'definition':'Project outer-arm reference: continuous piecewise-linear original-triangle surface route shoulder->authored outer elbow->authored wrist-loop point. Portal points optimized within a fixed authored triangle corridor; not a bone length or global geodesic claim.'})
    chest_y=sum(point(landmarks[f'chestSurfaceReference.{s}'])[1] for s in ['L','R'])/2
    chest,trace=selected_section((0,chest_y,0),(0,1,0),lambda p:abs(p[0])<.27 and -.02<p[1]<.27)
    authoring['chest']=trace
    measurements.insert(0,{'id':'chestSurfaceReference','targetKey':'bust','kind':'surfacePath','closed':True,**chest,
        'definition':'Project chest reference: horizontal actual torso skin contour through mean height of the two named visible chest surface references; unique loop strictly containing the declared torso axis, within the authored torso region. Not an automatic maximum-bust detector.'})
    measurements.insert(1,{'id':'shoulderSurfaceSpan','targetKey':'shoulder_w','kind':'pointDistance','samples':[landmarks['shoulderSurfaceReference.L'],landmarks['shoulderSurfaceReference.R']],
        'definition':'Project shoulder reference: 3D straight span between the authored upper-shoulder surface ray hits. These are actual skin attachments, not bone-head distance; no back-surface tape length is implied.'})
    measurements.insert(2,{'id':'shoulderLateralSurfaceWidth','targetKey':'shoulder_w','kind':'axisDistanceX',
        'samples':[landmarks['shoulderSurfaceReference.L'],landmarks['shoulderSurfaceReference.R']],
        'definition':'Project +X lateral separation of the two actual shoulder skin references. Pinned GarmentCode bodice/sleeve programs consume shoulder_w / 2 as a lateral half-width; this is not a back-surface tape arc.'})
    titles={'chestSurfaceReference':'胸围表面参考','shoulderSurfaceSpan':'两肩表面点直线跨度（参考）',
        'shoulderLateralSurfaceWidth':'两肩表面点横向间距','wristSurfaceLoop.L':'左腕表面环','wristSurfaceLoop.R':'右腕表面环',
        'outerArmSurfaceRoute.L':'左臂表面参考长度','outerArmSurfaceRoute.R':'右臂表面参考长度'}
    for m in measurements:
        m['title']=titles[m['id']]
        m['targetUse']='referenceOnly' if m['id']=='shoulderSurfaceSpan' else 'projectFittingReference'
        m['templateObservedMeters']=(abs(point(m['samples'][0])[0]-point(m['samples'][1])[0]) if m['kind']=='axisDistanceX' else length(m,m.get('closed',False)))
        for a,b,face in zip(m['samples'],m['samples'][1:]+(m['samples'][:1] if m.get('closed') else []),m.get('sourceTriangleIDs',[])):
            ids={VTO[v] for v in F[face]}
            assert set(a['sourceVertexIDs'])<=ids and set(b['sourceVertexIDs'])<=ids
    data={'format':'tailorass-project-body-surface-contract-v1','sourceLicense':'CC0-1.0','sourceCommit':R['sourceCommit'],
        'templateResourceSHA256':sha(ROOT/'template.json'),'rigResourceSHA256':sha(ROOT/'rig.json'),'sourceOBJ':provenance['assets'][0],
        'sourceVertexCount':len(STV),'visibleVertexCount':len(P),'triangleCount':len(F),'visibleToSource':VTO,
        'annotationOrigin':'TailorAss original project-authored geometric reference annotations; no third-party measurement plugin or path indices used.',
        'authoringPose':'Pinned canonical CC0 template; fit in this reference pose before optional skinning. No pose-independent anatomical claim.',
        'landmarks':landmarks,'measurements':measurements,
        'scope':'Read-only project-authored surface reference measurements; this does not fit a body or change the default visible/collision mesh.',
        'limitations':['Chest uses an authored reference level, not a detected fullest-bust plane.','Shoulder span is a specified straight reference between skin points, not an ISO or back-tape measurement.','Arm route is optimized inside selected original triangle corridors; it is an authored surface reference, not a globally certified geodesic or a measured physical tape.','Wrist loops are fixed skin paths on the source topology; arbitrary later deformation may make them nonplanar.','Rig proxy seeds only authored search regions; runtime measurements use only actual visible source attachments.']}
    import PrepareBodyRig
    data['generator']={'path':'Tests/NativePattern/PrepareBodySurfaceMeasurements.py','sha256':sha(Path(__file__)),
        'cc0ReconstructionHelperSHA256':sha(Path(PrepareBodyRig.__file__)),
        'inputs':'Only the four pinned CC0 assets and current unchanged template/rig/provenance; no MakeHuman app/plugin measurement paths.'}
    data['parameterConventionEvidence']=[{'commit':'d449629979028123a5c4dc9e732a2ec19b7fce31',
        'path':'assets/bodies/body_params.py','rule':'_base_sleeve_balance = shoulder_w - 2'},
        {'commit':'d449629979028123a5c4dc9e732a2ec19b7fce31','path':'assets/garment_programs/bodice.py','rule':'shoulder_w / 2 is consumed as lateral half-width'},
        {'commit':'d449629979028123a5c4dc9e732a2ec19b7fce31','path':'assets/garment_programs/sleeves.py','rule':'Sleeve total length uses arm_length after armhole projection; no surface tape path is specified there.'}]
    (ROOT/'GarmentCodeBodySurfaceMeasurements.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    (ROOT/'authoring-trace.json').write_text(json.dumps(authoring,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({m['id']:{'meters':m['templateObservedMeters'],'samples':len(m['samples']),'faces':len(m.get('sourceTriangleIDs',[]))} for m in measurements},indent=2))

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir',type=Path,required=True)
    parser.add_argument('--template',type=Path,required=True)
    parser.add_argument('--rig',type=Path,required=True)
    parser.add_argument('--rig-provenance',type=Path,required=True)
    parser.add_argument('--python-packages',type=Path,help='Optional pinned NumPy/SciPy package root for this offline authoring tool')
    parser.add_argument('--output',type=Path,required=True)
    initialize(parser.parse_args());main()
