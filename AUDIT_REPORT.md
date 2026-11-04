# Lantern Keeper: Rules Update Audit

Read-only audit of `main` at `31d37d4` (working tree clean before this report). The only file
created is this report. Nothing is committed. Paths are relative to `game/` unless they start
with a repo-level name. Format: `file : line/node → now → change → risk`.

## Summary

Already matching the new rules: left-half drag, swipe-up jump with hold height, tap does nothing
(gestures), jumping while carrying, no rope grab while carrying, carried-lantern safety, ghost
platforms, and the exit portal in all 10 levels.

The four biggest changes:

1. **Two lanterns in one level don't work today (high risk).** GameManager holds a single
   `_lantern`. The "new lantern after the rope" rule needs this reworked first.
2. **Automatic pickup is removed (high risk).** Level solutions in 3, 5, 6, 7, 8 and 10 depend
   on it, so each needs re-proving.
3. **`lantern_type` fits well (medium risk).** `oil_enabled` is already off in all 10 levels, and
   `GameManager.uses_oil()` is a ready-made switch.
4. **The Shade's sight needs a rule decision (medium risk).** Crevices contradict "or up close".

**Correction to the brief:** GameManager is not an autoload. `ServiceRegistry` is the autoload
(with `GameBus`, `Logger` and others under `game/autoloads/`); GameManager is a service created
by GameService in `Boot.tscn`. This doesn't change the plan.

## Decisions needed from you

| # | Question | My suggestion |
|---|---|---|
| D1 | The spare lantern after the rope: a real second lantern, or the same lantern moved there? | Real second lantern. It matches "left behind", and the moved version would vanish on screen |
| D2 | "Sees you only in the light, or up close" vs crevices: the Shade passes within 3.5 m of a hidden player | Crevices win. Otherwise level 10's hide encounter can't be solved |
| D3 | Final encounter: the Shade dives whether or not it can see you, even with no lantern | Keep it. It's a scripted set piece |
| D4 | "No HUD": the faint pause button on touch screens is the only on-screen item. Keep it? | Keep it. Phones have no other way to pause |
| D5 | Levels 1, 2, 4, 8, 10 have the dark meter off, so no vignette or heartbeat. Turn it on? | On for 1, 2, 4, 8. Level 10: test first, because it was switched off so the vignette wouldn't hide the crevices |
| D6 | "Respawns instantly": no fade at all, or a very short one? | Remove the delay, keep a 0.1 s fade to hide the camera snap |
| D7 | Levels 1, 2, 4, 8 have no shrine, so death returns to the spawn point. Add shrines? | Leave as is |
| D8 | The Level 10 opening line is 10 words (the hint style is 6 or fewer, about 3 s). Once per save, or every time? | Once per save, shown for about 5 s |
| D9 | Lantern art on the home screen: jar or oil lantern? | Jar, since World 1 is what players see first |

## 1. Lantern code and scene

How `lantern_type` fits: add `enum LanternType { JUGNOO, OIL }` as a `LevelRoot` export (one
setting per level, replacing `oil_enabled`) and let GameManager answer for everything else.
`uses_oil()` already exists, and its callers are few.

- `scenes/gameplay/levels/LevelRoot.gd : 26-29` → `oil_enabled`, `max_oil`, `start_oil` → add `lantern_type`; `oil_enabled` becomes `lantern_type == OIL` → **med**
- `scripts/managers/GameManager.gd : 531-532 uses_oil()` → reads `oil_enabled` → read `lantern_type`; add `uses_raise()`. Menu has no level, so it returns true today (see D9) → **low**
- `scenes/gameplay/actors/Lantern.gd : 31-34` → `base_radius`, `min_radius`, `raise_radius_multiplier` → keep; Jugnoo uses `base_radius` only → **low**
- `Lantern.gd : 201-214 _simulate()` → raise, burn, radius from oil → branch: Jugnoo skips raise and burn, target = `base_radius`. Oil path stays as it is → **med**
- `Lantern.gd : 274-300 _process()` → flicker and warmth from oil ratio → Jugnoo: gentle pulse, no low-oil look. Oil: warmth already goes toward orange-red; check against the brief → **low**
- `scenes/gameplay/actors/Lantern.tscn : Sprite` → one sprite, `lantern.png` → place a second `JarSprite` and a `Fireflies` CPUParticles3D in the scene and toggle visibility (no runtime creation) → **low**
- `Lantern.tscn : Light` (colour 1, 0.62, 0.28), `Glow`, `Dust` → amber → jar needs its own colour, set per type → **low**
- `Lantern.tscn` (oil art) → no oil level in the glass → new art or a shader fill for World 2 → **low, not needed yet**
- `W1_03.tscn : Lantern` → `base_radius = 5.5` → still "fixed", but differs from the 4.5 default. Keep; level 3 was tuned around it → **low**
- `scenes/Home/Home.tscn : Lantern` → uses the same scene → set type per D9 → **low**

## 2. Input

- `scenes/ui/hfw/touch/TouchControls.gd : 164-167 _process()` → hold still 0.3 s raises the light → skip when the level has no raise (else `HOLD` does nothing visible anyway) → **low**
- `scenes/ui/hfw/touch/TouchControls.tscn : .../ActionCluster/Raise` → classic Raise button always visible → hide when the level has no raise → **low**
- `project.godot : raise_light` (Shift key) → still mapped → keep for World 2; `Lantern._raised` stays false for Jugnoo → **low**
- `Player.gd : 222, 260-261` → raise animations and hand point → no change, they only follow `is_lantern_raised()` → **none**
- `Lantern.gd : 305-306 _on_place_requested()` → returns when not carried → must pick up here if the child is in reach, so one action does both on swipe down, the Place button and E → **high**
- `Lantern.gd : 324-332 _on_pickup_body_entered()` → **automatic pickup on touch and buttons** → remove; the area only tracks "in reach" → **high**
- `Lantern.gd : 248-252 _simulate_placed()` → **automatic pickup when a hook stops under the child** → remove → **high**
- `Lantern.gd : 74, 169, 309, 348-350 _awaiting_exit` → stops instant re-pickup → no longer needed → **low**
- `Lantern.tscn : PickupArea` → radius 0.7 m → too tight for a deliberate action; suggest about 1.2 m, tested by hand → **low**
- `TouchControls.gd : 92-124` → tap does nothing → matches; no change → **none**
- `TouchControls.gd : 13` → comment says pick-up is automatic → update → **low**
- `InputManager.gd : 109-114 _clear()` → clears held jump on pause but not `_virtual_raise`, so raise can stick through a pause → one-line fix if raise stays (World 2) → **low**

Jump is already correct: `Player.gd : 159-162` cuts the jump on early release (hop), and
`TouchControls.gd : 140-143` holds it while the finger stays down. Nothing limits jumping while
carrying. Not hand-tested on a phone.

## 3. Ropes

- `scripts/managers/GameManager.gd : 621-622 report_rope_touched()` → refuses the grab while carrying → matches → **none**
- `Rope.tscn` is used in one level only, `W1_09 : Rope (20.8, 7)`
- `W1_09.tscn` → **no spare lantern**. One Lantern, left between the holes; the end of the level is run in the dark → add a second Lantern (`start_carried = false`) after the rope, around x 30-34 on `FloorFar` → **med**
- `GameManager.gd : 106, 478-479` → `_lantern` single; `register_lantern()` overwrites, so the last lantern loaded wins → hold a list plus an "active" lantern (the carried one, else the nearest) → **high**
- Everything that reads `_lantern` must follow, or a second lantern breaks them:
  - `GameManager.gd : 383-384, 415-416` checkpoint capture / restore (one lantern only) → **high**
  - `GameManager.gd : 481-498, 501-510, 672-677` carried / raised / hung / lost / protected → **high**
  - `scenes/gameplay/enemies/Stalker.gd : 45-58` compares against `get_lantern()` → **med**
  - `scenes/gameplay/enemies/Shade.gd : 226-235` lure → **med**
  - `scenes/gameplay/props/ExitPortal.gd : _on_body_entered` shrinks one lantern → **low**
- Light sources are already a list (`_light_sources`), so light queries work with two lanterns → **none**

## 4. Shrines

- `GameManager.gd : 434-435, 438 report_shrine_reached()` → always refills oil → wrap in `if uses_oil()` → **low**
- `GameManager.gd : 436` → also refills the dark meter → not oil; keep → **none**
- `scenes/gameplay/props/Shrine.gd : 4` and `GameManager.gd : 429` → comments say every shrine refills → update → **low**
- `Shrine.gd : 23-25 shadow_restart_point` → left over from the Big Shadow; unused by the Shade → remove when convenient → **low**

## 5. Enemies: "holding the lantern = safe"

The rule is in place for all four.

- `scenes/gameplay/enemies/Enemy.gd : 368, 375` → hurtbox and catch both skip when `player_lit` or `is_player_protected()` → matches → **none**
- `Enemy.gd : 249, 313` → lunge only starts, and wind-up cancels, based on light → matches → **none**
- `GameManager.gd : 672-677 is_player_protected()` → carried + light active → safe. At zero oil the light is out, so an oil lantern gives no protection → matches. Must use the active lantern after section 3 → **med**
- `Stalker.gd : 45-58` → ignores a *hung* lantern's light when the child isn't lit (level 7 depends on this) → keep; follow the lantern list → **med**
- `Enemy.gd : 439` → an empty dark meter only speeds enemies up; **darkness itself never kills** → matches "no death" → **none**

## 6. Shade (Level 10)

- `Shade.gd : 226-235 _lure_target()` → drawn to a lantern set down within 30 m; ignored while carried → matches for placed lanterns → **none**
- `Shade.gd : 312-315 PATROL` → sees: in the open within 3.5 m, or **carrying** the light within 12 m → change `is_lantern_carried()` to `player_lit`, so standing in any light counts → **med**
- `Shade.gd : 312` → `is_player_hidden()` beats "up close" → contradicts the rule as written (D2) → **med**
- `Shade.gd : RUN and HOVER/DIVE` → scripted, ignores sight (D3) → **low**
- `W1_10.tscn` → **the opening line does not exist.** Hints present: "It hunts your light. Run!", "Use the light as bait", "Hide in the dark", "Bring the ceiling down" → add `shade_rule` to `TutorialManager.HINTS`, a `HINT_SHADE_RULE` string, and a TutorialTrigger at the spawn → **low**
- `scenes/ui/hfw/tutorial/GestureHint.gd : 15` → `display_time` 3 s, too short for 10 words → per-hint time, or raise it (D8) → **low**

## 7. All 10 levels

Oil pickups: **none in any level** (the only `OilFlask` is in `TestLevel.tscn`). Raise-light
hints: **none**. `oil_enabled = false` in all 10. Exit portal: **present in all 10.**

| Level | Lanterns | Shrines | Ropes | Hooks / plates | Dark meter | Exit portal | Hints that work | Auto-pickup dependency |
|---|---|---|---|---|---|---|---|---|
| 1 | 1 | 0 | 0 | 0 | off | (58, 2.4) | move, ghost | none |
| 2 | 1 | 0 | 0 | 0 | off | (31, 0) | place | only when retrying |
| 3 | 1 (r 5.5) | 1 | 0 | GateHook | on | (36, 0) | stay_in_light | **yes**: take it back off the hook |
| 4 | 1 | 0 | 0 | 0 | off | (33, 8.4) | none | only when retrying |
| 5 | 1 | 2 | 0 | RailHook | on | (76, 0) | none | **yes**: rail delivers it, line 249 |
| 6 | 1 | 2 | 0 | Cradle | on | (58, 1.3) | none | **yes**: take it off the cradle |
| 7 | 1 | 2 | 0 | Switch plate | on | (76, 0) | something_follows | **yes**: chain delivers it, line 249 |
| 8 | 1 (not carried) | 0 | 0 | 0 | off | (57, 0) | none | **yes**: the first pickup on the perch |
| 9 | 1, **needs 2** | 1 | 1 | 0 | on | (46, 0) | none | spare lantern needs a pickup |
| 10 | 1 | 4 | 0 | BaitHook, Cradle | off | (232, 0) | 4 Shade hints | **yes**: hook and cradle |

- Dead hint triggers (their ids aren't in `HINTS`, so they show nothing): `W1_01 : Hint_jump`, `W1_02 : Hint_wall`, `W1_04 : Hint_lid`, `W1_08 : Hint_find` → remove or give them hints → **low**
- Still not placed from earlier work: `W1_05` danger_above, `W1_09` seal_holes → place → **low**
- `W1_03 : Gate close_delay 3.0`, `W1_05 : TunnelGate close_delay 0.0` and `W1_07 : Door 0.4 s` → these timings assumed the walk-into pickup → re-check once pickup is manual → **med**
- Levels 2 and 8 end with the lantern left behind; `ExitPortal.gd` then pulls it across the level into the portal → skip the pull when it's far away → **low**

## 8. Tutorial and UI text

- `assets/localization/strings.csv : HINT_MOVE_TOUCH` → **"Drag to move · Tap to jump" is now wrong** (tap does nothing) → "Drag to move · Swipe up to jump" → **med**
- `strings.csv : HINT_PLACE_TOUCH / CLASSIC / PC` → say place only → pickup must be taught; add a hint at the first required pickup (level 3) → **med**
- `scripts/managers/TutorialManager.gd : 16` (`move`) → seen flags are stored per id, so existing saves won't see corrected text under `move` → use a new id such as `move_swipe` → **low**
- `TutorialManager.gd : 23` → `run` is unused → remove with its string → **low**
- Stale comments: `Lantern.gd : 4-8`, `scenes/ui/hfw/hud/HUD.gd : 4-6`, `LevelRoot.gd : 26` (mentions an oil bar that doesn't exist) → update → **low**
- `LEVEL_DESIGN.md : 51, 72, 91, 109, 165, 183, 207` → describe walking into the lantern, or tap to jump → update with each level → **low**
- `LEVEL_DESIGN.md : 23-24` → says levels 1, 2, 4, 8, 10 are original layouts; level 10 isn't → **low**
- No text mentions raising the light → **none**

## 9. Assets

- `assets/sprites/single/props/lantern.png` (64 × 96) → stays as the oil lantern → **none**
- `assets/ASSET_LIST.md : 92-93` → list `lantern_body.png` and `lantern_glow.png`, **which aren't on disk** → remove the rows → **low**
- New entries needed:
  - `sprites/single/props/firefly_jar.png`, 64 × 96, same pivot as `lantern.png` (handle at row 4, offset 0, −44)
  - `sprites/single/fx/firefly_dot.png`, 16 × 16, soft white dot tinted by the material
  - later, for World 2: oil level art in the glass
- `tools/generate_placeholders.py : 40 lantern()` regenerates all placeholders at random → add the jar to `tools/generate_level_props.py` instead → **low**
- `touch_btn_raise.png`, `player_raise_*` → keep for World 2 → **none**

## 10. Save system

- **No oil or lantern state is saved.** Saved: settings, level progress, tutorial flags, `control_layout`, `fullscreen` (`addons/datamanager/models/GameModels.gd` has no oil or lantern field) → **no change needed**
- Checkpoints live in memory only (`GameManager._checkpoint_*`) → section 3 covers them → **none here**
- Tutorial flags: see section 8 → **low**

## 11. Other rules checked

- **Move, Jump, Tap, Ghost platforms, Exit:** match. Ghost platforms (`scenes/gameplay/props/GhostPlatform.gd : 75-84`) stay solid for 0.35 s after the light leaves. Keep; it's a fair grace period → **none**
- **Death:** `GameManager.gd : 360-361` waits `respawn_delay` 0.25 s, then `ScreenFade` 0.25 s out and 0.35 s in, plus `Player.respawn_lock_time` 0.3 s of no input. That's about 0.85 s to full picture, not instant → D6 → **med** (the death pose plays during that delay)
- **No HUD:** `HUD.gd` shows only the pause button (touch) → D4. `DebugOverlay` is F3 only, off in release → **none**
- **Vignette and heartbeat:** only run where the dark meter is on → D5 → **med**
- `TestLevel.tscn` still uses `LevelExit` and `OilFlask` → test level; leave it → **none**

## Proof: startup log

Ran `W1_01` (400 frames), then `W1_03`, `W1_09`, `W1_10` (300 frames each), Godot 4.7.1, no input.
`git status` was clean afterwards.

```
Godot Engine v4.7.1.stable.official.a13da4feb - https://godotengine.org
OpenGL API 3.3.0 - Build 32.0.101.7085 - Compatibility - Using Device: Intel - Intel(R) UHD Graphics 770

[INFO][CONFIG] Config loaded. Log level: DEBUG, Encrypt: false, Extension: .json
[INFO][CORE] Loading local save data files...
[INFO][CORE] DataManager initialized successfully.
[INFO]  SaveManager initialized (backed by DataManager)
[INFO]  GameService initialized
[INFO]  Bootstrap sequence started...
[INFO]  SceneManager: going to | { "path": "res://game/scenes/gameplay/levels/world1/W1_01.tscn" }
[INFO]  GameManager state | { "state": "PLAYING" }
[INFO]  GameManager state | { "state": "MENU" }
```

| Level | Errors / warnings |
|---|---|
| W1_01 | 0 |
| W1_03 | 0 |
| W1_09 | 2, both at quit: "4 ObjectDB instances were leaked", "2 resources still in use" |
| W1_10 | 0 |

- **`Enemy.gd` "Function blocked during in/out signal":** not seen. `Enemy.gd : 196-202` now uses
  `set_deferred`, changed in `2e065e0`, so it looks fixed. This run had no input, so no enemy
  woke and the fix wasn't exercised. Confirm it in a play session.
- The level 9 messages appear when forcing an early quit; they're not a gameplay error, and the
  cause wasn't traced.

## Suggested order of prompts

1. **Multi-lantern support** in GameManager (list + active lantern, checkpoints). No gameplay change; re-run all levels.
2. **`lantern_type`** on LevelRoot and GameManager; set all 10 levels to Jugnoo; no raise, no burn, shrine refill oil-only.
3. **Hide raise in World 1**: hold gesture and classic button.
4. **Jar art**: `firefly_jar.png`, `firefly_dot.png`, `Fireflies` particles, ASSET_LIST.
5. **Manual pickup** in Lantern.gd (one action places and picks up), larger reach, remove auto-pickup.
6. **Re-prove levels 3, 5, 6, 7, 8, 10** with manual pickup; fix gate timings only where needed.
7. **Level 9 spare lantern** after the rope.
8. **Shade sight** per D2 and D3, plus the opening line.
9. **Text**: new move and pickup hints, remove dead triggers, place the level 5 and 9 hints.
10. **Instant respawn** per D6.
11. **Vignette and heartbeat** per D5.
12. **Docs clean-up**: LEVEL_DESIGN.md, ASSET_LIST.md, stale comments.
