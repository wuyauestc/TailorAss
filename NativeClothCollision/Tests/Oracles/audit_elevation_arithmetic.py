#!/usr/bin/env python3
"""Independent exact rational controls AND whole power-polynomial identity."""
from pathlib import Path
from fractions import Fraction as F
from math import comb
import argparse,json
p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
rows=json.loads(a.report.read_text());checks=0

def power(controls):
 n=len(controls)-1
 return[sum((controls[k]*comb(n,j)*comb(j,k)*(-1)**(j-k)for k in range(j+1)),F(0))for j in range(n+1)]
for row in rows:
 n=row['degree'];before=[sum(map(F,w),F(0))for w in row['input']];after=[sum(map(F,w),F(0))for w in row['output']]
 assert 4<=n<=8 and len(before)==n and len(after)==n+1
 expected=[n*before[0]]+[k*before[k-1]+(n-k)*before[k]for k in range(1,n)]+[n*before[-1]]
 assert after==expected
 p0,p1=power(before),power(after);assert p1==[n*z for z in p0]+[F(0)]
 assert all(len(w)<=64 for w in row['input']+row['output']);checks+=len(after)
result={'passed':True,'exactElevationStages':len(rows),'exactControlChecks':checks,'entirePolynomialIdentities':len(rows),'method':'Fraction of every stored binary64 word, exact weighted-control identity and independent Bernstein-to-power coefficient equality Pnew=n*Pold. No sampling and no production EFT imported.'}
a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
