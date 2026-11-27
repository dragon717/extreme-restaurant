"""Author the cutaway inn in Blender. Unit is one grid cell. In each wall module
local +Y faces the landscape and the playable rectangle ends exactly at Y=0.
The joints at X=-3,+3 allow straight, diagonal and stepped bays to meet."""
import math
import json
import struct
import sys
from pathlib import Path
import bpy
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "tavern"
OUT.mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

def material(name, color, tile=None, metal=0.0, emission=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    rgb = [((int(color[i:i+2], 16) / 255 + .055) / 1.055) ** 2.4 for i in (0, 2, 4)]
    bs.inputs["Base Color"].default_value = (*rgb, 1)
    bs.inputs["Roughness"].default_value = .52 if metal else .83
    bs.inputs["Metallic"].default_value = metal
    if emission:
        bs.inputs["Emission Color"].default_value = (*rgb, 1)
        bs.inputs["Emission Strength"].default_value = emission
    if tile:
        for suffix in ["", "-normal"]:
            tex = m.node_tree.nodes.new("ShaderNodeTexImage")
            tex.image = bpy.data.images.load(str(ROOT / "assets/materials" / (tile + suffix + (".jpg" if not suffix and tile.startswith(("inn-","house-")) else ".png"))), check_existing=True)
            if suffix:
                tex.image.colorspace_settings.name = "Non-Color"
                normal = m.node_tree.nodes.new("ShaderNodeNormalMap")
                normal.inputs["Strength"].default_value = .48
                m.node_tree.links.new(tex.outputs[0],normal.inputs["Color"])
                m.node_tree.links.new(normal.outputs[0],bs.inputs["Normal"])
            else:
                # glTF exports the tint as a factor as well as the authored grain.
                mix = m.node_tree.nodes.new("ShaderNodeMixRGB")
                mix.blend_type = "MULTIPLY"
                mix.inputs[0].default_value = 1
                mix.inputs[2].default_value = (*rgb, 1)
                m.node_tree.links.new(tex.outputs[0],mix.inputs[1])
                m.node_tree.links.new(mix.outputs[0],bs.inputs["Base Color"])
    return m

oak = material("Hewn_oak","b99064","inn-oak")
stone = material("River_masonry","e0d6bd","inn-stone")
plaster = material("Limewash","d6b588","inn-plaster")
copper = material("Weathered_copper","92948a","inn-slate",metal=.06)
tiles = material("Smoke_blue_slate","9d8f85","inn-shingles")
trim = material("Forged_bronze","98734c",metal=.48)
pane = material("Leadlight_amber","f8bd64",emission=.64)
iron = material("Blackened_iron","3b4246",metal=.48)
cloth = material("River_linen","4b827a")
ceramic = material("Cream_glaze","e4cc98")
embers = material("Stove_embers","ed7835",emission=.85)
materials = [oak,stone,plaster,copper,tiles,trim,pane,iron,cloth,ceramic,embers]

class Layer:
    def __init__(self):
        self.verts, self.faces, self.slots = [], [], []
    def face(self, points, mat):
        self.faces.append(tuple(range(len(self.verts),len(self.verts)+len(points))))
        self.verts.extend(points)
        self.slots.append(materials.index(mat))
    def prism(self, poly, bottom, top, mat):
        if len(poly) < 3: return
        # Counterclockwise top faces as viewed from above.
        if sum(a[0]*b[1]-a[1]*b[0] for a,b in zip(poly,poly[1:]+poly[:1])) < 0:
            poly = list(reversed(poly))
        low = [(x,y,bottom) for x,y in poly]
        high = [(x,y,top) for x,y in poly]
        for tri in tessellate_polygon([[Vector(p) for p in high]]):
            self.face([high[i] for i in tri],mat)
        for i,a in enumerate(low):
            j=(i+1)%len(low)
            self.face([a,low[j],high[j],high[i]],mat)
    def bar(self, a,b,width,depth,mat):
        a,b=Vector(a),Vector(b)
        axis=(b-a).normalized()
        cross=axis.cross(Vector((0,0,1)) if abs(axis.z)<.98 else Vector((0,1,0))).normalized()*width/2
        up=axis.cross(cross).normalized()*depth/2
        rings=[[end+cross+up,end-cross+up,end-cross-up,end+cross-up] for end in (a,b)]
        self.face(rings[0][::-1],mat)
        self.face(rings[1],mat)
        for i in range(4):
            j=(i+1)%4
            self.face([rings[0][i],rings[0][j],rings[1][j],rings[1][i]],mat)
    def bowl(self,x,y,bands,mat,n=12):
        rings=[[(x+r*math.cos(i*math.tau/n),y+r*math.sin(i*math.tau/n),z) for i in range(n)] for r,z in bands]
        for a,b in zip(rings,rings[1:]):
            for i in range(n):
                j=(i+1)%n
                self.face([a[i],a[j],b[j],b[i]],mat)
        self.face(rings[-1],mat)
    def mesh(self,name,coll):
        mesh=bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts,[],self.faces)
        mesh.update()
        for m in materials: mesh.materials.append(m)
        uv=mesh.uv_layers.new(name="Timber_and_stone")
        for face,slot in zip(mesh.polygons,self.slots):
            face.material_index=slot
            n=face.normal
            for i in face.loop_indices:
                p=mesh.vertices[mesh.loops[i].vertex_index].co
                xy=(p.x,p.y) if abs(n.z)>.64 else ((p.y,p.z) if abs(n.x)>abs(n.y) else (p.x,p.z))
                uv.data[i].uv=(xy[0]*.48,xy[1]*.48)
        import bmesh
        bm=bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if len(f.verts)>4])
        bm.to_mesh(mesh)
        bm.free()
        obj=bpy.data.objects.new(name,mesh)
        coll.objects.link(obj)
        return obj

def share_maps(path):
    # All wings use the same source textures and GPU resources after import.
    raw=path.read_bytes()
    length=struct.unpack_from("<I",raw,12)[0]
    doc=json.loads(raw[20:20+length])
    binary=raw[28+length:]
    images=doc.get("images",[])
    embedded={image["bufferView"] for image in images}
    remap,views,geometry={},[],bytearray()
    for i,view in enumerate(doc["bufferViews"]):
        if i in embedded: continue
        start=view.get("byteOffset",0)
        segment=binary[start:start+view["byteLength"]]
        remap[i]=len(views)
        view["byteOffset"]=len(geometry)
        geometry.extend(segment)
        geometry.extend(bytes(-len(geometry)%4))
        views.append(view)
    for acc in doc["accessors"]:
        acc["bufferView"]=remap[acc["bufferView"]]
    for image in images:
        del image["bufferView"]
        image["uri"]="../materials/"+image["name"]+(".jpg" if image["name"].startswith(("inn-","house-")) and not image["name"].endswith("-normal") else ".png")
        assert (path.parent/image["uri"]).is_file()
    doc["bufferViews"]=views
    doc["buffers"][0]["byteLength"]=len(geometry)
    for node in doc["nodes"]:
        node["name"]=node["name"].split(".")[0]
    header=json.dumps(doc,separators=(",",":")).encode()
    header+=b" "*(-len(header)%4)
    path.write_bytes(struct.pack("<4sIII4s",b"glTF",2,28+len(header)+len(geometry),len(header),b"JSON")+header+struct.pack("<I4s",len(geometry),b"BIN\0")+geometry)

def export(name,parts):
    coll=bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    bpy.ops.object.select_all(action="DESELECT")
    for layer,data in parts.items():
        if data.faces: data.mesh(layer,coll).select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,export_tangents=True)
    share_maps(OUT/(name+".glb"))
    return coll

def bay(name,path,height,roof_color,open_side=False):
    floor,frame,roof = Layer(),Layer(),Layer()
    floor.prism(path,-.23,.06,stone)
    # Radial floor boards follow each wall facet and close the space to the square tiles.
    for a,b in zip(path,path[1:]):
        if max(a[1],b[1]) <= .01: continue
        if abs(b[0]-a[0])<.001: continue
        count=max(1,math.ceil((b[0]-a[0])/.36))
        for i in range(count):
            aa=Vector(a).lerp(Vector(b),(i+.015)/count); bb=Vector(a).lerp(Vector(b),(i+.985)/count)
            floor.prism([(aa.x,0),(bb.x,0),(bb.x,bb.y),(aa.x,aa.y)],.061,.09,oak)
    for i,(a,b) in enumerate(zip(path,path[1:])):
        v=Vector(b)-Vector(a)
        normal=Vector((-v.y,v.x)).normalized()
        def pt(t,z,push=0):
            q=Vector(a)+v*t+normal*push
            return (q.x,q.y,z)
        frame.bar(pt(0,.20),pt(1,.20),.27,.40,stone)
        for t in [0,1]:
            frame.bar(pt(t,0),pt(t,height+.03),.15,.16,oak)
        if open_side:
            frame.bar(pt(0,height-.06),pt(1,height-.06),.20,.13,oak)
            if v.length>1.4:
                for t in [.33,.66]:
                    frame.bar(pt(t,.20),pt(t,height-.06),.08,.08,trim)
            continue
        frame.bar(pt(0,height*.52),pt(1,height*.52),.18,height*.89,plaster)
        frame.bar(pt(.05,.35,-.12),pt(.94,height-.28,-.12),.11,.13,oak)
        frame.bar(pt(0,.44,-.12),pt(1,.44,-.12),.13,.13,oak)
        frame.bar(pt(0,height-.06),pt(1,height-.06),.29,.22,oak)
        if v.length>1.55:
            for t in [.34,.66]:
                radius=min(.28,v.length*.09)
                center=Vector(pt(t,.72,-.16))
                horizontal=Vector((v.x,v.y,0)).normalized()
                arch=[center+horizontal*(-radius), center+horizontal*radius]
                arch += [center+horizontal*(radius*math.cos(k*math.pi/6))+Vector((0,0,height*.39+radius*math.sin(k*math.pi/6))) for k in range(7)]
                frame.face(arch[::-1],pane)
                frame.face(arch,pane)
                frame.bar(pt(t,.72,-.18),pt(t,.72+height*.39+radius,-.18),.055,.054,trim)
        # Shingle courses share an eave. Its ridge follows the angled masonry.
        for course in range(3):
            lo,hi=course/3,(course+1)/3
            for seg in range(max(2,math.ceil(v.length/.52))):
                divisions=max(2,math.ceil(v.length/.52))
                ta,tb=seg/divisions,(seg+1)/divisions
                coords=[pt(ta,height+lo*.83,-.35+lo*1.03),pt(tb,height+lo*.83,-.35+lo*1.03),pt(tb,height+hi*.83,-.35+hi*1.03),pt(ta,height+hi*.83,-.35+hi*1.03)]
                roof.face(coords,roof_color)
                roof.face(coords[::-1],roof_color)
                roof.bar(coords[0],coords[1],.048,.05,trim if course==0 else roof_color)
        roof.bar(pt(0,height+.83,.68),pt(1,height+.83,.68),.17,.12,trim)
    return export(name,{"Foundation":floor,"Structure":frame,"Eaves":roof})

collections=[]
# Most wall lengths stay straight between structural corners. The entrance,
# one hearth bay and one terrace supply the house's major changes of direction.
profiles=json.loads((ROOT/"data/architecture/eaves.json").read_text(encoding="utf-8"))
for key,spec in profiles.items():
    collections.append(bay(key,spec["line"],spec["height"],tiles if key=="hearth_bay" else copper,spec["open"]))
# Real utensils and cookware share one mesh per fixture for inexpensive instancing.
s=Layer()
s.prism([(-.45,-.42),(.32,-.42),(.45,-.29),(.45,.32),(.31,.44),(-.45,.44)],0,.50,stone)
s.bowl(0,0,[(.32,.48),(.40,.55),(.33,.60)],iron)
s.bowl(0,0,[(.25,.60),(.30,.64)],embers)
s.bowl(0,0,[(.18,.63),(.33,.70),(.38,.89),(.40,.92),(.34,.93),(.29,.84)],iron)
s.bowl(0,0,[(.29,.85),(.28,.86)],trim)
s.bar((-.41,0,.89),(.42,0,.89),.055,.04,trim)
collections.append(export("hearth_stove",{"Cauldron":s}))
s=Layer()
s.bowl(0,0,[(.28,0),(.17,.09),(.10,.42),(.30,.47)],oak)
s.bowl(0,0,[(.45,.46),(.49,.50),(.49,.56),(.46,.58)],oak)
s.prism([(-.13,-.42),(.10,-.42),(.10,.42),(-.13,.42)],.581,.588,cloth)
s.bowl(-.20,0,[(.09,.58),(.14,.61),(.10,.62)],ceramic)
s.bowl(.19,.08,[(.07,.58),(.074,.71),(.06,.72)],trim)
s.bowl(0,.26,[(.048,.58),(.05,.74)],ceramic)
collections.append(export("round_table",{"Tavern_table":s}))
# The gate remains a fixed landmark from the panoramic view to a close inspection.
yard=Layer()
def lantern(x,y):
    yard.bar((x,y,-.48),(x,y,2.45),.18,.18,oak)
    yard.bar((x-.46,y,2.38),(x+.32,y,2.38),.13,.14,trim)
    yard.bowl(x-.33,y,[(.06,1.66),(.13,1.76),(.108,2.02),(.06,2.08)],pane,8)
    yard.bowl(x-.33,y,[(.045,1.61),(.098,1.68),(.14,1.76)],trim,8)
    yard.bowl(x-.33,y,[(.125,2.02),(.15,2.05),(.045,2.19)],iron,8)
    yard.bar((x-.33,y,2.18),(x-.33,y,2.39),.034,.034,iron)
    for angle in range(0,360,90):
        t=math.radians(angle+22.5)
        yard.bar((x-.33+.132*math.cos(t),y+.132*math.sin(t),1.75),(x-.33+.113*math.cos(t),y+.113*math.sin(t),2.04),.016,.016,iron)
def barrel(x,y,scale=1.):
    yard.bowl(x,y,[(r*scale,h*scale-.29) for r,h in [(.35,0),(.44,.26),(.46,.59),(.35,.88)]],oak)
    for z,rad in [(.12,.40),(.44,.46),(.75,.39)]:
        yard.bowl(x,y,[(rad*scale,(z-.03)*scale-.29),((rad+.01)*scale,(z+.03)*scale-.29)],iron)
# Author in Blender space. Negative Y is the street to the south in Godot.
for x,y in [(-3.3,-10.2),(-5.5,-16.95),(-5.5,-19.0)]: lantern(x,y)
for x,y in [(-4.4,-7.7),(-5.1,-7.55),(-4.8,-6.95),(-6.85,-13.3)]: barrel(x,y,1.05)
# Well, timber windlass, bucket and a foot-worn apron beside the door.
x,y=-3.1,-7.8
for i in range(12):
    a,b=i*math.tau/12,(i+.96)*math.tau/12
    def ring(t,r): return (x+math.cos(t)*r,y+math.sin(t)*r)
    yard.prism([ring(a,.95),ring(b,.95),ring(b,.67),ring(a,.67)],-.48,.66,stone)
yard.bowl(x,y,[(.68,.24),(.68,.26)],copper)
for xx in [-.82,.82]: yard.bar((x+xx,y,0),(x+xx,y,2.1),.16,.18,oak)
yard.bar((x-.96,y,1.71),(x+1.04,y,1.71),.21,.21,oak)
yard.bar((x,y,1.70),(x,y,.72),.042,.045,trim)
for side in [-1,1]:
    roof=[(x-1.23,y+side*.8,1.96),(x+1.23,y+side*.8,1.96),(x+1.23,y,2.57),(x-1.23,y,2.57)]
    yard.face(roof,copper)
    yard.face(roof[::-1],copper)
walk_spec=json.loads((ROOT/"data/architecture/entrance_walk.json").read_text(encoding="utf-8"))
for stone_outline in walk_spec["path_stones"]:
    yard.prism([(x,-z) for x,z in stone_outline],-.50,walk_spec["stone_height"],stone)
collections.append(export("gate_court",{"Well_and_lanterns":yard}))
# The close-up porch is authored with its working doors and shares their atlas.
sys.path.insert(0,str(ROOT/"tools"))
from build_tavern_door import build_porch, write_glb
porch_collection=build_porch()
write_glb(porch_collection,"entrance_porch")
collections.append(porch_collection)

# Stacked stone flue crosses the same high roof as the hearth below it.
chim=Layer()
chimney_stone=material("Hearth_flue_stone","c1b293","house-masonry")
materials.append(chimney_stone)
def section(center,r):
    cx,cy=center
    return [(cx+x*r,cy+y*r) for x,y in [(-1,-.83),(-.76,-1),(.83,-1),(1,-.73),(1,.82),(.78,1),(-.83,1),(-1,.74)]]
for i in range(15):
    z=i*.49
    r=.50+(i%3)*.018
    chim.prism(section((.028*(i%2),0),r),z,z+.477,chimney_stone)
chim.prism(section((0,0),.64),7.34,7.58,stone)
chim.prism(section((0,0),.37),7.585,7.595,iron)
collections.append(export("stone_chimney",{"Masonry_flue":chim}))
# Keep the editable master arranged for inspection. Individual GLBs have local origins.
for idx,coll in enumerate(collections):
    for obj in coll.objects: obj.location.x=idx*8
bpy.ops.file.pack_all()
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"art_source/canyon/餐厅木石构件.blend"))
