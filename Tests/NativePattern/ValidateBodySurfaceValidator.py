#!/usr/bin/env python3
"""Independent Fraction closed-triangle reference for the Swift controls.
The six full-mesh reference goldens were independently audited previously and
are bound by actual geometry SHA and exact candidate/classification counts.
"""
from pathlib import Path
import json,sys,hashlib,struct,ast,types
out=Path(sys.argv[1]);oracle=Path(sys.argv[2])
# Execute the unchanged exact arithmetic function ASTs only. The original
# optional NumPy all-pair broad phase is not needed for these tiny controls.
core=['vsub','vadd','mul','dot','cross','exactpoint','normal','orient2','project','inside','expected_shared','coplanar_clip','exact_intersection']
tree=ast.parse(oracle.read_text());selected=[n for n in tree.body if isinstance(n,ast.ImportFrom)and n.module=='fractions' or isinstance(n,ast.FunctionDef)and n.name in core]
m=types.ModuleType('exact_static_core');exec(compile(ast.Module(body=selected,type_ignores=[]),str(oracle),'exec'),m.__dict__)
assert all(hasattr(m,k)for k in core)
cases=json.loads((out/'analytic-cases.json').read_text());bits={r['name']:r['positions']for r in json.loads((out/'analytic-runtime-bits.json').read_text())};rows=[]
for case in cases:
 p=[m.exactpoint([struct.unpack('>d',bytes.fromhex(x))[0]for x in point])for point in bits[case['name']]];ids=case['triangleIndices'];clear=True;kinds=[]
 for i in range(0,len(ids),3):
  a=ids[i:i+3]
  for j in range(i+3,len(ids),3):
   b=ids[j:j+3];shared=[p[k]for k in sorted(set(a)&set(b))];kind,_=m.exact_intersection([p[k]for k in a],[p[k]for k in b],shared);kinds.append(kind)
   clear &= kind in ['separated','expectedTopologicalTouch']
 assert clear==case['expectedClear'],(case['name'],clear,case['expectedClear'],kinds)
 rows.append({'name':case['name'],'matches':True,'fractionKinds':kinds})
result={'passed':True,'scope':'Exact Fraction static closed-triangle oracle of same binary64 controls; not a cloth/swept check.','controlCount':len(rows),'rows':rows,'oracleSHA256':hashlib.sha256(oracle.read_bytes()).hexdigest()}
(out/'fraction-oracle.json').write_text(json.dumps(result,indent=2)+'\n');print('EXACT_STATIC_ORACLE_PASS',len(rows))
