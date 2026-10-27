#!/usr/bin/env python3
"""Independent exact-binary rational equality of every exported EFT result."""
from pathlib import Path
from fractions import Fraction as F
import argparse,json,math
p=argparse.ArgumentParser();p.add_argument('--report',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
rows=json.loads(a.report.read_text())
for row in rows:
 aa,bb=F(row['a']),F(row['b'])
 for key,target in [('sum',aa+bb),('product',aa*bb)]:
  words=row[key];assert len(words)<=64 and all(math.isfinite(v)and v!=0 for v in words)
  assert sum(map(F,words),F(0))==target,(key,row)
result={'passed':True,'exactEqualityRows':len(rows),'exactSumChecks':len(rows),'exactProductChecks':len(rows),'method':'Fraction of exact stored binary64 operands and expansion words. No producer TwoSum/FMA implementation imported.','noRealUnderflowOrOverflowAccepted':True}
a.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
