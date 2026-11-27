"""Author the west doorway and its porch at the scale of the Godot entry camera.

Local -Y faces the street, Z is up. The moving leaves keep their original
hinge pivots at +/-1 m. Run with Blender in background after baking the atlas.
"""
import hashlib
import json
import math
import struct
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/tavern"
TEXTURES = ROOT / "assets/materials"
WOOD, STONE, BRASS, IRON, HONEY, TEAL = range(6)
TAU = math.tau


def atlas_material(name, glowing=False):
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, link = mat.node_tree.nodes, mat.node_tree.links.new
    bs = nodes.get("Principled BSDF")
    def image_node(filename, srgb=False):
        node = nodes.new("ShaderNodeTexImage")
        node.image = bpy.data.images.load(str(TEXTURES/filename),check_existing=True)
        node.image.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
        return node
    paint = image_node("gate-paint.jpg",True)
    link(paint.outputs["Color"],bs.inputs["Base Color"])
    normal = nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = .58
    link(image_node("gate-relief.png").outputs["Color"],normal.inputs["Color"])
    link(normal.outputs["Normal"],bs.inputs["Normal"])
    channels = nodes.new("ShaderNodeSeparateColor")
    link(image_node("gate-orm.png").outputs["Color"],channels.inputs[0])
    link(channels.outputs["Green"],bs.inputs["Roughness"])
    link(channels.outputs["Blue"],bs.inputs["Metallic"])
    if glowing:
        link(paint.outputs["Color"],bs.inputs["Emission Color"])
        bs.inputs["Emission Strength"].default_value = .47
    return mat


def shingle_material():
    mat = bpy.data.materials.new("Entrance_roof_tiles")
    mat.use_nodes = True
    nodes, link = mat.node_tree.nodes, mat.node_tree.links.new
    bs = nodes.get("Principled BSDF")
    bs.inputs["Roughness"].default_value = .78
    diffuse = nodes.new("ShaderNodeTexImage")
    diffuse.image = bpy.data.images.load(str(TEXTURES/"inn-shingles.jpg"),check_existing=True)
    link(diffuse.outputs[0],bs.inputs["Base Color"])
    normal = nodes.new("ShaderNodeTexImage")
    normal.image = bpy.data.images.load(str(TEXTURES/"inn-shingles-normal.png"),check_existing=True)
    normal.image.colorspace_settings.name = "Non-Color"
    nm = nodes.new("ShaderNodeNormalMap")
    nm.inputs["Strength"].default_value=.38
    link(normal.outputs[0],nm.inputs[1])
    link(nm.outputs[0],bs.inputs["Normal"])
    return mat


class Kit:
    def __init__(self,name):
        self.collection = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(self.collection)
        self.solid = atlas_material("Gate_surface")
        self.glass = atlas_material("Gate_glass",True)
        self.parts = []

    def pivot(self,name,position):
        obj = bpy.data.objects.new(name,None)
        self.collection.objects.link(obj)
        obj.location = position
        return obj

    def mesh(self,name,verts,faces,tile,bevel=0.,parent=None,rounded=False,grain=None,mat=None):
        data=bpy.data.meshes.new(name)
        data.from_pydata(verts,[],faces)
        data.update()
        obj=bpy.data.objects.new(name,data)
        self.collection.objects.link(obj)
        obj.parent=parent
        data.materials.append(mat or (self.glass if tile in (HONEY,TEAL) else self.solid))
        # Assign the UV island before bevelling; Blender interpolates the little
        # return faces. Every plank samples a different strip of the same oak.
        uv=data.uv_layers.new(name="Joinery")
        seed=int.from_bytes(hashlib.sha256(name.encode()).digest()[:4],"little")
        pmin=[min(v[i] for v in verts) for i in range(3)]
        pmax=[max(v[i] for v in verts) for i in range(3)]
        for poly in data.polygons:
            n=poly.normal
            if abs(n.z)>.77: axes=(0,1)
            elif abs(n.x)>abs(n.y): axes=(1,2)
            else: axes=(0,2)
            if grain is not None and grain in axes: axes=(axes[1-axes.index(grain)],grain)
            dim=[pmax[k]-pmin[k] for k in axes]
            lengths=(1.05,2.40) if tile==WOOD else (1.45,1.45)
            span=[max(.12,min(.94,d/scale)) for d,scale in zip(dim,lengths)]
            start=[.018+((seed>>shift)&255)/255*(.964-sz) for shift,sz in zip([0,8],span)]
            for li in poly.loop_indices:
                v=data.vertices[data.loops[li].vertex_index].co
                u,t=[st+sz*(v[k]-pmin[k])/max(.0001,d) for st,sz,k,d in zip(start,span,axes,dim)]
                uv.data[li].uv=((tile%3+u)/3,(1-tile//3+t)/2) if mat is None else (v.x*.95,v.y*.88)
        bm=bmesh.new()
        bm.from_mesh(data)
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces[:])
        bm.to_mesh(data)
        bm.free()
        if bevel:
            mod=obj.modifiers.new("Edge light","BEVEL")
            mod.width=bevel
            mod.segments=3 if bevel >= .02 else (2 if bevel >= .009 else 1)
            mod.limit_method="ANGLE"
            mod.angle_limit=math.radians(26)
            mod.harden_normals=True
        if rounded or bevel:
            for face in data.polygons: face.use_smooth=True
            if bevel:
                weighted=obj.modifiers.new("Face weighted normals","WEIGHTED_NORMAL")
                weighted.keep_sharp=True
                weighted.weight=60
        self.parts.append(obj)
        return obj

    def silhouette(self,name,points,front,back,tile,bevel=.008,parent=None,grain=None):
        n=len(points)
        verts=[(x,y,z) for y in (front,back) for x,z in points]
        faces=[tuple(range(n)),tuple(reversed(range(n,2*n)))]
        faces.extend((i,i+n,(i+1)%n+n,(i+1)%n) for i in range(n))
        return self.mesh(name,verts,faces,tile,bevel,parent,grain=grain)

    def box(self,name,x0,x1,z0,z1,front,back,tile,bevel=.008,parent=None,grain=None):
        return self.silhouette(name,[(x0,z0),(x1,z0),(x1,z1),(x0,z1)],front,back,tile,bevel,parent,grain)

    def line(self,name,a,b,width,depth,tile,bevel=.009,parent=None):
        a,b=Vector(a),Vector(b)
        v=b-a
        obj=self.box(name,-width/2,width/2,-v.length/2,v.length/2,-depth/2,depth/2,tile,bevel,parent,2)
        obj.location=(a+b)*.5
        obj.rotation_mode="QUATERNION"
        obj.rotation_quaternion=v.to_track_quat('Z','Y')
        return obj

    def horizontal(self,name,points,z0,z1,tile,bevel=.015):
        n=len(points)
        verts=[(x,y,z) for z in [z0,z1] for x,y in points]
        faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
        faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
        return self.mesh(name,verts,faces,tile,bevel)

    def lathe(self,name,at,profile,tile,sides=24,parent=None):
        verts=[(r*math.cos(i*TAU/sides),r*math.sin(i*TAU/sides),h) for r,h in profile for i in range(sides)]
        faces=[(j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i) for j in range(len(profile)-1) for i in range(sides)]
        faces += [tuple(reversed(range(sides))),tuple(range(len(verts)-sides,len(verts)))]
        obj=self.mesh(name,verts,faces,tile,parent=parent,rounded=True)
        obj.location=at
        return obj

    def stud(self,name,x,y,z,r,tile,parent=None):
        obj=self.lathe(name,(x,y,z),[(r,0),(r,.006),(r*.88,r*.23),(r*.5,r*.40),(r*.16,r*.45)],tile,12,parent)
        obj.rotation_euler.x=math.pi/2
        return obj

    def arch(self,name,cx,cz,r0,r1,lo,hi,front,back,tile,parent=None,bevel=.003):
        steps=max(2,math.ceil((hi-lo)*19))
        angles=[lo+(hi-lo)*i/steps for i in range(steps+1)]
        pts=[(cx+r1*math.cos(t),cz+r1*math.sin(t)) for t in angles]
        if r0==0: pts.append((cx,cz))
        else: pts.extend((cx+r0*math.cos(t),cz+r0*math.sin(t)) for t in reversed(angles))
        return self.silhouette(name,pts,front,back,tile,bevel,parent)

    def ring(self,name,center,major,minor,tile,parent):
        verts=[]; faces=[]
        for i in range(40):
            a=i*TAU/40
            for j in range(8):
                b=j*TAU/8
                rad=major+minor*math.cos(b)
                verts.append((rad*math.cos(a),minor*math.sin(b),rad*math.sin(a)))
                faces.append((i*8+j,i*8+(j+1)%8,((i+1)%40)*8+(j+1)%8,((i+1)%40)*8+j))
        obj=self.mesh(name,verts,faces,tile,parent=parent,rounded=True)
        obj.location=center

    def finish(self):
        # Evaluate bevels/weighted normals while each component still has its own
        # local grain direction. Join by hinge afterward to keep surface count low.
        bpy.context.view_layer.update()
        graph=bpy.context.evaluated_depsgraph_get()
        for obj in self.parts:
            if obj.modifiers:
                result=bpy.data.meshes.new_from_object(obj.evaluated_get(graph),depsgraph=graph,preserve_all_data_layers=True)
                obj.modifiers.clear()
                obj.data=result
        groups={}
        for obj in self.parts: groups.setdefault(obj.parent,[]).append(obj)
        for parent,objects in groups.items():
            bpy.ops.object.select_all(action="DESELECT")
            for obj in objects: obj.select_set(True)
            bpy.context.view_layer.objects.active=objects[0]
            bpy.ops.object.join()
            joined=objects[0]
            joined.name=parent.name+"_leaf" if parent else self.collection.name+"_frame"
            # The first local part is not always centred at the asset origin.
            # Keep joined geometry in parent space for clean pivots/master assembly.
            transform=joined.matrix_basis.copy()
            joined.data.transform(transform)
            joined.location=(0,0,0)
            joined.rotation_mode="XYZ"
            joined.rotation_euler=(0,0,0)
            joined.scale=(1,1,1)
            tri=joined.modifiers.new("Export triangulation","TRIANGULATE")
            tri.keep_custom_normals=True
        return self.collection


def faceted_rectangle(x0,x1,z0,z1,cut):
    return [(x0+cut,z0),(x1-cut,z0),(x1,z0+cut),(x1,z1-cut),
            (x1-cut,z1),(x0+cut,z1),(x0,z1-cut),(x0,z0+cut)]


def build_door():
    k=Kit("Hearth_door")
    spring=2.00
    for side in (-1,1):
        hand="L" if side<0 else "R"
        pivot=k.pivot("LeftHinge" if side<0 else "RightHinge",(side,0,0))
        def x(t): return -side*t
        def plank(name,a,b,z0,z1,front,back,tile,bevel=.008):
            return k.box(hand+name,*sorted((x(a),x(b))),z0,z1,front,back,tile,bevel,pivot,2)
        for i in range(5):
            plank(" stave %d"%i,.005+i*.198,.200+i*.198,.033,spring+.006,-.055,.060,WOOD,.009)
        for a,b in [(.004,.101),(.899,.995)]:
            plank(" stile",a,b,.033,spring+.02,-.095,.073,WOOD,.013)
        for i,(base,top) in enumerate([(.20,.77),(.94,1.77)]):
            xa,xb=sorted([x(.139),x(.862)])
            k.silhouette(hand+" panel rebate %d"%i,faceted_rectangle(xa,xb,base,top,.046),-.077,-.052,WOOD,.008,pivot)
            k.silhouette(hand+" raised field %d"%i,faceted_rectangle(xa+.018,xb-.018,base+.020,top-.020,.041),-.103,-.066,WOOD,.018,pivot,2)
        for z in [.145,.855,1.866]:
            plank(" cross rail",.06,.938,z-.054,z+.055,-.105,-.052,WOOD,.012)
        # Fanlight is split down the actual moving centre seam. Lead traces end
        # at that seam on each leaf, including the central amber roundel.
        cx=-side
        lo,hi=(math.pi/2,math.pi) if side<0 else (0,math.pi/2)
        for j in range(4):
            a,b=lo+(hi-lo)*j/4,lo+(hi-lo)*(j+1)/4
            for n,(r0,r1) in enumerate([(.009,.252),(.263,.641),(.653,.888)]):
                glass=HONEY if n==0 or (n==2 and j in (0,3)) else TEAL
                k.arch(hand+" light %d.%d"%(j,n),cx,spring,r0,r1,a+.004,b-.004,-.025,.005,glass,pivot,0)
            end=(cx+.90*math.cos(a),-.045,spring+.90*math.sin(a))
            k.line(hand+" radial came %d"%j,(cx,-.045,spring),end,.022,.029,BRASS,.003,pivot)
        for r in [.254,.646,.902]:
            k.arch(hand+" curved came",cx,spring,r-.011,r+.011,lo,hi,-.064,.030,BRASS,pivot,.003)
        k.arch(hand+" arched oak leaf",cx,spring,.906,.985,lo,hi,-.099,.062,WOOD,pivot,.009)
        plank(" meeting bead",.982,.997,spring,spring+.969,-.073,.037,BRASS,.003)
        plank(" fanlight sill",.01,.988,1.968,2.022,-.10,.07,WOOD,.008)
        for j,z in enumerate([.45,1.65]):
            outline=[(x(t),z+h) for t,h in [(0,-.062),(.22,-.056),(.35,-.027),(.56,-.023),(.635,0),(.56,.023),(.35,.027),(.22,.056),(0,.062)]]
            k.silhouette(hand+" forged strap %d"%j,outline,-.134,-.098,IRON,.008,pivot)
            k.lathe(hand+" hinge barrel",(.0,-.10,z),[(.029,-.073),(.042,-.063),(.042,.064),(.032,.075)],BRASS,20,pivot)
            for t in [.10,.29,.52]:
                k.stud(hand+" strap rivet",x(t),-.136,z,.022,BRASS,pivot)
        px=x(.735)
        plate=[(px,1.38),(px+.072,1.30),(px+.066,1.16),(px,1.09),(px-.066,1.16),(px-.072,1.30)]
        k.silhouette(hand+" handle escutcheon",plate,-.137,-.10,BRASS,.009,pivot)
        k.stud(hand+" handle rose",px,-.148,1.28,.049,IRON,pivot)
        k.ring(hand+" cast pull",(px,-.183,1.196),.094,.019,BRASS,pivot)
        for z in [1.34,1.135]: k.stud(hand+" rose pin",px,-.14,z,.012,IRON,pivot)
        xa,xb=sorted([1.002*side,1.203*side])
        k.box(hand+" jamb",xa,xb,.02,spring,-.118,.15,WOOD,.017,grain=2)
        for a,b,h0,h1,tile in [(1.001,1.218,.025,.30,STONE),(1.00,1.224,.29,.36,STONE),(1.001,1.219,1.91,2.025,BRASS)]:
            k.box(hand+" impost",*sorted((a*side,b*side)),h0,h1,-.153,.144,tile,.017)
        k.box(hand+" jamb fillet",*sorted([1.035*side,1.058*side]),.36,1.927,-.139,-.115,BRASS,.004)
    # Unbroken inner moulding with a separate keystone and sandstone voussoirs.
    for k0,k1,front,tile in [(1.002,1.044,-.15,WOOD),(1.045,1.069,-.165,BRASS),(1.070,1.132,-.139,WOOD)]:
        k.arch("Vault moulding",0,spring,k0,k1,0,math.pi,front,.14,tile,bevel=.005)
    for i in range(15):
        a,b=(i+.014)*math.pi/15,(i+.986)*math.pi/15
        r=1.212 if i!=7 else 1.26
        k.arch("Arch block %02d"%i,0,spring,1.132,r,a,b,-.13-(.035 if i==7 else 0),.15,STONE,bevel=.009)
    for i in range(14):
        a,b=[j*math.pi/14 for j in (i,i+1)]
        xa,xb=1.209*math.cos(a),1.209*math.cos(b)
        poly=[(xa,spring+1.20*math.sin(a)),(xa,3.98),(xb,3.98),(xb,spring+1.20*math.sin(b))]
        k.silhouette("Spandrel %02d"%i,poly,-.043,.13,STONE,.008)
    return k.finish()


def build_porch():
    k=Kit("Entrance_porch")
    # Four tread courses. The rounded nosing projects beyond each fitted riser.
    courses=json.loads((ROOT/"data/architecture/entrance_walk.json").read_text(encoding="utf-8"))["treads"]
    for i,(depth,span,z) in enumerate(courses):
        half=span*.5
        foot=[(-half,-depth+.24),(-half+.19,-depth+.035),(-half+.37,-depth),(half-.28,-depth),(half-.12,-depth+.05),(half,-depth+.23),(half,.17),(-half,.17)]
        k.horizontal("Threshold course %d"%i,foot,-.57 if not i else courses[i-1][2]-.04,z-.047,STONE,.027)
        # Separate tread stones only on the portion of each level that is seen.
        breaks=[-half,-.57,.54,half] if i%2==0 else [-half,-.24,.77,half]
        for j,(x0,x1) in enumerate(zip(breaks,breaks[1:])):
            x0+=.008; x1-=.008
            left_cut=.24 if j==0 else .027
            right_cut=.23 if j==len(breaks)-2 else .033
            rear=-courses[i+1][0]+.13 if i+1<len(courses) else .17
            shape=[(x0,-depth+left_cut),(x0+left_cut,-depth-.025),(x1-right_cut,-depth-.025),(x1,-depth+right_cut),(x1,rear),(x0,rear)]
            k.horizontal("Dressed tread %d.%d"%(i,j),shape,z-.086,z,STONE,.024)
    for side in (-1,1):
        x=1.25*side
        tag="West" if side<0 else "East"
        for z0,z1,r,tile in [(-.04,.28,.215,STONE),(.265,.355,.202,STONE),(.346,.425,.146,IRON),(.411,2.54,.124,WOOD),(2.51,2.62,.148,BRASS),(2.61,2.81,.181,WOOD)]:
            k.box(tag+" porch pier",x-r,x+r,z0,z1,-1.56-r,-1.56+r,tile,.019,grain=2)
        # A continuous hewn bracket with an ogee cut in its lower edge.
        bracket=[(0,1.92),(.095,2.02),(.18,2.24),(.26,2.37),(.38,2.46),(.57,2.53),(.76,2.59),(.79,2.72),(0,2.72)]
        k.silhouette(tag+" curved corbel",[(x-side*d,z) for d,z in bracket],-1.64,-1.48,WOOD,.018)
        k.line(tag+" wall plate",(x,-1.65,2.73),(x,.55,3.42),.18,.19,WOOD,.017)
        for z in [.39,2.565]: k.stud(tag+" peg",x,-1.715,z,.026,BRASS)
        # The bulb occupies the same anchor used by its OmniLight3D in Godot.
        at=(x,-1.8,2.095)
        k.lathe(tag+" amber glass",at,[(.049,-.145),(.096,-.115),(.119,-.063),(.126,-.006),(.122,.074),(.105,.122),(.070,.149)],HONEY,36)
        k.lathe(tag+" lantern plinth",at,[(.032,-.203),(.045,-.184),(.043,-.17),(.085,-.153),(.106,-.135),(.094,-.115)],BRASS)
        k.lathe(tag+" lantern crown",at,[(.109,.101),(.133,.115),(.135,.133),(.124,.144),(.108,.159),(.082,.178),(.054,.211),(.037,.219)],IRON,36)
        for z,r in [(-.113,.101),(.073,.125),(.128,.134)]:
            k.lathe(tag+" rolled lip",at,[(r-.004,z-.008),(r+.003,z-.006),(r+.005,z),(r+.002,z+.006),(r-.004,z+.009)],BRASS)
        for i in range(6):
            angle=TAU*i/6+.13
            for z0,z1,r0,r1 in [(-.116,-.028,.099,.127),(-.028,.112,.127,.117)]:
                a=(x+r0*math.cos(angle),-1.8+r0*math.sin(angle),at[2]+z0)
                b=(x+r1*math.cos(angle),-1.8+r1*math.sin(angle),at[2]+z1)
                k.line(tag+" lantern mullion",a,b,.012,.013,IRON,.002)
        k.line(tag+" hanging stem",(x,-1.8,2.31),(x,-1.8,2.53),.024,.024,IRON,.004)
        k.line(tag+" hanging arm",(x,-1.83,2.52),(x,-1.565,2.61),.037,.036,BRASS,.006)
    header=[(-1.41,2.60),(-.96,2.592),(-.45,2.568),(0,2.49),(.45,2.568),(.96,2.592),(1.41,2.60),(1.41,2.84),(-1.41,2.84)]
    k.silhouette("Threshold lintel",header,-1.705,-1.43,WOOD,.027,grain=0)
    for side in (-1,1):
        k.line("Lintel bronze pinstripe",(.125*side,-1.712,2.585),(1.24*side,-1.712,2.675),.016,.017,BRASS,.003)
        k.stud("Lintel join pin",side*1.19,-1.723,2.758,.034,BRASS)
    k.silhouette("Enamel lozenge mount",[(0,2.86),(.13,2.70),(0,2.52),(-.13,2.70)],-.015-1.713,-1.683,BRASS,.012)
    k.silhouette("Glazed harbour seal",[(0,2.814),(.089,2.70),(0,2.561),(-.089,2.70)],-1.741,-1.715,TEAL,.012)
    roof=shingle_material()
    for side in (-1,1):
        path=[(0,3.48),(.21,3.36),(.49,3.17),(.80,2.965),(1.12,2.79),(1.39,2.69),(1.61,2.67)]
        # Closed, curved roof plates with an actual soffit and end grain.
        upper=[(side*x,z) for x,z in path]
        outline=upper+[(x,z-.113) for x,z in reversed(upper)]
        vertices=[(x,y,z+lift) for y,lift in [(-1.91,0),(.61,.69)] for x,z in outline]
        n=len(outline)
        # Separate bright clay from the wood underneath. The front bargeboard
        # covers the join and is visible from the eye-height camera.
        faces=[(i,(i+1)%n,n+(i+1)%n,n+i) for i in range(n)]
        k.mesh("Canopy clay",vertices,faces[:len(path)-1],WOOD,mat=roof)
        k.mesh("Canopy soffit",vertices,faces[len(path)-1:]+[tuple(range(n)),tuple(reversed(range(n,2*n)))],WOOD,grain=0)
        trim_pts=upper+[(x,z-.105) for x,z in reversed(upper)]
        k.silhouette("Swept bargeboard",trim_pts,-1.963,-1.87,WOOD,.015,grain=0)
        ribbon=[(x,z-.023) for x,z in upper]+[(x,z-.052) for x,z in reversed(upper)]
        k.silhouette("Rolled eave bead",ribbon,-1.978,-1.956,BRASS,.005,grain=0)
        for idx,(x,z) in enumerate(upper[1:-1:2]):
            k.stud("Copper eave nail %d"%idx,x,-1.968,z-.08,.014,BRASS)
    k.line("Capped roof ridge",(0,-2.015,3.505),(0,.66,4.235),.145,.145,WOOD,.023)
    return k.finish()


def write_glb(collection,name):
    """Put shared external maps in the GLB; Godot imports each image just once."""
    OUT.mkdir(exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in collection.objects: obj.select_set(True)
    path=OUT/(name+".glb")
    bpy.ops.export_scene.gltf(filepath=str(path),export_format="GLB",use_selection=True,
                              export_tangents=True,export_apply=True)
    raw=path.read_bytes()
    size=struct.unpack_from("<I",raw,12)[0]
    doc=json.loads(raw[20:20+size])
    binary=raw[28+size:]
    images=doc.get("images",[])
    dropped={img["bufferView"] for img in images}
    for img in images:
        label=img["name"].split(".")[0]
        if not (TEXTURES/(label+".png")).exists() and not (TEXTURES/(label+".jpg")).exists():
            raise ValueError("Unmapped PBR export image: "+str(img))
        filename=next((label+suf for suf in [".jpg",".png"] if (TEXTURES/(label+suf)).exists()))
        img.pop("bufferView")
        img["uri"]="../materials/"+filename
    kept=[]; remap={}; buf=bytearray()
    for i,v in enumerate(doc["bufferViews"]):
        if i in dropped: continue
        start=v.get("byteOffset",0)
        fragment=binary[start:start+v["byteLength"]]
        remap[i]=len(kept)
        v["byteOffset"]=len(buf)
        buf.extend(fragment);buf.extend(bytes((-len(buf))%4))
        kept.append(v)
    for accessor in doc["accessors"]: accessor["bufferView"]=remap[accessor["bufferView"]]
    for mat in doc["materials"]:
        orm=mat.get("pbrMetallicRoughness",{}).get("metallicRoughnessTexture")
        if orm:
            mat["occlusionTexture"]={"index":orm["index"],"strength":.60}
    doc["bufferViews"]=kept;doc["buffers"][0]["byteLength"]=len(buf)
    header=json.dumps(doc,separators=(",",":")).encode("utf-8")
    header+=b" "*(-len(header)%4)
    path.write_bytes(struct.pack("<4sIII4s",b"glTF",2,28+len(header)+len(buf),len(header),b"JSON")+header+struct.pack("<I4s",len(buf),b"BIN\0")+buf)


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    door=build_door()
    write_glb(door,"hinged_door")
    porch=build_porch()
    write_glb(porch,"entrance_porch")
    # Editable kit laid out exactly as at the west doorway, oriented to the door.
    # The GLBs remain centred in their original independent mounting frames.
    mount=bpy.data.objects.new("Porch mounting angle",None)
    bpy.context.scene.collection.objects.link(mount)
    mount.rotation_euler.z=math.pi/2-.88
    mount.location=(-.024,-.215,-.02)
    for obj in porch.objects:
        if obj.parent is None: obj.parent=mount
    bpy.ops.file.pack_all()
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art_source/canyon/西门门扇与门廊.blend"))
