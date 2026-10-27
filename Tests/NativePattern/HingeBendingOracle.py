from pathlib import Path
import json,hashlib,math,argparse
import numpy as np
p=argparse.ArgumentParser();p.add_argument('--fixture-dir',required=True,type=Path);p.add_argument('--swift-summary',required=True,type=Path);p.add_argument('--output',required=True,type=Path);args=p.parse_args()
root=args.fixture_dir
x=json.loads((root/'native-source-topology.json').read_text());swift=json.loads(args.swift_summary.read_text())
r=np.array([[v[k] for k in ['x','y','z']] for v in x['referencePositions']]);t=np.array(x['referenceTriangles']).reshape((-1,3));owners=[None]*len(r)
for group in x['panelGroups']:
 for vertex in group['vertexIDs']:
  assert owners[vertex] is None
  owners[vertex]=group['panelID']
assert all(owner is not None for owner in owners)
edges={}
for ti,tri in enumerate(t):
 for j in range(3):
  a,b,c=(int(tri[j]),int(tri[(j+1)%3]),int(tri[(j+2)%3]))
  edges.setdefault(tuple(sorted((a,b))),[]).append((a,b,c,ti))
h=[]
for edge,faces in sorted(edges.items()):
 if len(faces)==1:continue
 assert len(faces)==2
 a,b,c,ta=faces[0];bb,aa,d,tb=faces[1]
 assert a==aa and b==bb and len({owners[z] for z in [a,b,c,d]})==1
 h.append((a,b,c,d))
h=np.array(h);e=r[h[:,1]]-r[h[:,0]];v=r[h[:,2]]-r[h[:,0]];w=r[h[:,3]]-r[h[:,0]]
A=.5*(np.linalg.norm(np.cross(e,v),axis=1)+np.linalg.norm(np.cross(w,e),axis=1));weight=3*np.sum(e*e,axis=1)/A
kb=swift['kbExperimentalNewtonMeter']
def energy(pos):
 e=pos[h[:,1]]-pos[h[:,0]];v=pos[h[:,2]]-pos[h[:,0]];w=pos[h[:,3]]-pos[h[:,0]]
 n1=np.cross(e,v);n2=np.cross(w,e)
 n1/=np.linalg.norm(n1,axis=1)[:,None];n2/=np.linalg.norm(n2,axis=1)[:,None]
 ep=e/np.linalg.norm(e,axis=1)[:,None]
 theta=np.arctan2(np.sum(ep*np.cross(n1,n2),axis=1),np.sum(n1*n2,axis=1))
 return float(kb*np.dot(weight,theta**2)),float(np.max(np.abs(theta)))
probe=r.copy();probe[:,2]=.012*np.sin(5*r[:,0])*np.cos(4*r[:,1])+.009*r[:,0]*r[:,1]
E,angle=energy(probe)
assert abs(E-swift['realSource']['derivativeProbeEnergyJ'])<1e-16
assert abs(angle-swift['realSource']['maxAbsAngleRadians'])<1e-13
H=np.array(swift['singleHinge']['exactHessianColumns']).T;eigenvalues=np.linalg.eigvalsh(H)
assert np.max(np.abs(H-H.T))<1e-12
assert min(eigenvalues)<-1e-3

def cylinder(n,phi):
 W=.4;HH=.3;R=.5
 ref=np.array([[W*i/n,HH*j/n,0] for j in range(n+1) for i in range(n+1)])
 tri=[]
 for j in range(n):
  for i in range(n):
   a=j*(n+1)+i;b=a+1;c=a+n+1;d=c+1
   tri.extend([(a,b,d),(a,d,c)])
 ed={}
 for a,b,c in tri:
  for aa,bb,cc in [(a,b,c),(b,c,a),(c,a,b)]:ed.setdefault(tuple(sorted((aa,bb))),[]).append((aa,bb,cc))
 hh=[]
 for f in ed.values():
  if len(f)==2:hh.append((f[0][0],f[0][1],f[0][2],f[1][2]))
 hh=np.array(hh);e=ref[hh[:,1]]-ref[hh[:,0]];v=ref[hh[:,2]]-ref[hh[:,0]];w=ref[hh[:,3]]-ref[hh[:,0]]
 weights=6*np.sum(e*e,axis=1)/(np.linalg.norm(np.cross(e,v),axis=1)+np.linalg.norm(np.cross(w,e),axis=1))
 # Exact isometric cylindrical map for arbitrary curvature direction in source.
 u=ref[:,0]*math.cos(phi)+ref[:,1]*math.sin(phi);vv=-ref[:,0]*math.sin(phi)+ref[:,1]*math.cos(phi)
 bend=R*np.sin(u/R)
 pos=np.column_stack((bend*math.cos(phi)-vv*math.sin(phi),bend*math.sin(phi)+vv*math.cos(phi),R*(1-np.cos(u/R))))
 e=pos[hh[:,1]]-pos[hh[:,0]];v=pos[hh[:,2]]-pos[hh[:,0]];w=pos[hh[:,3]]-pos[hh[:,0]]
 n1=np.cross(e,v);n2=np.cross(w,e);n1/=np.linalg.norm(n1,axis=1)[:,None];n2/=np.linalg.norm(n2,axis=1)[:,None]
 theta=np.arctan2(np.sum((e/np.linalg.norm(e,axis=1)[:,None])*np.cross(n1,n2),axis=1),np.sum(n1*n2,axis=1))
 return float(kb*np.dot(weights,theta**2))
refine=[]
for n in [8,16,32,64]:refine.append({'cellsEachAxis':n,'axisAlignedEnergyJ':cylinder(n,0),'diagonalCurvature45EnergyJ':cylinder(n,math.pi/4)})
report={'status':'pass','pythonIndependentEnergyJ':E,'pythonIndependentMaxAngleRadians':angle,'sourceInternalHinges':len(h),
 'sourceWeightMin':float(np.min(weight)),'sourceWeightMax':float(np.max(weight)),
 'exactFoldedSingleHingeEigenvalues':eigenvalues.tolist(),'exactHessianIndefiniteAtFoldedState':True,
 'directionalGridRefinement':refine,
 'refinementInterpretation':'Energy converges for each fixed grid family but is direction/triangulation dependent; no claim of general remeshing invariance or calibrated continuum bending modulus.'}
report['generatorSHA256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
report['canonicalSourceSHA256']=x['sourceSHA256']
report['exactHessianSpectrumIsIndependentNumpyAnalysisOfReportedSwiftMatrix']=True
args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
