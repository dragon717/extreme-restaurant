"""Build the gallery's hinged Hextech reliquary with the existing shared palette."""
import math
from pathlib import Path
import sys
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_tavern_door import Kit, OUT, IRON, BRASS, TEAL, write_glb

bpy.ops.wm.read_factory_settings(use_empty=True)
kit=Kit("HextechCoffer")
def corners(radius):
    return [(radius*math.cos((i+.5)*math.tau/6),radius*math.sin((i+.5)*math.tau/6)) for i in range(6)]
def course(label,radius,base,top,material):
    return kit.horizontal(label,corners(radius),base,top,material,.012)
course("Armoured plinth",.49,0,.095,BRASS)
course("Midnight enamel shell",.455,.073,.45,IRON)
course("Charged seal",.465,.443,.465,TEAL)
course("Brass collar",.49,.465,.507,BRASS)
for i,(x,y) in enumerate(corners(.45)):
    kit.line("Corner rib %d"%i,(x,y,.055),(x,y,.483),.045,.049,BRASS,.008)
hinge=kit.pivot("CofferHinge",(0,.405,.49))
def mount(obj):
    obj.parent=hinge
    obj.location.y-=.405
    obj.location.z-=.49
mount(course("Lid rim",.493,.506,.567,BRASS))
mount(course("Lid",.456,.556,.605,IRON))
mount(kit.lathe("Hexcore",(0,0,.596),[(.196,0),(.205,.03),(.115,.162),(.039,.18)],TEAL,6))
for i,(x,y) in enumerate(corners(.438)):
    mount(kit.line("Gilded conductor %d"%i,(x,y,.59),(x*.24,y*.24,.727),.030,.034,BRASS,.005))
course("Lens well",.341,.420,.437,TEAL)
collection=kit.finish()
write_glb(collection,"hextech_coffer")
