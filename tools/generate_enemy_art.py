"""Enemy silhouette art: original vector designs, posed per frame, rendered to PNG.

Each creature is a small rig (body shape, limbs, head) drawn as SVG paths. Every frame is
written as an SVG source and rendered at 2x the in-game size to a transparent PNG.

Output:
  game/assets/source/enemies/<enemy>/<anim>_<nn>.svg   vector sources (Godot ignores this folder)
  game/assets/source/enemies/contact_sheet.png         every frame, as it looks in-game
  game/assets/sprites/enemies/<enemy>/<anim>_<nn>.png  frames (alpha = silhouette, red channel =
                                                       faint inner detail for the rim shader)
  game/assets/sprites/enemies/<enemy>/<enemy>_frames.tres  SpriteFrames
  game/assets/sprites/enemies/<enemy>/eyes.json        per-frame eye positions (px), copied
                                                       into each enemy scene's EnemyVisual

Usage:  python tools/generate_enemy_art.py [enemy ...]   (needs: pip install resvg_py pillow)
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont
from resvg_py import svg_to_bytes

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets")
SRC = os.path.join(ROOT, "source", "enemies")
OUT = os.path.join(ROOT, "sprites", "enemies")
RES = "res://game/assets/sprites/enemies/"
TAU = math.tau
BODY = "#000000"
DETAIL = "rgb(70,0,0)"   # red channel = inner detail lines (the shader tints them toward the rim colour)


# ── geometry ──────────────────────────────────────────────────────────────
def add(a, b): return (a[0] + b[0], a[1] + b[1])
def sub(a, b): return (a[0] - b[0], a[1] - b[1])
def mul(a, k): return (a[0] * k, a[1] * k)
def lerp(a, b, t): return a + (b - a) * t
def lerp2(a, b, t): return (lerp(a[0], b[0], t), lerp(a[1], b[1], t))
def length(v): return math.hypot(v[0], v[1])
def polar(deg, r): return (math.cos(math.radians(deg)) * r, math.sin(math.radians(deg)) * r)


def rot(p, deg, c=(0.0, 0.0)):
    a = math.radians(deg)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a))


def catmull(pts, closed, steps=8):
    """Resample a Catmull-Rom spline through pts."""
    n = len(pts)
    out = []
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if closed else pts[max(i - 1, 0)]
        p1, p2 = pts[i], pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed else pts[min(i + 2, n - 1)]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in (0, 1)))
    if not closed:
        out.append(pts[-1])
    return out


def poly(pts, fill=BODY):
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts) + " Z"
    return f'<path d="{d}" fill="{fill}"/>'


def blob(pts, fill=BODY, rag=0.0, seed=0, spikes=0.0, every=3):
    """Smooth closed shape through pts; `rag` roughens the outline, `spikes` adds tufts."""
    sm = catmull(pts, True, 10)
    if rag or spikes:
        r = random.Random(seed)
        out = []
        n = len(sm)
        for i, p in enumerate(sm):
            a, b = sm[i - 1], sm[(i + 1) % n]
            t = sub(b, a)
            nl = length(t) or 1.0
            nrm = (t[1] / nl, -t[0] / nl)   # outward for clockwise-on-screen outlines
            k = r.uniform(-rag, rag)
            if spikes and i % every == 0:
                k += spikes * r.uniform(0.5, 1.0)
            out.append(add(p, mul(nrm, k)))
        sm = out
    return poly(sm, fill)


def taper(pts, w0, w1, fill=BODY, cap=True, steps=8):
    """A limb / tendril: a smooth centre line with width going w0 -> w1."""
    c = catmull(pts, False, steps) if len(pts) > 2 else [lerp2(pts[0], pts[1], i / 12) for i in range(13)]
    seg = [length(sub(c[i + 1], c[i])) for i in range(len(c) - 1)]
    total = sum(seg) or 1.0
    left, right = [], []
    acc = 0.0
    for i, p in enumerate(c):
        a = c[max(i - 1, 0)]
        b = c[min(i + 1, len(c) - 1)]
        t = sub(b, a)
        nl = length(t) or 1.0
        nrm = (-t[1] / nl, t[0] / nl)
        w = lerp(w0, w1, acc / total) * 0.5
        left.append(add(p, mul(nrm, w)))
        right.append(sub(p, mul(nrm, w)))
        if i < len(seg):
            acc += seg[i]
    out = poly(left + right[::-1], fill)
    if cap:
        out += circle(c[0], w0 * 0.5, fill)
        if w1 > 3:
            out += circle(c[-1], w1 * 0.5, fill)
    return out


def circle(p, r, fill=BODY):
    return f'<circle cx="{p[0]:.1f}" cy="{p[1]:.1f}" r="{r:.1f}" fill="{fill}"/>'


def ellipse(c, rx, ry, deg, fill=BODY):
    return (f'<ellipse cx="{c[0]:.1f}" cy="{c[1]:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" '
            f'transform="rotate({deg:.1f} {c[0]:.1f} {c[1]:.1f})" fill="{fill}"/>')


def line(pts, w, color=DETAIL):
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in catmull(pts, False, 6))
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{w:.1f}" stroke-linecap="round"/>'


def chain(root, angles, lengths):
    pts = [root]
    for a, l in zip(angles, lengths):
        pts.append(add(pts[-1], polar(a, l)))
    return pts


def ik(hip, foot, l1, l2, bend):
    """Two-bone joint position; bend = +1 / -1 picks the side the knee goes."""
    d = sub(foot, hip)
    dist = max(min(length(d), l1 + l2 - 0.01), abs(l1 - l2) + 0.01)
    a = math.atan2(d[1], d[0])
    cos_k = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    k = math.acos(max(-1.0, min(1.0, cos_k)))
    ang = a - bend * k
    return add(hip, (math.cos(ang) * l1, math.sin(ang) * l1))


def claw(tip, deg, size, fill=BODY):
    """A small hooked claw at a limb tip."""
    return taper([tip, add(tip, polar(deg, size)), add(tip, polar(deg + 50, size * 1.5))], size * 0.45, 1.5, fill)


# ── CRAWLER — a low, many-legged burrower with a hooked jaw ────────────────
# Canvas 768 x 512, origin (384, 480) on the ground, facing right. 0.001875 m/px.
def crawler(anim, i, n):
    G = 480.0
    p = i / n
    s = dict(sx=0.0, arch=58.0, low=0.0, hr=0.0, he=0.0, jaw=0.15, tuck=0.0, curl=0.0,
             feet=[(0.0, 0.0)] * 6, ant=0.0, front_up=0.0)
    if anim == "idle":
        s.update(arch=58 + 5 * math.sin(TAU * p), jaw=0.12 + 0.1 * math.sin(TAU * p), ant=10 * math.sin(TAU * p * 2))
    elif anim == "crawl":
        feet = []
        for k in range(6):
            q = p + (0.0 if k in (0, 3, 4) else 0.5) + k * 0.04
            feet.append((-math.cos(TAU * q) * 34, max(0.0, math.sin(TAU * q)) * 30))
        s.update(feet=feet, arch=56 + 5 * math.cos(2 * TAU * p), sx=4 * math.sin(2 * TAU * p), ant=8 * math.sin(TAU * p))
    elif anim == "emerge":
        k = (i + 1) / n
        s.update(low=lerp(-30, 0, k), tuck=lerp(0.85, 0.0, k), arch=lerp(95, 58, k), hr=lerp(40, 0, k),
                 front_up=lerp(70, 0, max(0.0, k * 1.4 - 0.4)), jaw=lerp(0.6, 0.15, k), curl=lerp(0.8, 0, k))
    elif anim == "windup":
        k = (i + 1) / n
        s.update(sx=-22 * k, hr=34 * k, jaw=0.25 + 0.6 * k, arch=58 + 16 * k, front_up=46 * k, ant=-14 * k)
    elif anim == "lunge":
        k = [1.0, 0.75, 0.35][i]
        s.update(sx=48 * k, he=38 * k, hr=-12 * k, jaw=[1.0, 0.4, 0.1][i], arch=58 - 22 * k,
                 feet=[(18 * k, 0), (-34 * k, 0), (18 * k, 0), (-34 * k, 0), (-40 * k, 0), (-40 * k, 0)])
    elif anim == "flinch":
        k = [1.0, 0.7, 0.35][i]
        s.update(sx=-32 * k, arch=58 + 48 * k, hr=-26 * k, tuck=0.55 * k, curl=k, jaw=0.0, low=-10 * k, ant=-20 * k)

    els, det = [], []
    sx = s["sx"]
    # backbone: tail (left) to neck (right)
    spine = []
    for k in range(10):
        t = k / 9
        x = 170 + sx + t * (390 + s["he"] * 0.4)
        y = G - 72 - s["low"] - s["arch"] * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.8
        if t < 0.25:
            y -= s["curl"] * (0.25 - t) * 260
        spine.append((x, y))
    thick = lambda t: 10 + 46 * math.sin(math.pi * (0.12 + 0.8 * t)) ** 0.7
    neck = spine[-1]
    head = add(neck, (34 + s["he"], -s["hr"] - 6))

    # far legs first (drawn the same colour; they just read as more legs)
    hips_t = [0.36, 0.55, 0.74]
    spread = [-58, 6, 64]

    def leg(k, far):
        t = hips_t[k]
        idx = t * 9
        a, b = spine[int(idx)], spine[min(int(idx) + 1, 9)]
        hip = add(lerp2(a, b, idx - int(idx)), (10 if far else 0, thick(t) * 0.45))
        fdx, lift = s["feet"][k * 2 + (1 if far else 0)]
        foot = (hip[0] + spread[k] + (16 if far else 0) + fdx, G - lift)
        if k == 2 and s["front_up"]:
            foot = add(foot, (30, -s["front_up"]))
        foot = lerp2(foot, add(hip, (spread[k] * 0.3, 40)), s["tuck"])
        knee = ik(hip, foot, 105, 140, 1 if spread[k] >= 0 else -1)
        if knee[1] > hip[1]:
            knee = (knee[0], hip[1] - 30)
        return taper([hip, knee], 22, 15) + taper([knee, lerp2(knee, foot, 0.55), foot], 15, 3, cap=False) \
            + claw(foot, 200 if spread[k] < 0 else 330, 12)

    for k in range(3):
        els.append(leg(k, True))
    # tail whip
    tail_tip = add(spine[0], (-70, -20 - s["curl"] * 60))
    els.append(taper([spine[2], spine[0], add(spine[0], (-40, -6 - s["curl"] * 40)), tail_tip], 26, 3))
    # body segments
    for k in range(9):
        t = k / 9
        c = lerp2(spine[k], spine[k + 1], 0.5)
        ang = math.degrees(math.atan2(spine[k + 1][1] - spine[k][1], spine[k + 1][0] - spine[k][0]))
        r = thick(t)
        els.append(ellipse(c, 34, r, ang))
        # back spines
        top = add(c, rot((0, -r), ang))
        els.append(poly([add(top, rot((-14, 6), ang)), add(top, rot((-22, -16 - r * 0.25), ang)), add(top, rot((10, 4), ang))]))
        if 0 < k < 8:
            det.append(line([add(c, rot((-26, -r * 0.6), ang)), add(c, rot((-30, 0), ang)), add(c, rot((-26, r * 0.6), ang))], 3))
    # head + jaws
    hx, hy = head
    els.append(taper([lerp2(spine[7], neck, 0.5), neck, head], 52, 44))
    els.append(blob([(hx - 34, hy - 26), (hx + 8, hy - 34), (hx + 50, hy - 18), (hx + 64, hy + 4),
                     (hx + 28, hy + 26), (hx - 30, hy + 26)]))
    j = s["jaw"]
    els.append(taper([(hx + 46, hy - 6), (hx + 88, hy - 16 - j * 18), (hx + 112, hy + 2 - j * 28)], 16, 2))
    els.append(taper([(hx + 44, hy + 10), (hx + 84, hy + 22 + j * 16), (hx + 108, hy + 6 + j * 26)], 14, 2))
    # antennae
    a = s["ant"]
    els.append(taper([(hx + 4, hy - 26), (hx - 20, hy - 84 - a), (hx - 92, hy - 116 - a * 1.5)], 6, 1.5))
    els.append(taper([(hx + 14, hy - 28), (hx + 4, hy - 96 + a), (hx - 50, hy - 140 + a)], 5, 1.5))
    for k in range(3):
        els.append(leg(k, False))
    det.append(line([(hx - 20, hy - 18), (hx + 20, hy - 22), (hx + 46, hy - 8)], 3))
    eyes = [(hx + 24, hy - 6)]
    return els + det, eyes


# ── DROPPER — a hanging husk that unfolds four long limbs ──────────────────
# Canvas 512 x 512, origin (256, 256) at the body centre. 0.00195 m/px. Ground at y 435.
FOLDED = [(30, 95, 150), (50, 100, 165), (150, 85, 15), (130, 80, 30)]   # limb angles, hanging
SPREAD = [(-30, 70, 100), (-80, 110, 95), (210, 110, 85), (230, 70, 80)]     # reaching down, dropping
CROUCH = [(-40, 75, 95), (-75, 95, 92), (215, 85, 88), (225, 105, 92)]       # standing on the ground
ROOTS = [(26, -20), (14, -6), (-14, -6), (-26, -20)]


def dropper(anim, i, n):
    p = i / n
    pod_rot, pod_c, limbs, head_out, curl = 90.0, (256.0, 230.0), FOLDED, 0.0, 0.0
    if anim == "hang":
        w = math.sin(TAU * p)
        limbs = [(a + w * 6 * (1 if k % 2 else -1), b + w * 5, c) for k, (a, b, c) in enumerate(FOLDED)]
    elif anim == "unfold":
        k = (i + 1) / n
        pod_rot = lerp(90, 8, k)
        pod_c = (256, lerp(230, 250, k))
        limbs = [tuple(lerp(f, s_, k) for f, s_ in zip(fa, sa)) for fa, sa in zip(FOLDED, SPREAD)]
        head_out = k
    elif anim in ("land", "windup", "lunge"):
        pod_rot, pod_c, head_out, limbs = 4.0, (256, 268), 1.0, CROUCH
        if anim == "land":
            w = 1 if i == 0 else -1
            limbs = [(a + w * 7 * (1 if k < 2 else -1), b, c) for k, (a, b, c) in enumerate(CROUCH)]
        elif anim == "windup":
            k = (i + 1) / n
            pod_rot = -18 * k
            pod_c = (256 - 14 * k, 268 + 12 * k)
            limbs = [(-80 - 40 * k, 20 - 50 * k, 60 - 90 * k), (-75, 95 + 10 * k, 92), CROUCH[2],
                     (225 - 10 * k, 105 + 10 * k, 92)]
        else:
            k = [1.0, 0.7, 0.3][i]
            pod_rot = 14 * k
            pod_c = (256 + 34 * k, 262)
            limbs = [(-10 * k - 30 * (1 - k), 10 * k + 75 * (1 - k), 20 * k + 95 * (1 - k)),
                     (-40 * k - 75 * (1 - k), 50 * k + 95 * (1 - k), 70 * k + 92 * (1 - k)),
                     (190, 120, 100), (205, 110, 95)]
    elif anim == "flinch":
        k = [1.0, 0.7, 0.35][i]
        pod_rot, pod_c, head_out, curl = lerp(4, -30, k), (256 - 20 * k, 262), 1.0 - 0.6 * k, k
        limbs = [tuple(lerp(c_, f, k * 0.8) for c_, f in zip(ca, fa)) for ca, fa in zip(CROUCH, [(-140, -40, 40), (-120, 0, 60), (240, 40, 0), (260, 90, 10)])]

    els, det = [], []
    lens = (78, 96, 70)

    def limb(k):
        root = add(pod_c, rot(ROOTS[k], pod_rot - 90 if pod_rot > 45 else pod_rot))
        pts = chain(root, limbs[k], lens)
        return taper(pts[:2], 22, 16) + taper(pts[1:], 16, 4) + claw(pts[-1], limbs[k][2] + 40, 12)

    for k in (1, 2):           # far limbs
        els.append(limb(k))
    # pod: a husk with ridges and a frayed tail
    rx, ry = 64 - 8 * curl, 104 - 26 * curl
    pts = []
    for a in range(0, 360, 30):
        r = 1.0 + (0.18 if a in (150, 180, 210) else 0.0)
        pts.append(add(pod_c, rot((math.cos(math.radians(a)) * ry * r, math.sin(math.radians(a)) * rx), pod_rot)))
    els.append(blob(pts, rag=2.5, seed=3, spikes=9, every=5))
    tail = add(pod_c, rot((-ry - 10, 0), pod_rot))
    els.append(taper([tail, add(tail, rot((-30, 8), pod_rot)), add(tail, rot((-48, -4), pod_rot))], 18, 2))
    for r_ in (-0.45, 0.0, 0.45):
        a_ = add(pod_c, rot((ry * r_, -rx * 0.75), pod_rot))
        b_ = add(pod_c, rot((ry * r_ - 10, rx * 0.75), pod_rot))
        det.append(line([a_, add(lerp2(a_, b_, 0.5), rot((-6, 0), pod_rot)), b_], 3))
    # head at the front end of the husk
    hc = add(pod_c, rot((ry * (0.75 + 0.25 * head_out), 6 * head_out), pod_rot))
    els.append(ellipse(hc, 34, 26, pod_rot))
    fang = add(hc, rot((30, 14), pod_rot))
    els.append(taper([fang, add(fang, rot((16, 14), pod_rot)), add(fang, rot((8, 28), pod_rot))], 8, 1.5))
    for k in (0, 3):           # near limbs
        els.append(limb(k))
    eyes = [add(hc, rot((10, -6), pod_rot))]
    return els + det, eyes


# ── STALKER — a gaunt, hovering figure with long arms and a frayed cloak ───
# Canvas 640 x 1024, origin (320, 784) = the point it hovers on. 0.0025 m/px (400 px/m).
def stalker(anim, i, n):
    O = (320.0, 784.0)
    p = i / n
    lean, bob, arm_n, arm_f, fing, sway, head_f, shrink = 0.0, 0.0, (62, 92), (72, 96), 0.0, 0.0, 0.0, 0.0
    if anim == "idle":
        bob = 6 * math.sin(TAU * p)
        fing = 8 * math.sin(TAU * p)
        sway = 0.3 * math.sin(TAU * p)
    elif anim == "walk":
        w = math.sin(TAU * p)
        lean, bob, sway = 6 + 2 * w, 10 * math.cos(2 * TAU * p), 1.0 + 0.25 * w
        arm_n = (62 - 18 * w, 92 - 12 * w)
        arm_f = (72 + 18 * w, 96 + 12 * w)
    elif anim == "windup":
        k = (i + 1) / n
        lean, head_f = -12 * k, -10 * k
        arm_n = (lerp(62, -95, k), lerp(92, -40, k))
        arm_f = (lerp(72, -75, k), lerp(96, -20, k))
        fing = 30 * k
    elif anim == "lunge":
        k = [1.0, 0.75, 0.4][i]
        lean, head_f, sway = 24 * k, 30 * k, 1.4
        arm_n = (lerp(62, 10, k), lerp(92, 0, k))
        arm_f = (lerp(72, 25, k), lerp(96, 10, k))
        fing = 20 * k
    elif anim == "flinch":
        k = [1.0, 0.7, 0.35][i]
        lean, shrink, head_f = -18 * k, 0.25 * k, -20 * k
        arm_n = (lerp(62, 200, k), lerp(92, -60, k))
        arm_f = (lerp(72, 215, k), lerp(96, -40, k))
        fing = -20 * k

    pivot = (O[0], O[1] - 200)
    def B(x, y):   # body-space point (px from origin, y up) -> canvas, with lean
        return rot((O[0] + x, O[1] - y - bob), lean, pivot)

    els, det = [], []
    sh = 1.0 - shrink
    shoulder = B(14, 570 * sh + 10)
    # far arm behind the cloak
    def arm(base, angles, far):
        sp = add(shoulder, (-26 if far else 0, 6 if far else 0))
        pts = chain(sp, (angles[0] + lean, angles[1] + lean), (230, 230))
        out = taper([pts[0], pts[1]], 38, 24) + taper([pts[1], lerp2(pts[1], pts[2], 0.5), pts[2]], 24, 14)
        for f in (-28, 0, 26):
            a = angles[1] + lean + f + fing
            out += taper([pts[2], add(pts[2], polar(a, 70)), add(pts[2], polar(a + 30 + fing, 120))], 9, 1.5, cap=False)
        return out
    els.append(arm(shoulder, arm_f, True))
    # cloak / torso with frayed hem
    torso = [B(-80, 590 * sh), B(-20, 650 * sh), B(50, 600 * sh), B(66, 470 * sh), B(40, 330 * sh), B(26, 200),
             B(56, 40), B(30, -40), B(-10, -20), B(-60, -50), B(-70, 60), B(-50, 220), B(-74, 380 * sh), B(-104, 500 * sh)]
    els.append(blob(torso, rag=4, seed=11, spikes=14, every=4))
    # tendrils trailing from the hem (they stream back as it moves)
    for k in range(6):
        x0 = -64 + k * 22
        root = B(x0, 10 - (k % 2) * 30)
        drift = -40 * sway - k * 6
        wave = 22 * math.sin(TAU * (p + k * 0.17))
        tip_len = 200 + (k % 3) * 40
        els.append(taper([root, add(root, (drift * 0.4 + wave * 0.4, 80)), add(root, (drift + wave, tip_len * 0.7)),
                          add(root, (drift * 1.5 - wave * 0.5, tip_len))], 26, 2, cap=False))
    det.append(line([B(-40, 520 * sh), B(-30, 300), B(-40, 80)], 4))
    det.append(line([B(30, 500 * sh), B(40, 300), B(26, 90)], 4))
    # neck + head (long, forward, chin pointed)
    neck0 = B(30, 580 * sh)
    hc = add(B(96 + head_f, 600 * sh + 10), (0, 0))
    els.append(taper([neck0, lerp2(neck0, hc, 0.5), hc], 42, 30))
    hang = lean + 12
    els.append(blob([add(hc, rot(mul(q, 1.35), hang)) for q in [(-40, -30), (0, -46), (44, -28), (72, 4), (96, 34), (40, 34), (-34, 24)]]))
    els.append(arm(shoulder, arm_n, False))
    eyes = [add(hc, rot((46, -10), hang))]
    return els + det, eyes


# ── MITE — a bristling flier with two pairs of wings and a stinger ─────────
# Canvas 512 x 512, origin (256, 256) at the body centre. 0.0011 m/px.
def mite(anim, i, n):
    c = (256.0, 256.0)
    tilt, squash, wing, wing2, spike, sting = 0.0, 1.0, -60.0, -40.0, 18.0, 0.0
    if anim == "fly":
        flap = [-140, -95, -25, -95][i]
        wing, wing2 = flap, flap + 25
    elif anim == "dive":
        k = (i + 1) / n
        tilt, wing, wing2, sting = 35 * k, lerp(-90, -170, k), lerp(-70, -165, k), k
    elif anim == "flinch":
        squash, spike, wing, wing2, tilt = [0.78, 0.88][i], [34, 26][i], -90 - 30 * (1 - i), -60, -12

    els, det = [], []
    T = lambda q: add(c, rot(q, tilt))
    def wing_shape(root, deg, ln, w, far):
        tip = add(root, polar(deg, ln))
        mid = add(lerp2(root, tip, 0.5), polar(deg + 90, w))
        mid2 = add(lerp2(root, tip, 0.5), polar(deg - 90, w * 0.35))
        return blob([root, mid2, tip, mid])
    els.append(wing_shape(T((-10, -60)), wing2 + tilt, 150, 32, True))
    els.append(wing_shape(T((-30, -50)), wing2 + tilt + 30, 110, 26, True))
    # stinger
    s0 = T((-80, 30))
    tip = T((lerp(-150, 30, sting), lerp(80, 150, sting)))
    els.append(taper([s0, lerp2(s0, tip, 0.5), tip], 26, 2))
    # dangling legs
    for k in range(3):
        r0 = T((-20 + k * 26, 70))
        els.append(taper([r0, add(r0, (-14 + k * 4, 42)), add(r0, (-30 + k * 6, 60))], 7, 1.5))
    # bristling body
    pts = [T((math.cos(a) * 100 * (1.0 / squash) * (1.15 if math.cos(a) < 0 else 1.0), math.sin(a) * 92 * squash))
           for a in [k * TAU / 14 for k in range(14)]]
    els.append(blob(pts, rag=3, seed=7, spikes=spike, every=4))
    det.append(line([T((-60, -30)), T((-10, -10)), T((-50, 40))], 4))
    els.append(wing_shape(T((0, -64)), wing + tilt, 170, 36, False))
    eyes = [T((62, -6))]
    return els + det, eyes


# ── BIG SHADOW — a towering, knuckle-walking mass that trails smoke ────────
# Canvas 1280 x 1024, origin (693, 677). 0.0075 m/px (133.3 px/m). Ground at y 1010.
def big_shadow(anim, i, n):
    O = (693.0, 677.0)
    M = 133.333
    G = 1010.0
    p = i / n
    heave, jaw, sink = 0.0, 0.2, 0.0
    hand_n, hand_f = (2.9, -2.5), (1.7, -2.5)
    if anim == "idle":
        heave = 0.12 * math.sin(TAU * p)
        jaw = 0.18 + 0.1 * math.sin(TAU * p)
    elif anim == "run":
        heave = 0.22 * math.sin(2 * TAU * p)
        q1, q2 = TAU * p, TAU * (p + 0.5)
        hand_n = (2.6 + 1.5 * math.cos(q1), -2.5 + max(0.0, math.sin(q1)) * 1.7)
        hand_f = (1.6 + 1.5 * math.cos(q2), -2.5 + max(0.0, math.sin(q2)) * 1.7)
        jaw = 0.3 + 0.15 * math.sin(2 * TAU * p)
    elif anim == "strike":
        hand_n = [(2.0, 3.6), (0.8, 4.4), (4.0, 0.4), (4.1, -2.4)][i]
        jaw = [0.5, 0.8, 1.0, 0.4][i]
        heave = [0.2, 0.35, -0.2, -0.1][i]
    elif anim == "emerge":
        k = [0.15, 0.4, 0.7, 1.0][i]
        sink = (1.0 - k) * 4.2
        hand_n = (3.0, -2.5 + sink * 0.55)
        hand_f = (1.9, -2.5 + sink * 0.4)
        jaw = 0.6 * k

    def W(x, y, s=1.0):   # metres (y up) -> canvas
        return (O[0] + x * M, O[1] - (y - sink * s) * M)

    els, det = [], []
    # smoke ribbons trailing behind
    for k in range(7):
        root = W(-3.2 + k * 0.25, 2.8 - k * 0.7 + heave)
        wave = math.sin(TAU * (p + k * 0.13)) * 0.35
        pts = [root, W(-4.0 + k * 0.1, 2.9 - k * 0.72 + wave), W(-4.6, 3.1 - k * 0.8 - wave), W(-5.1, 3.2 - k * 0.82 + wave * 0.5)]
        els.append(taper(pts, 70 - k * 4, 3, cap=False))
    # far arm
    def arm(sh, hand, far):
        s = W(*sh)
        h = W(hand[0], hand[1], 0.0)
        e = ik(s, h, 3.1 * M, 3.3 * M, 1)
        out = taper([s, e], 110 if not far else 90, 70) + taper([e, lerp2(e, h, 0.5), h], 70, 40)
        ang = 0.0 if hand[1] < -2.2 else 30.0
        for f in (-30, -5, 20, 45):
            a = ang + f
            out += taper([h, add(h, polar(a, 70)), add(h, polar(a + 55, 120))], 26, 3, cap=False)
        return out
    els.append(arm((0.3, 3.0 + heave), hand_f, True))
    # the mass
    body = [W(-4.6, -0.6), W(-3.8, 2.6 + heave), W(-2.0, 4.3 + heave), W(-0.4, 4.9 + heave), W(1.2, 4.3 + heave),
            W(2.4, 3.2 + heave * 0.6), W(3.0, 2.2), W(2.4, 0.4), W(1.0, -0.9), W(-0.9, -1.1), W(-2.8, -1.6), W(-4.0, -1.4)]
    els.append(blob(body, rag=6, seed=21, spikes=26, every=3))
    # head under the brow: skull, long lower jaw with teeth
    hb = W(2.6, 1.6 + heave * 0.5)
    els.append(blob([add(hb, q) for q in [(-80, -70), (40, -90), (150, -40), (190, 10), (120, 40), (-40, 50), (-110, 0)]], rag=3, seed=5))
    jaw_hinge = add(hb, (-40, 30))
    jt = add(jaw_hinge, polar(8 + jaw * 26, 230))
    els.append(taper([jaw_hinge, lerp2(jaw_hinge, jt, 0.5), jt], 80, 14))
    for t in (0.35, 0.55, 0.75, 0.92):
        b = lerp2(jaw_hinge, jt, t)
        els.append(poly([add(b, (-12, -14)), add(b, (4, -14 - 30 * (1 - t * 0.5))), add(b, (14, -10))]))
    for t in (0.25, 0.5, 0.75):
        b = add(hb, (lerp(-10, 170, t), 34))
        els.append(poly([add(b, (-10, 0)), add(b, (2, 28)), add(b, (12, 0))]))
    det.append(line([W(-2.6, 3.4 + heave), W(-0.8, 3.9 + heave), W(1.0, 3.3 + heave)], 6))
    det.append(line([W(-3.0, 1.4), W(-1.2, 1.6), W(0.6, 1.0)], 6))
    els.append(arm((1.1, 2.9 + heave), hand_n, False))
    eyes = [add(hb, (120, -10)), add(hb, (40, -30)), add(hb, (150, -50))]
    if sink > 0:
        # cut everything below the ground line (it is coming up out of the earth)
        clip = f'<clipPath id="g"><rect x="0" y="0" width="1280" height="{G:.0f}"/></clipPath>'
        els = [clip, '<g clip-path="url(#g)">'] + els + det + ["</g>"]
        det = []
        eyes = [e for e in eyes]
    return els + det, eyes


def shade(anim, i, n):
    """The Shade: a hunched flying shadow (filled silhouette), two big tattered wings, a long
    smoke tail, a hooked head. Faces right. `anim` may end in "_torn": the near wing is ripped
    (a missing panel, shorter fingers, dangling shreds). The returned eye point is the head's
    eye spot (EyeAnchor); the cluster of eyes sits around it in the scene."""
    torn = anim.endswith("_torn")
    base = anim[:-5] if torn else anim
    O = (560.0, 470.0)
    p = i / n
    tilt, heave, flap, tuck, jaw, spread, sink = -4.0, 0.0, 0.0, 0.0, 0.15, 0.0, 0.0
    tail_len = 1.0
    if base == "fly":
        flap = [8, 0, -26, -56, -70, -54, -24, 4][i]            # down-stroke on frames 2..4
        heave = [6, 2, -6, -14, -10, -2, 6, 8][i]
        tilt = -6 + math.sin(TAU * p) * 3
    elif base == "glide":
        flap = -30 + math.sin(TAU * p) * 6
        heave = math.sin(TAU * p) * 6
        tilt = -3
    elif base == "swoop":
        tilt = [12, 26, 30, 14][i]
        tuck = [0.45, 0.85, 0.9, 0.5][i]
        flap = -20
        heave = [-6, 4, 10, 2][i]
        tail_len = 1.1
        jaw = [0.3, 0.7, 0.9, 0.5][i]
    elif base == "screech":
        tilt = -16 + math.sin(TAU * p) * 4
        flap = 12
        spread = 18
        jaw = [0.6, 1.0, 0.95, 0.55][i]
        heave = -8
    elif base == "emerge":
        # unfurls from a tucked, smoke-wrapped shape
        k = (i + 1) / n
        tuck = (1.0 - k) * 0.9
        flap = lerp(-40, 4, k)
        heave = (1.0 - k) * 30
        tilt = lerp(16, -4, k)
        tail_len = lerp(1.1, 1.0, k)
        jaw = lerp(0.8, 0.2, k)

    def S(pt):
        return add(add(O, (0.0, heave)), rot(pt, tilt))

    els, det = [], []

    # ── smoke tail: thick near the body, splitting into thin wisps ──
    for r in range(7):
        root = S((-150.0 - r * 6, 18.0 + (r - 3) * 9))
        w1 = math.sin(TAU * (p + r * 0.15)) * 26.0
        w2 = math.cos(TAU * (p + r * 0.21)) * 34.0
        L = (260.0 + (r % 3) * 40.0) * tail_len
        pts = [root, add(root, (-L * 0.3, w1 * 0.5 + (r - 3) * 6)), add(root, (-L * 0.62, w2 + (r - 3) * 14)),
               add(root, (-L, w1 * 0.8 + (r - 3) * 22))]
        els.append(taper(pts, 46.0 - r * 3.0, 1.5, cap=False))

    # ── wings ──
    def wing(shoulder, base_ang, far):
        # Angles are screen degrees (0 right, -90 up, 180 left). The arm sweeps up and back
        # from the shoulder; the fingers fan from the leading edge back toward the tail.
        sc = 0.84 if far else 1.0
        sh = S(shoulder)
        ang = base_ang + flap * (0.85 if far else 1.0)
        ang = lerp(ang, -172.0, tuck)
        elbow = add(sh, polar(ang, (120.0 + spread) * sc))
        wdir = ang - 28.0
        wrist = add(elbow, polar(wdir, (135.0 + spread) * sc * (1.0 - tuck * 0.4)))
        lens = [210.0, 200.0, 175.0, 140.0, 100.0]
        fan = [10.0, -20.0, -48.0, -76.0, -102.0]
        ripped = torn and not far
        tips = []
        for k_, (ln, sp) in enumerate(zip(lens, fan)):
            ln *= sc * (1.0 - tuck * 0.5)
            if ripped and k_ in (1, 2):
                ln *= 0.28                                  # broken fingers
            tips.append(add(wrist, polar(wdir + sp * (1.0 - tuck * 0.6), ln)))
        out = []
        out.append(taper([sh, elbow, wrist], 36.0 * sc, 18.0 * sc))
        for t_ in tips:
            out.append(taper([wrist, lerp2(wrist, t_, 0.6), t_], 13.0 * sc, 2.0))
        # membrane, its trailing edge scalloped and torn between the fingers
        mem = [sh, elbow, wrist]
        for k_, t_ in enumerate(tips):
            mem.append(t_)
            if k_ < len(tips) - 1:
                nxt = tips[k_ + 1]
                depth = 0.38 + 0.1 * math.sin(k_ * 1.7 + p * TAU)
                notch = lerp2(lerp2(t_, nxt, 0.5), wrist, depth)
                if ripped and k_ in (0, 1, 2):
                    notch = lerp2(wrist, elbow, 0.45)       # the torn panel: ripped back toward the elbow
                mem.append(notch)
        mem.append(S(add(shoulder, (-110.0, 50.0))))
        out.append(blob(mem, rag=5.0, seed=7 if far else 19, spikes=10.0, every=2))
        # tatters hanging off the trailing edge
        for k_ in range(len(tips) - 1):
            a_ = lerp2(tips[k_], tips[k_ + 1], 0.5)
            hang = 30.0 + 12.0 * math.sin(k_ + p * TAU * 2)
            out.append(taper([a_, add(a_, (-8, hang * 0.6)), add(a_, (-16 + 6 * math.sin(p * TAU + k_), hang))], 9.0 * sc, 1.0, cap=False))
        if ripped:
            # shreds dangling from the rip
            for k_ in range(3):
                a_ = lerp2(wrist, tips[1 + (k_ % 2)], 0.3 + k_ * 0.12)
                L_ = 70.0 + k_ * 25.0
                sway = math.sin(p * TAU + k_) * 18.0
                out.append(taper([a_, add(a_, (sway * 0.5 - 6, L_ * 0.5)), add(a_, (sway - 16, L_))], 12.0, 1.0, cap=False))
        out.append(claw(elbow, ang - 60.0, 20.0 * sc))
        return out

    els += wing((-20.0, -40.0), -108.0, True)

    # ── body: a hunched, furred torso ──
    body = [S(q) for q in [(150.0, -24.0), (110.0, -58.0), (40.0, -74.0), (-40.0, -66.0), (-120.0, -40.0),
                           (-175.0, -2.0), (-168.0, 40.0), (-110.0, 64.0), (-20.0, 70.0), (60.0, 52.0),
                           (120.0, 22.0)]]
    els.append(blob(body, rag=3.0, seed=42, spikes=18.0, every=2))
    # back spines / ragged ruff
    for k_ in range(6):
        b_ = S((60.0 - k_ * 38.0, -62.0 + abs(k_ - 1.5) * 6))
        els.append(taper([b_, add(b_, rot((-24.0, -38.0 - (k_ % 2) * 18), tilt))], 18.0, 1.5, cap=False))
    # talons tucked under
    for k_, x_ in enumerate((10.0, -40.0)):
        f0 = S((x_, 60.0))
        f1 = S((x_ + 22.0, 92.0))
        els.append(taper([f0, f1], 22.0, 12.0))
        for a_ in (40.0, 75.0, 110.0):
            els.append(taper([f1, add(f1, polar(a_ + tilt, 28.0))], 8.0, 1.5))

    # ── head: a heavy skull with a hooked beak-jaw ──
    hc = S((178.0, -28.0))
    els.append(blob([add(hc, rot(q, tilt)) for q in [(-50.0, -30.0), (0.0, -42.0), (46.0, -26.0), (66.0, -6.0),
                                                     (40.0, 14.0), (-20.0, 26.0), (-56.0, 10.0)]], rag=2.0, seed=5))
    beak_top = add(hc, rot((92.0, 6.0), tilt))
    els.append(taper([add(hc, rot((40.0, -14.0), tilt)), add(hc, rot((78.0, -6.0), tilt)), beak_top], 30.0, 3.0))
    jt = add(hc, rot((70.0 + jaw * 6, 26.0 + jaw * 34.0), tilt))
    els.append(taper([add(hc, rot((14.0, 12.0), tilt)), add(hc, rot((44.0, 20.0 + jaw * 14), tilt)), jt], 24.0, 3.0))
    if jaw > 0.3:
        for k_ in range(3):
            b_ = add(hc, rot((48.0 + k_ * 12.0, 6.0 + jaw * 6), tilt))
            els.append(poly([add(b_, (-4, 0)), add(b_, (0, 12 + jaw * 6)), add(b_, (4, 0))]))
    # horn-like crest swept back
    els.append(taper([add(hc, rot((-10.0, -36.0), tilt)), add(hc, rot((-70.0, -78.0), tilt)), add(hc, rot((-130.0, -86.0), tilt))], 22.0, 1.5))

    # a couple of faint inner lines only (the silhouette carries the shape)
    det.append(line([S((-120.0, 10.0)), S((-60.0, 34.0)), S((10.0, 30.0))], 3.0))

    els += wing((24.0, -22.0), -120.0, False)

    eye = add(hc, rot((34.0, -10.0), tilt))
    if sink > 0.02:
        clip_h = 768.0 * (1.0 - sink * 0.75)
        clip = f'<clipPath id="emg"><rect x="0" y="0" width="1024" height="{clip_h:.0f}"/></clipPath>'
        els = [clip, '<g clip-path="url(#emg)">'] + els + det + ["</g>"]
        det = []
    return els + det, [eye]


ENEMIES = {
    #  name         (canvas, origin, metres/px, draw fn, [(anim, frames, fps, loop)])
    "crawler": ((768, 512), (384, 480), 0.001875, crawler,
                [("idle", 4, 10, True), ("crawl", 6, 12, True), ("emerge", 4, 10, False),
                 ("windup", 3, 12, False), ("lunge", 3, 12, False), ("flinch", 3, 10, False)]),
    "dropper": ((512, 512), (256, 256), 0.00195, dropper,
                [("hang", 4, 10, True), ("unfold", 4, 12, False), ("land", 2, 10, True),
                 ("windup", 3, 12, False), ("lunge", 3, 12, False), ("flinch", 3, 10, False)]),
    "stalker": ((640, 1024), (320, 784), 0.0025, stalker,
                [("idle", 4, 10, True), ("walk", 6, 10, True), ("windup", 3, 12, False),
                 ("lunge", 3, 12, False), ("flinch", 3, 10, False)]),
    "mite": ((512, 512), (256, 256), 0.0011, mite,
             [("fly", 4, 12, True), ("dive", 3, 12, False), ("flinch", 2, 10, False)]),
    "big_shadow": ((1280, 1024), (693, 677), 0.0075, big_shadow,
                   [("idle", 4, 10, True), ("run", 8, 12, True), ("strike", 4, 12, True), ("emerge", 4, 10, False)]),
    "shade": ((1024, 768), (560, 470), 0.006, shade,
              [("fly", 8, 12, True), ("glide", 4, 10, True), ("swoop", 4, 12, False),
               ("screech", 4, 10, False), ("emerge", 4, 10, False),
               ("fly_torn", 8, 12, True), ("glide_torn", 4, 10, True), ("swoop_torn", 4, 12, False),
               ("screech_torn", 4, 10, False), ("emerge_torn", 4, 10, False)]),
}


def svg_doc(w, h, els):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">' + "".join(els) + "</svg>"


def frames_tres(name, anims):
    exts, lines = [], []
    for anim, n, fps, loop in anims:
        for i in range(n):
            exts.append(f'[ext_resource type="Texture2D" path="{RES}{name}/{anim}_{i:02d}.png" id="{anim}_{i}"]')
    lines.append(f'[gd_resource type="SpriteFrames" load_steps={len(exts) + 1} format=3]\n')
    lines += exts
    lines.append("\n[resource]")
    anim_strs = []
    for anim, n, fps, loop in anims:
        fr = ", ".join(f'{{\n"duration": 1.0,\n"texture": ExtResource("{anim}_{i}")\n}}' for i in range(n))
        anim_strs.append(f'{{\n"frames": [{fr}],\n"loop": {str(loop).lower()},\n"name": &"{anim}",\n"speed": {float(fps)}\n}}')
    lines.append("animations = [" + ", ".join(anim_strs) + "]")
    with open(os.path.join(OUT, name, f"{name}_frames.tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def in_game_look(img):
    """Approximates enemy_silhouette.gdshader: dark body, cool rim, faint detail lines."""
    a = img.getchannel("A")
    edge = Image.eval(a.filter(ImageFilter.MinFilter(7)), lambda v: 255 - v)
    body = Image.new("RGBA", img.size, (10, 10, 15, 255))
    rim = Image.new("RGBA", img.size, (77, 92, 118, 255))
    det = img.getchannel("R").point(lambda v: min(255, v * 2))
    out = Image.composite(rim, body, det)
    out = Image.composite(rim, out, Image.eval(edge, lambda v: int(v * 0.7)))
    out.putalpha(a)
    return out


def main(only=()):
    """Renders every enemy, or only the ones named on the command line (the contact sheet
    then reuses the other enemies' existing frames)."""
    sheet_rows = []
    for name, (size, origin, mpp, fn, anims) in ENEMIES.items():
        if only and name not in only:
            done = json.load(open(os.path.join(OUT, name, "eyes.json"), encoding="utf-8"))["eyes"]
            row = [(f"{anim} {i}", os.path.join(OUT, name, f"{anim}_{i:02d}.png"), done[anim][i])
                   for anim, n, fps, loop in anims for i in range(n)]
            sheet_rows.append((name, size, row))
            continue
        os.makedirs(os.path.join(SRC, name), exist_ok=True)
        os.makedirs(os.path.join(OUT, name), exist_ok=True)
        eyes = {}
        row = []
        for anim, n, fps, loop in anims:
            eyes[anim] = []
            for i in range(n):
                els, eye = fn(anim, i, n)
                svg = svg_doc(size[0], size[1], els)
                base = f"{anim}_{i:02d}"
                with open(os.path.join(SRC, name, base + ".svg"), "w", encoding="utf-8", newline="\n") as f:
                    f.write(svg)
                png = os.path.join(OUT, name, base + ".png")
                with open(png, "wb") as f:
                    f.write(bytes(svg_to_bytes(svg_string=svg)))
                eyes[anim].append([[round(e[0], 1), round(e[1], 1)] for e in eye])
                row.append((f"{anim} {i}", png, eye))
        with open(os.path.join(OUT, name, "eyes.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump({"canvas": size, "origin": origin, "pixel_size": mpp, "eyes": eyes}, f, indent=1)
        frames_tres(name, anims)
        sheet_rows.append((name, size, row))
        print(f"wrote {name}: {sum(a[1] for a in anims)} frames at {size[0]}x{size[1]}")
    contact_sheet(sheet_rows)


def contact_sheet(rows):
    cell_h = 190
    pad = 8
    widths = []
    for name, size, row in rows:
        cw = int(size[0] * cell_h / size[1])
        widths.append(len(row) * (cw + pad))
    W = min(max(widths), 3200)
    blocks = []
    for name, size, row in rows:
        cw = int(size[0] * cell_h / size[1])
        per = max(1, (W - pad) // (cw + pad))
        nrows = math.ceil(len(row) / per)
        blocks.append((name, size, row, cw, per, nrows))
    H = sum(40 + nr * (cell_h + 26) for *_, nr in blocks) + pad
    sheet = Image.new("RGB", (W, H), (58, 62, 70))
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("arial.ttf", 16)
        big = ImageFont.truetype("arialbd.ttf", 24)
    except OSError:
        font = big = ImageFont.load_default()
    y = pad
    for name, size, row, cw, per, nrows in blocks:
        d.text((pad, y + 6), name, fill=(235, 235, 235), font=big)
        y += 40
        for k, (label, png, eye) in enumerate(row):
            cx = pad + (k % per) * (cw + pad)
            cy = y + (k // per) * (cell_h + 26)
            d.rectangle((cx, cy, cx + cw, cy + cell_h), fill=(150, 156, 168))
            img = in_game_look(Image.open(png).convert("RGBA")).resize((cw, cell_h), Image.LANCZOS)
            sheet.paste(img, (cx, cy), img)
            sc = cell_h / size[1]
            for e in eye:
                ex, ey = cx + e[0] * sc, cy + e[1] * sc
                d.ellipse((ex - 3, ey - 2, ex + 3, ey + 2), fill=(255, 40, 30))
            d.text((cx + 2, cy + cell_h + 4), label, fill=(230, 230, 230), font=font)
        y += nrows * (cell_h + 26)
    path = os.path.join(SRC, "contact_sheet.png")
    sheet.save(path)
    print("wrote", path)


if __name__ == "__main__":
    import sys
    main(tuple(sys.argv[1:]))
