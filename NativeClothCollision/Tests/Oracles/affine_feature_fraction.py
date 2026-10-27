"""Independent exact Fraction/Sturm validation of affine-normal leaf records.
Closest-point proposals and producer EFT implementation are not imported.
"""
from fractions import Fraction as F
from correlated_feature_fraction import f,vec,sub,add,scale,dot

def trim(p):
 p=list(p)
 while len(p)>1 and p[-1]==0:p.pop()
 return p

def value(p,t):
 r=F(0)
 for x in reversed(p):r=r*t+x
 return r

def remainder(p,q):
 p=trim(p);q=trim(q);assert any(q)
 while len(p)>=len(q) and any(p):
  k=len(p)-len(q);s=p[-1]/q[-1]
  for i,x in enumerate(q):p[k+i]-=s*x
  p=trim(p)
 return p

def strictly_positive_closed(p):
 p=trim(p)
 if value(p,F(0))<=0 or value(p,F(1))<=0:return False
 if len(p)==1:return True
 seq=[p,trim([i*p[i] for i in range(1,len(p))])]
 while any(seq[-1]):
  rem=[-x for x in remainder(seq[-2],seq[-1])]
  if not any(rem):break
  seq.append(rem)
 def variation(t):
  signs=[1 if x>0 else -1 for q in seq if (x:=value(q,t))]
  return sum(a!=b for a,b in zip(signs,signs[1:]))
 return variation(F(0))-variation(F(1))==0

def verify_affine_leaves(kind,start,end,floor,certificates):
 start,end=[[vec(v)for v in a]for a in[start,end]];floor=f(floor);cover=[]
 pairs=[(0,1),(0,2),(0,3)]if kind=='vertexFace'else[(0,2),(0,3),(1,2),(1,3)]
 def points(t):return [add(a,scale(sub(b,a),t))for a,b in zip(start,end)]
 def enclosed(x,b):assert f(b['lower'])<=x<=f(b['upper'])
 for leaf in certificates:
  assert leaf['kind']==kind and leaf['projectionScale']==2
  t0,t1=f(leaf['startTime']),f(leaf['endTime']);assert 0<=t0<t1<=1;cover.append((t0,t1))
  na,nb=vec(leaf['startDirection']),vec(leaf['endDirection']);dn=sub(nb,na)
  N=f(leaf['normalNormUpperBound']);assert N>0 and N*N>=dot(na,na)and N*N>=dot(nb,nb)
  a,b=points(t0),points(t1);lowers=[]
  assert [(p['firstVertex'],p['secondVertex'])for p in leaf['projections']]==pairs
  for p in leaf['projections']:
   i,j=p['firstVertex'],p['secondVertex'];r0=sub(a[i],a[j]);dr=sub(sub(b[i],b[j]),r0)
   cc=2*dot(r0,na);bc=2*(dot(dr,na)+dot(r0,dn));ac=2*dot(dr,dn)
   for x,bd in zip([cc,cc+bc/2,cc+bc+ac],p['scaledBernsteinBounds']):enclosed(x,bd)
   for x,bd in zip([ac,bc,cc],p['scaledPowerBounds']):enclosed(x,bd)
   L=f(p['scaledProjectionLowerBound']);assert L>0
   # Independent root counting validates the reported strict lower bound,
   # rather than trusting the production quadratic minimum formula.
   assert strictly_positive_closed([cc-L,bc,ac])
   if p['proofKind']=='concaveOrLinear':assert ac<=0
   elif p['proofKind']=='endpointMinimum':assert ac>0 and(bc>=0 or bc+2*ac<=0)
   else:
    assert p['proofKind']=='positiveInteriorMinimum'and ac>0 and bc<0 and bc+2*ac>0
    num=4*ac*cc-bc*bc;enclosed(num,p['interiorNumeratorBounds']);assert num>0 and 4*ac*L<num
   lowers.append(L)
  L=f(leaf['scaledProjectionLowerBound']);d=f(leaf['distanceLowerBoundMeters']);required=f(leaf['requiredScaledProductUpperBound'])
  assert 0<L<=min(lowers)and required>=2*floor*N and L>required
  assert d>floor and d*2*N<=L
 return cover
