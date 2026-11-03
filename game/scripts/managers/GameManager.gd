class_name GameManager
extends Node

## GameManager — the central hub of Lantern Keeper.
##
## Owns the game state (MENU / PLAYING / PAUSED / DEAD / LEVEL_COMPLETE), the current
## level, oil, the dark meter, the active checkpoint and a reference to every other
## manager. Gameplay scripts never talk to each other: they call a report_*() or
## register_*() method here, and GameManager relays the result through GameBus.
##
## Receives (method calls):
##   report_level_ready(level) / report_level_unloaded(level)  — LevelRoot
##   register_player(player)                                    — Player
##   register_light_source(src) / unregister_light_source(src)  — Lantern
##   register_lantern(lantern)                                  — Lantern (for is_lantern_carried / handle)
##   report_oil_burned(amount)                                  — Lantern
##   report_oil_collected(amount)                               — OilFlask
##   report_lantern_placed(at) / report_lantern_picked_up()     — Lantern
##   report_place_lantern_pressed() / report_pause_pressed()    — InputManager
##   report_platform_lost()                                     — GhostPlatform
##   report_player_died(cause)                                  — KillZone, Shadow
##   report_shrine_reached(shrine)                              — Shrine
##   report_level_exit_reached(menu_delay)                      — ExitPortal
##   report_lantern_lost()                                      — Lantern (fell into a pit)
##   report_enemy_woke(enemy) / report_enemy_repelled(enemy) /
##   report_player_caught(enemy) / report_wake_trigger(group)   — enemies, WakeTrigger
##   report_enemy_defeated(enemy)                               — Shade (crushed)
##   report_player_jumped() / report_player_landed(speed)       — Player (sound)
##   report_tutorial_trigger(hint_id)                           — TutorialTrigger
##   report_trap_sprung(trap)                                   — FallingTrap (rock, ceiling)
##   report_hiding_spot(spot, inside) / is_player_hidden()      — Crevice
##   report_player_pushing(direction)                           — Crate
##   report_camera_focus(point, duration)                       — FallingTrap (so the hit is seen)
##   report_fall_warning() / report_impact(point, size)         — FallFX (creak; thud, shake, vibration)
##   report_slow_motion(scale, duration)                        — Shade (crushed)
##   report_menu_ready()                                        — HomeScene (menu backdrop)
##   start_level(id), restart_level(), go_to_next_level(), go_to_level_select(),
##   go_to_main_menu(), quit_game(), pause()/resume()           — menus
##   set_volume(bus, v), set_control_layout(l), set_locale(code),
##   set_fullscreen(on) / is_fullscreen() / can_toggle_fullscreen() — Settings
## Sends (GameBus): game_state_changed, level_started, level_completed, oil_changed,
##   dark_meter_changed, dark_meter_emptied, dark_meter_recovered, lantern_place_requested,
##   lantern_placed, lantern_picked_up, platform_lost, player_died, player_respawned,
##   level_reset, checkpoint_saved, checkpoint_activated, enemy_woke, enemies_wake_requested,
##   trap_sprung, lever_pulled, camera_focus_requested, enemy_defeated, camera_shake_requested,
##   game_paused, game_resumed, game_started, game_over
##
## Checkpoints: at level start and at every new shrine GameManager saves a snapshot —
## the lantern's state (carried / placed + position) and the oil — and emits
## checkpoint_saved so every resettable object (enemies, triggers, crates…) stores its own
## state. On respawn the snapshot is restored exactly and level_reset tells the rest.
## Calls: UIManager (fades, menus), AudioManager (events, music, heartbeat), LevelManager
##   (loading, progress), TutorialManager (hints), SaveManager (settings), HapticsManager.
##
## Light sources are any node with get_light_position(), get_light_radius() and
## is_light_active(); is_point_lit() / is_box_lit() answer "is this spot in the light?".

enum State { MENU, PLAYING, PAUSED, DEAD, LEVEL_COMPLETE, GAME_OVER }

## A fall within this many seconds of a ghost platform vanishing is logged as "platform_lost".
const _PLATFORM_LOST_WINDOW := 1.5
## Height above the player's feet used for "is the player in the light?".
const _PLAYER_LIGHT_PROBE := Vector3(0.0, 0.8, 0.0)

var logger: Node
var bus: Node

# ── Managers (filled by GameService.register_managers) ────────────────────
var audio: AudioManager
var ui: UIManager
var save: SaveManager
var scene: SceneManager
var haptics: HapticsManager
var input: InputManager
var level: LevelManager
var tutorial: TutorialManager

# ── Game state ────────────────────────────────────────────────────────────
var state: State = State.MENU :
	set(v):
		if state == v:
			return
		state = v
		if logger:
			logger.info("GameManager state", { "state": State.keys()[v] })
		if bus:
			bus.game_state_changed.emit(v)

var current_level: LevelRoot = null
var current_level_id: String = ""

var oil: float = 0.0
var max_oil: float = 100.0
var dark_meter: float = 5.0
var dark_meter_max: float = 5.0

var checkpoint_position: Vector3 = Vector3.ZERO
var checkpoint_oil: float = 100.0
## Increments every time a new checkpoint is activated. Pickups use it to know
## whether they were collected after the active checkpoint (and must come back on respawn).
var checkpoint_serial: int = 0
## True while the player stands inside any light radius (updated every physics frame).
var player_lit: bool = true

var _player: Node3D = null
var _lantern: Node3D = null
var _active_shrine: Node3D = null
var _checkpoint_lantern: Dictionary = {}
var _checkpoint_enemies: Dictionary = {}
var _checkpoint_triggers: Dictionary = {}
var _checkpoint_resettables: Dictionary = {}
var _hook_in_reach: Node3D = null
var _hiding_spots: Array[Node3D] = []
var _last_hiss_at: float = -100.0
var _light_sources: Array[Node3D] = []
var _dark_emptied: bool = false
var _last_dark_ratio: float = -1.0
var _platform_lost_at: float = -100.0
var _menu_target: StringName = &"MainMenu"
var _transitioning: bool = false
var _heartbeat: float = 0.0

## Seconds between reaching the exit and the Level Complete screen.
const _LEVEL_COMPLETE_DELAY := 0.8
const _MASTER_VOLUME_KEY := "master_volume"
const _FULLSCREEN_KEY := "fullscreen"

func configure(p_logger: Node, p_bus: Node) -> void:
	logger = p_logger
	bus = p_bus

func register_managers(managers: Dictionary) -> void:
	audio = managers.get("audio")
	ui = managers.get("ui")
	save = managers.get("save")
	scene = managers.get("scene")
	haptics = managers.get("haptics")
	input = managers.get("input")
	level = managers.get("level")
	tutorial = managers.get("tutorial")
	_apply_saved_settings()

func _ready() -> void:
	set_physics_process(false)

# ── Template state API (kept for GameFlowFeature compatibility) ────────────

func start() -> void:
	if state != State.MENU:
		return
	state = State.PLAYING
	if bus:
		bus.game_started.emit()

func pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	_set_heartbeat(0.0)
	if ui:
		ui.open_menu(&"PauseMenu")
	if bus:
		bus.game_paused.emit()

func resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	get_tree().paused = false
	if ui:
		ui.close_all_menus()
	if bus:
		bus.game_resumed.emit()

func game_over(reason: String = "") -> void:
	state = State.GAME_OVER
	get_tree().paused = false
	if bus:
		bus.game_over.emit(reason)

func reset() -> void:
	state = State.MENU

func is_playing() -> bool:
	return state == State.PLAYING

# ── Level flow ────────────────────────────────────────────────────────────

func report_level_ready(level_root: LevelRoot) -> void:
	current_level = level_root
	current_level_id = level_root.level_id
	max_oil = maxf(level_root.max_oil, 1.0)
	oil = clampf(level_root.start_oil, 0.0, max_oil)
	dark_meter_max = maxf(level_root.dark_meter_time, 0.1)
	dark_meter = dark_meter_max
	checkpoint_position = level_root.get_spawn_position()
	checkpoint_oil = oil
	checkpoint_serial = 0
	_active_shrine = null
	player_lit = true
	_dark_emptied = false
	_last_dark_ratio = -1.0
	get_tree().paused = false
	state = State.PLAYING
	set_physics_process(true)
	_transitioning = false
	if ui:
		ui.close_all_menus()
		ui.fade_in()
	if audio:
		audio.play_world_music(level_root.world)
	if bus:
		bus.level_started.emit(current_level_id)
		bus.oil_changed.emit(oil, max_oil)
		bus.dark_meter_changed.emit(1.0)
	_save_checkpoint()

func report_level_unloaded(level_root: LevelRoot) -> void:
	if level_root != current_level:
		return
	current_level = null
	current_level_id = ""
	_player = null
	_lantern = null
	_active_shrine = null
	_light_sources.clear()
	_checkpoint_enemies.clear()
	_checkpoint_triggers.clear()
	_checkpoint_resettables.clear()
	_hook_in_reach = null
	_hiding_spots.clear()
	set_physics_process(false)
	_set_heartbeat(0.0)
	state = State.MENU

## `menu_delay`: seconds before the level-complete screen opens (the ExitPortal passes the
## length of its pull-in / flash / fade sequence).
func report_level_exit_reached(menu_delay: float = _LEVEL_COMPLETE_DELAY) -> void:
	if state != State.PLAYING:
		return
	state = State.LEVEL_COMPLETE
	_set_heartbeat(0.0)
	if level:
		level.mark_completed(current_level_id)
	if haptics:
		haptics.medium()
	if audio:
		audio.play_event(&"level_complete")
	if bus:
		bus.level_completed.emit(current_level_id)
	await get_tree().create_timer(menu_delay).timeout
	if state == State.LEVEL_COMPLETE and ui:
		ui.open_menu(&"LevelComplete")

# ── Navigation (menus → scenes, always through a fade) ─────────────────────

func start_level(level_id: String) -> void:
	if level == null or not level.has_level(level_id) or _transitioning:
		return
	await _leave_current_screen()
	level.load_level(level_id)

func restart_level() -> void:
	if not current_level_id.is_empty():
		start_level(current_level_id)

func go_to_next_level() -> void:
	var next := level.get_next_level_id(current_level_id) if level else ""
	if not next.is_empty() and level.has_level(next):
		start_level(next)
	else:
		go_to_level_select()

func go_to_level_select() -> void:
	_go_to_menu_scene(&"LevelSelect")

func go_to_main_menu() -> void:
	_go_to_menu_scene(&"MainMenu")

func has_next_level() -> bool:
	if level == null:
		return false
	var next := level.get_next_level_id(current_level_id)
	return not next.is_empty() and level.has_level(next)

func quit_game() -> void:
	if save:
		save.save_game()
	get_tree().quit()

## Called by the menu backdrop scene (Home) once it is wired up.
func report_menu_ready() -> void:
	state = State.MENU
	_transitioning = false
	get_tree().paused = false
	oil = max_oil
	if audio:
		audio.play_menu_music()
	if ui:
		ui.close_all_menus()
		ui.open_menu(_menu_target)
		ui.fade_in()

func _go_to_menu_scene(menu: StringName) -> void:
	if _transitioning or level == null or level.catalog == null:
		return
	_menu_target = menu
	await _leave_current_screen()
	scene.go_to(level.catalog.menu_scene_path)

func _leave_current_screen() -> void:
	_transitioning = true
	_set_heartbeat(0.0)
	if ui:
		await ui.fade_out()
		ui.close_all_menus()
	get_tree().paused = false
	state = State.MENU

# ── Player ────────────────────────────────────────────────────────────────

func register_player(player: Node3D) -> void:
	_player = player

func has_player() -> bool:
	return is_instance_valid(_player)

func get_player_position() -> Vector3:
	return _player.global_position if is_instance_valid(_player) else Vector3.ZERO

func get_player_hand_position() -> Vector3:
	return _player.get_hand_marker_position() if is_instance_valid(_player) and _player.has_method("get_hand_marker_position") else get_player_position()

## +1 facing right, -1 facing left.
func get_player_facing() -> int:
	return _player.facing if is_instance_valid(_player) else 1

func get_player_velocity() -> Vector3:
	return _player.velocity if is_instance_valid(_player) else Vector3.ZERO

func is_player_on_floor() -> bool:
	return _player.is_on_floor() if is_instance_valid(_player) else false

func report_player_died(cause: String) -> void:
	if state != State.PLAYING:
		return
	if cause == "fall" and _now() - _platform_lost_at < _PLATFORM_LOST_WINDOW:
		cause = "platform_lost"
	state = State.DEAD
	if logger:
		logger.info("Player died", { "cause": cause, "level": current_level_id })
	if haptics:
		haptics.heavy()
	if audio:
		audio.play_event(&"death")
	_set_heartbeat(0.0)
	if bus:
		bus.player_died.emit(cause)
	var delay := current_level.respawn_delay if is_instance_valid(current_level) else 0.25
	await get_tree().create_timer(delay, false).timeout
	if ui:
		await ui.fade_out()
	_respawn()
	if ui:
		ui.fade_in()

func get_respawn_position() -> Vector3:
	return checkpoint_position

## Interpolated (rendered) player position — for cameras and other per-frame visuals.
func get_player_visual_position() -> Vector3:
	return _player.get_global_transform_interpolated().origin if is_instance_valid(_player) else Vector3.ZERO

func get_player() -> Node3D:
	return _player if is_instance_valid(_player) else null

## Anything below this Y has fallen out of the level (LevelRoot.kill_y).
func get_kill_y() -> float:
	return current_level.kill_y if is_instance_valid(current_level) else -50.0

func _save_checkpoint() -> void:
	if is_instance_valid(_lantern):
		_checkpoint_lantern = _lantern.capture_state()
	checkpoint_oil = oil
	_checkpoint_enemies.clear()
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy.has_method("capture_checkpoint_state"):
			_checkpoint_enemies[enemy.get_path()] = enemy.capture_checkpoint_state()
	_checkpoint_triggers.clear()
	for trigger in get_tree().get_nodes_in_group(&"wake_triggers"):
		if trigger.has_method("capture_checkpoint_state"):
			_checkpoint_triggers[trigger.get_path()] = trigger.capture_checkpoint_state()
	_checkpoint_resettables.clear()
	for node in get_tree().get_nodes_in_group(&"resettables"):
		_checkpoint_resettables[node.get_path()] = node.capture_checkpoint_state()
	if bus:
		bus.checkpoint_saved.emit(checkpoint_serial)

func _respawn() -> void:
	if state != State.DEAD or not is_instance_valid(current_level):
		return
	oil = checkpoint_oil
	dark_meter = dark_meter_max
	player_lit = true
	_dark_emptied = false
	if bus:
		bus.level_reset.emit(checkpoint_serial)
		bus.player_respawned.emit()
		bus.oil_changed.emit(oil, max_oil)
		bus.dark_meter_changed.emit(1.0)
	# Hooks, gates and levers first, so a lantern restored onto a hook re-opens its gate.
	for node in get_tree().get_nodes_in_group(&"resettables"):
		node.reset_to_checkpoint(_checkpoint_resettables.get(node.get_path(), {}))
	if is_instance_valid(_lantern) and not _checkpoint_lantern.is_empty():
		_lantern.restore_state(_checkpoint_lantern)
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy.has_method("reset_to_checkpoint"):
			var st: Dictionary = _checkpoint_enemies.get(enemy.get_path(), {})
			enemy.reset_to_checkpoint(st)
	for trigger in get_tree().get_nodes_in_group(&"wake_triggers"):
		if trigger.has_method("reset_to_checkpoint"):
			var st: Dictionary = _checkpoint_triggers.get(trigger.get_path(), {})
			trigger.reset_to_checkpoint(st)
	state = State.PLAYING

# ── Shrines (checkpoint + full oil) ───────────────────────────────────────

## Shrines call this whenever the player touches them: full oil refill, and the
## shrine becomes the respawn point if it isn't already.
func report_shrine_reached(shrine: Node3D) -> void:
	if state != State.PLAYING:
		return
	oil = max_oil
	checkpoint_oil = max_oil
	dark_meter = dark_meter_max
	if bus:
		bus.oil_changed.emit(oil, max_oil)
	if shrine == _active_shrine:
		_save_checkpoint()   # touching the active shrine again refreshes the snapshot
		return
	if audio:
		audio.play_event(&"shrine")
	_active_shrine = shrine
	checkpoint_position = shrine.get_respawn_position()
	checkpoint_serial += 1
	_save_checkpoint()
	if haptics:
		haptics.medium()
	if logger:
		logger.info("Checkpoint", { "shrine": shrine.name, "serial": checkpoint_serial })
	if bus:
		bus.checkpoint_activated.emit(shrine)

func get_active_shrine() -> Node3D:
	return _active_shrine if is_instance_valid(_active_shrine) else null

# ── Lantern & oil ─────────────────────────────────────────────────────────

func report_place_lantern_pressed() -> void:
	if state == State.PLAYING and bus:
		bus.lantern_place_requested.emit()

func report_lantern_placed(at: Vector3) -> void:
	if audio:
		audio.play_event(&"lantern_place", true)
	if bus:
		bus.lantern_placed.emit(at)

func report_lantern_picked_up() -> void:
	if audio:
		audio.play_event(&"lantern_pickup")
	if haptics:
		haptics.light()
	if bus:
		bus.lantern_picked_up.emit()

func register_lantern(lantern: Node3D) -> void:
	_lantern = lantern

func is_lantern_raised() -> bool:
	return _lantern.is_raised() if is_instance_valid(_lantern) else false

func is_lantern_carried() -> bool:
	return _lantern.carried if is_instance_valid(_lantern) else false

func is_lantern_hung() -> bool:
	return _lantern.is_hung() if is_instance_valid(_lantern) else false

func get_lantern() -> Node3D:
	return _lantern

func get_light_sources() -> Array[Node3D]:
	return _light_sources

## World position of the lantern's handle (where the player's hand holds it).
func get_lantern_handle_position() -> Vector3:
	return _lantern.get_handle_position() if is_instance_valid(_lantern) else get_player_position()

## A placed lantern fell out of the level: put it down on safe ground beside the player.
func report_lantern_lost() -> void:
	if not is_instance_valid(_lantern) or _lantern.carried:
		return
	var spot: Variant = _player.find_lantern_spot() if is_instance_valid(_player) else null
	if spot == null:
		_lantern.return_to_hand()
	else:
		_lantern.respawn_at(spot)
	if audio:
		audio.play_event(&"lantern_return")
	if bus:
		bus.lantern_returned.emit()

func report_oil_burned(amount: float) -> void:
	if oil <= 0.0 or amount <= 0.0 or not uses_oil():
		return
	oil = maxf(oil - amount, 0.0)
	if bus:
		bus.oil_changed.emit(oil, max_oil)

func report_oil_collected(amount: float) -> void:
	oil = minf(oil + amount, max_oil)
	if audio:
		audio.play_event(&"oil_pickup", true)
	if haptics:
		haptics.light()
	if bus:
		bus.oil_changed.emit(oil, max_oil)

## False in levels with LevelRoot.oil_enabled off (the lantern never runs dry).
func uses_oil() -> bool:
	return current_level.oil_enabled if is_instance_valid(current_level) else true

func uses_dark_meter() -> bool:
	return current_level.dark_meter_enabled if is_instance_valid(current_level) else true

func get_oil_ratio() -> float:
	return oil / max_oil if max_oil > 0.0 else 0.0

# ── Light queries ─────────────────────────────────────────────────────────

func register_light_source(source: Node3D) -> void:
	if not _light_sources.has(source):
		_light_sources.append(source)

func unregister_light_source(source: Node3D) -> void:
	_light_sources.erase(source)

## True if `point` (X/Y plane) is inside any active light radius.
func is_point_lit(point: Vector3, padding: float = 0.0) -> bool:
	for source in _light_sources:
		if not is_instance_valid(source) or not source.is_light_active():
			continue
		var c: Vector3 = source.get_light_position()
		var r: float = source.get_light_radius() + padding
		if Vector2(point.x - c.x, point.y - c.y).length_squared() <= r * r:
			return true
	return false

## True if any part of the X/Y rectangle (center ± half_extents) is inside a light radius.
func is_box_lit(center: Vector3, half_extents: Vector2, padding: float = 0.0) -> bool:
	for source in _light_sources:
		if not is_instance_valid(source) or not source.is_light_active():
			continue
		var c: Vector3 = source.get_light_position()
		var r: float = source.get_light_radius() + padding
		var nearest := Vector2(
			clampf(c.x, center.x - half_extents.x, center.x + half_extents.x),
			clampf(c.y, center.y - half_extents.y, center.y + half_extents.y))
		if nearest.distance_squared_to(Vector2(c.x, c.y)) <= r * r:
			return true
	return false

## Position of the nearest active light source to `point` (X/Y plane), or `point` if none.
func get_nearest_light_position(point: Vector3) -> Vector3:
	var best := point
	var best_d := INF
	for source in _light_sources:
		if not is_instance_valid(source) or not source.is_light_active():
			continue
		var c: Vector3 = source.get_light_position()
		var d := Vector2(point.x - c.x, point.y - c.y).length_squared()
		if d < best_d:
			best_d = d
			best = c
	return best

# ── Hooks & levers ────────────────────────────────────────────────────────

func register_hook(_hook: Node3D) -> void:
	pass

func unregister_hook(hook: Node3D) -> void:
	if _hook_in_reach == hook:
		_hook_in_reach = null

## A LanternHook tells us the child entered / left its reach.
func report_hook_reach(hook: Node3D, inside: bool) -> void:
	if inside:
		_hook_in_reach = hook
	elif _hook_in_reach == hook:
		_hook_in_reach = null

## The hook the lantern would hang on if set down now (or null).
func get_hook_in_reach() -> Node3D:
	return _hook_in_reach if is_instance_valid(_hook_in_reach) else null

func report_lantern_hung(hook: Node3D) -> void:
	if audio:
		audio.play_event(&"lantern_place", true)
	if bus:
		bus.lantern_hook_changed.emit(hook.hook_id, true)
	if hook.wake_group_on_hang != &"":
		report_wake_trigger(hook.wake_group_on_hang)

func report_lantern_unhooked(hook: Node3D) -> void:
	if bus:
		bus.lantern_hook_changed.emit(hook.hook_id, false)

## A Rope's grab zone touched the child. Grab it if they're airborne and their hands are free.
func report_rope_touched(rope: Node3D) -> void:
	if state != State.PLAYING or not is_instance_valid(_player) or is_lantern_carried():
		return
	if _player.can_grab_rope():
		_player.attach_to_rope(rope)
		if audio:
			audio.play_event(&"land", true)

func report_lever_pulled(lever_id: StringName) -> void:
	if audio:
		audio.play_event(&"lantern_place", true)
	if bus:
		bus.lever_pulled.emit(lever_id)

## A falling trap landed. Creatures listening to trap_sprung ask the trap whether they were
## under it (trap.is_in_kill_zone(point)).
func report_trap_sprung(trap: Node3D) -> void:
	if state != State.PLAYING:
		return
	if haptics:
		haptics.medium()
	if audio:
		audio.play_event(&"land", true)
	if bus:
		bus.trap_sprung.emit(trap)

## Something important happens away from the child (a trap falling on a creature): the
## camera frames both for `duration` seconds.
func report_camera_focus(point: Vector3, duration: float) -> void:
	if bus and state == State.PLAYING:
		bus.camera_focus_requested.emit(point, duration)

## A hiding spot (Crevice) tells us the child went in / came out.
func report_hiding_spot(spot: Node3D, inside: bool) -> void:
	if inside and not _hiding_spots.has(spot):
		_hiding_spots.append(spot)
	elif not inside:
		_hiding_spots.erase(spot)

## True while the child is inside a hiding spot (creatures that hunt by sight can't see them).
func is_player_hidden() -> bool:
	return not _hiding_spots.is_empty()

## A crate is being pushed (1) / pulled (-1) by the child, or not (0): drives the push animation.
func report_player_pushing(direction: int) -> void:
	if is_instance_valid(_player) and _player.has_method("set_push_state"):
		_player.set_push_state(direction)

# ── Enemies ───────────────────────────────────────────────────────────────

## True while the player is inside any active lantern light radius (carried or placed): enemies can't touch them.
func is_player_protected() -> bool:
	if not is_instance_valid(_lantern) or not _lantern.is_light_active():
		return false
	if _lantern.carried:
		return true
	return player_lit

func report_wake_trigger(group: StringName) -> void:
	if bus and state == State.PLAYING:
		bus.enemies_wake_requested.emit(group)

func report_enemy_woke(enemy: Node3D) -> void:
	if audio:
		audio.play_event(&"enemy_wake", true)
	if bus:
		bus.enemy_woke.emit(enemy)

## An enemy hit the edge of a light. Rate-limited hiss.
func report_enemy_repelled(_enemy: Node3D) -> void:
	if audio and _now() - _last_hiss_at > 0.6:
		_last_hiss_at = _now()
		audio.play_event(&"enemy_hiss", true)

## A creature is beaten for good: gates waiting for it open (GameBus.enemy_defeated), with a
## rumble and a shake.
func report_enemy_defeated(enemy: Node3D) -> void:
	var kind: String = enemy.get("enemy_kind") if enemy.get("enemy_kind") else "enemy"
	print("[GameManager] enemy defeated: %s" % kind)
	if audio:
		audio.play_event(&"rumble")
	if bus:
		bus.camera_shake_requested.emit(0.18, 0.9)
		bus.enemy_defeated.emit(kind)

## Something is about to fall (FallFX anticipation): creak / crack.
func report_fall_warning() -> void:
	if audio and state == State.PLAYING:
		audio.play_event(&"fall_creak", true)

## Something heavy landed at `point`; `size` (≈0.3 plank … 2 ceiling) scales the shake.
func report_impact(_point: Vector3, size: float) -> void:
	if state != State.PLAYING and state != State.DEAD:
		return
	if audio:
		audio.play_event(&"fall_thud", true)
	if bus:
		bus.camera_shake_requested.emit(0.12 + 0.18 * size, 0.25 + 0.15 * size)
	if haptics:
		if size >= 1.0:
			haptics.heavy()
		else:
			haptics.medium()

## A brief slow-motion moment (Engine.time_scale), e.g. when the Shade is crushed.
func report_slow_motion(scale: float, duration: float) -> void:
	Engine.time_scale = clampf(scale, 0.05, 1.0)
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

func report_player_caught(enemy: Node3D) -> void:
	if state != State.PLAYING:
		return
	var kind: String = enemy.get("enemy_kind") if enemy.get("enemy_kind") else "enemy"
	report_player_died("caught_" + kind)

func report_platform_lost() -> void:
	_platform_lost_at = _now()
	if bus:
		bus.platform_lost.emit()

# ── Dark meter ────────────────────────────────────────────────────────────

func is_dark_meter_empty() -> bool:
	return _dark_emptied

func get_dark_meter_ratio() -> float:
	return dark_meter / dark_meter_max if dark_meter_max > 0.0 else 0.0

func _physics_process(delta: float) -> void:
	if state != State.PLAYING or not is_instance_valid(_player):
		return
	var lit := is_point_lit(_player.global_position + _PLAYER_LIGHT_PROBE)
	player_lit = lit
	if not uses_dark_meter():
		return
	if lit:
		var refill := current_level.dark_meter_refill_rate if is_instance_valid(current_level) else 2.0
		dark_meter = minf(dark_meter + delta * refill, dark_meter_max)
		if _dark_emptied:
			_dark_emptied = false
			if bus:
				bus.dark_meter_recovered.emit()
	else:
		dark_meter = maxf(dark_meter - delta, 0.0)
		if dark_meter <= 0.0 and not _dark_emptied:
			_dark_emptied = true
			if bus:
				bus.dark_meter_emptied.emit()
	var ratio := get_dark_meter_ratio()
	if absf(ratio - _last_dark_ratio) > 0.001:
		_last_dark_ratio = ratio
		if bus:
			bus.dark_meter_changed.emit(ratio)
	_update_heartbeat(ratio)

func _update_heartbeat(ratio: float) -> void:
	if audio == null or audio.library == null:
		return
	var threshold := audio.library.heartbeat_threshold
	var intensity := 0.0
	if threshold > 0.0 and ratio < threshold:
		intensity = clampf((threshold - ratio) / threshold, 0.05, 1.0)
	if absf(intensity - _heartbeat) > 0.02 or (intensity == 0.0) != (_heartbeat == 0.0):
		_set_heartbeat(intensity)

func _set_heartbeat(intensity: float) -> void:
	_heartbeat = intensity
	if audio:
		audio.set_heartbeat(intensity)

# ── Player sounds & tutorial ──────────────────────────────────────────────

func report_player_jumped() -> void:
	if audio and state == State.PLAYING:
		audio.play_event(&"jump", true)

func report_player_landed(fall_speed: float) -> void:
	if audio and state == State.PLAYING and fall_speed > 4.0:
		audio.play_event(&"land", true)

func report_tutorial_trigger(hint_id: String) -> void:
	if tutorial and state == State.PLAYING:
		tutorial.request_hint(hint_id)

# ── Settings (persisted through SaveManager) ──────────────────────────────

## bus_name: &"Master", &"Music" or &"SFX". linear 0..1.
func set_volume(bus_name: StringName, linear: float) -> void:
	if audio:
		audio.set_bus_volume(bus_name, linear)
	if save == null:
		return
	match bus_name:
		&"Music":
			if save.settings_data:
				save.settings_data.music_volume = linear
				save.settings.mark_dirty()
		&"SFX":
			if save.settings_data:
				save.settings_data.sfx_volume = linear
				save.settings.mark_dirty()
		_:
			save.set_value(_MASTER_VOLUME_KEY, linear)
	save.save_game()

func get_volume(bus_name: StringName) -> float:
	return audio.get_bus_volume(bus_name) if audio else 1.0

func set_control_layout(layout: StringName) -> void:
	if input:
		input.set_control_layout(layout)

func set_locale(locale: String) -> void:
	TranslationServer.set_locale(locale)
	if save and save.settings_data:
		save.settings_data.locale = locale
		save.settings.mark_dirty()
		save.save_game()

## Fullscreen or a resizable window (PC). Phones are always fullscreen; a game embedded in
## the editor's Game tab keeps the editor's sizing.
func set_fullscreen(on: bool) -> void:
	if save:
		save.set_value(_FULLSCREEN_KEY, on)
		save.save_game()
	_apply_window_mode(on)

func is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func can_toggle_fullscreen() -> bool:
	return not OS.has_feature("mobile") and not Engine.is_embedded_in_editor()

func _apply_window_mode(fullscreen: bool) -> void:
	if not can_toggle_fullscreen():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_saved_settings() -> void:
	if save == null:
		return
	_apply_window_mode(bool(save.get_value(_FULLSCREEN_KEY, true)))
	if audio:
		audio.set_bus_volume(&"Master", float(save.get_value(_MASTER_VOLUME_KEY, 1.0)))
		if save.settings_data:
			audio.set_bus_volume(&"Music", save.settings_data.music_volume)
			audio.set_bus_volume(&"SFX", save.settings_data.sfx_volume)
	if save.settings_data and not save.settings_data.locale.is_empty():
		TranslationServer.set_locale(save.settings_data.locale)

# ── Input relays ──────────────────────────────────────────────────────────

func report_pause_pressed() -> void:
	if _transitioning:
		return
	if state == State.PLAYING:
		pause()
	elif state == State.PAUSED:
		resume()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
