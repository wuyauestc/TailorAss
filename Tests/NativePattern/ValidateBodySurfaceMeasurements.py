#!/usr/bin/env python3
"""Independent scalar/Fraction checks on actual Swift-loaded body surfaces."""
from pathlib import Path
from fractions import Fraction as F
import hashlib,json,math,struct,sys

out=Path(sys.argv[1]);snapshot=out/'snapshot';resource=snapshot/'resources'
contract_bytes=(resource/'GarmentCodeBodySurfaceMeasurements.json').read_bytes()
contract=json.loads(contract_bytes);rig=json.loads((resource/'GarmentCodeStandardBodyRig/rig.json').read_text())
template=json.loads((resource/'GarmentCodeStandardBody.json').read_text());faces=template['triangleIndices'];inverse=rig['sourceToVisible']
sha=lambda b:hashlib.sha256(b).hexdigest()
assert contract['visibleToSource']==rig['visibleToSource']
assert sha((resource/'GarmentCodeStandardBody.json').read_bytes())==contract['templateResourceSHA256']
assert sha((resource/'GarmentCodeStandardBodyRig/rig.json').read_bytes())==contract['rigResourceSHA256']
def evaluate(a,p):
    return tuple(math.fsum(p[inverse[i]][k]*w for i,w in zip(a['sourceVertexIDs'],a['weights'])) for k in range(3))
def support(a):
    assert len(a['weights'])==len(a['sourceVertexIDs']) in (1,2,3)
    assert all(0<=w<=1 for w in a['weights']) and abs(math.fsum(a['weights'])-1)<1e-14
    assert all(inverse[i]>=0 for i in a['sourceVertexIDs'])
    return set(a['sourceVertexIDs'])
all_faces=[set(rig['visibleToSource'][v] for v in faces[i:i+3]) for i in range(0,len(faces),3)]
for a in contract['landmarks'].values():
    ids=support(a);assert any(ids<=f for f in all_faces)
rows=[];maximum_error=0.;segments=0;maximum_surface_roundoff=0.
for name in ['default','female']:
    for suffix in ['surface-measurements','scaled-control']:
        j=json.loads((out/f'{name}-{suffix}.json').read_text())
        p=[tuple(v[k] for k in ['x','y','z']) for v in j['positions']];values=j['bodyValues']
        assert j['triangleIndices']==faces and j['contractSHA256']==sha(contract_bytes)
        binary=b'rigid-clearance-visible-body-v1\0'+struct.pack('<QQ',len(p),len(faces))+b''.join(struct.pack('<ddd',*v) for v in p)+b''.join(struct.pack('<I',i) for i in faces)
        assert sha(binary)==j['geometrySHA256']
        parameters=b'body-surface-measurements-parameters-v1\0'+b''.join(k.encode()+b'\0'+struct.pack('<d',values[k]) for k in sorted(values))
        assert len(values)==33 and sha(parameters)==j['parameterSHA256']
        assert not j['bodyFittingApplied'] and not j['defaultBodyBehaviorChanged']
        for key,a in contract['landmarks'].items():
            q=evaluate(a,p);actual=tuple(j['landmarks'][key][k] for k in ['x','y','z'])
            assert math.dist(q,actual)<2e-15
        for definition,m in zip(contract['measurements'],j['measurements']):
            assert definition==m['definition'] or all(definition[k]==m['definition'][k] for k in m['definition'])
            points=[evaluate(a,p) for a in definition['samples']]
            assert len(points)==len(m['points']) and max(math.dist(q,tuple(a[k] for k in ['x','y','z'])) for q,a in zip(points,m['points']))<2e-15
            for a,actual in zip(definition['samples'],m['points']):
                weights=[F(w) for w in a['weights']];total=sum(weights)
                exact=[sum(F(p[inverse[i]][k])*w/total for i,w in zip(a['sourceVertexIDs'],weights)) for k in range(3)]
                coordinate_error=max(abs(F(actual[k])-value) for k,value in zip(['x','y','z'],exact))
                bound=math.nextafter(float(coordinate_error),math.inf)*math.nextafter(math.sqrt(3),math.inf)
                maximum_surface_roundoff=max(maximum_surface_roundoff,bound)
                assert bound<2e-12
            if definition['kind']=='surfacePath':
                following=definition['samples'][1:]+(definition['samples'][:1] if definition['closed'] else [])
                for a,b,face in zip(definition['samples'],following,definition['sourceTriangleIDs']):
                    assert support(a)|support(b)<=all_faces[face]
                    # Exact Fraction convex support: nonnegative weights put
                    # the mathematical endpoints in the original face. They
                    # need not sum to exactly1 after Float64 authoring, so use
                    # their normalized exact rational barycentric values.
                    for endpoint in [a,b]:
                        weights=[F(w) for w in endpoint['weights']];total=sum(weights)
                        assert total>0 and abs(total-1)<F(1,10**14)
                        assert all(0<=w/total<=1 for w in weights)
                    segments+=1
                closed=points+[points[0]] if definition['closed'] else points
                observed=math.fsum(math.dist(a,b) for a,b in zip(closed,closed[1:]))
            elif definition['kind']=='pointDistance':observed=math.dist(*points)
            else:assert definition['kind']=='axisDistanceX';observed=abs(points[1][0]-points[0][0])
            target=values[definition['targetKey']]/100
            error=abs(observed-m['observedMeters']);maximum_error=max(maximum_error,error)
            assert error<2e-12 and m['requestedMeters']==target and abs(m['observedMinusRequestedMeters']-(observed-target))<2e-12
            if suffix=='surface-measurements':rows.append({'profile':name,'id':definition['id'],'observedCentimeters':observed*100,'requestedCentimeters':target*100,'residualCentimeters':(observed-target)*100})
result={'passed':True,'method':'Independent math.fsum/math.dist on every actual source attachment; complete original-face endpoint support; exact Fraction nonnegative normalized barycentric support; recompute full geometry and all33parameter hashes.',
        'absoluteToleranceMeters':2e-12,'maximumScalarDifferenceMeters':maximum_error,
        'maximumDistanceToExactNormalizedBarycentricPointMeters':maximum_surface_roundoff,'sourceSegmentsChecked':segments,'rows':rows,
        'scope':'Actual reference measurements and covariance controls; no body fitting or cloth simulation.'}
(out/'independent-oracle.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
