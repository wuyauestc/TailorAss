#!/usr/bin/env python3
"""Independent authored sleeve-coordinate axes from the pinned MIT program.

This is a coordinate-placement oracle, not a measured human/sleeve centerline.
No Swift placement or MakeHuman application/measurement code is used.
"""
import argparse,copy,hashlib,json,os,sys,types
from pathlib import Path

COMMIT='d449629979028123a5c4dc9e732a2ec19b7fce31'
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--upstream-dir',type=Path,required=True);p.add_argument('--source-tree-proof',type=Path,required=True);p.add_argument('--body-input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
source=a.upstream_dir.resolve();a.output=a.output.resolve();a.body_input=a.body_input.resolve();a.source_tree_proof=a.source_tree_proof.resolve();proof=json.loads(a.source_tree_proof.read_bytes());assert proof['commit']==COMMIT and proof['treeSHA']=='fd422f0e3708f4d67f169cb2553fa38182601d44'
hashes={}
for f in sorted(source.rglob('*')):
 if f.is_file() and f.suffix in ['.py','.yaml']:
  data=f.read_bytes();name=str(f.relative_to(source));assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==proof['blobSHA'][name],'Changed official source: '+name
  hashes[name]=hashlib.sha256(data).hexdigest()
os.environ.setdefault('MPLCONFIGDIR','/private/tmp/TailorAssBodyRigMatplotlib');os.chdir(source);sys.path.insert(0,str(source))
cairo=types.ModuleType('cairosvg');cairo.svg2png=lambda *a,**k:None;cairo.svg2pdf=lambda *a,**k:None;sys.modules['cairosvg']=cairo
import numpy as np
import scipy
import yaml
from assets.garment_programs.meta_garment import MetaGarment
raw=json.loads(a.body_input.read_bytes());base_body=raw.get('values',raw.get('body',raw));base_design=yaml.safe_load((source/'assets/design_params/default.yaml').read_text())['design'];cases=[]
for upper in ['Shirt','FittedShirt']:
 for angle in [30.,45.,60.]:
  body=copy.deepcopy(base_body);body['arm_pose_angle']=angle;design=copy.deepcopy(base_design);design['meta']['upper']['v']=upper;design['meta']['bottom']['v']=None;design['meta']['wb']['v']=None;design['sleeve']['sleeveless']['v']=False
  garment=MetaGarment(f'rig-axis-{upper}-{angle:g}',body,design);spec=garment.assembly().spec;top=garment.subs[0];rows=[]
  for side in ['right','left']:
   sleeve=getattr(top,side).sleeve
   for half in ['f','b']:
    panel=getattr(sleeve,'f_sleeve' if half=='f' else 'b_sleeve');cuff=np.mean(panel.interfaces['out'].edges.verts(),axis=0);opening=np.mean(panel.interfaces['in'].edges.verts(),axis=0);sign=float(np.sign(cuff[0]-opening[0]));assert sign==(-1 if side=='right' else 1)
    q0=panel.point_to_3D([0,0]);q1=panel.point_to_3D([sign,0]);axis=q1-q0;axis/=np.linalg.norm(axis)
    expected=np.array([sign*np.cos(np.deg2rad(angle)),-np.sin(np.deg2rad(angle)),0.]);assert np.max(np.abs(axis-expected))<1e-12
    below=float(np.rad2deg(np.arctan2(-axis[1],abs(axis[0]))));down=float(np.rad2deg(np.arccos(np.clip(-axis[1],-1,1))))
    rows.append({'panelID':panel.name,'side':side,'half':half,'longitudinalLocalCoordinateAxis':[sign,0,0],'worldAxisFromOfficialPointTo3D':axis.tolist(),
     'worldPoint0':q0.tolist(),'worldPoint1':q1.tolist(),'officialEulerXYZDegrees':panel.rotation.as_euler('XYZ',degrees=True).tolist(),
     'belowHorizontalDegrees':below,'angleToDownYDegrees':down,'formulaError':float(np.max(np.abs(axis-expected)))})
  cases.append({'upper':upper,'armPoseAngleInputDegrees':angle,'body':body,'panels':rows,'completePatternPanelCount':len(spec['pattern']['panels']),
   'completeOfficialPatternSHA256':hashlib.sha256(json.dumps(spec,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()})
payload={'format':'tailorass-cc0-rig-garment-sleeve-axis-oracle-v1','source':{'repository':'https://github.com/maria-korosteleva/GarmentCode','commit':COMMIT,
 'treeProofSHA256':hashlib.sha256(a.source_tree_proof.read_bytes()).hexdigest(),'fileSHA256':hashes,'numpyVersion':np.__version__,'scipyVersion':scipy.__version__,
 'generatorSHA256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Unmodified official full MetaGarment; only unused Cairo rendering stubbed'},
 'semantic':'In this constructor arm_pose_angle is Rz(+alpha) on the unmirrored sleeve coordinate frame. Its outward longitudinal coordinate basis is (-cos alpha,-sin alpha,0) on right and (cos alpha,-sin alpha,0) on mirrored left. The angle to down Y is 90-alpha. This basis is NOT a measured body-bone axis or tapered sleeve centerline.',
 'measurementCodeOrAGPLPathsUsed':False,'cases':cases}
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(payload,indent=2,ensure_ascii=False,allow_nan=False)+'\n');print('PASS',len(cases),'complete garment cases',sum(len(x['panels']) for x in cases),'independent official axes')
