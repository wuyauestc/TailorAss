"""Exact Fraction audit for moving-normal Bernstein distance certificates.
No production closest-point/interval code is imported. Does not prove domains.
"""
from fractions import Fraction as F

def f(x):return x if isinstance(x,F) else F.from_float(float(x))
def vec(v):return [f(x) for x in (v if isinstance(v,list) else [v[k] for k in ['x','y','z']])]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def add(a,b):return [x+y for x,y in zip(a,b)]
def scale(a,s):return [x*s for x in a]
def dot(a,b):return sum((x*y for x,y in zip(a,b)),F(0))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def moving_controls(kind,start,end,t0,t1):
 def points(t):return [add(a,scale(sub(b,a),t)) for a,b in zip(start,end)]
 a,b=points(t0),points(t1)
 if kind=='vertexFace':
  u0,u1=sub(a[2],a[1]),sub(b[2],b[1]);v0,v1=sub(a[3],a[1]),sub(b[3],b[1]);w0,w1=sub(a[0],a[1]),sub(b[0],b[1])
 else:
  assert kind=='edgeEdge'
  u0,u1=sub(a[1],a[0]),sub(b[1],b[0]);v0,v1=sub(a[3],a[2]),sub(b[3],b[2]);w0,w1=sub(a[0],a[2]),sub(b[0],b[2])
 n=[cross(u0,v0),scale(add(cross(u0,v1),cross(u1,v0)),F(1,2)),cross(u1,v1)]
 g=[dot(w0,n[0]),(2*dot(w0,n[1])+dot(w1,n[0]))/3,(dot(w0,n[2])+2*dot(w1,n[1]))/3,dot(w1,n[2])]
 return n,g

def verify_moving_leaves(kind,start,end,floor,certificates):
 start,end=[[vec(v) for v in a] for a in [start,end]];floor=f(floor);cover=[]
 for leaf in certificates:
  assert leaf['kind']==kind
  t0,t1=f(leaf['startTime']),f(leaf['endTime']);assert 0<=t0<t1<=1;cover.append((t0,t1))
  n,g=moving_controls(kind,start,end,t0,t1)
  nb,gb=leaf['normalBernsteinBounds'],leaf['projectionBernsteinBounds'];assert len(nb)==3 and len(gb)==4
  for control,bound in zip(n,nb):
   for component,key in zip(control,['x','y','z']):assert f(bound[key]['lower'])<=component<=f(bound[key]['upper']),('normal control enclosure',leaf)
  for control,bound in zip(g,gb):assert f(bound['lower'])<=control<=f(bound['upper']),('projection control enclosure',leaf)
  sign=leaf['projectionSign'];assert sign in [-1,1]
  lower=f(leaf['absoluteProjectionLowerBound']);assert lower>0 and lower<=min(sign*x for x in g)
  intervalMinimum=min(f(x['lower']) for x in gb) if sign==1 else -max(f(x['upper']) for x in gb)
  assert 0<lower<=intervalMinimum
  boxSquared=sum(max(abs(f(control[key][side])) for control in nb for side in ['lower','upper'])**2 for key in ['x','y','z'])
  norm=f(leaf['normalNormUpperBound']);threshold=f(leaf['requiredProductUpperBound']);distance=f(leaf['distanceLowerBoundMeters'])
  assert norm>0 and norm*norm>=boxSquared
  assert threshold>=floor*norm and lower>threshold
  assert distance>=0 and distance*norm<=lower
 return cover

def verify_fixed_leaves(kind,start,end,floor,leaves):
 start,end=[[vec(v) for v in a] for a in [start,end]];floor=f(floor);cover=[]
 aa=[0] if kind=='vertexFace' else [0,1];bb=[1,2,3] if kind=='vertexFace' else [2,3]
 for leaf in leaves:
  t0,t1=f(leaf['startTime']),f(leaf['endTime']);cover.append((t0,t1));n=vec(leaf['direction'])
  values=[]
  for t in [t0,t1]:
   for i in aa:
    for j in bb:
     d0=sub(start[i],start[j]);d1=sub(end[i],end[j]);values.append(dot(n,add(d0,scale(sub(d1,d0),t))))
  lower=f(leaf['projectionLowerBound']);norm=f(leaf['directionNormUpperBound']);threshold=f(leaf['requiredProductUpperBound'])
  assert lower<=min(values) and norm>0 and norm*norm>=dot(n,n)
  assert threshold>=floor*norm and lower>threshold
  assert f(leaf['distanceLowerBoundMeters'])*norm<=lower
 return cover

def verify_expansion_leaves(kind,start,end,floor,certificates):
 """Independent exact control conversion/elevation, not producer EFT code."""
 start,end=[[vec(v)for v in a]for a in[start,end]];floor=f(floor);cover=[]
 for leaf in certificates:
  assert leaf['kind']==kind
  t0,t1=f(leaf['startTime']),f(leaf['endTime']);assert 0<=t0<t1<=1;cover.append((t0,t1))
  n,g=moving_controls(kind,start,end,t0,t1)
  controls=[3*x for x in g];scaleFactor=3
  degree=leaf.get('projectionDegree',len(leaf['scaledProjectionBernsteinBounds'])-1)
  assert 3<=degree<=8
  for target in range(4,degree+1):
   controls=[target*controls[0]]+[k*controls[k-1]+(target-k)*controls[k]for k in range(1,target)]+[target*controls[-1]]
   scaleFactor*=target
  assert leaf['projectionScale']==scaleFactor
  nb,gb=leaf['normalBernsteinBounds'],leaf['scaledProjectionBernsteinBounds'];assert len(nb)==3 and len(gb)==degree+1
  for control,bound in zip(n,nb):
   for component,key in zip(control,['x','y','z']):assert f(bound[key]['lower'])<=component<=f(bound[key]['upper'])
  for control,bound in zip(controls,gb):assert f(bound['lower'])<=control<=f(bound['upper']),('elevated control',leaf)
  sign=leaf['projectionSign'];assert sign in[-1,1]
  lower=f(leaf['absoluteScaledProjectionLowerBound']);assert 0<lower<=min(sign*x for x in controls)
  intervalMinimum=min(f(x['lower'])for x in gb)if sign==1 else-max(f(x['upper'])for x in gb)
  assert 0<lower<=intervalMinimum
  boxSquared=sum(max(abs(f(control[key][side]))for control in nb for side in['lower','upper'])**2for key in['x','y','z'])
  norm=f(leaf['normalNormUpperBound']);threshold=f(leaf['requiredScaledProductUpperBound']);distance=f(leaf['distanceLowerBoundMeters'])
  assert norm>0 and norm*norm>=boxSquared
  assert threshold>=floor*norm*scaleFactor and lower>threshold
  assert distance>=0 and distance*norm*scaleFactor<=lower
 return cover


def verify_critical_leaves(kind,start,end,floor,certificates):
 """Independent exact critical-value lemma AND quantitative lower bounds.
 Rebuild the true cubic from original binary endpoints, not producer words.
 Square comparisons below avoid trusting any float sqrt or critical root.
 """
 start,end=[[vec(v)for v in a]for a in[start,end]];cover=[]
 if certificates:assert f(floor)==0
 def enclosed(value,bounds):
  assert bounds is not None and f(bounds['lower'])<=value<=f(bounds['upper'])
 for leaf in certificates:
  assert leaf['kind']==kind and leaf['projectionScale']==3
  t0,t1=f(leaf['startTime']),f(leaf['endTime']);assert 0<=t0<t1<=1;cover.append((t0,t1))
  normal,g=moving_controls(kind,start,end,t0,t1)
  sign=leaf['projectionSign'];assert sign in[-1,1]
  exponent=leaf['binaryNormalizationExponent'];assert -512<=exponent<=512
  scale=F(2)**exponent;C=[3*sign*scale*x for x in g]
  d=C[0];c=3*(C[1]-C[0]);b=3*(C[0]-2*C[1]+C[2]);a=-C[0]+3*C[1]-3*C[2]+C[3]
  assert len(leaf['normalizedPowerCoefficientBounds'])==4
  for v,bd in zip([a,b,c,d],leaf['normalizedPowerCoefficientBounds']):enclosed(v,bd)
  endpoints=[d,a+b+c+d]
  for v,bd in zip(endpoints,leaf['normalizedEndpointBounds']):enclosed(v,bd)
  L=f(leaf['absoluteNormalizedProjectionLowerBound']);assert 0<L<=min(endpoints)
  method=leaf['proofKind']
  if a==0:
   if b<=0:assert method=='concaveOrLinear'
   else:
    assert method=='positiveQuadraticMinimum';q=4*b*d-c*c
    enclosed(q,leaf['quadraticNumeratorBounds']);assert q>0 and 4*b*L<=q
  else:
   D=b*b-3*a*c;enclosed(D,leaf['derivativeDiscriminantBounds'])
   if D<=0:assert method=='monotoneCubic'
   else:
    H=2*b**3-9*a*b*c+27*a*a*d
    disc=18*a*b*c*d-4*b**3*d+b*b*c*c-4*a*c**3-27*a*a*d*d
    assert H*H-4*D**3 == -27*a*a*disc
    assert method=='positiveCubicMinimum' and H>0 and disc<0
    enclosed(H,leaf['cubicHBounds']);enclosed(disc,leaf['cubicDiscriminantBounds'])
    # L <= -Disc/(H+2D sqrt(D)) iff this exact rational
    # numerator is nonnegative and its square dominates 4L²D³.
    A=-disc-L*H;assert A>=0 and A*A>=4*L*L*D**3
  nb=leaf['normalBernsteinBounds'];assert len(nb)==3
  for control,bd in zip(normal,nb):
   for component,key in zip(control,['x','y','z']):enclosed(component,bd[key])
  boxSquared=sum(max(abs(f(bd[key][side]))for bd in nb for side in['lower','upper'])**2for key in['x','y','z'])
  norm=f(leaf['normalNormUpperBound']);distance=f(leaf['distanceLowerBoundMeters'])
  assert norm>0 and norm*norm>=boxSquared
  assert distance>0 and distance*norm*3*scale<=L
 return cover
