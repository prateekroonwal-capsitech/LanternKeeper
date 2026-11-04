"""Generates the player child: animation strips + the lantern arm + player_frames.tres.

An original, pure-black silhouette child — round head, thin body and limbs, two small
glowing eyes — drawn from a small 2D skeleton so every pose stays on-model.

Output (game/assets/sprites/player/):
  player_<anim>.png        horizontal strip of FRAME x FRAME frames
  player_<anim>_carry.png  same poses with the near arm holding the lantern: short, bent,
                           the hand always at HAND_CARRY (raise_* frames: HAND_RAISE).
                           The game hangs the lantern's handle on Player/HandMarker,
                           which sits exactly at that hand point.
  player_frames.tres       SpriteFrames used by Player.tscn → Body

Replace any strip with final art of the same size and frame count.
Usage:  python tools/generate_player.py
"""
import math
import os

from PIL import Image, ImageDraw

FRAME = 192
GROUND = FRAME - 4
CENTER_X = FRAME // 2
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "sprites", "player")
RES_DIR = "res://game/assets/sprites/player/"

# ── Proportions (px) — a small child ──────────────────────────────────────
THIGH, SHIN, FOOT = 26, 25, 8
TORSO = 36
NECK = 5
HEAD_R = 19
UPPER_ARM, FOREARM = 20, 19
ARM_LEN = UPPER_ARM + FOREARM

# Fixed hand points while carrying, in px: (forward of centre, above the frame bottom).
# Player.gd mirrors these into HandMarker (x 0.009 m per px).
HAND_CARRY = (15, 66)
HAND_RAISE = (16, 128)
# Hand points of the new poses, same units. Player.gd holds these in metres.
HAND_REACH = (44, 47)      # place / pickup: at the reach frame the hand is at the lantern's rest height
HAND_FEET = (10, 47)       # place_feet: the same bend, set down close in
HAND_HOOK = (34, 118)      # hook_reach: standing, arm up to a hook
HAND_PUSH = (36, 70)       # push: palms on the box
HAND_ROPE = (4, 152)       # rope_*: hands above the head, on the rope
BEND_PATH = [HAND_CARRY, (26, 54), HAND_REACH, (26, 54), HAND_CARRY]
FEET_PATH = [HAND_CARRY, (12, 54), HAND_FEET, (12, 54), HAND_CARRY]
HOOK_PATH = [HAND_CARRY, (22, 92), HAND_HOOK, (22, 92), HAND_CARRY]

BLACK = (0, 0, 0, 255)
EYE = (255, 255, 255, 255)
TAU = math.tau


def limb_dir(angle_deg):
    a = math.radians(angle_deg)
    return math.sin(a), -math.cos(a)


def add(p, d, length):
    return p[0] + d[0] * length, p[1] + d[1] * length


def solve(pose):
    lean = math.radians(pose.get("lean", 0.0))
    up = (math.sin(lean), math.cos(lean))
    hip = (0.0, 0.0)
    shoulder = add(hip, up, TORSO)
    tilt = math.radians(pose.get("head", 0.0)) + lean
    head_up = (math.sin(tilt), math.cos(tilt))
    head = add(shoulder, head_up, NECK + HEAD_R)
    legs = []
    for thigh_a, knee in pose["legs"]:
        k = add(hip, limb_dir(thigh_a), THIGH)
        shin_a = thigh_a - knee
        a = add(k, limb_dir(shin_a), SHIN)
        f = add(a, limb_dir(min(max(shin_a + 90, 60), 120)), FOOT)
        legs.append((hip, k, a, f))
    arms = []
    for upper_a, elbow in pose["arms"]:
        e = add(shoulder, limb_dir(upper_a), UPPER_ARM)
        h = add(e, limb_dir(upper_a + elbow), FOREARM)
        arms.append((shoulder, e, h))
    return {"hip": hip, "shoulder": shoulder, "head": head, "head_up": head_up, "up": up,
            "legs": legs, "arms": arms}


def ground_shift(j, air):
    pts = [p for leg in j["legs"] for p in leg] + [p for arm in j["arms"] for p in arm]
    pts += [j["hip"], j["shoulder"], (j["head"][0], j["head"][1] - HEAD_R)]
    return -min(p[1] for p in pts) + 3 + air


def to_img(p, shift):
    return CENTER_X + p[0], GROUND - (p[1] + shift)


def capsule(d, a, b, w):
    d.line((a, b), fill=BLACK, width=int(w))
    r = w / 2
    for c in (a, b):
        d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=BLACK)


def draw_leg(d, leg, s):
    hip, k, a, f = (to_img(p, s) for p in leg)
    capsule(d, hip, k, 9)
    capsule(d, k, a, 8)
    capsule(d, a, f, 6)


def draw_arm(d, arm, s):
    sh, e, h = (to_img(p, s) for p in arm)
    capsule(d, sh, e, 7)
    capsule(d, e, h, 6)
    d.ellipse((h[0] - 3.5, h[1] - 3.5, h[0] + 3.5, h[1] + 3.5), fill=BLACK)


def draw_body(d, j, s):
    hip, sh = to_img(j["hip"], s), to_img(j["shoulder"], s)
    ux, uy = j["up"]
    nx, ny = uy, ux
    hw, sw = 8, 9
    d.polygon([(hip[0] - nx * hw, hip[1] - ny * hw), (hip[0] + nx * hw, hip[1] + ny * hw),
               (sh[0] + nx * sw, sh[1] + ny * sw), (sh[0] - nx * sw, sh[1] - ny * sw)], fill=BLACK)
    d.ellipse((sh[0] - sw, sh[1] - sw, sh[0] + sw, sh[1] + sw), fill=BLACK)
    d.ellipse((hip[0] - hw, hip[1] - hw, hip[0] + hw, hip[1] + hw), fill=BLACK)
    capsule(d, sh, to_img(j["head"], s), 7)


def draw_head(d, j, s, blink=False):
    c = to_img(j["head"], s)
    r = HEAD_R
    d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=BLACK)
    hx, hy = j["head_up"]
    fx, fy = hy, hx                       # "forward" direction in image space
    for off in (5.5, 13.0):               # two small eyes toward the front of the face
        ex = c[0] + fx * off - hx * 1.5
        ey = c[1] + fy * off - hy * -1.5 - 1
        if blink:
            d.line((ex - 2.5, ey, ex + 2.5, ey), fill=EYE, width=1)
        else:
            d.ellipse((ex - 2.4, ey - 2.4, ex + 2.4, ey + 2.4), fill=EYE)


def draw_carry_arm(d, j, s, hand_px, stretch=False):
    """Near arm reaching a fixed hand point (two-bone IK, elbow bent back and down).
    `stretch`: a point past the arm's length (hands above the head on a rope) pulls it straight."""
    sh = to_img(j["shoulder"], s)
    tx, ty = CENTER_X + hand_px[0], FRAME - hand_px[1]
    dx, dy = tx - sh[0], ty - sh[1]
    if stretch and math.hypot(dx, dy) > UPPER_ARM + FOREARM:
        capsule(d, sh, (tx, ty), 7)
        d.ellipse((tx - 3.5, ty - 3.5, tx + 3.5, ty + 3.5), fill=BLACK)
        return
    dist = min(math.hypot(dx, dy), UPPER_ARM + FOREARM - 0.5)
    base = math.atan2(dy, dx)
    cos_a = (UPPER_ARM ** 2 + dist ** 2 - FOREARM ** 2) / (2 * UPPER_ARM * dist)
    a = math.acos(max(-1.0, min(1.0, cos_a)))
    # Two elbow solutions; pick the one further back (smaller x) so the arm bends naturally.
    e1 = (sh[0] + math.cos(base + a) * UPPER_ARM, sh[1] + math.sin(base + a) * UPPER_ARM)
    e2 = (sh[0] + math.cos(base - a) * UPPER_ARM, sh[1] + math.sin(base - a) * UPPER_ARM)
    elbow = e1 if e1[0] < e2[0] else e2
    hand = (sh[0] + math.cos(base) * dist, sh[1] + math.sin(base) * dist)
    capsule(d, sh, elbow, 7)
    capsule(d, elbow, hand, 6)
    d.ellipse((hand[0] - 3.5, hand[1] - 3.5, hand[0] + 3.5, hand[1] + 3.5), fill=BLACK)


def render(pose, carry):
    img = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    j = solve(pose)
    s = ground_shift(j, pose.get("air", 0.0))
    if "far_hand" in pose:
        draw_carry_arm(d, j, s, pose["far_hand"], pose.get("stretch", False))
    else:
        draw_arm(d, j["arms"][0], s)
    draw_leg(d, j["legs"][0], s)
    draw_leg(d, j["legs"][1], s)
    draw_body(d, j, s)
    draw_head(d, j, s, pose.get("blink", False))
    if not carry and "near_hand" in pose:
        draw_carry_arm(d, j, s, pose["near_hand"], pose.get("stretch", False))
    elif not carry:
        draw_arm(d, j["arms"][1], s)
    else:
        draw_carry_arm(d, j, s, HAND_RAISE if pose.get("hand") == "raise" else HAND_CARRY)
    alpha = pose.get("alpha", 1.0)
    if alpha < 1.0:
        a = img.split()[3].point(lambda v: int(v * alpha))
        img.putalpha(a)
        wd = ImageDraw.Draw(img)
        for i in range(10):                # wisps gathering back into the body
            ang = i * TAU / 10 + alpha * 3
            rad = 60 * (1.0 - alpha) + 8
            px = CENTER_X + math.cos(ang) * rad
            py = GROUND - 70 + math.sin(ang) * rad * 1.3
            wd.ellipse((px - 2, py - 2, px + 2, py + 2), fill=(10, 10, 14, int(220 * (1 - alpha) + 35)))
    return img


# ── Poses ─────────────────────────────────────────────────────────────────
def idle(n=6):
    out = []
    for i in range(n):
        b = math.sin(TAU * i / n)
        out.append({"lean": 1 + b * 0.8, "head": -1 + b, "legs": [(-5, 2), (5, 3)],
                    "arms": [(-3 + b * 2, 10), (4 - b * 2, 12)], "blink": i == 4})
    return out


def gait(n, amp, knee_base, knee_kick, arm_amp, elbow, lean, bob, reverse=False, arms=None):
    out = []
    for i in range(n):
        t = TAU * i / n * (-1 if reverse else 1)
        legs = []
        for side in (0, 1):
            ph = t + side * math.pi
            legs.append((amp * math.sin(ph), knee_base + knee_kick * max(0.0, math.cos(ph))))
        arm_pose = arms or [(arm_amp * math.sin(t), elbow), (arm_amp * math.sin(t + math.pi), elbow)]
        out.append({"lean": lean, "head": -lean * 0.4, "legs": legs, "arms": arm_pose,
                    "air": bob * max(0.0, math.sin(2 * t))})
    return out


def bend(path):
    """Crouch, arm forward and down to the reach frame (index 2), then stand."""
    crouch = [(14, (20, 38), (26, 44)), (26, (32, 60), (38, 66)), (38, (42, 78), (48, 84)),
              (26, (32, 60), (38, 66)), (14, (20, 38), (26, 44))]
    return [{"lean": lean, "head": -lean * 0.3, "legs": [a, b], "arms": [(-12, 14), (0, 0)],
             "near_hand": hand} for (lean, a, b), hand in zip(crouch, path)]


def reach_up(path):
    """Standing: only the arm moves, up to a hook and back."""
    return [{"lean": -2, "head": -6 - i * 2 if i < 3 else -6, "legs": [(-5, 2), (5, 3)],
             "arms": [(-4, 12), (0, 0)], "near_hand": hand} for i, hand in enumerate(path)]


def rope(near, far, legs, lean=0, head=-8):
    return {"lean": lean, "head": head, "legs": legs, "arms": [(0, 0), (0, 0)],
            "near_hand": near, "far_hand": far, "stretch": True}


LOW = (HAND_ROPE[0], HAND_ROPE[1] - 26)      # the lower hand while climbing
TOGETHER = [(2, 5), (5, 7)]
ROPE_CLIMB = [rope(HAND_ROPE, LOW, [(16, 34), (-2, 4)]), rope(HAND_ROPE, HAND_ROPE, TOGETHER),
              rope(LOW, HAND_ROPE, [(-2, 4), (16, 34)]), rope(HAND_ROPE, HAND_ROPE, TOGETHER)]

ANIMS = {
    # name: (poses, fps, loop, has_carry_variant, carry_only)
    "idle": (idle(), 6.0, True, True, False),
    "walk": (gait(8, 22, 6, 30, 18, 14, 3, 1.5), 9.0, True, True, False),
    "run": (gait(8, 34, 16, 66, 40, 70, 11, 4), 13.0, True, True, False),
    "jump_start": ([{"lean": 8, "legs": [(22, 40), (30, 48)], "arms": [(-20, 15), (-15, 15)]},
                    {"lean": 12, "legs": [(34, 66), (40, 72)], "arms": [(-35, 20), (-30, 20)]}],
                   16.0, False, True, False),
    "jump_rise": ([{"lean": 6, "legs": [(-14, 22), (55, 72)], "arms": [(110, 25), (90, 30)], "air": 3},
                   {"lean": 4, "legs": [(-10, 26), (60, 80)], "arms": [(120, 20), (100, 25)], "air": 4}],
                  8.0, True, True, False),
    "fall": ([{"lean": -3, "legs": [(10, 26), (-8, 20)], "arms": [(140, 15), (115, 22)], "air": 2},
              {"lean": -5, "legs": [(5, 22), (-14, 28)], "arms": [(150, 22), (125, 14)], "air": 2}],
             6.0, True, True, False),
    "land": ([{"lean": 18, "legs": [(40, 85), (48, 90)], "arms": [(35, 25), (45, 25)]},
              {"lean": 10, "legs": [(26, 52), (32, 56)], "arms": [(18, 20), (25, 20)]},
              {"lean": 4, "legs": [(8, 16), (12, 18)], "arms": [(4, 12), (8, 12)]}],
             14.0, False, True, False),
    "push": ([dict(p, near_hand=HAND_PUSH, far_hand=HAND_PUSH)
              for p in gait(6, 18, 12, 24, 0, 0, 22, 0.5, arms=[(75, 10), (82, 8)])], 7.0, True, True, False),
    "pull": (gait(6, 16, 10, 20, 0, 0, -12, 0.5, reverse=True, arms=[(68, 6), (74, 4)]), 6.0, True, False, False),
    "place": (bend(BEND_PATH), 14.0, False, False, False),
    "place_feet": (bend(FEET_PATH), 14.0, False, False, False),
    "pickup": (bend(BEND_PATH), 14.0, False, False, False),
    "hook_reach": (reach_up(HOOK_PATH), 14.0, False, False, False),
    "rope_grab": ([rope(HAND_ROPE, HAND_ROPE, [(18, 34), (26, 42)], 6),
                   rope(HAND_ROPE, HAND_ROPE, [(8, 14), (12, 20)], 3)], 12.0, False, False, False),
    "rope_hang": ([rope(HAND_ROPE, HAND_ROPE, TOGETHER), rope(HAND_ROPE, HAND_ROPE, [(0, 3), (3, 5)])],
                  3.0, True, False, False),
    "rope_climb_up": (ROPE_CLIMB, 8.0, True, False, False),
    "rope_climb_down": (list(reversed(ROPE_CLIMB)), 8.0, True, False, False),
    "rope_let_go": ([rope((12, 142), (22, 132), [(12, 24), (-6, 16)], -3),
                     rope((24, 128), (34, 118), [(16, 28), (-10, 20)], -5)], 12.0, False, False, False),
    "raise": ([{"lean": -6 - b, "head": -14 - b, "legs": [(-6, 2), (6, 3)], "arms": [(-6, 12), (0, 0)], "hand": "raise"}
               for b in (0.0, 0.8, 1.2, 0.8)], 6.0, True, False, True),
    "raise_walk": ([dict(p, hand="raise", lean=-3, head=-10) for p in gait(8, 20, 6, 28, 16, 14, 3, 1.5)],
                   9.0, True, False, True),
    "death": ([{"lean": -12, "head": -10, "legs": [(-6, 6), (8, 10)], "arms": [(125, 20), (105, 25)]},
               {"lean": 8, "head": 15, "legs": [(28, 66), (36, 76)], "arms": [(40, 30), (30, 30)]},
               {"lean": 22, "head": 25, "legs": [(78, 150), (84, 155)], "arms": [(30, 20), (20, 20)]},
               {"lean": 50, "head": 25, "legs": [(84, 155), (88, 160)], "arms": [(55, 10), (45, 10)]},
               {"lean": 80, "head": 10, "legs": [(90, 120), (94, 130)], "arms": [(90, 10), (80, 5)]},
               {"lean": 88, "head": 6, "legs": [(92, 110), (96, 120)], "arms": [(95, 5), (85, 5)]}],
              12.0, False, False, False),
    "respawn": ([dict(idle()[0], alpha=a) for a in (0.08, 0.22, 0.42, 0.62, 0.82, 1.0)], 14.0, False, False, False),
}


def strip(poses, carry):
    img = Image.new("RGBA", (FRAME * len(poses), FRAME), (0, 0, 0, 0))
    for i, p in enumerate(poses):
        img.paste(render(p, carry), (i * FRAME, 0))
    return img


def write_frames(entries):
    ext, subs, anims = [], [], []
    for idx, (anim, file, count, fps, loop) in enumerate(entries, start=1):
        ext.append(f'[ext_resource type="Texture2D" path="{RES_DIR}{file}" id="{idx}_{anim}"]')
        frames = []
        for f in range(count):
            sid = f"AtlasTexture_{anim}_{f}"
            subs.append(f'[sub_resource type="AtlasTexture" id="{sid}"]\natlas = ExtResource("{idx}_{anim}")\n'
                        f'region = Rect2({f * FRAME}, 0, {FRAME}, {FRAME})\n')
            frames.append(f'{{\n"duration": 1.0,\n"texture": SubResource("{sid}")\n}}')
        anims.append('{\n"frames": [' + ", ".join(frames) + '],\n'
                     f'"loop": {"true" if loop else "false"},\n"name": &"{anim}",\n"speed": {fps}\n}}')
    text = ('[gd_resource type="SpriteFrames" format=3]\n\n' + "\n".join(ext) + "\n\n" + "\n".join(subs)
            + "\n[resource]\nanimations = [" + ", ".join(anims) + "]\n")
    with open(os.path.join(OUT_DIR, "player_frames.tres"), "w", newline="\n") as fh:
        fh.write(text)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    entries = []
    for name, (poses, fps, loop, has_carry, carry_only) in ANIMS.items():
        variants = [(name + "_carry", True)] if carry_only else [(name, False)] + ([(name + "_carry", True)] if has_carry else [])
        for anim, carry in variants:
            file = f"player_{anim}.png"
            strip(poses, carry).save(os.path.join(OUT_DIR, file))
            entries.append((anim, file, len(poses), fps, loop))
            print(f"wrote {file:28s} {len(poses)} frames  {FRAME * len(poses)}x{FRAME}")
    write_frames(entries)
    j = solve(idle()[0])
    s = ground_shift(j, 0)
    print("shoulder px above feet:", round(j["shoulder"][1] + s, 1), "fwd:", round(j["shoulder"][0], 1), "arm px:", ARM_LEN)


if __name__ == "__main__":
    main()
