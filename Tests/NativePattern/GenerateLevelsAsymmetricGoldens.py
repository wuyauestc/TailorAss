#!/usr/bin/env python3
"""Generate asymmetric tier oracles from pinned, unchanged GarmentCode.

This uses complete explicit body/design inputs and upstream MetaGarment only.
It neither imports Swift nor substitutes geometry calculations. Optional Cairo
rendering is unavailable and fails if called; no rendering is requested.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import sys
import types

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--upstream-dir',type=Path,required=True)
parser.add_argument('--source-hash-fixture',type=Path,required=True)
parser.add_argument('--input-manifest',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
script_path=Path(__file__).resolve()
args.source_hash_fixture=args.source_hash_fixture.resolve()
args.input_manifest=args.input_manifest.resolve()
args.output=args.output.resolve()
commit='d449629979028123a5c4dc9e732a2ec19b7fce31'
source=args.upstream_dir.resolve()
old=json.loads(args.source_hash_fixture.read_text())
assert old['source']['commit']==commit
source_hashes={}
for path in sorted(source.rglob('*.py')):
    relative=str(path.relative_to(source))
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    assert old['source']['sourceFileSHA256'][relative]==digest,relative
    source_hashes[relative]=digest
assert len(source_hashes)>=48
input_manifest=json.loads(args.input_manifest.read_text())
selected=[row for row in input_manifest['cases']
          if row['caseID'].startswith('discrete:') and ':levels:' in row['caseID']
          and row['caseID'].endswith(':AsymmSkirtCircle')]
assert len(selected)==8 and {row['profile'] for row in selected}=={'default','female'}
os.environ.setdefault('MPLCONFIGDIR','/private/tmp/TailorAssLevelsOracleMatplotlib')
sys.path.insert(0,str(source))
os.chdir(source)
cairo=types.ModuleType('cairosvg')
def unused_render(*args,**kwargs):
    raise AssertionError('Rendering must not be called by the geometry oracle')
cairo.svg2png=unused_render
cairo.svg2pdf=unused_render
sys.modules['cairosvg']=cairo
import numpy as np
import scipy
from assets.garment_programs.meta_garment import MetaGarment

cases=[]
input_hashes={}
for row in selected:
    pattern_path=args.input_manifest.resolve().parent/row['patternFile']
    raw=pattern_path.read_bytes()
    assert hashlib.sha256(raw).hexdigest()==row['paperJSONBytesSHA256']
    input_hashes[row['caseID']]=hashlib.sha256(raw).hexdigest()
    original=json.loads(raw)
    for count in [2,3,5]:
        body=copy.deepcopy(original['parameters']['body'])
        design=copy.deepcopy(original['parameters']['design'])
        design['levels-skirt']['num_levels']['v']=count
        name=f"{row['profile']}-{design['levels-skirt']['base']['v']}-AsymmSkirtCircle-n{count}"
        garment=MetaGarment(name,copy.deepcopy(body),copy.deepcopy(design))
        expected=garment.assembly().spec
        cases.append({'id':name,'body':body,'design':design,'originalCaseID':row['caseID'],
                      'tiers':count,'expected':expected})
        print('OFFICIAL',name,len(expected['pattern']['panels']),flush=True)
assert all(hashlib.sha256((source/path).read_bytes()).hexdigest()==digest
           for path,digest in source_hashes.items())
payload={'format':'GarmentCodeAsymmetricTierOracles/v1','source':{
    'repository':'https://github.com/maria-korosteleva/GarmentCode','commit':commit,
    'sourceFileSHA256':source_hashes,
    'sourceHashFixtureSHA256':hashlib.sha256(args.source_hash_fixture.read_bytes()).hexdigest(),
    'inputManifestSHA256':hashlib.sha256(args.input_manifest.read_bytes()).hexdigest(),
    'originalPaperBytesSHA256':input_hashes,'numpyVersion':np.__version__,'scipyVersion':scipy.__version__,
    'generatorSHA256':hashlib.sha256(script_path.read_bytes()).hexdigest(),
    'scope':'Unmodified pinned MetaGarment, same explicit resolved body/design inputs; no Swift geometry or 3D cloth simulation',
    'renderingCalled':False},'cases':cases}
args.output.write_text(json.dumps(payload,ensure_ascii=False,indent=2,allow_nan=False)+'\n')
print('PASS official asymmetric tiers',len(cases),flush=True)
