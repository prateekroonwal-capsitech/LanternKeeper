"""Generates the placeholder PNGs for Lantern Keeper.

Every file is written at its final pixel size, so final art can replace it 1:1
(same file name, same size). Re-running overwrites placeholders only; it never
touches a file listed in KEEP (add a path there once real art lands).

Usage:  python tools/generate_placeholders.py
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "sprites")
KEEP: set[str] = set()

random.seed(7)


def out(rel: str) -> str | None:
    if rel in KEEP:
        return None
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def save(img: Image.Image, rel: str) -> None:
    path = out(rel)
    if path:
        img.save(path)
        print("wrote", rel, img.size)


# ── Player ───────────────────────────────────────────────────────────────
def player_idle() -> None:
    w, h = 128, 192
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    body = (10, 10, 16, 255)
    # hooded head
    d.ellipse((44, 14, 84, 56), fill=body)
    d.polygon([(48, 30), (64, 4), (80, 30)], fill=body)
    # cloak
    d.polygon([(40, 52), (88, 52), (100, 150), (28, 150)], fill=body)
    # legs
    d.rectangle((46, 148, 58, 188), fill=body)
    d.rectangle((70, 148, 82, 188), fill=body)
    # arm reaching forward (lantern hand, facing right)
    d.polygon([(80, 70), (108, 96), (102, 104), (76, 84)], fill=body)
    # faint rim so the silhouette reads on black
    edge = img.filter(ImageFilter.FIND_EDGES)
    rim = Image.new("RGBA", (w, h), (70, 70, 90, 0))
    rim.putalpha(edge.split()[3].point(lambda a: 120 if a > 0 else 0))
    img = Image.alpha_composite(rim, img)
    save(img, "single/player/player_idle.png")


# ── Props ────────────────────────────────────────────────────────────────
def lantern() -> None:
    w, h = 64, 96
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    frame = (20, 16, 12, 255)
    d.ellipse((22, 2, 42, 18), outline=frame, width=3)           # handle
    d.rectangle((16, 16, 48, 24), fill=frame)                    # cap
    d.rectangle((14, 24, 50, 80), fill=frame)                    # cage
    d.rounded_rectangle((19, 28, 45, 76), radius=6, fill=(255, 170, 70, 255))
    d.ellipse((25, 40, 39, 66), fill=(255, 235, 170, 255))       # flame core
    d.rectangle((12, 80, 52, 90), fill=frame)                    # base
    for x in (24, 32, 40):
        d.line((x, 28, x, 76), fill=frame, width=2)              # bars
    save(img, "single/props/lantern.png")


def oil_flask() -> None:
    w, h = 64, 64
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((26, 4, 38, 14), fill=(60, 40, 30, 255))         # cork
    d.rectangle((24, 14, 40, 24), fill=(40, 70, 110, 255))       # neck
    d.ellipse((10, 20, 54, 62), fill=(40, 90, 160, 255))         # bottle
    d.ellipse((16, 34, 48, 60), fill=(90, 170, 255, 255))        # oil
    d.ellipse((20, 26, 30, 36), fill=(200, 230, 255, 200))       # highlight
    save(img, "single/props/oil_flask.png")


def exit_door() -> None:
    w, h = 128, 256
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    stone = (16, 18, 26, 255)
    d.rectangle((8, 40, 120, 256), fill=stone)
    d.ellipse((8, 0, 120, 100), fill=stone)
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    g.rectangle((30, 60, 98, 256), fill=(120, 190, 255, 255))
    g.ellipse((30, 26, 98, 100), fill=(120, 190, 255, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(6))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)
    d.rectangle((38, 70, 90, 256), fill=(200, 230, 255, 255))
    d.ellipse((38, 36, 90, 96), fill=(200, 230, 255, 255))
    save(img, "single/props/exit_door.png")


# ── Environment ──────────────────────────────────────────────────────────
def platform_stone() -> None:
    w = h = 256
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            n = random.randint(0, 10)
            px[x, y] = (18 + n, 18 + n, 24 + n, 255)
    d = ImageDraw.Draw(img)
    line = (8, 8, 12, 255)
    for row in range(4):
        y = row * 64
        d.line((0, y, w, y), fill=line, width=3)
        off = 0 if row % 2 == 0 else 64
        for col in range(3):
            x = (off + col * 128) % w
            d.line((x, y, x, y + 64), fill=line, width=3)
    save(img, "single/environment/platform_stone.png")


def ghost_platform() -> None:
    w, h = 256, 64
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y in range(h):
        for x in range(w):
            wave = 0.5 + 0.5 * math.sin(2 * math.pi * (x / w * 3 + y / h * 0.5))
            a = int(150 + 80 * wave)
            v = int(200 + 40 * wave)
            px[x, y] = (v, v, v, a)
    save(img, "single/environment/ghost_platform.png")


def dust_mote() -> None:
    w = h = 16
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((4, 4, 12, 12), fill=(255, 255, 255, 255))
    img = img.filter(ImageFilter.GaussianBlur(2))
    save(img, "single/fx/dust_mote.png")


# ── Parallax backgrounds (tile horizontally) ─────────────────────────────
def ridge(w: int, base: float, waves: list[tuple[int, float]]) -> list[float]:
    phases = [random.random() * math.tau for _ in waves]
    return [base + sum(a * math.sin(math.tau * k * x / w + p) for (k, a), p in zip(waves, phases))
            for x in range(w)]


def layer(rel: str, color: tuple, base: float, waves: list, trees: int = 0) -> None:
    w, h = 2048, 512
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    top = ridge(w, base, waves)
    for x in range(w):
        d.line((x, int(top[x]), x, h), fill=color)
    for _ in range(trees):
        x = random.randint(0, w - 1)
        y = int(top[x])
        th = random.randint(60, 140)
        d.line((x, y, x, y - th), fill=color, width=6)
        for _ in range(4):
            by = y - random.randint(th // 3, th)
            dx = random.choice((-1, 1)) * random.randint(15, 40)
            d.line((x, by, x + dx, by - random.randint(10, 30)), fill=color, width=3)
    save(img, rel)


def sky() -> None:
    w, h = 64, 512
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    top, bottom = (4, 5, 10), (20, 26, 42)
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line((0, y, w, y), fill=c + (255,))
    save(img, "backgrounds/bg_sky.png")


if __name__ == "__main__":
    player_idle()
    lantern()
    oil_flask()
    exit_door()
    platform_stone()
    ghost_platform()
    dust_mote()
    sky()
    layer("backgrounds/bg_far.png", (16, 21, 34, 255), 220, [(2, 40), (5, 25), (11, 10)])
    layer("backgrounds/bg_mid.png", (10, 13, 22, 255), 300, [(3, 30), (7, 15)], trees=14)
    layer("backgrounds/bg_near.png", (5, 6, 10, 255), 380, [(4, 20), (13, 8)], trees=8)
