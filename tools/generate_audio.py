"""Generates placeholder audio (.ogg) for Lantern Keeper.

All sounds are synthesized, so they are free to use and replace. Swap any file
with final audio of the same name (any length); music files are looped in-game.

Requires: numpy, soundfile   (pip install soundfile)
Usage:    python tools/generate_audio.py
"""
import os

import numpy as np
import soundfile as sf

ROOT = os.path.join(os.path.dirname(__file__), "..", "game", "assets", "audio")
SR_SFX = 44100
SR_MUSIC = 32000
rng = np.random.default_rng(11)


def write(rel: str, data: np.ndarray, sr: int) -> None:
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = float(np.max(np.abs(data))) or 1.0
    samples = (data / peak * 0.7).astype(np.float32)
    # Written in blocks: one big write overflows libvorbis' stack on Windows.
    with sf.SoundFile(path, "w", sr, 1, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(samples), 4096):
            f.write(samples[i:i + 4096])
    print("wrote", rel, f"{len(data) / sr:.2f}s")


def t_axis(seconds: float, sr: int = SR_SFX) -> np.ndarray:
    return np.arange(int(seconds * sr)) / sr


def env(t: np.ndarray, attack: float, decay: float) -> np.ndarray:
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))


def lowpass(x: np.ndarray, k: int) -> np.ndarray:
    kernel = np.ones(k) / k
    return np.convolve(x, kernel, mode="same")


def noise(n: int) -> np.ndarray:
    return rng.uniform(-1, 1, n)


def sweep(t: np.ndarray, f0: float, f1: float) -> np.ndarray:
    f = f0 + (f1 - f0) * t / t[-1]
    return np.sin(2 * np.pi * np.cumsum(f) / SR_SFX)


# ── SFX ───────────────────────────────────────────────────────────────────
def sfx() -> None:
    t = t_axis(0.2)
    write("sfx/jump.ogg", sweep(t, 260, 520) * env(t, 0.01, 0.06) * 0.6
          + lowpass(noise(len(t)), 6) * env(t, 0.005, 0.04) * 0.5, SR_SFX)

    t = t_axis(0.25)
    write("sfx/land.ogg", np.sin(2 * np.pi * 85 * t) * env(t, 0.003, 0.06)
          + lowpass(noise(len(t)), 20) * env(t, 0.002, 0.03), SR_SFX)

    t = t_axis(0.5)
    clink = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((1180, 1.0), (2630, 0.6), (3910, 0.35)))
    write("sfx/lantern_place.ogg", clink * env(t, 0.002, 0.12)
          + np.sin(2 * np.pi * 110 * t) * env(t, 0.002, 0.05) * 0.8, SR_SFX)

    t = t_axis(0.45)
    a = np.sin(2 * np.pi * 660 * t) * env(t, 0.005, 0.15)
    b = np.sin(2 * np.pi * 990 * t) * env(np.maximum(t - 0.09, 0), 0.005, 0.2) * (t > 0.09)
    write("sfx/lantern_pickup.ogg", a + b, SR_SFX)

    t = t_axis(0.5)
    glug = np.zeros_like(t)
    for start, f0 in ((0.0, 520), (0.12, 440), (0.24, 380)):
        seg = (t >= start) & (t < start + 0.12)
        tt = t[seg] - start
        glug[seg] += np.sin(2 * np.pi * (f0 + 900 * tt) * tt) * env(tt, 0.005, 0.05)
    write("sfx/oil_pickup.ogg", glug, SR_SFX)

    t = t_axis(2.0)
    bell = sum(np.sin(2 * np.pi * f * t) * a * env(t, 0.004, d)
               for f, a, d in ((523, 1.0, 0.9), (784, 0.7, 0.7), (1047, 0.5, 0.6), (1568, 0.3, 0.4)))
    shimmer = np.sin(2 * np.pi * 2093 * t) * env(t, 0.3, 0.5) * 0.2 * (1 + np.sin(2 * np.pi * 7 * t))
    write("sfx/shrine.ogg", bell + shimmer, SR_SFX)

    t = t_axis(1.1)
    boom = np.sin(2 * np.pi * (60 - 25 * t) * t) * env(t, 0.005, 0.35)
    rumble = lowpass(noise(len(t)), 60) * env(t, 0.01, 0.4) * 3
    write("sfx/death.ogg", boom + rumble, SR_SFX)

    t = t_axis(1.0)
    beat = np.zeros_like(t)
    for start, amp in ((0.0, 1.0), (0.26, 0.75)):
        tt = np.maximum(t - start, 0)
        beat += np.sin(2 * np.pi * 52 * tt) * env(tt, 0.008, 0.07) * amp * (t >= start)
    write("sfx/heartbeat.ogg", beat, SR_SFX)

    t = t_axis(0.07)
    write("sfx/ui_button.ogg", np.sin(2 * np.pi * 1400 * t) * env(t, 0.001, 0.015)
          + lowpass(noise(len(t)), 3) * env(t, 0.001, 0.008) * 0.4, SR_SFX)

    t = t_axis(1.8)
    arp = np.zeros_like(t)
    for i, f in enumerate((392, 494, 587, 784)):
        start = i * 0.14
        tt = np.maximum(t - start, 0)
        arp += np.sin(2 * np.pi * f * tt) * env(tt, 0.005, 0.6) * (t >= start)
    write("sfx/level_complete.ogg", arp, SR_SFX)


def sfx_enemies() -> None:
    t = t_axis(0.6)
    scrape = lowpass(noise(len(t)), 4) * env(t, 0.02, 0.25) * (0.6 + 0.4 * np.sin(2 * np.pi * 37 * t))
    clicks = np.zeros_like(t)
    for c in np.linspace(0.02, 0.45, 9):
        tt = np.maximum(t - c, 0)
        clicks += np.sin(2 * np.pi * 2400 * tt) * env(tt, 0.0005, 0.006) * (t >= c)
    write("sfx/enemy_wake.ogg", scrape + clicks * 0.7, SR_SFX)

    t = t_axis(0.55)
    hiss = noise(len(t)) - lowpass(noise(len(t)), 12)          # high-passed noise
    write("sfx/enemy_hiss.ogg", hiss * env(t, 0.03, 0.18) * (1 + 0.5 * np.sin(2 * np.pi * 9 * t)), SR_SFX)

    t = t_axis(0.8)
    chime = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((880, 1.0), (1320, 0.5), (1760, 0.3)))
    swell = np.clip(t / 0.35, 0, 1) * np.exp(-np.maximum(t - 0.35, 0) / 0.2)
    write("sfx/lantern_return.ogg", chime * swell * (1 + 0.4 * np.sin(2 * np.pi * 14 * t)), SR_SFX)


def sfx_falls() -> None:
    """Falling objects (FallFX) and the Shade: creak, thud, rumble, screech. Own random
    stream, so running this alone doesn't change any other sound."""
    r = np.random.default_rng(23)
    nz = lambda n: r.uniform(-1, 1, n)

    t = t_axis(0.55)                                            # wood / stone creak + crack
    creak = np.sin(2 * np.pi * (180 + 60 * np.sin(2 * np.pi * 3 * t)) * t) * env(t, 0.05, 0.35)
    crack = lowpass(nz(len(t)), 2) * env(np.maximum(t - 0.38, 0), 0.001, 0.05) * (t >= 0.38)
    grit = lowpass(nz(len(t)), 6) * 0.25 * env(t, 0.1, 0.4)
    write("sfx/fall_creak.ogg", creak * 0.5 + crack * 0.9 + grit, SR_SFX)

    t = t_axis(0.9)                                             # heavy thud + debris
    boom = np.sin(2 * np.pi * (70 * np.exp(-t * 4) + 38) * t) * env(t, 0.002, 0.35)
    debris = lowpass(nz(len(t)), 3) * env(t, 0.005, 0.25) * 0.6
    write("sfx/fall_thud.ogg", boom + debris, SR_SFX)

    t = t_axis(1.6)                                             # low rumble (gate / cave)
    rumble = lowpass(nz(len(t)), 40) * 3.0 * np.clip(t / 0.25, 0, 1) * np.exp(-np.maximum(t - 0.6, 0) / 0.5)
    write("sfx/rumble.ogg", rumble + np.sin(2 * np.pi * 42 * t) * 0.3 * np.exp(-t), SR_SFX)

    t = t_axis(1.0)                                             # the Shade's screech
    f = 900 + 500 * np.sin(2 * np.pi * 5 * t) - 400 * t
    screech = np.sin(2 * np.pi * np.cumsum(f) / SR_SFX) * env(t, 0.02, 0.5)
    rasp = (nz(len(t)) - lowpass(nz(len(t)), 8)) * env(t, 0.02, 0.4) * 0.5
    write("sfx/shade_screech.ogg", screech * 0.6 + rasp, SR_SFX)


# ── Music (seamless loops) ────────────────────────────────────────────────
def note(n: float) -> float:
    return 440.0 * 2 ** ((n - 69) / 12)


def pad(t: np.ndarray, chords: list[list[int]], length: float, detune: float = 0.25) -> np.ndarray:
    out = np.zeros_like(t)
    seg = length / len(chords)
    for i, chord in enumerate(chords):
        center = (i + 0.5) * seg
        d = (t - center + length / 2) % length - length / 2         # wrapped distance
        w = np.clip(1 - np.abs(d) / seg, 0, 1)
        w = 0.5 - 0.5 * np.cos(np.pi * w)                          # raised cosine crossfade
        for n in chord:
            f = note(n)
            for k in (-detune, 0, detune):
                fk = round((f + k) * length) / length               # whole cycles per loop
                out += np.sin(2 * np.pi * fk * t) * w / (3 * len(chord))
    return out


def plucks(t: np.ndarray, length: float, scale: list[int], count: int, decay: float) -> np.ndarray:
    out = np.zeros_like(t)
    sr = SR_MUSIC
    for _ in range(count):
        start = rng.uniform(0, length)
        f = note(rng.choice(scale))
        tt = (t - start) % length
        out += np.sin(2 * np.pi * f * tt) * np.exp(-tt / decay) * (tt < decay * 6) * 0.25
    return out


def wind(n: int, length: float) -> np.ndarray:
    w = lowpass(noise(n), 300)
    fade = int(SR_MUSIC * 2)
    w[:fade] = w[:fade] * np.linspace(0, 1, fade) + w[-fade:] * np.linspace(1, 0, fade)
    return w[: n] * (0.6 + 0.4 * np.sin(2 * np.pi * np.arange(n) / n * 2))


def music() -> None:
    length = 32.0
    t = np.arange(int(length * SR_MUSIC)) / SR_MUSIC
    worlds = {
        "music/menu.ogg": ([[57, 60, 64], [53, 57, 60], [55, 59, 62], [52, 55, 59]], [69, 72, 76, 79], 6),
        "music/world_1_light.ogg": ([[50, 57, 62, 66], [55, 62, 67, 71], [52, 59, 64, 67], [57, 64, 69, 73]],
                                   [74, 76, 78, 81, 83], 10),
        "music/world_2_oil.ogg": ([[48, 55, 60, 63], [44, 51, 56, 60], [46, 53, 58, 62], [43, 50, 55, 59]],
                                 [72, 75, 77, 79], 7),
        "music/world_3_shadows.ogg": ([[40, 41, 47], [38, 39, 45], [40, 46, 47], [36, 37, 43]],
                                     [64, 65, 70], 4),
        "music/world_4_mirrors.ogg": ([[52, 59, 64, 67], [48, 55, 60, 64], [50, 57, 62, 66], [47, 54, 59, 62]],
                                     [76, 79, 83, 86, 88], 14),
    }
    for rel, (chords, scale, n_plucks) in worlds.items():
        mix = pad(t, chords, length) * 0.8 + plucks(t, length, scale, n_plucks, 0.6) + wind(len(t), length) * 0.6
        write(rel, mix, SR_MUSIC)


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["falls"]:
        sfx_falls()                     # only the falling-object / Shade sounds
    else:
        sfx()
        music()
        sfx_enemies()
        sfx_falls()
