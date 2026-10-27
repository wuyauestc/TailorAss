#!/usr/bin/env python3
"""Independent draft-fit field/measurement oracle and full static triangle audit."""
from pathlib import Path
import argparse,json,hashlib,struct,math,time,traceback,sys
from functools import lru_cache
from collections import Counter
parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('output',type=Path);parser.add_argument('--phase',choices=['fields','geometry'],required=True);parser.add_argument('--profile',choices=['default','female']);parser.add_argument('--python-packages',type=Path);args=parser.parse_args()
if args.python_packages:sys.path.insert(0,str(args.python_packages))
import numpy as np
import BodyLocalFitOracle as Reference
import ExactBodySurfaceGeometry as G
ROOT=args.output;SNAPSHOT=ROOT/'snapshot';RESOURCE=SNAPSHOT/'resources'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,x):p.write_text(json.dumps(x,indent=2,ensure_ascii=False,allow_nan=False)+'\n')
def geometry_hash(p,tri):
    raw=b'rigid-clearance-visible-body-v1\0'+struct.pack('<QQ',len(p),tri.size)+p.astype('<f8').tobytes()+tri.astype('<u4').tobytes()
    return hashlib.sha256(raw).hexdigest()
def parameters_hash(values):
    raw=b'body-surface-measurements-parameters-v1\0'+b''.join(k.encode()+b'\0'+struct.pack('<d',values[k]) for k in sorted(values))
    return hashlib.sha256(raw).hexdigest()
def points(values):return np.array([[q[k] for k in ['x','y','z']] for q in values],dtype=np.float64)
def bind(name):
    attempt=json.loads((ROOT/(name+'-attempt.json')).read_text());m=attempt['diagnosticMeasurement'];p=points(attempt['diagnosticPositions']);tri=np.array(attempt['triangleIndices'],int).reshape(-1,3)
    assert attempt['status']=='draftSurfaceGoalsReached' and not attempt['bodyCapabilityIssued'] and attempt['requiresCompleteIntersectionAudit']
    assert not attempt['compatibleWithLegacyInverseSDF'] and not attempt['all26BodyFieldsIndependentlyFitted']
    assert m['positions']==attempt['diagnosticPositions'] and m['triangleIndices']==attempt['triangleIndices']
    assert geometry_hash(p,tri)==m['geometrySHA256']
    assert parameters_hash(m['bodyValues'])==attempt['sourceParameterSHA256']==m['parameterSHA256'] and len(m['bodyValues'])==33
    assert m['contractSHA256']==attempt['contractSHA256']==sha(RESOURCE/'GarmentCodeBodySurfaceMeasurements.json')
    assert attempt['rigResourceSHA256']==sha(RESOURCE/'GarmentCodeStandardBodyRig/rig.json')
    assert tri.size==26756*3 and p.shape==(13380,3) and np.all(np.isfinite(p))
    return attempt,m,p,tri
def fields():
    contract=json.loads((RESOURCE/'GarmentCodeBodySurfaceMeasurements.json').read_text());rig=json.loads((RESOURCE/'GarmentCodeStandardBodyRig/rig.json').read_text());rows=[]
    template=json.loads((RESOURCE/'GarmentCodeStandardBody.json').read_text());tp=np.array(template['positions']);position_indices={tuple(p):i for i,p in enumerate(tp)}
    assert len(position_indices)==len(tp);partners=np.array([position_indices[(-p[0],p[1],p[2])] for p in tp]);assert len(set(partners))==len(tp)
    for name in ['default','female']:
        attempt,m,p,tri=bind(name);original=points(json.loads((ROOT/(name+'-original-positions.json')).read_text()))
        assert geometry_hash(original,tri)==attempt['sourceGeometrySHA256'] and list(tri.ravel())==template['triangleIndices']
        reference=Reference.Draft({'positions':json.loads((ROOT/(name+'-original-positions.json')).read_text()),'triangleIndices':attempt['triangleIndices'],'bodyValues':m['bodyValues']},contract,rig)
        controls=attempt['controls'];parameter=np.array([controls[0],controls[1]*.05,controls[2],controls[3]])
        expected=reference.deform(parameter);error=float(np.linalg.norm(p-expected,axis=1).max());assert error<2e-12
        scalar=reference.measure(p);actual=np.array([r['observedMeters'] for r in attempt['residuals']]);assert np.max(abs(scalar-actual))<2e-12
        for metric,observed,target,r in zip(reference.measurements,scalar,reference.targets,attempt['residuals']):
            assert r['id']==metric['id'] and r['requestedMeters']==target and abs(r['observedMinusRequestedMeters']-(observed-target))<2e-12
        for metric in m['measurements']:
            original_definition=next(q for q in contract['measurements'] if q['id']==metric['definition']['id'])
            assert metric['definition']['samples']==original_definition['samples'] and metric['definition'].get('sourceTriangleIDs')==original_definition.get('sourceTriangleIDs')
        outside=(reference.chest_mask==0)&(reference.arm['L']==0)&(reference.arm['R']==0)&(reference.wrist_masks['L']==0)&(reference.wrist_masks['R']==0)
        assert np.array_equal(p[outside].view(np.uint64),original[outside].view(np.uint64))
        reflected=p.copy();reflected[:,0]*=-1;mirror=np.linalg.norm(reflected-p[partners],axis=1)
        rows.append({'profile':name,'maximumIndependentVertexErrorMeters':error,'maximumIndependentMeasurementErrorMeters':float(np.max(abs(scalar-actual))),
            'maximumResidualMeters':float(abs(scalar-reference.targets).max()),'outsideFieldVerticesBitExact':int(outside.sum()),'maximumBilateralMirrorDifferenceMeters':float(mirror.max()),
            'sourceGeometrySHA256':attempt['sourceGeometrySHA256'],'draftGeometrySHA256':m['geometrySHA256'],'sameOriginalTopologyAndAttachments':True})
    for filename in ['default-cancel-after-accepted.json','default-cancel-publication.json']:
        a=json.loads((ROOT/filename).read_text());assert a['status']=='cancelled' and a.get('diagnosticMeasurement') is None
        before=json.loads((ROOT/'default-attempt.json').read_text())['diagnosticMeasurement']
        raw=json.loads((ROOT/'default-original-positions.json').read_text());model=Reference.Draft({'positions':raw,'triangleIndices':a['triangleIndices'],'bodyValues':before['bodyValues']},contract,rig)
        scalar=model.measure(points(a['diagnosticPositions']));assert np.max(abs(scalar-np.array([q['observedMeters'] for q in a['residuals']])))<2e-12
    return {'passed':True,'method':'Independent NumPy reference deformation and scalar surface lengths on every actual Swift output; complete original contract/path/33parameter/geometry binding; cancelled last-state residuals recomputed.','absoluteToleranceMeters':2e-12,'profiles':rows,'bodyCapabilityIssued':False}
def geometry(name):
    a,m,p,tri=bind(name);G.self_tests();directed=Counter();edges=Counter()
    for face in tri:
        for u,v in zip(face,np.roll(face,-1)):
            directed[(int(u),int(v))]+=1;edges[tuple(sorted([int(u),int(v)]))]+=1
    assert set(edges.values())=={2} and all(directed[(v,u)]==n for (u,v),n in directed.items())
    original_normal=G.normal
    @lru_cache(maxsize=131072)
    def cached(t):return original_normal(t)
    G.normal=lambda t:cached(tuple(t))
    exact=G.exact_intersection;count=0
    def bounded(x,y,shared=()):
        nonlocal count
        count+=1
        if count>2_000_000:raise RuntimeError('Complete self audit narrow-phase budget; no clear result')
        if count%256==0 and (ROOT/'CANCEL').exists():raise RuntimeError('Complete self audit cancelled; no clear result')
        return exact(x,y,shared)
    G.exact_intersection=bounded
    crossing=G.intersection_audit(p,tri,p,tri,True)
    passed=crossing['unresolvedPairs']==0 and set(crossing['classifications']).issubset({'separated','expectedTopologicalTouch'})
    return {'passed':passed,'method':'All26756 actual triangles; inclusive exact-coordinate AABB candidate cover; Fraction closed-triangle clipping including shared vertex/edge; expected touch restricted to actual shared source simplex.',
        'profile':name,'geometrySHA256':m['geometrySHA256'],'orientedClosedEdges':len(edges),'completeSelf':crossing,'bodyCapabilityIssued':False}
started=time.monotonic();path=ROOT/('independent-fields.json' if args.phase=='fields' else args.profile+'-independent-geometry.json')
try:
    result=fields() if args.phase=='fields' else geometry(args.profile)
except Exception:result={'passed':False,'error':traceback.format_exc(),'bodyCapabilityIssued':False}
result['seconds']=time.monotonic()-started;write(path,result);print(json.dumps(result,indent=2));raise SystemExit(0 if result['passed'] else 1)
