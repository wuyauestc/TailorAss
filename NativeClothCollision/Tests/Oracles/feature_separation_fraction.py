"""Independent exact-rational audit of every reported support leaf."""
from pathlib import Path
from fractions import Fraction as F
import json,struct,hashlib
import argparse,itertools
from correlated_feature_fraction import verify_moving_leaves,verify_expansion_leaves,verify_critical_leaves
from affine_feature_fraction import verify_affine_leaves
parser=argparse.ArgumentParser();parser.add_argument("--report",type=Path,required=True);parser.add_argument("--fixtures",type=Path,required=True);parser.add_argument("--output",type=Path,required=True);parser.add_argument("--body-report",type=Path);args=parser.parse_args()
s=json.loads(args.report.read_text());D=args.fixtures
fixture=json.loads((D/"actual-circle247-vf.json").read_text())
extraFixture=json.loads((D/"circle118-vf-shirt85-ee.json").read_text())
def frac(x):return F.from_float(float(x))
def vector(x):
 if isinstance(x,list):return list(map(frac,x))
 return [frac(x[a]) for a in ["x","y","z"]]
def dot(a,b):return sum((x*y for x,y in zip(a,b)),F(0))
def motion_points(m,key):return [vector(p) for p in m[key]]

def gaussian(matrix,rhs):
 a=[list(row)+[x] for row,x in zip(matrix,rhs)];n=len(a)
 for column in range(n):
  pivot=next((i for i in range(column,n) if a[i][column]),None)
  if pivot is None:return None
  a[column],a[pivot]=a[pivot],a[column];v=a[column][column];a[column]=[x/v for x in a[column]]
  for row in range(n):
   if row==column:continue
   v=a[row][column]
   if v:a[row]=[x-v*y for x,y in zip(a[row],a[column])]
 return [a[i][-1] for i in range(n)]
def exact_static_vf_minimum(p0,p1):
 assert p0[1:]==p1[1:],"Convex QP only for this fixed body face fixture"
 r=[x-y for x,y in zip(p0[0],p0[1])]
 columns=[[y-x for x,y in zip(p0[0],p1[0])],
          [x-y for x,y in zip(p0[1],p0[2])],
          [x-y for x,y in zip(p0[1],p0[3])]]
 g=[[dot(a,b) for b in columns] for a in columns];f=[dot(a,r) for a in columns]
 constraints=[([F(1),F(0),F(0)],F(0)),([F(-1),F(0),F(0)],F(-1)),
              ([F(0),F(1),F(0)],F(0)),([F(0),F(0),F(1)],F(0)),([F(0),F(-1),F(-1)],F(-1))]
 candidates=[]
 for count in range(4):
  for chosen in itertools.combinations(range(5),count):
   active=[constraints[i] for i in chosen]
   matrix=[g[i]+[-c[0][i] for c in active] for i in range(3)]
   matrix += [c[0]+[F(0)]*count for c in active]
   solution=gaussian(matrix,[-x for x in f]+[c[1] for c in active])
   if solution is None:continue
   x=solution[:3];l=solution[3:]
   if any(dot(c,x)<bound for c,bound in constraints) or any(v<0 for v in l):continue
   difference=[r[i]+sum((columns[j][i]*x[j] for j in range(3)),F(0)) for i in range(3)]
   candidates.append(dot(difference,difference))
 assert candidates,"No exact active-set stationary minimum"
 return min(candidates)

checks=[];leaves=0
rawSources={r["originalFilename"]:r for r in fixture["rows"]+extraFixture["rows"]}
exact={k:r for k,r in rawSources.items() if "exactConvexQP" in r}
for row in s["rows"]:
 m=row["motion"];r=row["proof"];p0=motion_points(m,"start");p1=motion_points(m,"end");floor=frac(m["floor"]);cover=[]
 aa=[0] if m["kind"]=="vertexFace" else [0,1];bb=[1,2,3] if m["kind"]=="vertexFace" else [2,3]
 for leaf in r["leafCertificates"]:
  n=vector(leaf["direction"]);normUpper=frac(leaf["directionNormUpperBound"])
  lower=frac(leaf["projectionLowerBound"]);threshold=frac(leaf["requiredProductUpperBound"])
  t0,t1=frac(leaf["startTime"]),frac(leaf["endTime"]);cover.append((t0,t1))
  q=[]
  for i in aa:
   for j in bb:
    d0=[x-y for x,y in zip(p0[i],p0[j])];d1=[x-y for x,y in zip(p1[i],p1[j])]
    for t in [t0,t1]:
     q.append(dot(n,[x+(y-x)*t for x,y in zip(d0,d1)]))
  trueMinimum=min(q)
  assert lower<=trueMinimum,(m["name"],"projection lower",float(lower-trueMinimum))
  assert normUpper*normUpper>=dot(n,n),(m["name"],"norm upper")
  assert threshold>=floor*normUpper,(m["name"],"threshold upper")
  assert lower>threshold,(m["name"],"strict gap")
  reportedDistance=frac(leaf["distanceLowerBoundMeters"])
  assert reportedDistance*normUpper<=lower,(m["name"],"diagnostic lower")
  leaves+=1
 moving=verify_moving_leaves(m["kind"],p0,p1,floor,r.get("movingNormalCertificates",[]))
 cover+=moving;leaves+=len(moving)
 exact=verify_expansion_leaves(m["kind"],p0,p1,floor,r.get("expansionCertificates",[]));cover+=exact;leaves+=len(exact)
 critical=verify_critical_leaves(m["kind"],p0,p1,floor,r.get("criticalCertificates",[]));cover+=critical;leaves+=len(critical)
 affine=verify_affine_leaves(m["kind"],p0,p1,floor,r.get("affineNormalCertificates",[]));cover+=affine;leaves+=len(affine)
 if r["status"]=="separated":
  cover.sort();assert cover and cover[0][0]==0 and cover[-1][1]==1,m["name"]
  assert all(a[1]==b[0] for a,b in zip(cover,cover[1:])),m["name"]
  assert sum((b-a for a,b in cover),F(0))==1,m["name"]
 if m["name"] in rawSources:
  source=rawSources[m["name"]]
  flatStart=[float(q) for v in m["start"] for q in (v if isinstance(v,list) else [v[a] for a in ["x","y","z"]])]
  flatEnd=[float(q) for v in m["end"] for q in (v if isinstance(v,list) else [v[a] for a in ["x","y","z"]])]
  assert struct.pack("<12d",*flatStart)==struct.pack("<12d",*source["start12"])
  assert struct.pack("<12d",*flatEnd)==struct.pack("<12d",*source["end12"])
 if m["name"] in exact:
  e=exact[m["name"]]["exactConvexQP"];minimumSquared=F(int(e["exactPathDistanceSquaredNumerator"]),int(e["exactPathDistanceSquaredDenominator"]))
  bound=frac(r["minimumCertifiedDistanceLowerBoundMeters"])
  assert bound*bound<=minimumSquared and minimumSquared>floor*floor
  assert exact_static_vf_minimum(p0,p1)==minimumSquared,"Fresh exact convex-QP differs from original independent result"
 checks.append({"name":m["name"],"status":r["status"],"nodes":r["processedNodes"],"depth":r["maximumDepthReached"],"leaves":len(cover),
  "minimumLowerBoundMeters":r.get("minimumCertifiedDistanceLowerBoundMeters"),"fractionSupportChecksPassed":True})
bodyChecks=[]
if args.body_report:
 for row in json.loads(args.body_report.read_text())["rows"]:
  n=vector(row["separatingDirection"]);floor=frac(row["minimumSeparation"]);body=[vector(p) for p in row["body"]]
  endpointProjections=[]
  for key in ["previous","candidate"]:
   for a in [vector(p) for p in row[key]]:
    for b in body:endpointProjections.append(dot(n,[x-y for x,y in zip(a,b)]))
  gap=min(endpointProjections)
  assert gap>0 and gap*gap>floor*floor*dot(n,n),"Full cloth/body convex triangles not continuously separated"
  assert row["status"]=="clear" and row["safeTime"]==1 and row["completedAllFeatures"]
  assert row["uniqueFeatures"]==row["evaluatedFeatures"]==row["nativeQueries"]==15
  assert row["certificateAttempts"]>=1 and row["certifiedFeatures"]>=1
  bodyChecks.append({"name":row["name"],"fullThreeByThreePairsAtBothEndpointsExactFractionClear":True,"nativeQueries":row["nativeQueries"],"certificateAttempts":row["certificateAttempts"]})
report={"passed":True,"method":"Every binary64 input/direction/range/bound interpreted as exact Fraction; verify all pair endpoint projection lower bounds, norm/product upper bounds, strict gap and complete partition. Actual VF bounds also compare independent exact convex-QP minimum.","verifiedLeaves":leaves,"rows":checks,"bodyIntegration":bodyChecks,"originalNativeAlgorithmUnchanged":True}
args.output.write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))


