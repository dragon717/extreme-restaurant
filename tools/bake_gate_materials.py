"""Pack the painted entrance palette and its linear surface response maps.

The six islands follow GateBuilder's UV layout. Normal derivatives are taken
within each island so a neighbouring swatch cannot create a ridge at its edge.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "art_source/canyon/门廊材质/手绘母版.png"
OUT = ROOT / "assets/materials"
TILE = 512
# roughness, exposed metal, relief gain, cavity influence for each material
RESPONSE = [
    (.60, .00, 3.6, .18), (.86, .00, 4.4, .24), (.38, .73, 1.3, .07),
    (.53, .63, 2.4, .12), (.27, .00, .76, .02), (.30, .00, 1.05, .03),
]

def blurred_height(a, amount):
    field = Image.fromarray(np.uint8(np.clip(a, 0, 1)*255))
    return np.asarray(field.filter(ImageFilter.GaussianBlur(amount)),dtype=float)/255.

def pack():
    paint = Image.open(SOURCE).convert("RGB").resize((3*TILE,2*TILE),Image.Resampling.LANCZOS)
    color = Image.new("RGB",paint.size)
    relief = Image.new("RGB",paint.size)
    response = Image.new("RGB",paint.size)
    for i,(rough,metal,gain,cavity) in enumerate(RESPONSE):
        x,y = i%3*TILE,i//3*TILE
        swatch = paint.crop((x+3,y+3,x+TILE-3,y+TILE-3)).resize((TILE,TILE),Image.Resampling.LANCZOS)
        rgb = np.asarray(swatch,dtype=float)/255.
        luma = rgb @ np.array([.26,.61,.13])
        middle = blurred_height(luma,3.5)
        broad = blurred_height(luma,13)
        detail = (blurred_height(luma,.85)-middle)*.8+(middle-broad)*.36
        dy,dx = np.gradient(detail)
        normal = np.stack((-gain*dx,gain*dy,np.ones_like(dx)),axis=-1)
        normal /= np.linalg.norm(normal,axis=2)[:,:,None]
        pits = np.clip((broad-luma)*4,0,1)
        tarnish = np.clip((rgb[:,:,1]-.8*rgb[:,:,0])*4,0,1) if i==2 else pits*.24
        orm = np.stack((1.-pits*cavity,
                        np.clip(rough+1.15*(broad-luma)+.12*tarnish,.20,.98),
                        metal*(1.-.80*tarnish)),axis=-1)
        if i == 1:
            # The porch sits in moist grass; its limestone is cooler and less
            # chalky than an exposed sunlit piece of the same stone.
            rgb = rgb*np.array([.78,.83,.87])
        elif i == 3:
            rgb = np.clip(rgb*1.12+.023,0,1)
        color.paste(Image.fromarray(np.uint8(rgb*255)),(x,y))
        relief.paste(Image.fromarray(np.uint8((normal*.5+.5)*255)),(x,y))
        response.paste(Image.fromarray(np.uint8(orm*255)),(x,y))
    color.save(OUT/"gate-paint.jpg",quality=92,subsampling=0)
    relief.save(OUT/"gate-relief.png",optimize=True)
    response.save(OUT/"gate-orm.png",optimize=True)

if __name__ == "__main__":
    pack()
