"""Pack authored profile/back walk cycles on a shared, foot-aligned frame grid.
Pass a JSON {character: source PNG/webp} file to rebuild the production clips.
"""
import json
from pathlib import Path
import sys
import re
from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
CREW = ROOT/"assets/crew"
OUT = CREW/"directions"
OUT.mkdir(exist_ok=True)

def silhouette(rgba,name):
    if name != "Gromp": return rgba
    # The neutral matte extends into a few curled toes and the moss crown.
    # Classify the exterior per frame, then extend interior RGB through the
    # antialiased edge to keep bilinear filtering clean on dark backgrounds.
    import cv2
    from scipy.ndimage import binary_erosion, distance_transform_edt, gaussian_filter
    arr=np.asarray(rgba).copy()
    h,w=arr.shape[:2]
    for row in range(2):
        for col in range(4):
            frame=arr[row*h//2:(row+1)*h//2,col*w//4:(col+1)*w//4]
            rgb=frame[:,:,:3].copy()
            hsv=cv2.cvtColor(rgb,cv2.COLOR_RGB2HSV)
            sat=hsv[:,:,1];val=hsv[:,:,2]
            mask=np.full(val.shape,cv2.GC_PR_BGD,dtype='uint8')
            mask[(sat>28)|(val<91)] = cv2.GC_PR_FGD
            mask[(sat>64)&(frame[:,:,3]>105)] = cv2.GC_FGD
            mask[((sat<21)&(val>93))|(frame[:,:,3]<35)] = cv2.GC_BGD
            mask[:2]=mask[-2:]=mask[:,:2]=mask[:,-2:]=cv2.GC_BGD
            cv2.grabCut(rgb,mask,None,np.zeros((1,65)),np.zeros((1,65)),4,cv2.GC_INIT_WITH_MASK)
            fg=(mask==cv2.GC_FGD)|(mask==cv2.GC_PR_FGD)
            _,labels,stats,_=cv2.connectedComponentsWithStats(fg.astype('uint8'))
            fg=labels==1+np.argmax(stats[1:,cv2.CC_STAT_AREA])
            core=binary_erosion(fg,iterations=3)
            _,ind=distance_transform_edt(~core,return_indices=True)
            edge=~core
            frame[:,:,:3][edge]=rgb[ind[0][edge],ind[1][edge]]
            frame[:,:,3]=np.uint8(255*gaussian_filter(binary_erosion(fg,iterations=1).astype(float),.76))
    return Image.fromarray(arr)

def cut(im,rows):
    a=np.asarray(im.getchannel('A'))>52
    def joins(v,n):
        span=len(v)/n
        return [0]+[min(range(round((i-.18)*span),round((i+.18)*span)),key=lambda p:(v[p],abs(p-i*span))) for i in range(1,n)]+[len(v)]
    xs,ys=joins(a.sum(0),4),joins(a.sum(1),rows)
    return [im.crop((xs[c],ys[r],xs[c+1],ys[r+1])) for r in range(rows) for c in range(4)]

def bounds(im):
    a=np.asarray(im.getchannel('A'))
    y,x=np.where(a>48)
    bottom=np.percentile(y,99.75)
    anchor=np.median(x[y>bottom-max(3,(bottom-y.min())*.22)])
    return (x.min(),y.min(),x.max()+1,y.max()+1),anchor,bottom

def contact(im):
    a=np.asarray(im.getchannel('A'))
    ys,xs=np.where(a>100)
    low=np.percentile(ys,99.7)
    feet=xs[ys>=low-1.4]
    return (round(float(np.median(feet))/im.width,5),round((low+.5)/im.height,5))

def normal(atlas):
    """Bake convex forms independently for each silhouette on a four-column atlas."""
    from scipy.ndimage import distance_transform_edt, gaussian_filter

    rgba = np.asarray(atlas.convert("RGBA"), dtype=float) / 255.0
    width = atlas.width // 4
    rgb = np.full((*rgba.shape[:2], 3), [128, 128, 255], dtype=np.uint8)
    for top in range(0, atlas.height, width):
        for left in range(0, atlas.width, width):
            tile = rgba[top:top+width, left:left+width]
            alpha = tile[:, :, 3]
            depth = gaussian_filter(distance_transform_edt(alpha > .45), 1.4)
            radius = width * .095
            dome = radius * .69 * np.sin(np.minimum(depth/radius, 1) * np.pi/2)
            pigment = gaussian_filter(tile[:, :, :3].mean(2) * alpha, 1.1)
            dy, dx = np.gradient(dome + 1.8 * pigment)
            vectors = np.stack((-dx, dy, np.ones_like(dx)), axis=2)
            vectors /= np.linalg.norm(vectors, axis=2, keepdims=True)
            rgb[top:top+width, left:left+width] = np.rint((vectors * .5 + .5) * 255)
    return Image.fromarray(rgb)

def resource(sheet_id,row,w,tex,foot):
    u,v=foot
    return f'[sub_resource type="AtlasTexture" id="{sheet_id}"]\natlas = ExtResource("{tex}")\nregion = Rect2({row%4*w}, {row//4*w}, {w}, {w})\nfilter_clip = true\nmetadata/sole = Vector2({u}, {v})\n'

def animation(name,ids,fps):
    frames=', '.join('{"duration": 1.0, "texture": SubResource("'+i+'")}' for i in ids)
    return '{"name": &"%s", "speed": %.1f, "loop": true, "frames": [%s]}'%(name,fps,frames)

def generate(key,path):
    new=key in ['blue-caster','blue-siege']
    w=112 if key.startswith('blue-') else 128
    rows=3 if new else 2
    im=silhouette(Image.open(path).convert('RGBA'),key)
    frames=cut(im,rows)
    if new:
        for i in range(4):frames[i]=frames[i].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    parts=[bounds(x) for x in frames]
    if new: target_height=92 if key=='blue-caster' else 83
    else:
        base=Image.open(CREW/(key+'.webp')).convert('RGBA')
        box,_,_=bounds(base.crop((0,0,w,w)))
        target_height=box[3]-box[1]
    factor=min(target_height/max(cy-box[1] for box,cx,cy in parts),
               (w*.47)/max(max(cx-box[0],box[2]-cx) for box,cx,cy in parts))
    atlas=Image.new('RGBA',(w*4,w*rows));subs=[]
    for i,(frame,(box,cx,cy)) in enumerate(zip(frames,parts)):
        tile=Image.new('RGBA',(w,w));fg=frame.crop(box)
        fg=fg.resize((max(1,round(fg.width*factor)),max(1,round(fg.height*factor))),Image.Resampling.LANCZOS)
        tile.paste(fg,(round(w*.5-(cx-box[0])*factor),round(w*.947-(cy-box[1])*factor)))
        atlas.paste(tile,(i%4*w,i//4*w));subs.append(resource('dir'+str(i),i,w,'directions',contact(tile)))
    atlas.save(OUT/(key+'.webp'),quality=93,method=6)
    normal(atlas).save(OUT/(key+'-normal.png'),optimize=True)
    path=CREW/(key+'.tres')
    if new:
        head='[gd_resource type="SpriteFrames" format=3]\n'
        clips=[animation(n,['dir'+str(k) for k in ids],fps) for n,ids,fps in [('idle',[0],1),('walk',range(4),8),('work',[0,1,0,3],5)]]
    else:
        text=path.read_text()
        head,tail=text.split('[resource]',1)
        head=re.sub(r'\[ext_resource[^\n]*id="directions"\]\n','',head)
        head=re.sub(r'\[sub_resource type="AtlasTexture" id="dir\d+"\].*?(?=\[sub_resource|\Z)','',head,flags=re.S)
        # Recompute contact anchors for existing forward/action frames.
        pat=r'(region = Rect2\((\d+), (\d+), (\d+), (\d+)\)\nfilter_clip = true)(?:\nmetadata/sole = Vector2\([^)]*\))?'
        def add(m):
            x,y,fw,fh=map(int,m.groups()[1:]);u,v=contact(base.crop((x,y,x+fw,y+fh)))
            return m[1]+f'\nmetadata/sole = Vector2({u}, {v})'
        head=re.sub(pat,add,head)
        clip_text=tail.split('animations = [',1)[1].strip()[:-1]
        # Existing action definitions are single-line dictionaries.
        clips=[line.rstrip(',') for line in clip_text.splitlines() if '"walk_side"' not in line and '"walk_away"' not in line]
    extra='[ext_resource type="Texture2D" path="res://assets/crew/directions/'+key+'.webp" id="directions"]\n'
    split=head.find('[sub_resource')
    head=head[:split]+extra+'\n'+head[split:] if split>=0 else head+'\n'+extra
    for row,n in enumerate(['walk_side','walk_away'],start=1 if new else 0):
        clips.append(animation(n,['dir'+str(row*4+c) for c in range(4)],8))
    path.write_text(head.strip()+'\n\n'+'\n'.join(subs)+'\n[resource]\nanimations = ['+',\n'.join(clips)+']\n')

if __name__=='__main__':
    sources = json.loads(Path(sys.argv[1]).read_text()) if len(sys.argv)>1 else {p.stem:p for p in sorted((ROOT/"art_source/canyon/员工行走").glob("*.webp"))}
    for key,path in sources.items():generate(key,path)
