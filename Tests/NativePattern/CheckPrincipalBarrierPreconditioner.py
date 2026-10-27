#!/usr/bin/env python3
"""Independent NumPy/LAPACK eig + 90-digit scalar reference for the PSD proxy."""
import argparse,json
from decimal import Decimal,localcontext
from pathlib import Path
import numpy as np

def scalar(s):
    lo,la,ua,hi,k=map(Decimal.from_float,[.93,.97,1.03,1.07,11.])
    if s>ua:d,w,sign=s-ua,hi-ua,1
    elif s<la:d,w,sign=la-s,la-lo,-1
    else:return Decimal(0),Decimal(0)
    r=w-d;l=(r/w).ln()
    return sign*k*(-2*d*l+d*d/r),k*(-2*l+4*d/r+d*d/(r*r))

def physical_density_psd(F):
    with localcontext() as context:
        context.prec=90
        u=[Decimal.from_float(float(x)) for x in F[:,0]];v=[Decimal.from_float(float(x)) for x in F[:,1]]
        a=sum(x*x for x in u);b=sum(x*y for x,y in zip(u,v));c=sum(x*x for x in v)
        disc=((a-c)**2+4*b*b).sqrt();lh=(a+c+disc)/2;sh=lh.sqrt()
        # Exact repeated metric: share the same root rather than introducing
        # a spurious 90-digit gap through two differently rounded expressions.
        sl=sh if disc==0 else (a*c-b*b).sqrt()/sh
        if b:
            p,q=b,lh-a;norm=(p*p+q*q).sqrt();vh=(p/norm,q/norm)
        else:vh=(Decimal(1),Decimal(0)) if a>=c else (Decimal(0),Decimal(1))
        vl=(-vh[1],vh[0])
        ul=np.array([float((x*vl[0]+y*vl[1])/sl) for x,y in zip(u,v)])
        uh=np.array([float((x*vh[0]+y*vh[1])/sh) for x,y in zip(u,v)])
        vl=np.array([float(x) for x in vl]);vh=np.array([float(x) for x in vh]);normal=np.cross(ul,uh)
        low=scalar(sl);high=scalar(sh)
        shear=low[1] if sl==sh else (high[0]-low[0])/(sh-sl)
        rotation=(high[0]+low[0])/(sl+sh)
        mode=lambda left,right:np.r_[left*right[0],left*right[1]]
        ql,qh=mode(ul,vl),mode(uh,vh);qa,qb=mode(ul,vh),mode(uh,vl)
        modes=[(low[1],ql),(high[1],qh),(shear,(qa+qb)/np.sqrt(2)),
               (rotation,(qa-qb)/np.sqrt(2)),(low[0]/sl,mode(normal,vl)),(high[0]/sh,mode(normal,vh))]
        matrix=sum(max(0,float(k))*np.outer(q,q) for k,q in modes)
        return matrix,[float(sl),float(sh)]

def check(path,output):
    data=json.loads(path.read_text());assert data['passed'];rows=[]
    for c in data['cases']:
        raw=np.array(c['rawDensity6']).reshape(6,6);proxy=np.array(c['PSDDensity6']).reshape(6,6)
        eig,basis=np.linalg.eigh((raw+raw.T)/2);positive=(basis*np.maximum(eig,0))@basis.T
        physical,sigma=physical_density_psd(np.array(c['F']))
        norm=lambda x:max(1,float(np.linalg.norm(x,ord=2)))
        error=lambda x,y:float(np.linalg.norm(x-y,ord=2))/max(norm(x),norm(y))
        physical_error=error(proxy,physical);raw_error=error(proxy,positive)
        assert physical_error<2e-10,(c['name'],'90-digit physical density PSD',physical_error)
        if not c['nearRepeated']:assert raw_error<2e-10,(c['name'],'independent full raw6 eig positive part',raw_error)
        # The source pullback is a congruence, not a second eigenvalue clamp.
        D=np.zeros((6,9))
        for i in range(3):
            for axis in range(3):D[axis,3*i+axis]=c['du'][i];D[3+axis,3*i+axis]=c['dv'][i]
        expected=c['sourceArea']*D.T@(physical if c['nearRepeated'] else positive)@D
        local=np.array(c['localPSD9']).reshape(9,9);pullback=error(local,expected)
        assert pullback<2e-10,(c['name'],'complete9 source pullback',pullback)
        p_eigen=np.linalg.eigvalsh((local+local.T)/2)
        assert p_eigen[0]>=-2e-14*norm(local),(c['name'],'PSD',p_eigen[0])
        rows.append({'name':c['name'],'nearRepeated':c['nearRepeated'],'independentDensitySingularValues':sigma,
            'physical90DigitDensityPSDRelativeError':physical_error,'binary64RawDensityEigPositivePartRelativeDifference':raw_error,
            'fullSourcePullbackRelativeError':pullback,'minimumLocalEigenvalue':float(p_eigen[0]),'rawDensityEigenvalues':eig.tolist()})
    report={'passed':True,'numpyVersion':np.__version__,'independentScalarDigits':90,'cases':rows,
        'maximumPhysicalDensityRelativeError':max(r['physical90DigitDensityPSDRelativeError'] for r in rows),
        'maximumPullbackRelativeError':max(r['fullSourcePullbackRelativeError'] for r in rows),
        'scope':'F-space eigenvalue positive part then exact source pullback; not eigenvalue clamp of the9x9 congruence.',
        'nearRepeatedBoundary':'Near-repeated cases use independent high-precision physical secants; binary64 raw divided-difference discrepancy is recorded, not hidden or changed.'}
    output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({k:report[k] for k in ['passed','maximumPhysicalDensityRelativeError','maximumPullbackRelativeError']}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args();check(a.input,a.output)
