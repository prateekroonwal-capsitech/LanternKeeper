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
##   report_oil_burned(amount)                                  — Lantern
##   report_oil_collected(amount)                               — OilFlask
##   report_lantern_placed(at) / report_lantern_picked_up()     — Lantern
##   report_place_lantern_pressed() / report_pause_pressed()    — InputManager
##   report_platform_lost()                                     — GhostPlatform
##   report_player_died(cause)                                  — KillZone (Phase 3: shadows)
##   report_level_exit_reached()                                — LevelExit
## Sends (GameBus): game_state_changed, level_started, level_completed, oil_changed,
##   dark_meter_changed, dark_meter_emptied, dark_meter_recovered, lantern_place_requested,
##   lantern_placed, lantern_picked_up, platform_lost, player_died, player_respawned,
##   level_reset, game_paused, game_resumed, game_started, game_over
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

var _player: Node3D = null
var _light_sources: Array[Node3D] = []
var _dark_emptied: bool = false
var _last_dark_ratio: float = -1.0
var _platform_lost_at: float = -100.0

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
	if bus:
		bus.game_paused.emit()

func resume() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	get_tree().paused = false
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
	_dark_emptied = false
	_last_dark_ratio = -1.0
	get_tree().paused = false
	state = State.PLAYING
	set_physics_process(true)
	if bus:
		bus.level_started.emit(current_level_id)
		bus.oil_changed.emit(oil, max_oil)
		bus.dark_meter_changed.emit(1.0)

func report_level_unloaded(level_root: LevelRoot) -> void:
	if level_root != current_level:
		return
	current_level = null
	current_level_id = ""
	_player = null
	_light_sources.clear()
	set_physics_process(false)
	state = State.MENU

func report_level_exit_reached() -> void:
	if state != State.PLAYING:
		return
	state = State.LEVEL_COMPLETE
	if level:
		level.mark_completed(current_level_id)
	if haptics:
		haptics.medium()
	if bus:
		bus.level_completed.emit(current_level_id)

# ── Player ────────────────────────────────────────────────────────────────

func register_player(player: Node3D) -> void:
	_player = player

func has_player() -> bool:
	return is_instance_valid(_player)

func get_player_position() -> Vector3:
	return _player.global_position if is_instance_valid(_player) else Vector3.ZERO

## +1 facing right, -1 facing left.
func get_player_facing() -> int:
	return _player.facing if is_instance_valid(_player) else 1

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
	if bus:
		bus.player_died.emit(cause)
	var delay := current_level.respawn_delay if is_instance_valid(current_level) else 0.5
	await get_tree().create_timer(delay, false).timeout
	_respawn()

func get_respawn_position() -> Vector3:
	return checkpoint_position

func _respawn() -> void:
	if state != State.DEAD or not is_instance_valid(current_level):
		return
	oil = checkpoint_oil
	dark_meter = dark_meter_max
	_dark_emptied = false
	if bus:
		bus.level_reset.emit(checkpoint_serial)
		bus.player_respawned.emit()
		bus.oil_changed.emit(oil, max_oil)
		bus.dark_meter_changed.emit(1.0)
	state = State.PLAYING

# ── Lantern & oil ─────────────────────────────────────────────────────────

func report_place_lantern_pressed() -> void:
	if state == State.PLAYING and bus:
		bus.lantern_place_requested.emit()

func report_lantern_placed(at: Vector3) -> void:
	if bus:
		bus.lantern_placed.emit(at)

func report_lantern_picked_up() -> void:
	if haptics:
		haptics.light()
	if bus:
		bus.lantern_picked_up.emit()

func report_oil_burned(amount: float) -> void:
	if oil <= 0.0 or amount <= 0.0:
		return
	oil = maxf(oil - amount, 0.0)
	if bus:
		bus.oil_changed.emit(oil, max_oil)

func report_oil_collected(amount: float) -> void:
	oil = minf(oil + amount, max_oil)
	if haptics:
		haptics.light()
	if bus:
		bus.oil_changed.emit(oil, max_oil)

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

# ── Input relays ──────────────────────────────────────────────────────────

func report_pause_pressed() -> void:
	if state == State.PLAYING:
		pause()
	elif state == State.PAUSED:
		resume()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
