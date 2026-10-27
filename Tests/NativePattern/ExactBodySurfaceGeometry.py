#!/usr/bin/env python3
"""Exact static closed-triangle oracle; shared source simplex is not a full-face exemption.

Core functions copied unchanged from the reviewed failed-state independent audit.
Original complete helper SHA256: 097d3391edf8aa09070feb4dd0c612ae2369cfd84b73c892a6e87432414cbe0b
"""
from fractions import Fraction as F
from collections import Counter
import time
import numpy as np

def points(a): return np.array([[p['x'],p['y'],p['z']] for p in a],dtype=np.float64)

def vsub(a,b): return tuple(x-y for x,y in zip(a,b))

def vadd(a,b): return tuple(x+y for x,y in zip(a,b))

def mul(a,t): return tuple(x*t for x in a)

def dot(a,b): return sum(x*y for x,y in zip(a,b))

def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])

def exactpoint(p): return tuple(F(float(x)) for x in p)

def normal(t): return cross(vsub(t[1],t[0]),vsub(t[2],t[0]))

def orient2(a,b,c): return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])

def project(p,k): return tuple(x for i,x in enumerate(p) if i!=k)

def inside(p,t,strict=False):
    n=normal(t);k=max(range(3),key=lambda i:abs(n[i]))
    a,b,c=[project(q,k) for q in t];q=project(p,k)
    s=orient2(a,b,c);w=[orient2(a,b,q),orient2(b,c,q),orient2(c,a,q)]
    return all(x*s>0 if strict else x*s>=0 for x in w)

def expected_shared(p,shared):
    if not shared:return False
    if len(shared)==1:return p==shared[0]
    if len(shared)==2:
        a,b=shared;d=vsub(b,a);r=vsub(p,a)
        return cross(d,r)==(0,0,0) and 0<=dot(r,d)<=dot(d,d)
    return inside(p,shared)

def coplanar_clip(a,b):
    n=normal(b);k=max(range(3),key=lambda i:abs(n[i]));bb=[project(q,k) for q in b]
    sign=1 if orient2(*bb)>0 else -1;poly=list(a)
    for i in range(3):
        u,v=bb[i],bb[(i+1)%3];out=[]
        if not poly:break
        for j,p in enumerate(poly):
            q=poly[(j+1)%len(poly)];dp=sign*orient2(u,v,project(p,k));dq=sign*orient2(u,v,project(q,k))
            if dp>=0:out.append(p)
            if (dp<0<dq) or (dq<0<dp):out.append(vadd(p,mul(vsub(q,p),dp/(dp-dq))))
        poly=list(dict.fromkeys(out))
    area=abs(sum(orient2((0,0),project(poly[i],k),project(poly[(i+1)%len(poly)],k)) for i in range(len(poly)))) if poly else F(0)
    return poly,area

def exact_intersection(a,b,shared=()):
    na,nb=normal(a),normal(b)
    if na==(0,0,0) or nb==(0,0,0):return 'degenerate',[]
    da=[dot(vsub(p,b[0]),nb) for p in a];db=[dot(vsub(p,a[0]),na) for p in b]
    if all(x>0 for x in da) or all(x<0 for x in da) or all(x>0 for x in db) or all(x<0 for x in db):return 'separated',[]
    if cross(na,nb)==(0,0,0):
        if any(da):return 'separated',[]
        ps,area=coplanar_clip(a,b)
        if not ps:return 'separated',[]
        if area:return 'coplanarPositiveArea',ps
    else:
        ps=[]
        for tri,ds,other in [(a,da,b),(b,db,a)]:
            for i,p in enumerate(tri):
                j=(i+1)%3;q=tri[j]
                if ds[i]==0 and inside(p,other):ps.append(p)
                if ds[i]*ds[j]<0:
                    r=vadd(p,mul(vsub(q,p),ds[i]/(ds[i]-ds[j])))
                    if inside(r,other):ps.append(r)
        ps=list(dict.fromkeys(ps))
        if not ps:return 'separated',[]
        middle=mul(tuple(sum(p[k] for p in ps) for k in range(3)),F(1,len(ps)))
        if inside(middle,a,True) and inside(middle,b,True):return 'properCrossing',ps
    if all(expected_shared(p,shared) for p in ps):return 'expectedTopologicalTouch',ps
    return 'unexpectedClosedTouch',ps

def intersection_audit(x,tri,y,other,self_mode):
    # Raw binary64 min/max comparisons are exact ordering of the supplied
    # vertices; inclusive AABB broad phase cannot cull a true intersection.
    aa=x[tri];bb=y[other];lo=bb.min(1);hi=bb.max(1)
    ex=[exactpoint(p) for p in x];ey=ex if self_mode else [exactpoint(p) for p in y]
    counts=Counter();examples=[];candidate_count=0;t0=time.time()
    for i,a in enumerate(aa):
        ids=np.flatnonzero(np.all(lo<=a.max(0),axis=1)&np.all(hi>=a.min(0),axis=1))
        if self_mode:ids=ids[ids>i]
        candidate_count+=len(ids)
        for j0 in ids:
            j=int(j0);shared_ids=set(map(int,tri[i]))&set(map(int,other[j])) if self_mode else set()
            shared=[ex[k] for k in sorted(shared_ids)]
            kind,ps=exact_intersection([ex[int(k)] for k in tri[i]],[ey[int(k)] for k in other[j]],shared)
            counts[kind]+=1
            if kind not in ['separated','expectedTopologicalTouch'] and len(examples)<30:
                examples.append(dict(triangleIDs=[i,j],vertexIDs=[tri[i].tolist(),other[j].tolist()],kind=kind,sharedVertexIDs=sorted(shared_ids),intersectionPoints=[[float(v) for v in p] for p in ps]))
        if i%500==0:print('crossing',self_mode,i,'/',len(tri),'candidates',candidate_count,flush=True)
    return dict(candidateTrianglePairs=candidate_count,allTrianglePairs=len(tri)*(len(tri)-1)//2 if self_mode else len(tri)*len(other),classifications=dict(counts),examples=examples,seconds=time.time()-t0,unresolvedPairs=counts['degenerate'])

def self_tests():
    q=lambda a:[exactpoint(p) for p in a]
    a=q([[0,0,0],[2,0,0],[0,2,0]])
    controls=[('separated',a,q([[0,0,1],[2,0,1],[0,2,1]]),()),('properCrossing',a,q([[.25,.25,-1],[.25,.25,1],[1,.25,0]]),()),('coplanarPositiveArea',a,q([[.2,.2,0],[1,.2,0],[.2,1,0]]),()),('expectedTopologicalTouch',a,q([[0,0,0],[2,0,0],[0,-2,0]]),a[:2]),('unexpectedClosedTouch',a,q([[0,0,0],[0,0,1],[-1,0,1]]),())]
    for expected,aa,bb,shared in controls:
        got,_=exact_intersection(aa,bb,shared);assert got==expected,(got,expected)
    # Disjoint coplanar but overlapping AABBs, and two perpendicular faces
    # sharing an edge, exercise degeneracies beyond ordinary proper crossing.
    assert exact_intersection(a,q([[1.5,1.5,0],[2,1.5,0],[1.5,2,0]]))[0]=='separated'
    assert exact_intersection(a,q([[0,0,0],[2,0,0],[0,0,1]]),a[:2])[0]=='expectedTopologicalTouch'
    return dict(exactTriangleIntersectionAnalyticControls=7,passed=True,syntheticGarmentGenerated=False)
