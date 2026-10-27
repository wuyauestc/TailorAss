#!/usr/bin/env python3
"""Archive the already independently checked frozen 25+4 Double endpoint pairs.
Daily verification needs only the repository fixture, never the research /tmp.
"""
from pathlib import Path
import argparse,json,gzip,hashlib
SOURCE='28eb56b2ec46feddde570c300896cd6422045e6d119d0a2af11f667ae7604a35'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--research-dir',type=Path);p.add_argument('--output-dir',type=Path);p.add_argument('--verify-dir',type=Path);a=p.parse_args()
 if a.verify_dir:
  d=a.verify_dir;m=json.loads((d/'manifest.json').read_text())
  for f,h in m['files'].items():assert digest(d/f)==h, f
  raw=gzip.decompress((d/'controls.json.gz').read_bytes());assert hashlib.sha256(raw).hexdigest()==m['uncompressedSHA256']
  c=json.loads(raw);assert c['canonicalSourceSHA256']==SOURCE and len(c['newtonCases'])==25 and len(c['activeCases'])==4
  assert m['generatorSHA256']==digest(Path(__file__))
  print(json.dumps({'status':'pass','canonicalSourceSHA256':SOURCE,'newtonControls':25,'activeControls':4}));return
 assert a.research_dir and a.output_dir
 r=a.research_dir;d=a.output_dir;d.mkdir(parents=True,exist_ok=True)
 params=json.loads((r/'captured-newton/exact-native-parameters.json').read_text());prepared=json.loads((r/'prepared-native.json').read_text());assert params['triangles']==prepared['triangles']
 context={'inertial':params['inertialDouble'],'rows':params['rows'],'sewingStiffness':params['sewingKDouble']}
 def pos(path):
  x=json.loads(path.read_text());return x['positions'] if isinstance(x,dict) else x
 context['base']=pos(r/'captured-newton/inputs/frozen-r2-candidate.json');context['predictor']=pos(r/'captured-newton/inputs/previous-frame.json')
 main=json.loads((r/'actual-newton-line-error-bounds.json').read_text())['results'];table=json.loads((r/'captured-newton/alpha-table.json').read_text())['table']
 cases=[]
 for e,t in zip(main,table):
  cases.append({'power':e['power'],'alpha':e['alpha'],'candidate':pos(r/'captured-newton'/t['candidateFile']),
   'expectedNHDelta':float(e['components']['membrane']['decimal100Delta']),'expectedFullPhiDelta':float(e['decimal100TotalDelta']),
   'armijoIncrement':t['swiftArmijoIncrement'],'expectedArmijoPass':e['decimal100ArmijoDecision']=='pass',
   'actualRoundedGradientWork':float(e['actualRoundedGradientWorkDecimal100'])})
 active_inputs=json.loads((r/'native-activated-cases.json').read_text());active_reports=json.loads((r/'native-activated-diagnostic.json').read_text())['results'];active=[]
 for c,e in zip(active_inputs,active_reports):
  def xyz(v):return {'x':v[0],'y':v[1],'z':v[2]}
  active.append({'name':c['name'],'base':list(map(xyz,c['x'])),'candidate':list(map(xyz,c['candidate'])),
   'expectedDelta':{k:float(e['terms'][k]['decimal100Delta']) for k in ['membrane','barrier','hinge','total']},
   'gradientWork':float(e['terms']['total']['gradientWorkDecimal100']),'activePrincipalTerms':e['activeTerms']['baseActiveTerms']})
 full={'format':'GarmentCodeElasticEnergyDeltaControls/v1','canonicalSourceSHA256':SOURCE,'material':{'mu':params['muDouble'],'lambda':params['lambdaDouble'],'kb':prepared['kbDouble']},'barrier':prepared['barrier'],
  'storedTriangles':prepared['triangles'],'storedHinges':prepared['hinges'],'newtonContext':context,'newtonCases':cases,'activeCases':active,
  'reference':'Independent Decimal80/100 direct same-real-valued objective endpoints with exact import of actual Double coordinates/du/dv/A0/hinge weights. No candidate accepted. kappa0 in Newton controls; kb active only in separate analytic source controls.'}
 raw=(json.dumps(full,separators=(',',':'))+'\n').encode();(d/'controls.json.gz').write_bytes(gzip.compress(raw,compresslevel=9,mtime=0))
 m={'scope':'Frozen actual rounded 25 captured Newton line candidates + 4 all-source active barrier/hinge probes; no accepted simulation',
 'canonicalSourceSHA256':SOURCE,'generatorSHA256':digest(Path(__file__)),'uncompressedSHA256':hashlib.sha256(raw).hexdigest(),'files':{'controls.json.gz':digest(d/'controls.json.gz')},
 'oraclePrecisions':[80,100],'referenceIsPosthocNotAnOnlineErrorCertificate':True,'numpyLongDoubleMantissaBits':53,'nativeReferenceTriangles':3472,'nativeHinges':4948,'newtonCases':25,'activeCases':4}
 (d/'manifest.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps(m,indent=2))
if __name__=='__main__':main()
