#!/usr/bin/env python3
"""Independent NumPy SVD oracle. Reads a rejected captured run; no simulation."""
from pathlib import Path
import json,hashlib,numpy as np
root=Path(__file__).resolve().parent/'Fixtures/3d-membrane'
f=json.loads((root/'native-rigid-469.json').read_text())
ref=np.array([[p[k] for k in ['x','y','z']] for p in f['referencePositions']]);x=np.array([[p[k] for k in ['x','y','z']] for p in f['positions']])
t=np.array(f['referenceTriangles']).reshape((-1,3))
dm=np.stack([ref[t[:,1],:2]-ref[t[:,0],:2],ref[t[:,2],:2]-ref[t[:,0],:2]],axis=2)
area=np.linalg.det(dm)/2;inverse=np.linalg.inv(dm);mu=310.;lam=170.
def values(x):
 ds=np.stack([x[t[:,1]]-x[t[:,0]],x[t[:,2]]-x[t[:,0]]],axis=2)
 singular=np.linalg.svd(ds@inverse,compute_uv=False)
 logs=np.log(singular).sum(axis=1)
 energy=(area*(mu/2*((singular**2).sum(axis=1)-2-2*logs)+lam/2*logs**2)).sum()
 return singular,energy
s,e=values(x)
x60=np.array([[p[k] for k in ['x','y','z']] for p in f['frame60Positions']]);s60,_=values(x60)
edge60=max(abs(np.linalg.norm(x60[e['a']]-x60[e['b']])/e['length']-1) for e in f['sourceEdges'])
probes=[]
for i in [0,96,208,350,969,1152,1168,1169,1170,1427,1740,1999]:
 for a in range(3):
  h=1e-7;xp=x.copy();xm=x.copy();xp[i,a]+=h;xm[i,a]-=h
  probes.append({'vertex':i,'axis':a,'gradientNewton':float((values(xp)[1]-values(xm)[1])/(2*h))})
result={'scope':'NumPy LAPACK 3x2 SVD directly from original source Dm and captured actual frame469; energy differences use singular values, no native gradient implementation',
 'fixtureSHA256':hashlib.sha256((root/'native-rigid-469.json').read_bytes()).hexdigest(),'generatorSHA256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
 'numpyVersion':np.__version__,'shearStiffnessNewtonPerMeter':mu,'areaStiffnessNewtonPerMeter':lam,
 'minimumPrincipalStretch':float(s.min()),'maximumPrincipalStretch':float(s.max()),'minimumAreaRatio':float(s.prod(axis=1).min()),
 'referenceAreaSquareMeters':float(area.sum()),'actualAreaSquareMeters':float((area*s.prod(axis=1)).sum()),
 'frame60MaximumEdgeStrain':float(edge60),'frame60MaximumPrincipalStretch':float(s60.max()),'energyJoules':float(e),'gradientCentralDifferenceStepMeters':1e-7,'gradientProbes':probes}
(root/'numpy-svd-oracle.json').write_text(json.dumps(result,indent=2)+'\n')
manifest=json.loads((root/'manifest.json').read_text());manifest['files']['numpy-svd-oracle.json']=hashlib.sha256((root/'numpy-svd-oracle.json').read_bytes()).hexdigest();(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print({k:v for k,v in result.items() if k not in ['gradientProbes','scope']})
