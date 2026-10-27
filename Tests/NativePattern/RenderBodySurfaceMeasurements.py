#!/usr/bin/env python3
"""Draw original source triangles and the actual measured surface attachments."""
from pathlib import Path
import argparse,json,math
from PIL import Image,ImageDraw,ImageFont

def render(report, output, profile, font_path):
    p=[tuple(q[k] for k in ['x','y','z']) for q in report['positions']]
    ids=report['triangleIndices'];faces=[ids[i:i+3] for i in range(0,len(ids),3)]
    width,height=1920,1380;im=Image.new('RGB',(width,height),'#f7f4ef');draw=ImageDraw.Draw(im)
    font=ImageFont.truetype(font_path,22);small=ImageFont.truetype(font_path,17);title=ImageFont.truetype(font_path,31)
    draw.text((35,23),'TailorAss · '+profile+' · 原人体表面量法',font=title,fill='#44373d')
    draw.text((35,69),'实际加载的完整原网格 · +Y 向上 · +Z 向前 · 测量点与路径保留原三角面来源',font=font,fill='#786b69')
    palette={'chestSurfaceReference':'#c07549','shoulderSurfaceSpan':'#927640','shoulderLateralSurfaceWidth':'#927640',
        'wristSurfaceLoop.L':'#456f99','wristSurfaceLoop.R':'#456f99','outerArmSurfaceRoute.L':'#a74667','outerArmSurfaceRoute.R':'#a74667'}
    def sub(a,b):return tuple(x-y for x,y in zip(a,b))
    def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
    for name,left,top,w,h,horizontal,depth,xlim,ylim in [
        ('正视图',35,117,1220,900,0,2,(-.66,.66),(-.16,.47)),
        ('侧视图（从 +X 看）',1280,117,605,900,2,0,(-.24,.26),(-.16,.47))]:
        draw.rounded_rectangle((left,top,left+w,top+h),radius=13,fill='#fffdf9',outline='#ddd4cc',width=2)
        draw.text((left+15,top+12),name,font=font,fill='#5c4c51')
        scale=min((w-35)/(xlim[1]-xlim[0]),(h-75)/(ylim[1]-ylim[0]))
        def xy(q):return (left+w/2+(q[horizontal]-(xlim[0]+xlim[1])/2)*scale,top+h/2+23-(q[1]-(ylim[0]+ylim[1])/2)*scale)
        # Full original visible triangle list; only the view window clips it.
        for f in sorted(faces,key=lambda f:sum(p[i][depth] for i in f)/3):
            q=[p[i] for i in f]
            if max(v[1] for v in q)<ylim[0] or min(v[1] for v in q)>ylim[1]:continue
            n=cross(sub(q[1],q[0]),sub(q[2],q[0]));length=math.sqrt(sum(v*v for v in n)) or 1
            brightness=.70+.24*abs((.3*n[0]+.5*n[1]+.7*n[2])/length)
            draw.polygon([xy(v) for v in q],fill=tuple(round(c*brightness) for c in [206,205,199]))
        for m in report['measurements']:
            key=m['definition']['id']
            if key=='shoulderLateralSurfaceWidth' or (horizontal==2 and key.endswith('.R')):continue
            q=[xy(tuple(v[k] for k in ['x','y','z'])) for v in m['points']]
            if m['definition'].get('closed'):q.append(q[0])
            draw.line(q,fill=palette[key],width=5,joint='curve')
        for label,q in report['landmarks'].items():
            if 'Guide' in label or (horizontal==2 and label.endswith('.R')):continue
            x,y=xy(tuple(q[k] for k in ['x','y','z']));draw.ellipse((x-5,y-5,x+5,y+5),fill='#fffdf9',outline='#6b3448',width=2)
            if label.endswith('.L'):
                short={'chestSurfaceReference.L':'胸部表面参考点','shoulderSurfaceReference.L':'肩部表面点','outerElbowSurfaceReference.L':'外肘表面点','wristArmRouteEnd.L':'臂线的腕端'}[label]
                # Each label has a leader so it remains legible at close points.
                dx,dy=(12,-26)
                if horizontal==2 and label=='outerElbowSurfaceReference.L':dx,dy=(-165,10)
                draw.line([(x,y),(x+dx,y+dy+8)],fill='#6b3448',width=1)
                draw.text((x+dx,y+dy),short,font=small,fill='#6b3448')
    draw.text((35,1048),'橙：胸部表面参考闭环　金：两肩表面点跨度　紫红：经外肘的连续表面臂线　蓝：腕部表面环',font=font,fill='#786b69')
    draw.text((35,1090),'量法',font=font,fill='#44373d');draw.text((850,1090),'实测 / cm',font=font,fill='#44373d');draw.text((1110,1090),'输入 / cm',font=font,fill='#44373d');draw.text((1380,1090),'差值 / cm',font=font,fill='#44373d')
    for i,key in enumerate(['chestSurfaceReference','shoulderLateralSurfaceWidth','outerArmSurfaceRoute.L','wristSurfaceLoop.L']):
        m=next(m for m in report['measurements'] if m['definition']['id']==key);y=1130+i*43
        draw.text((35,y),m['definition']['title'],font=font,fill=palette[key])
        for x,val in [(850,m['observedMeters']),(1110,m['requestedMeters']),(1380,m['observedMinusRequestedMeters'])]:
            draw.text((x,y),f'{val*100:+.3f}' if x==1380 else f'{val*100:.3f}',font=font,fill='#5c4c51')
    draw.text((35,1320),'项目参考量法、尚未拟合。',font=font,fill='#786b69')
    output.parent.mkdir(parents=True,exist_ok=True);im.save(output)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--report',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--profile',default='默认人体');parser.add_argument('--font',default='/System/Library/Fonts/STHeiti Medium.ttc');args=parser.parse_args()
    render(json.loads(args.report.read_text()),args.output,args.profile,args.font);print(args.output)
