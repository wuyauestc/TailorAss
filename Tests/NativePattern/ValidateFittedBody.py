#!/usr/bin/env python3
"""Independent final fitted mesh, source/goal binding and complete static audit."""
from pathlib import Path
from functools import lru_cache
from collections import Counter
import argparse,hashlib,json,math,struct,sys,time,traceback
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('output',type=Path);parser.add_argument('--profile',choices=['default','female'],required=True);parser.add_argument('--python-packages',type=Path);a=parser.parse_args()
if a.python_packages:sys.path.insert(0,str(a.python_packages))
import numpy as np
import ExactBodySurfaceGeometry as G
r=a.output;name=a.profile;started=time.monotonic()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def points(v):return np.array([[p[k] for k in ['x','y','z']] for p in v],dtype=np.float64)
try:
    j=json.loads((r/(name+'-prepared.json')).read_text());b=j['bindings'];p=points(j['positions']);tri=np.array(j['triangleIndices'],int).reshape(-1,3);resource=r/'snapshot/resources'
    contract=json.loads((resource/'GarmentCodeBodySurfaceMeasurements.json').read_text());rig=json.loads((resource/'GarmentCodeStandardBodyRig/rig.json').read_text());template=json.loads((resource/'GarmentCodeStandardBody.json').read_text())
    assert b['templateResourceSHA256']==sha(resource/'GarmentCodeStandardBody.json') and b['rigResourceSHA256']==sha(resource/'GarmentCodeStandardBodyRig/rig.json')
    assert b['contractSHA256']==sha(resource/'GarmentCodeBodySurfaceMeasurements.json') and b['auxiliaryResourceSHA256']==sha(resource/'GarmentCodeBodyFitAuxiliaryWeights.json')
    assert p.shape==(13380,3) and len(tri)==26756 and list(tri.ravel())==template['triangleIndices']
    raw=b'rigid-clearance-visible-body-v1\0'+struct.pack('<QQ',len(p),tri.size)+p.astype('<f8').tobytes()+tri.astype('<u4').tobytes();assert hashlib.sha256(raw).hexdigest()==b['finalGeometrySHA256']
    source_map=b'fitted-visible-source-map-v1\0'+b''.join(struct.pack('<Q',i) for i in contract['visibleToSource']);assert hashlib.sha256(source_map).hexdigest()==b['sourceMappingSHA256']
    faces=b'fitted-source-triangles-v1\0'+tri.astype('<u4').tobytes();assert hashlib.sha256(faces).hexdigest()==b['triangleIndicesSHA256']
    values=b['bodyValues'];param=b'body-surface-measurements-parameters-v1\0'+b''.join(k.encode()+b'\0'+struct.pack('<d',values[k]) for k in sorted(values));assert len(values)==33 and hashlib.sha256(param).hexdigest()==b['sourceParameterSHA256']
    assert b['patternReferenceCompatible'] and b['alphaDegrees']==values['arm_pose_angle'] and b['goalToleranceMeters']==1e-5
    rest=j['restMeasurements'];rp=points(rest['positions']);inverse=rig['sourceToVisible'];maximum_error=0.;goals=[]
    assert rest['bodyValues']==values and rest['geometrySHA256']==b['fittedRestGeometrySHA256']
    for m in contract['measurements']:
        if m['targetUse']!='projectFittingReference':continue
        q=[tuple(math.fsum(float(rp[inverse[i],k])*w for i,w in zip(x['sourceVertexIDs'],x['weights'])) for k in range(3)) for x in m['samples']]
        if m['kind']=='axisDistanceX':observed=abs(q[1][0]-q[0][0])
        else:
            if m.get('closed'):q.append(q[0])
            observed=math.fsum(math.dist(x,y) for x,y in zip(q,q[1:]))
        stored=next(x for x in rest['measurements'] if x['definition']['id']==m['id']);error=abs(observed-stored['observedMeters']);maximum_error=max(maximum_error,error);assert error<2e-12
        residual=observed-values[m['targetKey']]/100;assert abs(residual)<=1e-5
        goals.append({'id':m['id'],'observedMeters':observed,'residualMeters':residual})
    assert len(goals)==6
    counts=Counter();directions=Counter()
    for face in tri:
        for u,v in zip(face,np.roll(face,-1)):counts[tuple(sorted([int(u),int(v)]))]+=1;directions[(int(u),int(v))]+=1
    assert set(counts.values())=={2} and all(directions[(v,u)]==n for (u,v),n in directions.items())
    t=p[tri];normal=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);area=np.linalg.norm(normal,axis=1)/2;assert np.all(area>0)
    original=G.normal
    @lru_cache(maxsize=131072)
    def cached(t):return original(t)
    G.normal=lambda t:cached(tuple(t));G.self_tests();intersection=G.exact_intersection;visits=0
    def bounded(x,y,shared=()):
        global visits
        visits+=1
        if visits>2_000_000:raise RuntimeError('Independent candidate budget; no clear result')
        if visits%256==0 and (r/'CANCEL').exists():raise RuntimeError('Independent audit cancelled; no clear result')
        return intersection(x,y,shared)
    G.exact_intersection=bounded;cross=G.intersection_audit(p,tri,p,tri,True)
    assert cross['unresolvedPairs']==0 and set(cross['classifications']).issubset({'separated','expectedTopologicalTouch'})
    production=j['finalGeometry'];assert cross['candidateTrianglePairs']==production['candidateTrianglePairs'] and cross['classifications']['expectedTopologicalTouch']==production['expectedTopologicalTouchPairs']
    result={'passed':True,'profile':name,'geometrySHA256':b['finalGeometrySHA256'],'independentGoals':goals,'maximumIndependentLengthDifferenceMeters':maximum_error,
        'completeStaticSelf':cross,'orientedClosedEdges':len(counts),'minimumTriangleAreaSquareMeters':float(area.min()),'signedVolumeCubicMeters':float(np.einsum('ij,ij->i',t[:,0],np.cross(t[:,1],t[:,2])).sum()/6),
        'scope':'Actual factory final fixed mesh and rest-goal binding only; no cloth or swept motion proof.'}
except Exception:result={'passed':False,'profile':name,'error':traceback.format_exc()}
result['seconds']=time.monotonic()-started;(r/(name+'-independent.json')).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2));raise SystemExit(0 if result['passed'] else 1)
