# Lantern Keeper: Level Editor Plugin, 7 Prompts (Antigravity)

Send them in order, one at a time. Paste the header into each prompt.
After each one: check its proof yourself, then ask Claude to run that prompt's **Claude check**.
Do this AFTER the World 1 rules update, so the levels include the new lantern, pickup and vignette rules.

## Header (paste into every prompt)
```
Project: Lantern Keeper (Godot 4.7.1, 2.5D side view: X right, Y up, gameplay on the z = 0 plane; landscape 1920x1080, mobile + PC).
- Read the template structure first: LevelRoot.gd, LevelManager.gd, LevelCatalog.gd + game/resources/level_catalog.tres, two finished levels (W1_03.tscn, W1_10.tscn), and the folders game/scenes/gameplay/{actors,props,enemies,environment}.
- The plugin is EDITOR-ONLY (addons/level_editor/, @tool scripts). The game must never depend on it; exported builds must run without it.
- No runtime creation in the game: levels are normal .tscn files with everything placed. The plugin only adds nodes while editing.
- Use EditorUndoRedoManager for every scene change, so Ctrl+Z works.
- ONE task only. Change nothing outside the scope below. If a gameplay script would need a change, stop and list it instead of doing it.
- Every tunable is an @export or a dock setting; every script has a Sends/Receives doc comment.
- Proof required: editor screenshots + run the game, logs.
- Plain commit message. Do NOT commit or push until I personally say so.
```

### How levels are built today (facts for every prompt)
- **Level list:** `game/resources/level_catalog.tres` (a `LevelCatalog`), read only by `LevelManager`.
  `level_paths` is a fixed slot list: `levels_per_world` = 10 slots per world, 4 worlds
  (`world_names`), slot index = (world − 1) × 10 + (number − 1). Ids are `w<world>_<2 digits>`
  (`LevelManager.make_id`). Saves store progress by that id.
- **Level root:** `LevelRoot.gd` exports `level_id`, `world`, `title_key` (`LEVEL_W1_04` …, a row in
  `game/assets/localization/strings.csv`), `spawn_point` (a `SpawnPoint` Marker3D), `lantern_type`,
  dark meter settings, `kill_y`.
- **Standard nodes** (see W1_03): WorldEnvironment, Backdrop (`environment/Backdrop.tscn`), Camera
  (Camera3D + `CameraController3D.gd`), SpawnPoint, Player, Lantern, containers `Geometry`
  (platforms, walls), `GhostPlatforms`, `Decor` (sprites), `Hints` (TutorialTriggers), and at the
  root: shrines, hooks, gates, levers, plates, crates, ropes, enemies, WakeTriggers, KillZone, ExitPortal.
- **No camera limits and no parallax nodes:** the camera follows the child (only `min_y`). Backdrop is
  four very wide 3D panels (≈ 960–1100 m) that already cover every level. The "kill floor" is the
  `KillZone` box plus `LevelRoot.kill_y`.
- **Ghost platforms** (`props/GhostPlatform.tscn`) have `Segment0..N` StaticBody3D children that the
  script builds in the editor (`regenerate_segments()`), giving them the node's `owner`. They must be
  saved in the .tscn; at runtime nothing is rebuilt.

---

## Prompt 1: Level catalog from the folders
**Goal:** a level becomes playable just by saving it as `levels/world<N>/W<N>_<##>.tscn`.
- Keep `level_catalog.tres` as the one list the game reads (it already works in exported builds).
  Don't add a second index and don't scan folders at runtime.
- Add an editor step that scans `res://game/scenes/gameplay/levels/world*/` for `W<world>_<2 digits>.tscn`
  and writes each path into its slot in `level_paths` (slot = (world − 1) × 10 + (number − 1)), leaving
  empty slots empty. Run it from a button and automatically when a level scene is saved.
- Ignore `TestLevel.tscn`, `_`-prefixed files and anything outside `world*` folders. A number above
  `levels_per_world` or a world above `world_names.size()` is reported, not written.
- Report a mismatch between file name and the scene's `level_id` / `world` (don't fix it silently).
- Don't change LevelManager, level select or saves; they already read the catalog.
**Proof:** the regenerated catalog is identical to today's for World 1 (show the diff: none). Add a
dummy `levels/world2/W2_01.tscn` (copy of W1_01 with `level_id = "w2_01"`, `world = 2`), regenerate,
show it in level select and reach it from W1_10's exit, then delete it and regenerate again.
**Claude check:** catalog unchanged for World 1 after the run; no runtime code touched; exported build unaffected.

## Prompt 2: Plugin skeleton + "New level"
**Goal:** one click makes a correct empty level.
- `addons/level_editor/` with `plugin.cfg` and an `EditorPlugin`; enable it in project settings.
- A template `addons/level_editor/templates/LevelTemplate.tscn` with only the standard nodes listed
  above (copy them from W1_03, don't invent new containers): LevelRoot with today's default exports,
  WorldEnvironment, Backdrop, Camera, SpawnPoint, Player, Lantern, `Geometry` with a start floor and
  a left wall, `GhostPlatforms`, `Decor`, `Hints`, KillZone, ExitPortal with a right wall behind it.
  Report the node list.
- Dock button "New level": pick the world → it suggests the next free `W<N>_<##>` → duplicates the
  template, sets `level_id`, `world`, `title_key` (`LEVEL_W<N>_<##>`), saves to `levels/world<N>/`,
  adds a `LEVEL_W<N>_<##>` row to `strings.csv` if missing (placeholder text), regenerates the catalog
  (prompt 1) and opens the scene.
- Never overwrite an existing file (ask or abort).
**Proof:** screenshots of the dock and the new scene tree; the new level runs from level select:
spawn, walk to the exit, level complete shows its title.
**Claude check:** the new level loads through LevelManager with the plugin disabled; node names match W1_03.

## Prompt 3: Object palette
**Goal:** place anything from a side panel; new objects appear automatically.
- Dock "Palette": scan `props/`, `enemies/`, `actors/`, `environment/` (plus a `palette_folders`
  setting) for `.tscn`. Group by folder, with a thumbnail (EditorResourcePreview) and a name.
- Hide scenes that aren't placed on their own: `_` filename prefix, a `palette_hidden` metadata, and
  by default `props/FallFX.tscn` (it lives inside other props) and `actors/Player.tscn` /
  `actors/Lantern.tscn` when the level already has them.
- Click an item, then click in the 3D viewport → instance it at the clicked point on the z = 0 plane,
  snapped to `grid_size` (default 0.5 m, toggle), under the standard parent: Platform → `Geometry`,
  GhostPlatform → `GhostPlatforms`, decor → `Decor`, TutorialTrigger → `Hints`, everything else → level root.
  Unique readable names (`Hook1`, `Crawler2` …).
- **Ghost platforms:** add the node, set its `owner` to the scene root, THEN call `regenerate_segments()`,
  so every `Segment*` child is owned by the scene root and saved. Same after any resize.
- Refresh button + auto-refresh on filesystem changes.
**Proof:** place a shrine, a crawler and a ghost platform with snapping; undo one; save, reopen, they're
still there; run the level, carry the lantern onto the ghost platform and stand on it (it must hold);
add a dummy prop .tscn, show it appears after refresh, delete it.
**Claude check:** saved .tscn has the `Segment*` nodes with collision shapes; the ghost platform works in game.

## Prompt 4: Fit level (kill zone and bounds)
**Goal:** the level's safety net follows what you placed.
- Dock button "Fit level" (and on save, as a setting): compute the bounds of `Geometry`,
  `GhostPlatforms` and the root gameplay nodes (ignore Camera, Backdrop, Decor, WorldEnvironment).
- Update only: the `KillZone` position and `size` so it spans the whole level plus a margin, and
  `LevelRoot.kill_y` = lowest floor − a margin (setting, default 8 m). Written into the .tscn.
- Report (don't fix): no wall at the left or right end; the level reaching past the Backdrop panels.
- Don't move or scale placed gameplay objects; don't touch the camera or the Backdrop.
**Proof:** stretch a test level to about 3× length, press "Fit level", fall into a pit at both ends
(both kill). Run it on W1_10 (the longest) and report what changed (ideally nothing, or a larger kill zone).
**Claude check:** W1_10 and the other levels still play the same (proof bots) after Fit level.

## Prompt 5: Link helper
**Goal:** connect puzzle pieces without typing ids.
- Pieces connect by ids: `LanternHook.hook_id` ↔ `Gate.hook_id`; `Lever.lever_id` and
  `PressurePlate.plate_id` ↔ `Gate.lever_id` / `LanternHook.lever_id`; enemy `wake_group` ↔
  `WakeTrigger.wake_group`, `LanternHook.wake_group_on_hang`, `Rope.wake_group_on_grab`,
  `TutorialTrigger.on_wake_group`.
- Select two nodes → "Link" picks the right fields and sets a shared id (a new unique one, or an
  existing one from a list). "Unlink" clears it. Undo works.
- Draw a line between linked nodes in the 3D viewport (one colour per id), toggle in the dock.
**Proof:** link a hook to a gate and a lever to a second gate in a test level, run it: hanging the lantern
opens gate 1, the lever opens gate 2; screenshot the link lines on W1_05.
**Claude check:** ids written to the right exports; existing levels unchanged unless edited.

## Prompt 6: Overlays (light and jump)
**Goal:** see what the lantern lights and where the child can jump while designing.
- Editor-only gizmos, each toggled in the dock:
  - **Light:** a circle around each Lantern (its `base_radius`; a dotted one × `raise_radius_multiplier`
    when the level uses oil) and each hook's HookPoint (radius of the level's lantern); shrines with
    a `sanctuary_radius`. Ghost platform segments inside a circle drawn filled.
  - **Jump reach:** from the selected platform's top edges, the arc the child can reach, computed from
    the live `Player.tscn` / `Player.gd` exports (`run_speed`, `jump_velocity`, `gravity`,
    `fall_gravity_multiplier`, `coyote_time`). Today that's about 2.1 m up and 3.9 m across. Don't hard-code.
  - **Paths:** a hook's `travel_offset` rail, a rope's swing arc (`length`, `swing_degrees`), a crate's
    `min_x`…`max_x`, a LanternHook's reach box.
**Proof:** screenshots of each overlay on W1_04, W1_06, W1_09; change `base_radius` on a lantern and
`jump_velocity` on the player and show the overlays update.
**Claude check:** the jump arc matches a real jump in game (measure the child's highest and longest jump).

## Prompt 7: Validate level
**Goal:** catch broken levels before playing.
- Dock button "Validate": checks the open level, lists error/warning lines with the node path;
  clicking selects the node. Read-only: never changes the scene. Also a "Validate all" for every catalog level.
- **Errors:** no SpawnPoint or `spawn_point` not set; more than one SpawnPoint; no ExitPortal;
  no KillZone; `level_id` / `world` not matching the file name; level missing from the catalog;
  `title_key` missing from `strings.csv`; a Gate whose `hook_id` / `lever_id` no hook, lever or
  plate uses (or the other way round); an enemy `wake_group` nothing wakes (count WakeTrigger,
  `wake_group_on_hang`, `wake_group_on_grab`; an enemy with `wake_distance` > 0 needs none);
  a TutorialTrigger `hint_id` not in `TutorialManager.HINTS`; a ghost platform whose `Segment*`
  count or sizes don't match its `size`.
- **Warnings:** an enemy or dark section with no Shrine before it; a ghost platform no lantern
  position, hook or rail can light; a rope (needs both hands) with the only lantern left behind and
  no lever/rail that brings it back; nodes off the z = 0 plane (decor excluded); nothing walling an end.
**Proof:** "Validate all" on the 10 World 1 levels; paste the output (expected: only the known dead
hint triggers if not fixed yet); screenshot of the panel; break a link on purpose and show the error.
**Claude check:** each error checked by hand on the 10 levels: no false errors, none missed.

---
**Reminder in every prompt: do NOT commit or push until I personally say so.**
