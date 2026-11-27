"""Blender background entry point. Rebuild the editable canyon set and per-landmark GLBs."""
from pathlib import Path
from math import cos, exp, pi, sin, sqrt
import sys
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
# Blender ships its own Python. The bake tool runs separately with Pillow.
import ast
source = ast.parse((ROOT/"tools/bake_canyon_maps.py").read_text())
CROPS = next(ast.literal_eval(n.value) for n in source.body if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id=="CROPS" for t in n.targets))
MAPS = ROOT/"art_source/canyon/maps"
OUT = ROOT/"assets/canyon_world"
OUT.mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
SCALE = 6.8
DEPTH = sqrt(1+(48/72)**2)
LIFT = 48/sqrt(72**2+48**2)

def xyz(p):
    x, y, z = p
    return Vector(((x-511)/SCALE, -((y-479)/SCALE+z*LIFT)*DEPTH,z))

def material(key):
    mat = bpy.data.materials.new(key+"_paint")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bs = nodes.get("Principled BSDF")
    for suffix, kind in [("color.jpg","Base Color"),("normal.png","Normal"),("orm.png","Roughness")]:
        tex=nodes.new("ShaderNodeTexImage")
        tex.image=bpy.data.images.load(str(MAPS/(key+"_"+suffix)),check_existing=True)
        if kind=="Base Color":
            links.new(tex.outputs["Color"],bs.inputs[kind])
        else:
            tex.image.colorspace_settings.name="Non-Color"
            if kind=="Normal":
                normal=nodes.new("ShaderNodeNormalMap")
                normal.inputs["Strength"].default_value=.50
                links.new(tex.outputs["Color"],normal.inputs["Color"])
                links.new(normal.outputs["Normal"],bs.inputs[kind])
            else:
                rgb=nodes.new("ShaderNodeSeparateColor")
                links.new(tex.outputs["Color"],rgb.inputs[0])
                links.new(rgb.outputs["Green"],bs.inputs["Roughness"])
                links.new(rgb.outputs["Blue"],bs.inputs["Metallic"])
    return mat

class Landmark:
    def __init__(self,key,anchor):
        self.key=key
        self.base=xyz((*anchor,0))
        self.mat=material(key)
        self.rect=CROPS[key][1]
        self.group=bpy.data.collections.new(key)
        bpy.context.scene.collection.children.link(self.group)
        self.objects=[]
    def part(self,name,faces,orient=True):
        points=[]; indices=[]; lookup={}
        for poly in faces:
            group=[]
            for p in poly:
                p=tuple(round(i,5) for i in p)
                if p not in lookup:
                    lookup[p]=len(points); points.append(p)
                group.append(lookup[p])
            if len(set(group))<3: continue
            if orient:
                v=[xyz(points[i]) for i in group[:3]]
                if (v[1]-v[0]).cross(v[2]-v[0]).dot(Vector((0,-48,72)))<0: group.reverse()
            indices.append(group)
        data=bpy.data.meshes.new(name)
        data.from_pydata([xyz(p)-self.base for p in points],[],indices)
        data.materials.append(self.mat)
        uv=data.uv_layers.new(name="PaintUV")
        l,t,r,b=self.rect
        for loop in data.loops:
            x,y,_=points[loop.vertex_index]
            uv.data[loop.index].uv=((x-l)/(r-l),1-(y-t)/(b-t))
        data.update()
        obj=bpy.data.objects.new(name,data)
        self.group.objects.link(obj);obj.location=self.base
        self.objects.append(obj)
    def box(self,name,top,foot,z):
        up=[(*p,z) for p in top]; low=[(*p,0) for p in foot]
        self.part(name,[up,low[::-1]]+[[up[i],up[(i+1)%len(up)],low[(i+1)%len(up)],low[i]] for i in range(len(up))])
    def building(self,name,eaves,feet,ridge,base,wall,crest):
        hi=[(*p,base+wall) for p in eaves]; lo=[(*p,base) for p in feet]
        a,b,c,d=hi
        u,v=[(*p,base+crest) for p in ridge]
        self.part(name+"_walls", [[hi[i],hi[(i+1)%4],lo[(i+1)%4],lo[i]] for i in range(4)]+[lo[::-1]])
        self.part(name+"_roof",[[a,b,v,u],[b,c,v],[c,d,u,v],[d,a,u]])
    def beam(self,name,a,b,r):
        va,vb=xyz(a),xyz(b);axis=(vb-va).normalized()
        ref=Vector((1,0,0)) if abs(axis.x)<.8 else Vector((0,1,0))
        u=axis.cross(ref).normalized()*r;v=axis.cross(u).normalized()*r
        def pixel(q):
            return (511+SCALE*q.x,479+SCALE*(-q.y/DEPTH-q.z*LIFT),q.z)
        rings=[[pixel(end+u*cos(i*pi*.5+.785)+v*sin(i*pi*.5+.785)) for i in range(4)] for end in [va,vb]]
        self.part(name,[rings[0],rings[1][::-1]]+[[rings[0][i],rings[0][(i+1)%4],rings[1][(i+1)%4],rings[1][i]] for i in range(4)])
    def export(self):
        import bmesh
        for obj in self.objects:
            bm=bmesh.new()
            bm.from_mesh(obj.data)
            bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if len(f.verts)>4])
            bm.to_mesh(obj.data)
            bm.free()
        bpy.ops.object.select_all(action="DESELECT")
        for obj in self.objects:
            obj.location=(0,0,0);obj.select_set(True)
        folder=ROOT/"art_source/canyon/studies" if self.key in ("inn","cottage") else OUT
        folder.mkdir(exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=str(folder/(self.key+".glb")),export_format="GLB",use_selection=True,export_tangents=True,export_yup=True)
        for obj in self.objects: obj.location=self.base
        assets.append((self.key,self.base.copy()))

assets=[]
land=Landmark("valley",(511,479))
river=[(0,648,82),(122,681,63),(220,800,42),(325,793,59),(430,866,68),(525,947,57),(620,891,85),(720,951,150),(826,1065,167),(991,1372,273)]
def cross(y):
    for a,b in zip(river,river[1:]):
        if y<=b[0]:
            t=max(0,(y-a[0])/(b[0]-a[0]))
            return (a[1]*(1-t)+b[1]*t,a[2]*(1-t)+b[2]*t)
    return river[-1][1:]
def elevation(x,y):
    cx,width=cross(y)
    t=max(0,min(1,(abs(x-cx)/width-.68)/.57));t=t*t*(3-2*t)
    bank=-.48+8.0*max(0,min(1,(325-y)/110))
    water=-7.2+9.2*max(0,min(1,(330-y)/240))
    ridge=11*exp(-((x-165)/260)**2-((y-65)/140)**2)+8*exp(-((x-1470)/170)**2-((y-66)/165)**2)
    height=water*(1-t)+(bank+ridge)*t
    # The lower-right tidal basin is connected to the river downstream.
    if x>1160 and y>557:
        shore=610+24*sin(x*.012)
        ramp=max(0,min(1,(y-shore)/48))*max(0,min(1,(x-1160)/85))
        height=height*(1-ramp)-8.5*ramp
    return height
nx,ny=109,69
coords=[[(1585*x/nx,992*y/ny,elevation(1585*x/nx,992*y/ny)) for x in range(nx+1)] for y in range(ny+1)]
land.part("Cliffs_banks_and_riverbed",[[coords[y][x],coords[y][x+1],coords[y+1][x+1],coords[y+1][x]] for y in range(ny) for x in range(nx)])
land.export()

def painted_shell(landmark, name, border, creases):
    """Triangulated elevations under the approved painted outline. Every
    ridge, chimney and lower eave is a constrained 3D edge with matching UV."""
    from mathutils.geometry import delaunay_2d_cdt
    points=[]; lookup={}
    def index(p):
        key=p[:2]
        if key not in lookup:
            lookup[key]=len(points)
            points.append(p)
        return lookup[key]
    outside=[index(p) for p in border]
    edges=[]
    for line in creases:
        ids=[index(p) for p in line]
        edges.extend(zip(ids,ids[1:]))
    verts,_,faces,source,_,_=delaunay_2d_cdt(
        [Vector(p[:2]) for p in points],edges,[outside],1,1e-5)
    samples=[]
    for i,v in enumerate(verts):
        candidates=source[i]
        if candidates: h=points[candidates[0]][2]
        else:
            nearest=sorted(points,key=lambda p:(p[0]-v.x)**2+(p[1]-v.y)**2)[:2]
            h=sum(p[2] for p in nearest)/len(nearest)
        samples.append((v.x,v.y,h))
    landmark.part(name,[[samples[i] for i in face] for face in faces])

hut=Landmark("cottage",(558,569))
painted_shell(hut,"Swept_gable_and_entry",[
    (496,528,4.8),(507,519,5.8),(520,504,7.2),(530,489,8.3),(530,481,10.2),
    (543,477,10.4),(555,480,10.3),(554,487,9.4),(562,491,8.1),(579,487,8.5),
    (597,480,9.5),(597,489,8.6),(602,502,7.7),(611,517,6.0),(621,526,5.),
    (629,532,4.5),(627,535,4.4),(619,533,4.4),(619,570,.3),(624,573,.2),
    (617,582,.15),(609,585,.1),(606,591,.1),(586,595,.1),(565,589,.1),
    (552,581,.15),(543,581,.1),(529,576,.1),(514,570,.1),(505,562,.15),(505,529,4.6)
],[
    [(496,528,4.8),(511,518,6.0),(521,507,7.3),(531,521,6.3),(544,541,4.4),(552,540,4.4),(570,545,4.25),(586,527,6.),(600,505,7.9),(614,522,5.8),(629,532,4.5)],
    [(521,507,7.3),(536,490,8.5),(562,491,8.1),(578,497,8.),(600,505,7.9)],
    [(531,481,10.),(544,485,10.),(554,481,10.2)],[(544,485,10.),(544,518,7.2),(552,514,7.4),(554,487,9.4)],
    [(544,541,4.4),(544,571,.5)],[(570,545,4.25),(570,582,.45)],[(600,505,7.9),(600,539,4.5)],
    [(570,550,3.9),(593,543,4.1),(618,538,4.1)]
])
hut.export()

inn=Landmark("inn",(561,592))
painted_shell(inn,"Great_hall_cross_gables_and_terrace",[
    (245,435,5),(270,419,6),(270,398,7),(293,383,7),(288,375,8.2),
    (337,363,8.4),(384,345,10),(406,320,13.8),(406,309,14.4),(424,308,14.4),
    (456,320,13.6),(478,322,13.7),(483,316,15.8),(495,314,16.0),(498,322,15.2),
    (513,323,13.5),(546,316,14.2),(573,304,15.2),(603,284,17),(605,272,17.7),
    (621,269,18.0),(635,275,17.5),(627,286,16.7),(631,323,14.3),(645,353,12),
    (658,366,10.7),(640,370,10.3),(640,384,9),(671,397,7.8),(706,389,8.7),
    (711,383,9.6),(716,389,9),(757,402,8.1),(759,391,8.9),(766,391,8.9),
    (763,405,8),(760,440,4.3),(789,443,4),(827,454,3.4),(850,478,.55),
    (849,508,.35),(836,535,.36),(805,557,.37),(771,576,.38),(712,596,.36),
    (660,614,.3),(644,624,.28),(561,628,.12),(519,625,.15),(486,618,.2),
    (448,606,.18),(415,600,.22),(404,580,.5),(378,572,.32),(350,567,.3),
    (333,553,.3),(332,539,1.5),(276,517,.45),(253,500,.3),(246,477,.5)
],[
    [(406,309,14.4),(430,314,14.1),(459,324,13.6),(496,328,13.3),(533,322,13.8),(568,309,15.1),(602,288,16.7),(621,269,18.)],
    [(406,309,14.4),(429,347,11.7),(440,381,10.),(430,417,7.9),(472,441,7.2),(502,424,8.1),(533,400,9.0),(575,383,10.2),(616,372,11.),(658,366,10.7)],
    [(430,417,7.9),(472,441,7.2),(493,452,6.8),(515,460,7.1),(551,437,8.7),(583,402,10.6),(611,389,11.6),(637,419,9.4),(663,435,7.9),(695,446,7.3)],
    [(495,334,15.),(496,414,10.2),(478,419,10.),(465,408,10.4),(466,337,15.1),(495,334,15.)],
    [(411,526,4.8),(442,516,5.4),(476,507,5.8),(512,497,6.6),(565,479,8.1),(597,489,7.3),(634,505,6.),(665,509,5.9),(699,487,7.)],
    [(411,526,4.8),(437,552,4.4),(475,542,5.),(515,522,6.0),(566,510,6.8),(600,524,5.8),(634,530,5.2),(665,509,5.9)],
    [(437,552,4.4),(437,601,.4)],[(515,522,6.0),(513,611,.4)],[(634,530,5.2),(636,612,.4)],
    [(245,435,5),(288,420,6.3),(358,391,7.4),(410,379,8.5)],
    [(333,539,1.5),(367,525,1.7),(416,508,2.4)],[(640,437,7.8),(709,424,7.0),(760,408,7.9)]
])
inn.export()

shed=Landmark("warehouse",(325,254))
shed.building("Supply_warehouse",[(202,183),(296,146),(429,165),(313,201)],[(214,257),(298,219),(422,246),(317,270)],[(246,152),(357,129)],6.8,6.5,9.1)
shed.building("Side_shed",[(191,234),(214,223),(250,232),(220,244)],[(194,265),(218,250),(246,260),(219,272)],[(202,224),(235,215)],6.8,3.1,4.5)
shed.export()

cr=Landmark("crane",(512,209))
for j,(a,b) in enumerate([((469,207,6.3),(478,110,17)),((526,205,6.3),(518,107,17)),((484,203,6.3),(496,109,17)),((475,172,11),(515,120,16)),((480,116,16),(522,170,11)),((510,104,18),(621,121,16)),((519,165,11),(618,123,16)),((620,126,16),(615,166,10))]):
    cr.beam("Hoist_beam_%02d"%j,a,b,.30 if j!=7 else .11)
cr.box("Lookout",[(466,96),(489,84),(527,95),(498,110)],[(471,120),(490,109),(523,116),(499,131)],18)
cr.part("Crane_roof",[[(463,93,18),(496,72,20),(532,90,18),(502,104,18)]])
cr.box("Freight_cradle",[(593,162),(611,151),(637,163),(619,176)],[(593,190),(612,183),(638,186),(620,195)],12)
cr.export()

shop=Landmark("supply",(1044,372))
# Dome courses are circular in plan, with their image projection matched to the painted shop.
rings=[]
for rx,ry,cy,z in [(71,24,365,3),(74,23,305,10),(55,18,279,13),(27,8,265,15),(5,2,258,16)]:
    rings.append([(1038+rx*cos(i*pi/10),cy+ry*sin(i*pi/10),z) for i in range(20)])
shop.part("Arcade_and_copper_dome",[[a[i],a[(i+1)%20],b[(i+1)%20],b[i]] for a,b in zip(rings,rings[1:]) for i in range(20)]+[rings[-1]])
shop.box("Cupola",[(1035,240),(1047,237),(1053,243),(1041,247)],[(1035,260),(1047,258),(1053,262),(1040,266)],17.8)
shop.export()
work=Landmark("workshop",(1264,268))
work.building("Glass_atelier",[(1161,227),(1241,164),(1362,221),(1271,245)],[(1176,272),(1243,232),(1353,261),(1272,288)],[(1177,124),(1261,163)],5,5.3,12)
work.box("Kiln_flue",[(1290,132),(1305,133),(1309,142),(1294,143)],[(1290,182),(1303,182),(1308,187),(1293,188)],19)
work.export()
gal=Landmark("gallery",(1390,413))
gal.building("Exhibition_hall",[(1271,355),(1389,304),(1523,348),(1409,381)],[(1278,415),(1394,376),(1511,407),(1407,433)],[(1329,333),(1487,265)],2,7.1,12)
gal.export()

def bridge(key,points,half,deck_height,arch,r):
    obj=Landmark(key,points[len(points)//2]); near=[];far=[]
    for i,(x,y) in enumerate(points):
        h=deck_height+sin(pi*i/(len(points)-1))*arch
        near.append((x,y+half,h));far.append((x,y-half,h))
    obj.part("Arched_deck",[[near[i],far[i],far[i+1],near[i+1]] for i in range(len(points)-1)])
    for side,edge in enumerate([near,far]):
        under=[(x,y+5,h-1.25) for x,y,h in edge]
        obj.part("Outer_girder_%d"%side,[[a,b,d,c] for a,b,c,d in zip(edge,edge[1:],under,under[1:])])
        for i,(x,y,h) in enumerate(edge):
            top=(x,y-9,h+1.25)
            obj.beam("Post_%d_%d"%(side,i),(x,y,h),top,r)
            if i:
                xx,yy,hh=edge[i-1]
                obj.beam("Rail_%d_%d"%(side,i),(xx,yy-9,hh+1.25),top,r*.80)
    for i in [1,len(points)-2]:
        x,y,h=near[i]
        obj.beam("Pier_%d"%i,(x,y,h),(x,y+34,h-7.7),r*3.0)
    if key=="timber_bridge":
        obj.part("River_arch_west", [[(694,733,1),(765,699,2),(763,736,-5),(735,759,-7),(708,767,-7)]])
        obj.part("Main_masonry_pier", [[(799,707,2.4),(849,686,3.0),(847,737,-6.5),(817,771,-7.5),(801,757,-7.0)]])
        obj.part("River_arch_east", [[(1002,665,2.4),(1079,665,.8),(1083,720,-6),(1050,742,-7),(1040,698,-2)]])
        for n,(x,y) in enumerate([(761,609),(820,650),(1007,553),(1091,608)]):
            obj.beam("Banner_mast_%d"%n,(x,y+54,1.7),(x,y,8.4),.22)
            obj.part("Ochre_pennant_%d"%n,[[(x+2,y+1,8.4),(x+22,y-2,8.5),(x+18,y+37,4.1),(x+8,y+31,4.8)]])
    obj.export()
bridge("stone_bridge",[(738,198),(769,189),(799,177),(824,177),(851,184),(882,194)],4.5,6.2,1.65,.45)
bridge("timber_bridge",[(678,716),(725,694),(773,674),(826,649),(885,634),(937,628),(994,629),(1041,637),(1092,653)],16.5,.35,3.10,.50)
dock=Landmark("dock",(1390,756))
dock.part("Pontoon",[[(1206,776,-4.1),(1378,706,-4.1),(1584,782,-4.1),(1584,852,-4.1),(1380,756,-4.1),(1222,795,-4.1)]])
dock.part("South_walkway", [[(1371,706,-3.9),(1441,686,-3.9),(1584,742,-3.9),(1584,819,-3.9),(1464,785,-3.9)]])
for i,(x,y) in enumerate([(1216,789),(1250,780),(1359,748),(1403,749),(1489,805),(1547,825)]):
    dock.beam("Mooring_post_%d"%i,(x,y-10,-3),(x,y+29,-9),.35)
dock.building("Wharf_shelter",[(1412,665),(1472,645),(1570,681),(1494,704)],[(1418,738),(1472,714),(1566,759),(1495,775)],[(1445,640),(1512,646)],-4,6.5,8.3)
dock.export()

def persist():
    bpy.ops.file.pack_all()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art_source/canyon/河港建筑组.blend"))
    landmarks=[a for a in assets if a[0] not in ("inn","cottage")]
    scene=['[gd_scene load_steps=%d format=3]'%(len(landmarks)+2),'']
    for key,_ in landmarks:
        scene.append('[ext_resource type="PackedScene" path="res://assets/canyon_world/%s.glb" id="%s"]'%(key,key))
    scene+=['','[ext_resource type="Script" path="res://scripts/visuals/painted_canyon.gd" id="paint"]','','[node name="Canyon" type="Node3D"]','script = ExtResource("paint")']
    for key,v in landmarks:
        scene+=['','[node name="%s" parent="." instance=ExtResource("%s")]'%(key,key),'position = Vector3(%.6f, %.6f, %.6f)'%(v.x,v.z,-v.y)]
    (ROOT/"scenes/canyon/geography.tscn").write_text('\n'.join(scene)+'\n')
persist()
