"""Independent NumPy reference fields for the four-type Swift draft fitter.

Imported only by the read-only oracle; no optimizer, App or measurement path edit.
"""
from pathlib import Path
import sys,json,math,hashlib,struct,copy,time
import numpy as np
ROOT=Path(__file__).parent
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,x):p.write_text(json.dumps(x,indent=2,ensure_ascii=False,allow_nan=False)+'\n')
def points(p):return np.array([[q[k] for k in ['x','y','z']] for q in p],dtype=np.float64)
def encode(p):return [dict(zip(['x','y','z'],map(float,q))) for q in p]
def smooth(t):t=np.clip(t,0,1);return t*t*(3-2*t)
def window(t,inner,outer):return 1-smooth((abs(t)-inner)/(outer-inner))

class Draft:
    def __init__(self,report,contract,rig):
        self.report=report;self.contract=contract;self.rig=rig;self.base=points(report['positions']);self.tri=np.array(report['triangleIndices'],int).reshape(-1,3)
        self.map=np.array(rig['sourceToVisible'],int)
        self.measurements=[m for m in contract['measurements'] if m['targetUse']=='projectFittingReference']
        self.targets=np.array([report['bodyValues'][m['targetKey']]/100 for m in self.measurements])
        w=rig['weights'];names=[b['name'] for b in rig['bones']];self.arm={}
        arm_prefixes=('clavicle.','shoulder01.','upperarm','lowerarm','wrist.','metacarpal','finger')
        for side in ['L','R']:
            selected={i for i,n in enumerate(names) if n.endswith('.'+side) and n.startswith(arm_prefixes)}
            self.arm[side]=np.array([math.fsum(w['normalizedValues'][j] for j in range(w['vertexOffsets'][v],w['vertexOffsets'][v+1]) if w['boneIndices'][j] in selected) for v in range(len(self.base))])
        self.torso=np.clip(1-self.arm['L']-self.arm['R'],0,1)
        self.chest_y=np.mean([self.point(contract['landmarks']['chestSurfaceReference.'+s],self.base)[1] for s in ['L','R']])
        self.chest_mask=self.torso*window(self.base[:,1]-self.chest_y,.030,.105)
        self.wrist_masks={}
        for side in ['L','R']:
            m=next(m for m in self.measurements if m['id']=='wristSurfaceLoop.'+side)
            q=np.array([self.point(a,self.base) for a in m['samples']]);center=q.mean(0)
            # The normal is derived from the fixed actual surface loop. Bone
            # proxy distance never enters a measurement or fit objective.
            _,_,basis=np.linalg.svd(q-center,full_matrices=False);normal=basis[-1]
            self.wrist_masks[side]=self.arm[side]*window((self.base-center)@normal,.015,.070)
        assert all(np.all((mask>=0)&(mask<=1+1e-14)) for mask in self.arm.values())
        t=self.base[self.tri];self.reference_normals=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])
        self.evaluations=[]
    def point(self,a,p):return np.sum(p[self.map[a['sourceVertexIDs']]]*np.array(a['weights'])[:,None],axis=0)
    def measure(self,p):
        values=[]
        for m in self.measurements:
            q=np.array([self.point(a,p) for a in m['samples']])
            if m['kind']=='axisDistanceX':value=abs(q[1,0]-q[0,0])
            elif m['kind']=='pointDistance':value=np.linalg.norm(q[1]-q[0])
            else:
                if m.get('closed'):q=np.concatenate([q,q[:1]])
                value=np.linalg.norm(q[1:]-q[:-1],axis=1).sum()
            values.append(value)
        return np.array(values)
    def deform(self,parameters):
        chest,shoulder,arm,wrist=parameters;p=self.base.copy()
        # Each fixed mask is a nodal scalar field on the original connected
        # skin; shared vertices are transformed once. Its face interpolation
        # is continuous across all original shared edges.
        radial=np.exp(chest*self.chest_mask)
        p[:,0]*=radial;p[:,2]*=radial
        p[:,0]+=shoulder*(self.arm['L']-self.arm['R'])
        for side in ['L','R']:
            center=self.point(self.contract['landmarks']['shoulderSurfaceReference.'+side],p)
            delta_scale=np.expm1(arm*self.arm[side]);p+=(p-center)*delta_scale[:,None]
        for side in ['L','R']:
            m=next(m for m in self.measurements if m['id']=='wristSurfaceLoop.'+side)
            q=np.array([self.point(a,p) for a in m['samples']]);center=q.mean(0)
            elbow=self.point(self.contract['landmarks']['outerElbowSurfaceReference.'+side],p)
            axis=center-elbow;axis/=np.linalg.norm(axis)
            delta=p-center;radial=delta-(delta@axis)[:,None]*axis
            p+=radial*np.expm1(wrist*self.wrist_masks[side])[:,None]
        return p
    def quality(self,p):
        t=p[self.tri];n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);areas=np.linalg.norm(n,axis=1)/2
        cos=np.einsum('ij,ij->i',n,self.reference_normals)/(np.linalg.norm(n,axis=1)*np.linalg.norm(self.reference_normals,axis=1))
        return {'finite':bool(np.all(np.isfinite(p))),'minimumTriangleAreaSquareMeters':float(areas.min()),'minimumReferenceNormalCosine':float(cos.min()),'signedVolumeCubicMeters':float(np.einsum('ij,ij->i',t[:,0],np.cross(t[:,1],t[:,2])).sum()/6)}
    def residual(self,a):
        p=self.deform(a);values=self.measure(p);r=(values-self.targets)*100
        quality=self.quality(p)
        self.evaluations.append({'parameters':list(map(float,a)),'residualCentimeters':r.tolist(),'quality':quality})
        # This is draft optimization, not an acceptance gate. A failure is
        # recorded and stops, rather than silently changing the source domain.
        assert quality['finite'] and quality['minimumTriangleAreaSquareMeters']>0 and quality['minimumReferenceNormalCosine']>0
        return r
