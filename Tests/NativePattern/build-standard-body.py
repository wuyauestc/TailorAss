#!/usr/bin/env python3
"""Convert the CC0 MakeHuman hm08 body group into our fixed standard mannequin.

Input: official base.obj at a8bc2d54ff0ac92e78ff71431b1023eda42bf482.
Only anatomical `body` faces are retained; helpers, joints, clothing, hair,
teeth and genital helper geometry are excluded. A piecewise dimensional warp
sets named reference circumferences/heights; this is not personal body recovery.
"""
import argparse, hashlib, json, math
from pathlib import Path

BASELINE = dict(height=1.7199, waist=0.843338, hips=1.03478,
                hipLine=0.234837, waistLevel=1.087725)

def convert(source, destination, obj):
    vertices, triangles = [], []
    group = ''
    for line in source.read_text().splitlines():
        p = line.split()
        if not p: continue
        if p[0] == 'v': vertices.append(tuple(map(float,p[1:4])))
        elif p[0] == 'g': group=p[1]
        elif p[0] == 'f' and group == 'body':
            indices=[int(x.split('/')[0])-1 for x in p[1:]]
            triangles.extend((indices[0],indices[i],indices[i+1]) for i in range(1,len(indices)-1))
    used=sorted(set(i for t in triangles for i in t))
    remap={old:new for new,old in enumerate(used)}
    triangles=[tuple(remap[i] for i in t) for t in triangles]
    vertices=[vertices[i] for i in used]
    foot=min(p[1] for p in vertices); head=max(p[1] for p in vertices)
    waist_y, hip_y = 2.75, .5
    def slice_segments(y):
        segments=[]
        for t in triangles:
            ps=[vertices[i] for i in t]; points=[]
            for a,b in zip(ps,ps[1:]+ps[:1]):
                if (a[1]<=y<b[1]) or (b[1]<=y<a[1]):
                    f=(y-a[1])/(b[1]-a[1]); points.append((a[0]+f*(b[0]-a[0]),a[2]+f*(b[2]-a[2])))
            if len(points)==2 and all(abs(p[0])<2.4 for p in points): segments.append(points)
        return segments
    waist_segments, hip_segments=slice_segments(waist_y),slice_segments(hip_y)
    wc=sum(math.dist(a,b) for a,b in waist_segments)
    hc=sum(math.dist(a,b) for a,b in hip_segments)
    z_origin=(min(p[1] for s in waist_segments for p in s)+max(p[1] for s in waist_segments for p in s))/2
    waist_scale, hip_scale=BASELINE['waist']/wc, BASELINE['hips']/hc
    def transform(p):
        x,y,z=p
        # Smooth transverse scaling avoids a visible waist/hip crease.
        t=max(0,min(1,(y-hip_y)/(waist_y-hip_y)));t=t*t*(3-2*t)
        horizontal=hip_scale+(waist_scale-hip_scale)*t
        if y>=waist_y: yy=(y-waist_y)*(BASELINE['height']-BASELINE['waistLevel'])/(head-waist_y)
        elif y>=hip_y: yy=(y-waist_y)*BASELINE['hipLine']/(waist_y-hip_y)
        else: yy=-BASELINE['hipLine']+(y-hip_y)*(BASELINE['waistLevel']-BASELINE['hipLine'])/(hip_y-foot)
        return [round(x*horizontal,7),round(yy,7),round((z-z_origin)*horizontal,7)]
    result=[transform(p) for p in vertices]
    # Exact source slice samples are saved for arc-length waist support.
    # Order the segment loop through rounded source endpoint keys.
    adjacency={}; point_map={}
    def key(p): return (round(p[0],6),round(p[1],6))
    for a,b in waist_segments:
        ka,kb=key(a),key(b);point_map[ka]=a;point_map[kb]=b
        adjacency.setdefault(ka,[]).append(kb);adjacency.setdefault(kb,[]).append(ka)
    start=max(adjacency,key=lambda p:p[0]);current=start;previous=None;loop=[]
    while True:
        loop.append(current)
        choices=[p for p in adjacency[current] if p!=previous]
        if not choices: raise ValueError('Open waist slice')
        nxt=choices[0]
        if nxt==start: break
        previous,current=current,nxt
        if len(loop)>len(adjacency)+1:raise ValueError('Invalid waist slice')
    waist_path=[[round(point_map[p][0]*waist_scale,7),0,round((point_map[p][1]-z_origin)*waist_scale,7)] for p in loop]
    # Start +X and proceed toward +Z (front half); stable panel placement.
    area=sum(a[0]*b[2]-b[0]*a[2] for a,b in zip(waist_path,waist_path[1:]+waist_path[:1]))
    if area<0:waist_path=[waist_path[0]]+list(reversed(waist_path[1:]))
    payload=dict(format='tailorass-standard-body-v1',
                 sourceCommit='a8bc2d54ff0ac92e78ff71431b1023eda42bf482',
                 sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest(),
                 license='CC0-1.0', baseline=BASELINE,
                 positions=result,triangleIndices=[i for t in triangles for i in t],waistPath=waist_path,
                 # Same lower grid samples, extended upward beyond the head.
                 collisionGrid=dict(origin=[-.6337,-1.1137,-.3037],spacing=.01,dimensions=[128,181,65],encoding='float32-little-endian',filename='GarmentCodeStandardBodySDF.bin'))
    destination.write_text(json.dumps(payload,separators=(',',':'))+'\n')
    obj.write_text('\n'.join(['v '+' '.join(map(str,p)) for p in result]+['f '+' '.join(str(i+1) for i in t) for t in triangles])+'\n')
    print('Source SHA256',payload['sourceSHA256'])
    print('Retained body',len(result),'vertices',len(triangles),'triangles; waist slice',len(waist_path),'points')
    print('Baseline',BASELINE,'waist source',wc,'hips source',hc)
    print(destination)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('destination',type=Path)
    p.add_argument('--obj',type=Path,default=Path('/private/tmp/TailorAssStandardBodyCollider.obj'))
    args=p.parse_args();convert(args.source,args.destination,args.obj)
