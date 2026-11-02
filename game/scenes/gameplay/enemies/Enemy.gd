class_name Enemy
extends CharacterBody3D

## Enemy — shared base for every creature (Crawler, Dropper, Stalker, SwarmMite, BigShadow).
##
## Life cycle: DORMANT (hidden in its lair — a crack, hole, ceiling or off-screen edge,
## placed in the level scene) → EMERGING (steps out to `emerge_offset`) → ACTIVE (the
## subclass hunts) → back to DORMANT at its spawn spot whenever the player respawns.
## If light pins it for `flee_after_lit_time`, it slips back into its lair (RETURNING)
## and lurks there, coming out again when the child is in darkness within `relurk_distance`.
## Nothing is instanced at runtime: every enemy is pre-placed in the level.
##
## Waking: a WakeTrigger with the same `wake_group`, or the player coming within
## `wake_distance` (0 = off).
##
## The lantern rule: enemies can never enter light (carried or placed) — they stop at the
## edge, hiss and pull back, and retreat if light reaches them. A child holding a lit
## lantern can't be caught at all. Lights shrink with oil, so enemies get closer as it runs
## down. When the dark meter is empty they move `frenzy_multiplier` faster.
## (BigShadow sets `ignores_light`: it can only be outrun.)
##
## Sends: GameManager.report_enemy_woke(self), report_enemy_repelled(self),
##   report_player_caught(self)
## Receives: GameBus.enemies_wake_requested(group), GameBus.level_reset (back to dormant);
##   GameManager light / player queries (polled).

enum Mode { DORMANT, EMERGING, ACTIVE, RETURNING }

## Used in the death cause ("caught_<kind>").
@export var enemy_kind: String = "enemy"

@export_group("Waking")
## Woken by any WakeTrigger with this group (empty = triggers ignored).
@export var wake_group: StringName = &""
## Also wakes when the player comes this close (0 = off).
@export var wake_distance: float = 0.0
## Where it steps out to, relative to its spawn spot.
@export var emerge_offset: Vector3 = Vector3.ZERO
@export var emerge_time: float = 0.5
## Faint blinking eyes in the lair while dormant (foreshadowing).
@export var show_eyes_while_dormant: bool = true

@export_group("Light")
## Body size used for light tests.
@export var body_radius: float = 0.35
## Extra gap it keeps from a light's edge.
@export var light_margin: float = 0.25
## True only for creatures that can only be outrun.
@export var ignores_light: bool = false
## Seconds pinned in light before it slips back into its lair (0 = never).
@export var flee_after_lit_time: float = 1.2
## After fleeing, it comes out again when the child is in darkness this close to the lair.
@export var relurk_distance: float = 10.0

@export_group("Catch")
## Touch distance from the child's chest.
@export var catch_radius: float = 0.55
## Speed multiplier once the dark meter is empty.
@export var frenzy_multiplier: float = 1.5

var mode: Mode = Mode.DORMANT

var _game: GameManager
var _home: Vector3
var _emerge_t: float = 0.0
var _time: float = 0.0
var _hiss_timer: float = 0.0
var _speed_now: float = 0.0
var _move_dir: float = 1.0
var _lit_time: float = 0.0
var _relurk: bool = false

@onready var _visual: Node3D = $Visual
@onready var _eyes: Node3D = $Visual/Eyes

const _CHEST := Vector3(0.0, 0.7, 0.0)

func _ready() -> void:
	_home = global_position
	_time = randf() * TAU
	set_physics_process(false)
	_enter_dormant()

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.bus.enemies_wake_requested.connect(_on_wake_requested)
	_game.bus.level_reset.connect(func(_serial: int) -> void: _reset())
	set_physics_process(true)

# ── Life cycle ────────────────────────────────────────────────────────────

func wake() -> void:
	if mode != Mode.DORMANT or not _can_wake():
		return
	mode = Mode.EMERGING
	_emerge_t = 0.0
	_visual.visible = true
	_eyes.modulate.a = 1.0
	_game.report_enemy_woke(self)
	_on_woke()

func _on_wake_requested(group: StringName) -> void:
	if group != &"" and group == wake_group:
		wake()

func _reset() -> void:
	global_position = _home
	velocity = Vector3.ZERO
	_relurk = false
	_lit_time = 0.0
	_enter_dormant()
	reset_physics_interpolation()

func _enter_dormant() -> void:
	mode = Mode.DORMANT
	_visual.visible = show_eyes_while_dormant
	_set_body_visible(false)

## Subclasses with a separate body sprite hide it while dormant (eyes stay).
func _set_body_visible(v: bool) -> void:
	var body := _visual.get_node_or_null("Body")
	if body:
		body.visible = v

func _physics_process(delta: float) -> void:
	_time += delta
	_hiss_timer = maxf(_hiss_timer - delta, 0.0)
	_speed_now = 0.0
	if _game.is_playing():
		match mode:
			Mode.DORMANT:
				_eyes.modulate.a = 0.25 + 0.25 * sin(_time * 2.0) if show_eyes_while_dormant else 0.0
				var near := _flat(_game.get_player_position() - _home).length()
				if wake_distance > 0.0 and near <= wake_distance:
					wake()
				elif _relurk and not _game.player_lit and near <= relurk_distance:
					wake()
			Mode.EMERGING:
				_set_body_visible(true)
				_emerge_t = minf(_emerge_t + delta / maxf(emerge_time, 0.01), 1.0)
				global_position = _home + emerge_offset * smoothstep(0.0, 1.0, _emerge_t)
				if _emerge_t >= 1.0:
					mode = Mode.ACTIVE
			Mode.ACTIVE:
				_hunt(delta)
				_check_catch()
				_update_flee(delta)
			Mode.RETURNING:
				var to := _home - global_position
				if to.length() < 0.1:
					global_position = _home
					_relurk = true
					_enter_dormant()
				else:
					global_position += to.normalized() * minf(8.0 * delta, to.length())
					_speed_now = 8.0 * delta
	_animate(delta)

func _update_flee(delta: float) -> void:
	if ignores_light or flee_after_lit_time <= 0.0:
		return
	if _is_lit(global_position + Vector3(0.0, 0.3, 0.0)):
		_lit_time += delta
		if _lit_time >= flee_after_lit_time:
			_lit_time = 0.0
			velocity = Vector3.ZERO
			mode = Mode.RETURNING
	else:
		_lit_time = 0.0

# ── Overridables ──────────────────────────────────────────────────────────

## Subclass condition for waking (e.g. swarm mites stay sealed while their hole is lit).
func _can_wake() -> bool:
	return true

func _on_woke() -> void:
	pass

func _hunt(_delta: float) -> void:
	pass

func _animate(_delta: float) -> void:
	_visual.scale.x = -1.0 if _move_dir < 0.0 else 1.0

func _check_catch() -> void:
	if not ignores_light and _game.is_player_protected():
		return
	var chest := _game.get_player_position() + _CHEST
	if global_position.distance_to(chest) <= catch_radius + body_radius:
		_game.report_player_caught(self)

# ── Helpers for subclasses ────────────────────────────────────────────────

func _speed(base: float) -> float:
	return base * (frenzy_multiplier if _game.is_dark_meter_empty() else 1.0)

func _is_lit(point: Vector3) -> bool:
	return not ignores_light and _game.is_point_lit(point, body_radius + light_margin)

func _repelled() -> void:
	if _hiss_timer <= 0.0:
		_hiss_timer = 0.8
		_game.report_enemy_repelled(self)

## Free-flying move toward `target` that never enters light: slides along the light's
## edge when blocked, retreats straight out if light reaches it.
func _float_toward(target: Vector3, speed: float, delta: float) -> void:
	var pos := global_position
	if _is_lit(pos):
		var away := _flat(pos - _game.get_nearest_light_position(pos))
		if away.length_squared() < 0.0001:
			away = Vector3.UP
		_float_step(away.normalized() * speed * 1.5 * delta)
		_repelled()
		return
	var to := _flat(target - pos)
	var dist := to.length()
	if dist < 0.02:
		return
	var step := to / dist * minf(speed * delta, dist)
	if not _is_lit(pos + step):
		_float_step(step)
		return
	# Blocked by light: circle along its edge.
	_repelled()
	var tangent := Vector3(-step.y, step.x, 0.0)
	for t in [tangent, -tangent]:
		if not _is_lit(pos + t * 0.6):
			_float_step(t * 0.6)
			return

func _float_step(step: Vector3) -> void:
	global_position += step
	global_position.z = _home.z
	_speed_now = step.length()
	if absf(step.x) > 0.001:
		_move_dir = signf(step.x)

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, 0.0)
