class_name Lantern
extends CharacterBody3D

## Lantern — the one light. Carried, it follows the player's hand; placed, it drops
## to the nearest surface below (solid ground, or a ghost platform it lights itself)
## and lights that spot. Placing or picking up the lantern is a deliberate action (Place button, swipe down, or E).
## In JUGNOO mode (World 1) fireflies pulse gently at a constant radius without burning fuel;
## in OIL mode (World 2+) it burns oil (3× while raised), shrinking and flickering as fuel runs low.
##
## Hooks: set down while the child is within a LanternHook's reach, it hangs from the hook
## (no gravity, follows the hook if it rides a rail) instead of dropping.
##
## A level can hold several lanterns. When the child picks up a different one, GameManager
## calls retire() on the one they held last: its light fades and its motes drift out, then it
## is hidden and switched off (never freed), so a checkpoint from before can bring it back.
##
## Checkpoints: GameManager calls capture_state() when a checkpoint is saved and
## restore_state() on respawn, so a lantern that was placed is back where it was.
## A placed lantern that falls below the level's kill height reports report_lantern_lost();
## GameManager then calls respawn_at() with a safe spot beside the player.
##
## Sends: GameManager.register_lantern(self) / unregister_lantern(self),
##   register_light_source(self) / unregister_light_source(self), report_oil_burned(amount),
##   report_lantern_placed(at), report_lantern_picked_up(self), report_lantern_lost(self)
## Receives: GameBus.lantern_place_requested → place; GameManager.input.raise_held,
##   GameManager.get_oil_ratio(), GameManager.get_kill_y() (polled);
##   capture_state() / restore_state() / respawn_at() / retire() from GameManager.
## Light-source API (used by GameManager.is_point_lit): get_light_position(),
##   get_light_radius(), is_light_active().

@export var start_carried: bool = true

@export_group("Light")
## Radius with a full tank.
@export var base_radius: float = 4.5
## Radius just before the oil runs out. At 0 oil the light goes out.
@export var min_radius: float = 1.6
@export var raise_radius_multiplier: float = 1.6
## How fast the visible radius eases toward its target.
@export var radius_smoothing: float = 6.0
## OmniLight range relative to the gameplay radius (ambience only).
@export var light_range_scale: float = 1.25
@export var light_energy: float = 2.2

@export_group("Oil")
## Oil units burned per second.
@export var burn_rate: float = 2.0
@export var raise_burn_multiplier: float = 3.0

@export_group("Carry")
## Where the lantern's handle sits relative to the player's feet (fallback if HandMarker missing).
@export var carry_offset: Vector3 = Vector3(0.26, 0.64, 0.01)
## Added to carry_offset while the light is raised (X mirrored with facing).
@export var raise_offset: Vector3 = Vector3(0.02, 0.31, 0.0)
## Height of the handle relative to lantern origin (0.0 since pivot is at the handle).
@export var handle_height: float = 0.0
@export var max_sway_angle: float = 0.35
@export var sway_speed: float = 10.0

@export_group("Placed")
@export var gravity: float = 25.0
@export var max_fall_speed: float = 20.0

@export_group("Flicker")
@export var flicker_strength: float = 0.1
@export var flicker_speed: float = 9.0
## Below this oil ratio the flicker grows toward low_oil_flicker_strength.
@export_range(0.0, 1.0) var low_oil_ratio: float = 0.25
@export var low_oil_flicker_strength: float = 0.45
## Seconds of the flicker-in effect when the lantern reappears beside the player.
@export var appear_time: float = 0.6

@export_group("Retire")
## Seconds the light takes to fade out when the child picks up a different lantern.
@export var retire_time: float = 0.8
## Upward pull on the motes while they drift out.
@export var retire_drift: float = 1.2

enum Retire { ACTIVE, FADING, GONE }

var carried: bool = true

var _game: GameManager
var _radius: float = 0.0
var _raised: bool = false
var _player_in_reach: bool = false
var _time: float = 0.0
var _flicker: float = 1.0
var _appear: float = 1.0
var _sway: float = 0.0
var _hook: Node3D = null
var _retire: Retire = Retire.ACTIVE
var _retire_fade: float = 1.0
var _dust_gravity: Vector3

const OIL_LIGHT_COLOR := Color(1.0, 0.62, 0.28, 1.0)
const OIL_GLOW_COLOR := Color(1.0, 0.60, 0.22, 1.0)
const OIL_DUST_COLOR := Color(1.0, 0.75, 0.45, 1.0)

const JUGNOO_LIGHT_COLOR := Color(0.74, 0.96, 0.36, 1.0)
const JUGNOO_GLOW_COLOR := Color(0.74, 0.96, 0.36, 1.0)
const JUGNOO_DUST_COLOR := Color(0.82, 0.98, 0.46, 1.0)

@onready var _light: OmniLight3D = $Light
@onready var _glow: MeshInstance3D = $Glow
@onready var _glow_material: ShaderMaterial = _glow.material_override
@onready var _dust: CPUParticles3D = $Dust
@onready var _sprite: Sprite3D = $Sprite
@onready var _jar_sprite: Sprite3D = $JarSprite
@onready var _fireflies: CPUParticles3D = $Fireflies
@onready var _pickup_area: Area3D = $PickupArea
@onready var _light_area: Area3D = $LightArea
@onready var _light_area_shape: CollisionShape3D = $LightArea/CollisionShape3D
@onready var _body_shape: CollisionShape3D = $CollisionShape3D
@onready var _pickup_shape: CollisionShape3D = $PickupArea/CollisionShape3D

func _ready() -> void:
	# Run after the Player each physics tick, so the hand it follows is this tick's hand.
	process_physics_priority = 10
	carried = start_carried
	_dust_gravity = _dust.gravity
	set_physics_process(false)
	set_process(false)
	_pickup_area.body_entered.connect(_on_pickup_body_entered)
	_pickup_area.body_exited.connect(_on_pickup_body_exited)
	_apply_type()

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.register_lantern(self)
	_game.register_light_source(self)
	_game.bus.lantern_place_requested.connect(_on_place_requested)
	_game.bus.level_started.connect(func(_id: String) -> void:
		_apply_type()
		if carried:
			_snap_to_hand())
	_radius = base_radius
	_apply_type()
	set_physics_process(true)
	set_process(true)

func _apply_type() -> void:
	var is_oil := _game != null and _game.uses_oil()
	if _sprite:
		_sprite.visible = is_oil
	if _jar_sprite:
		_jar_sprite.visible = not is_oil
	if _fireflies:
		_fireflies.visible = not is_oil
		_fireflies.emitting = not is_oil and is_light_active()
	var light_col := OIL_LIGHT_COLOR if is_oil else JUGNOO_LIGHT_COLOR
	var glow_col := OIL_GLOW_COLOR if is_oil else JUGNOO_GLOW_COLOR
	var dust_col := OIL_DUST_COLOR if is_oil else JUGNOO_DUST_COLOR
	if _light:
		_light.light_color = light_col
	if _glow_material:
		_glow_material.set_shader_parameter(&"glow_color", glow_col)
	if _dust:
		_dust.color = dust_col

func _exit_tree() -> void:
	if _game:
		_game.unregister_light_source(self)
		_game.unregister_lantern(self)

# ── Light-source API ──────────────────────────────────────────────────────

func get_handle_position() -> Vector3:
	return global_position

func get_light_position() -> Vector3:
	return global_position + Vector3(0.0, -0.2, 0.0)   # centre of the glass (pivot = handle)

func get_light_radius() -> float:
	return _radius * _appear * _retire_fade

func is_light_active() -> bool:
	return get_light_radius() > 0.05

func is_raised() -> bool:
	return _raised

func is_hung() -> bool:
	return is_instance_valid(_hook)

## True from the moment it starts fading: it no longer counts as a lantern in play.
func is_retired() -> bool:
	return _retire != Retire.ACTIVE

## The child picked up a different lantern: fade this one out, then hide and switch it off.
func retire() -> void:
	if is_retired():
		return
	carried = false
	_raised = false
	_retire = Retire.FADING
	_dust.gravity = Vector3(0.0, retire_drift, 0.0)

func _finish_retire() -> void:
	_retire = Retire.GONE
	_retire_fade = 0.0
	_release_hook()
	velocity = Vector3.ZERO
	visible = false
	_dust.emitting = false
	if _fireflies:
		_fireflies.emitting = false
	_set_shapes_disabled(true)
	_update_transforms()

func _unretire() -> void:
	_retire = Retire.ACTIVE
	_retire_fade = 1.0
	visible = true
	_dust.gravity = _dust_gravity
	_set_shapes_disabled(false)
	_apply_type()

func _set_shapes_disabled(off: bool) -> void:
	_body_shape.set_deferred(&"disabled", off)
	_pickup_shape.set_deferred(&"disabled", off)
	_light_area_shape.set_deferred(&"disabled", off)

# ── Checkpoint snapshot (called by GameManager) ───────────────────────────

func capture_state() -> Dictionary:
	return { "carried": carried, "position": global_position, "retired": is_retired(),
		"hook": _hook.get_path() if is_instance_valid(_hook) else NodePath() }

func restore_state(state: Dictionary) -> void:
	velocity = Vector3.ZERO
	_raised = false
	_appear = 1.0
	_release_hook()
	if state.get("retired", false):
		carried = false
		_finish_retire()
		return
	_unretire()
	var hook_path: NodePath = state.get("hook", NodePath())
	if not hook_path.is_empty() and has_node(hook_path):
		carried = false
		_hang_on(get_node(hook_path))
	elif state.get("carried", true):
		carried = true
		_snap_to_hand()
	else:
		carried = false
		global_position = state.get("position", global_position)
		reset_physics_interpolation()

## Puts a lost lantern down at `point` (on the ground) with a flicker-in.
func respawn_at(point: Vector3) -> void:
	_release_hook()
	carried = false
	velocity = Vector3.ZERO
	global_position = Vector3(point.x, point.y, 0.0)
	reset_physics_interpolation()
	_appear = 0.0

func return_to_hand() -> void:
	_release_hook()
	carried = true
	velocity = Vector3.ZERO
	_snap_to_hand()

# ── Simulation ────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _retire == Retire.GONE:
		return
	_appear = move_toward(_appear, 1.0, delta / maxf(appear_time, 0.01))
	if _retire == Retire.FADING:
		_retire_fade = move_toward(_retire_fade, 0.0, delta / maxf(retire_time, 0.01))
		if _retire_fade <= 0.0:
			_finish_retire()
			return
	if _game and _game.is_playing():
		_simulate(delta)
	elif _game:
		_simulate_menu(delta)
	_update_transforms()

func _simulate_menu(delta: float) -> void:
	_radius = base_radius
	if carried:
		global_position = _hand_position()
		var sway_target := sin(_time * 2.2) * 0.04
		_sway = lerpf(_sway, sway_target, 1.0 - exp(-sway_speed * delta))
		rotation.z = _sway

func _simulate(delta: float) -> void:
	var is_oil := _game != null and _game.uses_oil()
	if not is_oil:
		# JUGNOO: skips raise and burn; radius stays at base_radius.
		_raised = false
		_radius = base_radius
	else:
		# OIL path unchanged
		var oil_ratio := _game.get_oil_ratio() if _game else 1.0
		_raised = carried and _game and _game.uses_raise() and _game.input.raise_held and oil_ratio > 0.0

		# One shared tank: only the active lantern burns it.
		if _game and _game.get_lantern() == self:
			var burn := burn_rate * (raise_burn_multiplier if _raised else 1.0)
			_game.report_oil_burned(burn * delta)

		var target := 0.0
		if oil_ratio > 0.0:
			target = lerpf(min_radius, base_radius, oil_ratio)
			if _raised:
				target *= raise_radius_multiplier
		_radius = lerpf(_radius, target, 1.0 - exp(-radius_smoothing * delta))
		if target == 0.0 and _radius < 0.05:
			_radius = 0.0

	if carried:
		# The handle sits exactly on the child's HandMarker; only the pendulum sway moves it.
		global_position = _hand_position()
		var p_vel := _game.get_player_velocity() if _game else Vector3.ZERO
		var sway_target := -clampf(p_vel.x * 0.045, -max_sway_angle, max_sway_angle)
		if absf(p_vel.x) < 0.1:
			sway_target = sin(_time * 2.2) * 0.03
		_sway = lerpf(_sway, sway_target, 1.0 - exp(-sway_speed * delta))
		rotation.z = _sway
	else:
		_sway = lerpf(_sway, 0.0, 1.0 - exp(-sway_speed * delta))
		rotation.z = _sway
		_simulate_placed(delta)

func _hand_position() -> Vector3:
	if _game and _game.has_player():
		return _game.get_player_hand_position()
	var facing := _game.get_player_facing() if _game else 1
	var offset := carry_offset + (raise_offset if _raised else Vector3.ZERO)
	var p := _game.get_player_position() if _game else Vector3.ZERO
	return p + Vector3(offset.x * facing, offset.y, offset.z)

func _snap_to_hand() -> void:
	if _game == null:
		return
	global_position = _hand_position()
	reset_physics_interpolation()

func _simulate_placed(delta: float) -> void:
	if is_instance_valid(_hook):
		global_position = _hook.get_hook_point()
		velocity = Vector3.ZERO
		return
	velocity.x = 0.0
	velocity.z = 0.0
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	move_and_slide()
	global_position.z = 0.06
	if global_position.y < _game.get_kill_y():
		_game.report_lantern_lost(self)

## Transform-affecting visuals live in the physics step so interpolation stays smooth.
func _update_transforms() -> void:
	var r := maxf(get_light_radius(), 0.001)
	_glow.scale = Vector3(r, r, 1.0)
	if is_instance_valid(_light_area_shape) and _light_area_shape.shape is SphereShape3D:
		(_light_area_shape.shape as SphereShape3D).radius = r

# ── Visuals (non-transform) ───────────────────────────────────────────────

func _process(delta: float) -> void:
	if _retire == Retire.GONE:
		return
	_time += delta
	var is_oil := _game != null and _game.uses_oil()
	if not is_oil:
		# JUGNOO: gentle pulse and no low-oil look
		_flicker = 1.0 + 0.06 * (sin(_time * 2.2) * 0.7 + sin(_time * 4.1 + 0.8) * 0.3)
	else:
		# OIL: flicker increases as oil runs low
		var ratio := _game.get_oil_ratio() if _game else 1.0
		var strength := flicker_strength
		if ratio < low_oil_ratio:
			strength = lerpf(low_oil_flicker_strength, flicker_strength, ratio / maxf(low_oil_ratio, 0.001))
		_flicker = 1.0 + strength * (
			sin(_time * flicker_speed) * 0.5
			+ sin(_time * flicker_speed * 2.3 + 1.7) * 0.3
			+ sin(_time * flicker_speed * 5.1 + 0.4) * 0.2)
	if _appear < 1.0:
		_flicker *= 0.5 + 0.5 * signf(sin(_time * 60.0))  # stutter while flickering in
	var r := get_light_radius()
	var lit := r > 0.05
	_light.visible = lit
	_glow.visible = lit
	_dust.emitting = lit
	if _fireflies:
		_fireflies.emitting = lit and not is_oil
	var alpha := _appear * _retire_fade
	_sprite.modulate.a = alpha
	if _jar_sprite:
		_jar_sprite.modulate.a = alpha
	if not lit:
		_sprite.modulate = Color(0.35, 0.35, 0.4, alpha)
		if _jar_sprite:
			_jar_sprite.modulate = Color(0.35, 0.35, 0.4, alpha)
		return
	_light.omni_range = r * light_range_scale
	_light.light_energy = light_energy * _flicker * alpha
	_glow_material.set_shader_parameter(&"flicker", _flicker * alpha)
	_dust.emission_sphere_radius = r * 0.8
	if not is_oil:
		_sprite.modulate = Color(1.0, 1.0, 1.0, alpha)
		if _jar_sprite:
			_jar_sprite.modulate = Color(1.0, 1.0, 1.0, alpha)
	else:
		var ratio := _game.get_oil_ratio() if _game else 1.0
		var warmth := clampf(ratio * 1.5, 0.4, 1.0)
		_sprite.modulate = Color(1.0, warmth, warmth * 0.9, alpha)

# ── Place / pick up ───────────────────────────────────────────────────────

func _on_place_requested() -> void:
	if is_retired():
		return
	if carried:
		carried = false
		_raised = false
		rotation.z = 0.0
		_sway = 0.0
		var hook := _game.get_hook_in_reach()
		if is_instance_valid(hook):
			_hang_on(hook)
			return
		var p := _game.get_player_position()
		global_position = Vector3(p.x, p.y + 0.6, 0.06)
		rotation.z = 0.0
		_sway = 0.0
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		_game.report_lantern_placed(global_position)
	else:
		if not is_player_in_reach():
			return
		if is_instance_valid(_hook) and _hook.is_moving():
			return   # can't snatch it from a moving cradle
		if _game and _game.is_playing():
			carried = true
			_release_hook()
			_game.report_lantern_picked_up(self)

func _on_pickup_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_player_in_reach = true

func _on_pickup_body_exited(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_player_in_reach = false

func is_player_in_reach() -> bool:
	if _player_in_reach:
		return true
	if is_instance_valid(_pickup_area):
		for b in _pickup_area.get_overlapping_bodies():
			if b.is_in_group(&"player"):
				return true
	return false

func _hang_on(hook: Node3D) -> void:
	_hook = hook
	global_position = hook.get_hook_point()
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_game.report_lantern_hung(hook)

func _release_hook() -> void:
	if is_instance_valid(_hook):
		var h := _hook
		_hook = null
		_game.report_lantern_unhooked(h)
	_hook = null
