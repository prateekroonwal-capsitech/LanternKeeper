class_name Enemy
extends CharacterBody3D

## Enemy — shared base for every creature (Crawler, Dropper, Stalker, SwarmMite, BigShadow).
##
## Life cycle: DORMANT (hidden in its lair — a crack, hole, ceiling or off-screen edge,
## placed in the level scene) → EMERGING (steps out to `emerge_offset`) → HUNT (the
## subclass hunts) → ATTACK (0.3 s telegraph wind-up then lunge) → (KILL | RETREAT),
## plus FROZEN while in light, and RETURNING back to lair if pinned in light.
## Nothing is instanced at runtime: every enemy is pre-placed in the level.
##
## Waking: a WakeTrigger with the same `wake_group`, or the player coming within
## `wake_distance` (0 = off).
##
## The lantern rule: enemies can never enter light (carried or placed) — they stop at the
## edge, hiss and pull back, and retreat if light reaches them. A child holding a lit
## lantern or standing inside lantern light can't be caught. Creatures only freeze when
## light reaches them; while the child is lit they keep stalking up to the light's edge.
##
## Sends: GameManager.report_enemy_woke(self), report_enemy_repelled(self),
##   report_player_caught(self)
## Receives: GameBus.enemies_wake_requested(group), GameBus.level_reset (back to dormant);
##   GameManager light / player queries (polled).

enum Mode { DORMANT, EMERGING, HUNT, FROZEN, ATTACK, RETREAT, RETURNING, ACTIVE = 2 }

enum AttackPhase { WINDUP, LUNGE }

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

@export_group("Attack")
## Distance to trigger attack wind-up.
@export var lunge_distance: float = 1.2
## Seconds of telegraph (eyes flare, hiss) before lunging.
@export var windup_time: float = 0.3
## Speed during the lunge.
@export var lunge_speed: float = 6.0
## Duration of the lunge movement in seconds.
@export var lunge_duration: float = 0.25
## Seconds backing away after a missed lunge or cancelled attack.
@export var retreat_time: float = 0.5
## Speed while retreating.
@export var retreat_speed: float = 4.0

@export_group("Debug")
## Print every state change (wake → hunt → attack → kill) to the output log.
@export var debug_log: bool = false

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

var _attack_phase: AttackPhase = AttackPhase.WINDUP
var _attack_timer: float = 0.0
var _lunge_dir: float = 1.0
var _retreat_timer: float = 0.0

@onready var _visual: Node3D = $Visual
@onready var _eyes: Node3D = $Visual/Eyes
@onready var _hurtbox: Area3D = get_node_or_null("Hurtbox")
@onready var _particles: CPUParticles3D = get_node_or_null("DarkParticles")

const _CHEST := Vector3(0.0, 0.7, 0.0)

func _ready() -> void:
	add_to_group(&"enemies")
	_home = global_position
	if has_node("Lair"):
		$Lair.global_position = _home + Vector3(0, 0, -0.05)
	_time = randf() * TAU
	set_physics_process(false)
	if is_instance_valid(_hurtbox):
		if not _hurtbox.body_entered.is_connected(_on_hurtbox_body_entered):
			_hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	_enter_dormant()

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.bus.enemies_wake_requested.connect(_on_wake_requested)
	set_physics_process(true)

# ── Life cycle ────────────────────────────────────────────────────────────

func wake() -> void:
	if mode != Mode.DORMANT or not _can_wake():
		return
	mode = Mode.EMERGING
	_emerge_t = 0.0
	_visual.visible = true
	_set_body_visible(true)
	_set_hurtbox_active(true)
	_set_particles_emitting(true)
	_eyes.modulate.a = 1.0
	_game.report_enemy_woke(self)
	_dbg("woke → emerging")
	_on_woke()

func _on_wake_requested(group: StringName) -> void:
	if group != &"" and group == wake_group:
		wake()

func capture_checkpoint_state() -> Dictionary:
	return {
		"mode": mode,
		"position": global_position,
		"relurk": _relurk,
		"home": _home
	}

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	if state.is_empty():
		_reset()
		return
	mode = state.get("mode", Mode.DORMANT)
	global_position = state.get("position", _home)
	_home = state.get("home", _home)
	if has_node("Lair"):
		$Lair.global_position = _home + Vector3(0, 0, -0.05)
	_relurk = state.get("relurk", false)
	velocity = Vector3.ZERO
	_lit_time = 0.0
	_hiss_timer = 0.0
	_speed_now = 0.0
	_attack_timer = 0.0
	_retreat_timer = 0.0
	if mode == Mode.DORMANT:
		_enter_dormant()
	else:
		_visual.visible = true
		_set_body_visible(true)
		_set_hurtbox_active(true)
		_set_particles_emitting(true)
		_eyes.modulate.a = 1.0
	reset_physics_interpolation()

func _reset() -> void:
	global_position = _home
	velocity = Vector3.ZERO
	_relurk = false
	_lit_time = 0.0
	_attack_timer = 0.0
	_retreat_timer = 0.0
	_enter_dormant()
	reset_physics_interpolation()

func _enter_dormant() -> void:
	mode = Mode.DORMANT
	_visual.visible = show_eyes_while_dormant
	_set_body_visible(false)
	_set_hurtbox_active(false)
	_set_particles_emitting(false)

func _set_body_visible(v: bool) -> void:
	var body := _visual.get_node_or_null("Body")
	if body:
		body.visible = v

func _set_hurtbox_active(active: bool) -> void:
	if is_instance_valid(_hurtbox):
		_hurtbox.set_deferred(&"monitoring", active)
		_hurtbox.set_deferred(&"monitorable", active)
		var col := _hurtbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col:
			col.set_deferred(&"disabled", not active)

func _set_particles_emitting(active: bool) -> void:
	if is_instance_valid(_particles):
		_particles.emitting = active

func _physics_process(delta: float) -> void:
	_time += delta
	_hiss_timer = maxf(_hiss_timer - delta, 0.0)
	_speed_now = 0.0
	if _game and _game.is_playing():
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
				_set_hurtbox_active(true)
				_set_particles_emitting(true)
				_emerge_t = minf(_emerge_t + delta / maxf(emerge_time, 0.01), 1.0)
				global_position = _home + emerge_offset * smoothstep(0.0, 1.0, _emerge_t)
				if _emerge_t >= 1.0:
					if _is_lit(global_position):
						mode = Mode.FROZEN
						velocity = Vector3.ZERO
						_repelled()
						_dbg("emerged into light → frozen")
					else:
						mode = Mode.HUNT
						_dbg("emerged → hunt")

			Mode.HUNT:
				# Freeze only when light reaches the creature itself. While the child is lit it
				# keeps stalking up to the light's edge (its _hunt stops there and hisses).
				if _is_lit(global_position):
					mode = Mode.FROZEN
					velocity = Vector3.ZERO
					_repelled()
					_dbg("light reached me → frozen")
				else:
					var p_pos := _game.get_player_position()
					var dist := _flat(p_pos - global_position).length()
					if not ignores_light and dist <= lunge_distance and not _game.player_lit and not _is_lit(global_position):
						_start_attack()
					else:
						_hunt(delta)
						_check_catch()
						_update_flee(delta)

			Mode.FROZEN:
				velocity = Vector3.ZERO
				_repelled()
				if not _is_lit(global_position):
					mode = Mode.HUNT
					_dbg("out of light → hunt")
				else:
					_update_flee(delta)

			Mode.ATTACK:
				_process_attack(delta)

			Mode.RETREAT:
				_process_retreat(delta)

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

# ── Attack state machine (Telegraph → Lunge → Kill / Retreat) ─────────────

func _start_attack() -> void:
	mode = Mode.ATTACK
	_dbg("in reach of child in darkness → telegraph")
	_attack_phase = AttackPhase.WINDUP
	_attack_timer = 0.0
	_lunge_dir = signf(_game.get_player_position().x - global_position.x)
	if _lunge_dir == 0.0:
		_lunge_dir = _move_dir
	_move_dir = _lunge_dir
	_repelled()

func _process_attack(delta: float) -> void:
	match _attack_phase:
		AttackPhase.WINDUP:
			_attack_timer += delta
			velocity = Vector3.ZERO
			# Cancel if player enters light during wind-up
			if not ignores_light and (_game.player_lit or _is_lit(global_position)):
				mode = Mode.RETREAT
				_retreat_timer = 0.0
				return
			if _attack_timer >= windup_time:
				_attack_phase = AttackPhase.LUNGE
				_attack_timer = 0.0
				_dbg("lunge")
				_lunge_dir = signf(_game.get_player_position().x - global_position.x)
				if _lunge_dir == 0.0:
					_lunge_dir = _move_dir
				_move_dir = _lunge_dir

		AttackPhase.LUNGE:
			_attack_timer += delta
			var spd := _speed(lunge_speed)
			_perform_lunge_step(spd, delta)
			_check_catch()
			if _attack_timer >= lunge_duration:
				mode = Mode.RETREAT
				_retreat_timer = 0.0

func _perform_lunge_step(spd: float, delta: float) -> void:
	velocity.x = _lunge_dir * spd
	velocity.z = 0.0
	move_and_slide()
	global_position.z = _home.z
	_speed_now = spd * delta

func _process_retreat(delta: float) -> void:
	_retreat_timer += delta
	var away := -signf(_game.get_player_position().x - global_position.x)
	if away == 0.0:
		away = -_move_dir
	_move_dir = away
	var spd := _speed(retreat_speed)
	_perform_retreat_step(away, spd, delta)
	if _retreat_timer >= retreat_time:
		if _is_lit(global_position):
			mode = Mode.FROZEN
		else:
			mode = Mode.HUNT

func _perform_retreat_step(away: float, spd: float, delta: float) -> void:
	velocity.x = away * spd
	velocity.z = 0.0
	move_and_slide()
	global_position.z = _home.z
	_speed_now = spd * delta

# ── Hurtbox & Catch ───────────────────────────────────────────────────────

func _on_hurtbox_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return
	if not ignores_light and _game and (_game.player_lit or _game.is_player_protected()):
		return
	if _game and _game.is_playing():
		_dbg("touched the child in darkness → caught")
		_game.report_player_caught(self)

func _check_catch() -> void:
	if not ignores_light and _game and (_game.player_lit or _game.is_player_protected()):
		return
	var chest := _game.get_player_position() + _CHEST
	if global_position.distance_to(chest) <= catch_radius + body_radius:
		if _game and _game.is_playing():
			_dbg("caught the child")
			_game.report_player_caught(self)

# ── Overridables ──────────────────────────────────────────────────────────

func _can_wake() -> bool:
	return true

func _on_woke() -> void:
	pass

func _hunt(_delta: float) -> void:
	pass

func _animate(delta: float) -> void:
	_visual.scale.x = -1.0 if _move_dir < 0.0 else 1.0
	# Subtle breathing animation
	var breathe := 1.0 + 0.035 * sin(_time * 2.8)
	_visual.scale.y = breathe
	
	# Idle twitch
	var twitch := sin(_time * 23.0) * 0.02 if fmod(_time, 3.5) < 0.25 else 0.0
	_visual.position.y = twitch

	# Eye telegraph flare in ATTACK windup
	if mode == Mode.ATTACK and _attack_phase == AttackPhase.WINDUP:
		_eyes.modulate = Color(5.2, 0.45, 0.35, 1.0)
		_eyes.scale = Vector3(1.3, 1.3, 1.3)
		_visual.position.x = -_move_dir * 0.04 * (_attack_timer / windup_time)
	elif mode == Mode.FROZEN:
		_eyes.modulate = Color(2.6, 0.18, 0.12, 1.0)
		_eyes.scale = Vector3(1.0, 1.0, 1.0)
		_visual.position.x = sin(_time * 40.0) * 0.03
	else:
		_eyes.modulate = Color(2.6, 0.18, 0.12, 1.0)
		_eyes.scale = Vector3(1.0, 1.0, 1.0)
		_visual.position.x = 0.0

## What the creature is doing, for its EnemyVisual (visual only): "idle", "move", "emerge",
## "windup", "lunge" or "flinch".
func get_visual_state() -> StringName:
	match mode:
		Mode.EMERGING:
			return &"emerge"
		Mode.FROZEN:
			return &"flinch"
		Mode.ATTACK:
			return &"windup" if _attack_phase == AttackPhase.WINDUP else &"lunge"
		Mode.HUNT, Mode.RETREAT, Mode.RETURNING:
			return &"move" if _speed_now > 0.0005 else &"idle"
	return &"idle"

func _dbg(msg: String) -> void:
	if debug_log:
		print("[%s %s] %s  at (%.1f, %.1f)" % [enemy_kind, name, msg, global_position.x, global_position.y])

# ── Helpers for subclasses ────────────────────────────────────────────────

func _speed(base: float) -> float:
	return base * (frenzy_multiplier if _game.is_dark_meter_empty() else 1.0)

func _is_lit(point: Vector3) -> bool:
	return not ignores_light and _game.is_point_lit(point, body_radius + light_margin)

func _repelled() -> void:
	if _hiss_timer <= 0.0:
		_hiss_timer = 0.8
		_game.report_enemy_repelled(self)

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
