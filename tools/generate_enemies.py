"""Generates placeholder enemy art: animation strips + SpriteFrames, lairs, thread.

Output: game/assets/sprites/enemies/
  <enemy>_move.png    horizontal strip (frame size below) — silhouette body, no eyes
  <enemy>_frames.tres SpriteFrames with one looping "move" animation
  enemy_eyes.png      WHITE eye shapes (coloured red + glowing in-game via modulate)
  lair_crack.png      wall/floor crack a creature hides in
  lair_hole.png       floor/ceiling hole
  thread.png          the Dropper's thread (stretched vertically in-game)

Replace a strip with final art of the same frame size/count. Usage:
  python tools/generate_enemies.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "sprites", "enemies")
RES = "res://game/assets/sprites/enemies/"
SIL = (4, 3, 8, 255)
TAU = math.tau


def strip(name, fw, fh, frames, draw):
    img = Image.new("RGBA", (fw * frames, fh), (0, 0, 0, 0))
    for i in range(frames):
        f = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
        draw(ImageDraw.Draw(f), fw, fh, i / frames)
        img.paste(f, (i * fw, 0))
    img.save(os.path.join(OUT, f"{name}_move.png"))
    frames_tres(name, fw, fh, frames)
    print(f"wrote {name}_move.png  {frames} x {fw}x{fh}")


def frames_tres(name, fw, fh, frames, fps=8.0):
    subs = []
    refs = []
    for i in range(frames):
        subs.append(f'[sub_resource type="AtlasTexture" id="a{i}"]\natlas = ExtResource("1")\n'
                    f'region = Rect2({i * fw}, 0, {fw}, {fh})\n')
        refs.append(f'{{\n"duration": 1.0,\n"texture": SubResource("a{i}")\n}}')
    text = (f'[gd_resource type="SpriteFrames" format=3]\n\n'
            f'[ext_resource type="Texture2D" path="{RES}{name}_move.png" id="1"]\n\n' + "\n".join(subs) +
            '\n[resource]\nanimations = [{\n"frames": [' + ", ".join(refs) +
            f'],\n"loop": true,\n"name": &"move",\n"speed": {fps}\n}}]\n')
    open(os.path.join(OUT, f"{name}_frames.tres"), "w", newline="\n").write(text)


def leg(d, x, y, length, angle, knee, width):
    a = math.radians(angle)
    kx, ky = x + math.cos(a) * length, y - math.sin(a) * length
    b = a - math.radians(knee)
    fx, fy = kx + math.cos(b) * length, ky - math.sin(b) * length
    d.line((x, y, kx, ky), fill=SIL, width=width)
    d.line((kx, ky, fx, fy), fill=SIL, width=max(1, width - 1))


def crawler(d, w, h, t):
    cx, cy = w * 0.5, h * 0.55
    d.ellipse((cx - 46, cy - 20, cx + 40, cy + 14), fill=SIL)
    d.ellipse((cx + 22, cy - 22, cx + 54, cy + 6), fill=SIL)          # head (faces right)
    for i in range(3):
        ph = t * TAU + i * 2.1
        for side in (0, 1):
            x = cx - 30 + i * 26
            leg(d, x, cy + 4, 22, 200 + side * 140 + math.sin(ph + side * math.pi) * 18, 70 - side * 140, 4)
    for i in range(5):                                                 # spines
        x = cx - 40 + i * 14
        d.polygon([(x, cy - 16), (x + 6, cy - 34 - (i % 2) * 6), (x + 10, cy - 16)], fill=SIL)


def dropper(d, w, h, t):
    cx, cy = w * 0.5, h * 0.42
    d.ellipse((cx - 26, cy - 26, cx + 26, cy + 26), fill=SIL)
    for i in range(8):
        ang = 200 + i * 20 + math.sin(t * TAU + i) * 6
        a = math.radians(ang)
        kx, ky = cx + math.cos(a) * 34, cy - math.sin(a) * 34
        d.line((cx, cy, kx, ky), fill=SIL, width=4)
        d.line((kx, ky, kx + (kx - cx) * 0.2, ky + 26), fill=SIL, width=3)


def stalker(d, w, h, t):
    cx = w * 0.5
    sway = math.sin(t * TAU) * 6
    d.ellipse((cx - 16 + sway, 20, cx + 16 + sway, 58), fill=SIL)                      # head
    d.polygon([(cx - 18 + sway, 56), (cx + 18 + sway, 56), (cx + 26, 210), (cx - 26, 210)], fill=SIL)
    for side in (-1, 1):                                                                 # long arms
        d.line((cx + side * 16 + sway, 70, cx + side * 30, 170 + math.sin(t * TAU + side) * 8), fill=SIL, width=5)
        d.line((cx + side * 30, 170, cx + side * 26, 205), fill=SIL, width=3)
    r = random.Random(int(t * 100))
    for i in range(9):                                                                   # wispy hem
        x = cx - 26 + i * 6.5
        d.polygon([(x, 205), (x + 6, 205), (x + 3 + r.uniform(-6, 6), 250 + r.uniform(0, 30))], fill=SIL)


def mite(d, w, h, t):
    cx, cy = w * 0.5, h * 0.5
    d.ellipse((cx - 13, cy - 11, cx + 13, cy + 11), fill=SIL)
    for i in range(10):
        a = i * TAU / 10 + t * 0.6
        ln = 20 + (6 if (i + int(t * 4)) % 2 else 0)
        d.line((cx, cy, cx + math.cos(a) * ln, cy + math.sin(a) * ln), fill=SIL, width=3)


def big_shadow(d, w, h, t):
    cx, cy = w * 0.45, h * 0.42
    d.ellipse((cx - 170, cy - 140, cx + 170, cy + 120), fill=SIL)
    d.ellipse((cx + 90, cy - 120, cx + 250, cy + 30), fill=SIL)                          # head (faces right)
    for i in range(6):
        ph = t * TAU + i * 1.1
        x = cx - 140 + i * 56
        kx = x + 40 + math.sin(ph) * 30
        d.line((x, cy + 60, kx, cy - 40), fill=SIL, width=16)
        d.line((kx, cy - 40, kx + 30 + math.sin(ph) * 25, h - 10), fill=SIL, width=12)
    for i in range(14):                                                                  # ragged fur
        a = math.radians(100 + i * 12)
        d.polygon([(cx + math.cos(a) * 150, cy - math.sin(a) * 120),
                   (cx + math.cos(a) * 210, cy - math.sin(a) * 175),
                   (cx + math.cos(a + 0.12) * 150, cy - math.sin(a + 0.12) * 120)], fill=SIL)


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
    strip("crawler", 160, 96, 4, crawler)
    strip("dropper", 128, 128, 2, dropper)
    strip("stalker", 128, 288, 4, stalker)
    strip("mite", 64, 64, 2, mite)
    strip("big_shadow", 640, 640, 4, big_shadow)
    misc()
