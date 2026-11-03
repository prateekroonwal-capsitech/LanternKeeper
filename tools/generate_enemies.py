"""Generates the small enemy extras: eye glow, lairs, thread. (Creature bodies come from
tools/generate_enemy_art.py.)

Output: game/assets/sprites/enemies/
  enemy_eyes.png      WHITE eye shapes (coloured red + glowing in-game via modulate)
  lair_crack.png      wall/floor crack a creature hides in
  lair_hole.png       floor/ceiling hole
  thread.png          the Dropper's thread (stretched vertically in-game)

Usage:
  python tools/generate_enemies.py
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "sprites", "enemies")


def misc():
    eyes = Image.new("RGBA", (96, 48), (0, 0, 0, 0))
    e = ImageDraw.Draw(eyes)
    for cx in (28, 68):
        e.polygon([(cx - 14, 24), (cx + 12, 16), (cx + 10, 30)], fill=(255, 255, 255, 255))
    eyes = Image.alpha_composite(eyes.filter(ImageFilter.GaussianBlur(4)), eyes)
    eyes.save(os.path.join(OUT, "enemy_eyes.png"))

    crack = Image.new("RGBA", (96, 160), (0, 0, 0, 0))
    c = ImageDraw.Draw(crack)
    pts = [(48, 0)]
    r = random.Random(4)
    for y in range(16, 161, 16):
        pts.append((48 + r.uniform(-16, 16), y))
    for i in range(len(pts) - 1):
        c.line((pts[i], pts[i + 1]), fill=(1, 1, 2, 255), width=int(18 - abs(i - 5) * 2))
    crack = crack.filter(ImageFilter.GaussianBlur(1.5))
    crack.save(os.path.join(OUT, "lair_crack.png"))

    hole = Image.new("RGBA", (160, 64), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hole)
    hd.ellipse((8, 14, 152, 54), fill=(1, 1, 2, 255))
    hd.ellipse((0, 8, 160, 60), outline=(20, 18, 26, 255), width=4)
    hole.save(os.path.join(OUT, "lair_hole.png"))

    thread = Image.new("RGBA", (4, 64), (40, 40, 48, 200))
    thread.save(os.path.join(OUT, "thread.png"))
    print("wrote enemy_eyes.png, lair_crack.png, lair_hole.png, thread.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    misc()
