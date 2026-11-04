"""Placeholder art for the level 10 trap props (replace each PNG with final art of the same size).

Output: game/assets/sprites/single/props/
  rock_trap.png       192 x 160  boulder hanging on a rope (RockTrap.tscn → Block/Sprite)
  ceiling_slab.png    384 x 128  cracked ceiling slab (CeilingCollapse.tscn → Block/Sprite)
  crate.png           128 x 128  wooden crate (Crate.tscn → Sprite)
  pressure_plate.png  160 x 48   stone plate in a frame (PressurePlate.tscn → Plate)
  crevice.png         160 x 288  dark hiding crevice in the cave wall (Crevice.tscn → Sprite)
  ../fx/debris_chunk.png  32 x 32  a stone chip (FallFX.tscn → Pebbles / ImpactChunks)

Usage:  python tools/generate_level_props.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "sprites", "single", "props")
STONE = (24, 24, 30, 255)
STONE_HI = (52, 52, 62, 255)
DARK = (6, 6, 9, 255)


def save(img, name):
    img.save(os.path.join(OUT, name))
    print("wrote", name, img.size)


def boulder():
    r = random.Random(3)
    w, h = 192, 160
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pts = []
    for k in range(18):
        a = k / 18 * math.tau
        rad = 1.0 + r.uniform(-0.08, 0.08)
        pts.append((w / 2 + math.cos(a) * 88 * rad, h / 2 + 6 + math.sin(a) * 66 * rad))
    d.polygon(pts, fill=STONE)
    for k in range(5):                                      # cracks / facets
        x0, y0 = r.uniform(40, 150), r.uniform(40, 120)
        d.line((x0, y0, x0 + r.uniform(-30, 30), y0 + r.uniform(10, 30)), fill=DARK, width=3)
    d.arc((20, 18, 172, 150), 200, 320, fill=STONE_HI, width=4)  # rim highlight
    d.rectangle((90, 0, 102, 22), fill=(40, 34, 28, 255))   # rope knot
    save(img, "rock_trap.png")


def slab():
    r = random.Random(5)
    w, h = 384, 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = [(0, 0), (w, 0)]
    bottom = [(w - x, 100 + r.uniform(-6, 18)) for x in range(0, w + 1, 24)]
    d.polygon(top + bottom, fill=STONE)
    for k in range(7):                                      # cracks running through it
        x = r.uniform(20, w - 20)
        pts = [(x, 0)]
        for _ in range(5):
            pts.append((pts[-1][0] + r.uniform(-16, 16), pts[-1][1] + r.uniform(14, 24)))
        d.line(pts, fill=DARK, width=4)
    for x in range(10, w, 40):                              # hanging grit
        d.line((x, 100, x + 2, 116 + r.uniform(0, 8)), fill=STONE, width=3)
    save(img, "ceiling_slab.png")


def crate():
    w = h = 128
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    wood, dark, edge = (58, 40, 26, 255), (30, 20, 13, 255), (84, 60, 38, 255)
    d.rectangle((2, 2, w - 3, h - 3), fill=wood, outline=dark, width=6)
    for y in (42, 84):
        d.line((6, y, w - 6, y), fill=dark, width=3)
    d.line((10, 10, w - 10, h - 10), fill=edge, width=10)   # cross brace
    d.line((10, 10, w - 10, h - 10), fill=dark, width=2)
    for x, y in ((12, 12), (w - 12, 12), (12, h - 12), (w - 12, h - 12)):
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=dark)
    save(img, "crate.png")


def plate():
    w, h = 160, 48
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 18, w - 1, h - 1), fill=DARK)            # frame in the floor
    d.rectangle((10, 6, w - 11, 26), fill=STONE_HI)          # the plate
    d.line((14, 10, w - 15, 10), fill=(80, 80, 92, 255), width=2)
    for x in (30, 80, 130):                                 # rune notches
        d.line((x, 12, x + 6, 22), fill=DARK, width=3)
    save(img, "pressure_plate.png")


def crevice():
    w, h = 160, 288
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = random.Random(9)
    pts = [(w / 2 + math.sin(y / 30.0) * 8 - 44 + r.uniform(-6, 6), y) for y in range(0, h + 1, 24)]
    pts += [(w / 2 + math.sin(y / 26.0) * 8 + 44 + r.uniform(-6, 6), y) for y in range(h, -1, -24)]
    d.polygon(pts, fill=(2, 2, 3, 255))
    img = img.filter(ImageFilter.GaussianBlur(5))           # soft, deep shadow edges
    core = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(core).polygon([(p[0] * 0.8 + w * 0.1, p[1]) for p in pts], fill=(0, 0, 0, 255))
    img.alpha_composite(core)
    save(img, "crevice.png")


def debris_chunk():
    r = random.Random(13)
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    pts = [(16 + math.cos(a) * r.uniform(9, 14), 16 + math.sin(a) * r.uniform(8, 13)) for a in [k * math.tau / 7 for k in range(7)]]
    ImageDraw.Draw(img).polygon(pts, fill=(255, 255, 255, 255))   # white: tinted in the material
    img.save(os.path.join(OUT, "..", "fx", "debris_chunk.png"))
    print("wrote debris_chunk.png", img.size)


def firefly_jar():
    w, h = 64, 96
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Wire handle at top (pivot = handle top image row 4, same as lantern.png)
    wire = (120, 110, 100, 255)
    d.arc((22, 2, 42, 22), 180, 360, fill=wire, width=2)
    d.line((22, 12, 22, 20), fill=wire, width=2)
    d.line((42, 12, 42, 20), fill=wire, width=2)

    # Cork / lid
    cork = (115, 85, 55, 255)
    cork_dark = (70, 50, 30, 255)
    d.rounded_rectangle((20, 14, 44, 21), radius=2, fill=cork, outline=cork_dark, width=1)
    # Wire wrapped around neck
    d.rectangle((18, 20, 46, 24), fill=(100, 95, 90, 255))

    # Translucent glass body
    glass_fill = (180, 240, 195, 40)
    glass_edge = (170, 230, 190, 170)
    d.rounded_rectangle((14, 23, 50, 85), radius=8, fill=glass_fill, outline=glass_edge, width=2)

    # Thick glass bottom
    d.rounded_rectangle((16, 79, 48, 84), radius=3, fill=(150, 215, 175, 75))

    # Soft luminous firefly glow inside
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse((23, 40, 41, 68), fill=(210, 255, 160, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(5))
    img.alpha_composite(glow)

    # Re-draw highlights on top of glow
    d = ImageDraw.Draw(img)
    # Glass vertical rim highlight (left curve)
    d.line((18, 32, 18, 75), fill=(240, 255, 245, 140), width=2)
    # Glass shoulder glint
    d.arc((16, 24, 30, 36), 190, 270, fill=(250, 255, 250, 180), width=2)

    save(img, "firefly_jar.png")


def firefly_dot():
    w = h = 16
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((4, 4, 12, 12), fill=(255, 255, 255, 255))
    img = img.filter(ImageFilter.GaussianBlur(1.8))
    fx_path = os.path.join(OUT, "..", "fx", "firefly_dot.png")
    os.makedirs(os.path.dirname(fx_path), exist_ok=True)
    img.save(fx_path)
    print("wrote firefly_dot.png", img.size)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    boulder()
    slab()
    crate()
    plate()
    crevice()
    debris_chunk()
    firefly_jar()
    firefly_dot()
