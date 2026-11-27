"""Build the gallery coffer with a hollow well and a lid hinged along the rear flat."""
import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_tavern_door import Kit, IRON, BRASS, TEAL, write_glb

bpy.ops.wm.read_factory_settings(use_empty=True)
kit = Kit("HextechCoffer")


def corners(radius):
    return [(radius * math.cos(i * math.tau / 6), radius * math.sin(i * math.tau / 6)) for i in range(6)]


def course(label, radius, base, top, material):
    return kit.horizontal(label, corners(radius), base, top, material, .009)


def rim(label, outer, inner, base, top, tile):
    vertices = [(x, y, z) for rad, z in [(outer, base), (outer, top), (inner, top), (inner, base)] for x, y in corners(rad)]
    faces = []
    for row in range(4):
        for i in range(6):
            next_row = (row + 1) % 4
            j = (i + 1) % 6
            faces.append((row*6+i, row*6+j, next_row*6+j, next_row*6+i))
    return kit.mesh(label, vertices, faces, tile, bevel=.006)


course("Armoured plinth", .49, 0, .083, BRASS)
rim("Enamel walls", .455, .375, .079, .45, IRON)
rim("Charged seal", .465, .373, .443, .465, TEAL)
rim("Brass collar", .49, .37, .465, .507, BRASS)
course("Radiant chamber floor", .377, .17, .19, TEAL)
for i, (x, y) in enumerate(corners(.45)):
    kit.line("Brass corner rib %d" % i, (x,y,.063), (x,y,.48), .054, .06, BRASS, .008)
    kit.line("Luminous conduit %d" % i, (x*.88,y*.88,.19), (x*.86,y*.86,.45), .014, .017, TEAL, .003)

hinge = kit.pivot("CofferHinge", (0,.407,.515))
first_lid_piece = len(kit.parts)
course("Lid rim", .493, .509, .56, BRASS)
course("Enamel lid", .456, .555, .598, IRON)
kit.lathe("Faceted Hexcore", (0,0,.596), [(.185,0),(.191,.024),(.114,.142),(.034,.16)], TEAL, 6)
for i, (x, y) in enumerate(corners(.438)):
    kit.line("Gilded conductor %d" % i, (x,y,.585), (x*.25,y*.25,.730), .035, .034, BRASS, .006)
rim("Crystal bezel", .126, .105, .713, .733, BRASS)
rim("Inner lid circuit", .365, .353, .504, .511, TEAL)
for x in [-.19,.19]:
    kit.box("Front clasp", x-.027,x+.027,.39,.536,-.428,-.389,BRASS,.008)
    kit.stud("Latch pin",x,-.43,.416,.016,IRON)
for part in kit.parts[first_lid_piece:]:
    part.parent = hinge
    part.location -= hinge.location

collection = kit.finish()
write_glb(collection, "hextech_coffer")
