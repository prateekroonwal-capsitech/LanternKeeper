"""Generates the player boy: animation strips + the lantern arm + player_frames.tres.

The boy is an original silhouette character (big head, tousled hair, thin limbs)
drawn from a tiny 2D skeleton, so every pose stays on-model.

Output (game/assets/sprites/atlases/animations/player/):
  player_<anim>.png        — horizontal strip, FRAME x FRAME per frame, both arms drawn
  player_<anim>_carry.png  — same, without the near (lantern) arm; the game draws that
                             arm separately (player_arm.png) and aims it at the lantern
  player_arm.png           — the lantern arm, shoulder at the left edge
  player_frames.tres       — SpriteFrames resource used by Player.tscn → Body

Replace a strip with final art of the same size and frame count; the .tres keeps working.
Usage:  python tools/generate_player.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

FRAME = 192
GROUND = FRAME - 4          # feet rest on this image row
CENTER_X = FRAME // 2
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "sprites", "atlases",
                       "animations", "player")
RES_DIR = "res://game/assets/sprites/atlases/animations/player/"

# ── Proportions (px) ──────────────────────────────────────────────────────
THIGH, SHIN, FOOT = 29, 27, 11
TORSO = 42                   # hip → shoulder
NECK = 7
HEAD_R = 23
UPPER_ARM, FOREARM = 24, 23
ARM_LEN = UPPER_ARM + FOREARM

NEAR = (9, 9, 14, 255)       # near limbs + body
FAR = (24, 25, 34, 255)      # far limbs, a touch lighter so they read
EYE = (175, 185, 200, 255)

# ── Geometry helpers ──────────────────────────────────────────────────────

def limb_dir(angle_deg: float) -> tuple[float, float]:
    """Angle from straight down; positive swings forward (+x). Returns (dx, dy) with y up."""
    a = math.radians(angle_deg)
    return math.sin(a), -math.cos(a)


def add(p, d, length):
    return p[0] + d[0] * length, p[1] + d[1] * length


def solve(pose: dict) -> dict:
    """Builds joint positions (y up, hip at origin) from a pose."""
    lean = math.radians(pose.get("lean", 0.0))
    up = (math.sin(lean), math.cos(lean))
    hip = (0.0, 0.0)
    shoulder = add(hip, up, TORSO)
    head_tilt = math.radians(pose.get("head", 0.0)) + lean
    head_up = (math.sin(head_tilt), math.cos(head_tilt))
    head = add(shoulder, head_up, NECK + HEAD_R)
    legs = []
    for thigh_a, knee in pose["legs"]:
        k = add(hip, limb_dir(thigh_a), THIGH)
        shin_a = thigh_a - knee
        a = add(k, limb_dir(shin_a), SHIN)
        foot_a = shin_a + 90 + pose.get("toe", 0.0)
        f = add(a, limb_dir(min(max(foot_a, 60), 120)), FOOT)
        legs.append((hip, k, a, f))
    arms = []
    for upper_a, elbow in pose["arms"]:
        e = add(shoulder, limb_dir(upper_a), UPPER_ARM)
        h = add(e, limb_dir(upper_a + elbow), FOREARM)
        arms.append((shoulder, e, h))
    return {"hip": hip, "shoulder": shoulder, "head": head, "head_up": head_up, "up": up,
            "legs": legs, "arms": arms}


def ground_shift(j: dict, airborne: float) -> float:
    """Vertical offset that puts the lowest point on the ground (+ airborne lift)."""
    pts = [p for leg in j["legs"] for p in leg] + [p for arm in j["arms"] for p in arm]
    pts += [j["hip"], j["shoulder"], (j["head"][0], j["head"][1] - HEAD_R)]
    lowest = min(p[1] for p in pts)
    return -lowest + 3 + airborne


def to_img(p, shift):
    return CENTER_X + p[0], GROUND - (p[1] + shift)


def capsule(d: ImageDraw.ImageDraw, a, b, w, color):
    d.line((a, b), fill=color, width=int(w))
    r = w / 2
    for c in (a, b):
        d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=color)


def draw_leg(d, leg, shift, color):
    hip, k, a, f = (to_img(p, shift) for p in leg)
    capsule(d, hip, k, 14, color)
    capsule(d, k, a, 11, color)
    capsule(d, a, f, 8, color)


def draw_arm(d, arm, shift, color):
    s, e, h = (to_img(p, shift) for p in arm)
    capsule(d, s, e, 10, color)
    capsule(d, e, h, 9, color)
    d.ellipse((h[0] - 5, h[1] - 5, h[0] + 5, h[1] + 5), fill=color)


def draw_body(d, j, shift):
    hip, sh = to_img(j["hip"], shift), to_img(j["shoulder"], shift)
    ux, uy = j["up"]
    nx, ny = uy, ux                     # normal to the spine, in image space (y down)
    hw, sw = 12, 14
    poly = [(hip[0] - nx * hw, hip[1] - ny * hw), (hip[0] + nx * hw, hip[1] + ny * hw),
            (sh[0] + nx * sw, sh[1] + ny * sw), (sh[0] - nx * sw, sh[1] - ny * sw)]
    d.polygon(poly, fill=NEAR)
    d.ellipse((sh[0] - sw, sh[1] - sw, sh[0] + sw, sh[1] + sw), fill=NEAR)
    d.ellipse((hip[0] - hw - 1, hip[1] - hw - 1, hip[0] + hw + 1, hip[1] + hw + 1), fill=NEAR)
    # neck
    head = to_img(j["head"], shift)
    capsule(d, sh, head, 9, NEAR)


def draw_head(d, j, shift, blink=False):
    c = to_img(j["head"], shift)
    r = HEAD_R
    d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=NEAR)
    hx, hy = j["head_up"]
    # tousled hair: a few soft tufts swept up and back (away from the facing direction)
    up_img = (hx, -hy)
    for theta, length, spread in ((-8, 7, 0.32), (18, 10, 0.34), (45, 12, 0.32), (72, 11, 0.30),
                                  (100, 8, 0.28), (128, 5, 0.26)):
        phi = -math.radians(theta)
        dx = up_img[0] * math.cos(phi) - up_img[1] * math.sin(phi)
        dy = up_img[0] * math.sin(phi) + up_img[1] * math.cos(phi)
        ang = math.atan2(dy, dx)
        base_l = (c[0] + math.cos(ang - spread) * r * 0.92, c[1] + math.sin(ang - spread) * r * 0.92)
        base_r = (c[0] + math.cos(ang + spread) * r * 0.92, c[1] + math.sin(ang + spread) * r * 0.92)
        sweep = ang - 0.35
        tip = (c[0] + math.cos(sweep) * (r + length), c[1] + math.sin(sweep) * (r + length))
        d.polygon([base_l, tip, base_r], fill=NEAR)
    # one pale eye, toward the front of the face
    ex = c[0] + hx * 2 + hy * 11
    ey = c[1] - hy * 2 + hx * 11 - 1
    if blink:
        d.line((ex - 3, ey, ex + 3, ey), fill=EYE, width=1)
    else:
        d.ellipse((ex - 2.5, ey - 2.5, ex + 2.5, ey + 2.5), fill=EYE)


def render(pose: dict, carry: bool) -> Image.Image:
    img = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    j = solve(pose)
    shift = ground_shift(j, pose.get("air", 0.0))
    draw_arm(d, j["arms"][0], shift, FAR)
    draw_leg(d, j["legs"][0], shift, FAR)
    draw_leg(d, j["legs"][1], shift, NEAR)
    draw_body(d, j, shift)
    draw_head(d, j, shift, pose.get("blink", False))
    if not carry:
        draw_arm(d, j["arms"][1], shift, NEAR)
    # faint cold rim so the silhouette reads on near-black backgrounds
    alpha = img.split()[3]
    edge = alpha.filter(ImageFilter.FIND_EDGES).point(lambda a: 110 if a > 0 else 0)
    rim = Image.new("RGBA", img.size, (70, 75, 100, 0))
    rim.putalpha(edge)
    return Image.alpha_composite(rim, img)


# ── Animations ────────────────────────────────────────────────────────────
TAU = math.tau


def idle(n=6):
    out = []
    for i in range(n):
        t = i / n
        b = math.sin(TAU * t)
        out.append({"lean": 1 + b, "head": -1 + b, "legs": [(-6, 2), (6, 3)],
                    "arms": [(-4 + b * 2, 12), (6 - b * 2, 14)], "blink": i == 4, "air": 0})
    return out


def gait(n, amp, knee_base, knee_kick, arm_amp, elbow, lean, bob):
    out = []
    for i in range(n):
        t = TAU * i / n
        frames_legs = []
        for side in (0, 1):
            ph = t + side * math.pi
            thigh = amp * math.sin(ph)
            knee = knee_base + knee_kick * max(0.0, math.cos(ph))
            frames_legs.append((thigh, knee))
        arms = [(arm_amp * math.sin(t), elbow), (arm_amp * math.sin(t + math.pi), elbow)]
        out.append({"lean": lean, "head": -lean * 0.5, "legs": frames_legs, "arms": arms,
                    "air": bob * max(0.0, math.sin(2 * t))})
    return out


def walk():
    return gait(8, amp=24, knee_base=6, knee_kick=34, arm_amp=22, elbow=18, lean=4, bob=2)


def run():
    return gait(8, amp=40, knee_base=18, knee_kick=78, arm_amp=48, elbow=78, lean=14, bob=6)


def jump():
    return [
        {"lean": 10, "legs": [(30, 60), (40, 70)], "arms": [(-30, 20), (-25, 20)], "air": 0},
        {"lean": 6, "legs": [(-18, 25), (62, 78)], "arms": [(120, 30), (95, 40)], "air": 4},
        {"lean": 2, "legs": [(30, 70), (48, 80)], "arms": [(140, 20), (125, 25)], "air": 6},
    ]


def fall():
    return [
        {"lean": -4, "legs": [(12, 30), (-10, 22)], "arms": [(150, 15), (125, 25)], "air": 2},
        {"lean": -6, "legs": [(6, 24), (-16, 30)], "arms": [(160, 25), (135, 15)], "air": 2},
    ]


def land():
    return [
        {"lean": 22, "legs": [(45, 95), (55, 100)], "arms": [(40, 30), (55, 30)], "air": 0},
        {"lean": 12, "legs": [(30, 60), (38, 65)], "arms": [(20, 25), (30, 25)], "air": 0},
        {"lean": 5, "legs": [(10, 20), (14, 22)], "arms": [(5, 15), (10, 15)], "air": 0},
    ]


def place():
    return [
        {"lean": 20, "legs": [(30, 55), (40, 60)], "arms": [(10, 20), (35, 15)]},
        {"lean": 40, "legs": [(55, 100), (60, 105)], "arms": [(20, 20), (20, 5)]},
        {"lean": 40, "legs": [(55, 100), (60, 105)], "arms": [(20, 20), (15, 0)]},
        {"lean": 15, "legs": [(25, 45), (30, 50)], "arms": [(5, 15), (10, 15)]},
    ]


def death():
    return [
        {"lean": -14, "head": -10, "legs": [(-8, 6), (10, 10)], "arms": [(130, 20), (110, 25)]},
        {"lean": 10, "head": 15, "legs": [(30, 70), (40, 80)], "arms": [(40, 30), (30, 30)]},
        {"lean": 25, "head": 25, "legs": [(80, 150), (85, 155)], "arms": [(30, 20), (20, 20)]},
        {"lean": 55, "head": 25, "legs": [(85, 155), (90, 160)], "arms": [(55, 10), (45, 10)]},
        {"lean": 82, "head": 10, "legs": [(90, 120), (95, 130)], "arms": [(90, 10), (80, 5)]},
        {"lean": 88, "head": 6, "legs": [(92, 110), (96, 120)], "arms": [(95, 5), (85, 5)]},
    ]


# name: (poses, fps, loop, has_carry_variant)
ANIMS = {
    "idle": (idle(), 6.0, True, True),
    "walk": (walk(), 10.0, True, True),
    "run": (run(), 14.0, True, True),
    "jump": (jump(), 10.0, False, True),
    "fall": (fall(), 6.0, True, True),
    "land": (land(), 14.0, False, True),
    "place": (place(), 14.0, False, False),
    "death": (death(), 10.0, False, False),
}


def strip(poses, carry: bool) -> Image.Image:
    img = Image.new("RGBA", (FRAME * len(poses), FRAME), (0, 0, 0, 0))
    for i, p in enumerate(poses):
        img.paste(render(p, carry), (i * FRAME, 0))
    return img


def arm_sprite() -> Image.Image:
    """Straight lantern arm: shoulder at x=0, hand at x=ARM_LEN, vertically centred."""
    w, h = 64, 20
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    capsule(d, (5, h / 2), (ARM_LEN, h / 2), 8, NEAR)
    d.ellipse((ARM_LEN - 5, h / 2 - 6, ARM_LEN + 7, h / 2 + 6), fill=NEAR)   # fist
    return img


def write_frames(entries: list[tuple[str, str, int, float, bool]]) -> None:
    ext, subs, anims = [], [], []
    for idx, (anim, file, count, fps, loop) in enumerate(entries, start=1):
        ext.append(f'[ext_resource type="Texture2D" path="{RES_DIR}{file}" id="{idx}_{anim}"]')
        frames = []
        for f in range(count):
            sid = f"AtlasTexture_{anim}_{f}"
            subs.append(f'[sub_resource type="AtlasTexture" id="{sid}"]\n'
                        f'atlas = ExtResource("{idx}_{anim}")\n'
                        f'region = Rect2({f * FRAME}, 0, {FRAME}, {FRAME})\n')
            frames.append(f'{{\n"duration": 1.0,\n"texture": SubResource("{sid}")\n}}')
        anims.append('{\n"frames": [' + ", ".join(frames) + '],\n'
                     f'"loop": {"true" if loop else "false"},\n'
                     f'"name": &"{anim}",\n"speed": {fps}\n}}')
    text = '[gd_resource type="SpriteFrames" format=3]\n\n' + "\n".join(ext) + "\n\n" + \
           "\n".join(subs) + "\n[resource]\nanimations = [" + ", ".join(anims) + "]\n"
    with open(os.path.join(OUT_DIR, "player_frames.tres"), "w", newline="\n") as fh:
        fh.write(text)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    entries = []
    for name, (poses, fps, loop, has_carry) in ANIMS.items():
        variants = [(name, False)] + ([(name + "_carry", True)] if has_carry else [])
        for anim, carry in variants:
            file = f"player_{anim}.png"
            strip(poses, carry).save(os.path.join(OUT_DIR, file))
            entries.append((anim, file, len(poses), fps, loop))
            print("wrote", file, f"{len(poses)} frames")
    arm_sprite().save(os.path.join(OUT_DIR, "player_arm.png"))
    write_frames(entries)
    j = solve(idle()[0])
    shift = ground_shift(j, 0)
    print("idle shoulder (px above feet, fwd):", round(j["shoulder"][1] + shift, 1), round(j["shoulder"][0], 1))
    print("arm length px:", ARM_LEN)


if __name__ == "__main__":
    main()
