"""Prepare fixed-camera paint atlases and their material maps for build_canyon.py."""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_source/canyon"
MAPS = SOURCE / "maps"
# Crop bounds are in the approved 1585 x 992 composition.
CROPS = {
    "valley": ("empty", (0, 0, 1585, 992)),
    "cottage": ("opening", (473, 457, 641, 611)),
    "inn": ("full", (225, 264, 866, 634)),
    "warehouse": ("full", (183, 120, 460, 293)),
    "crane": ("full", (451, 60, 650, 235)),
    "supply": ("full", (936, 216, 1150, 409)),
    "workshop": ("full", (1150, 88, 1382, 298)),
    "gallery": ("full", (1254, 246, 1540, 453)),
    "stone_bridge": ("full", (712, 153, 917, 253)),
    "timber_bridge": ("full", (650, 535, 1137, 810)),
    "dock": ("full", (1187, 618, 1585, 889)),
}

if __name__ == "__main__":
    MAPS.mkdir(exist_ok=True)
    images = {
        "empty": Image.open(SOURCE / "empty-valley.png"),
        "opening": Image.open(ROOT / "docs/原型/峡谷开局-一间小屋.png").resize((1585, 992)),
        "full": Image.open(ROOT / "docs/原型/峡谷底图-美术稿.png"),
    }
    for name, (source, rect) in CROPS.items():
        art = images[source].crop(rect).convert("RGB")
        if name == "cottage":
            art = Image.open(SOURCE/"小屋近景精绘.jpg").convert("RGB")
        art.save(MAPS / (name + "_color.jpg"), quality=95, subsampling=0)
        value = np.asarray(art.convert("L").filter(ImageFilter.GaussianBlur(1)), dtype=np.float32)/255
        dy, dx = np.gradient(value)
        normals = np.dstack((-dx*1.6, dy*1.6, np.ones_like(dx)))
        normals /= np.linalg.norm(normals, axis=2, keepdims=True)
        Image.fromarray(np.uint8((normals*.5+.5)*255)).save(MAPS / (name+"_normal.png"))
        rgb = np.asarray(art, dtype=np.float32)/255
        # Smooth painted metal catches a tighter highlight than stone and timber.
        brass = np.clip((rgb[:,:,0]-rgb[:,:,2]-.10)*1.5,0,.7) if name in ("supply","workshop","crane") else np.zeros_like(dx)
        rough = np.clip(.89-.18*value-.32*brass,.30,.95)
        packed = np.dstack((np.ones_like(dx),rough,brass))
        Image.fromarray(np.uint8(packed*255)).save(MAPS / (name+"_orm.png"))
