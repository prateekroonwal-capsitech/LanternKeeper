class_name Lantern
extends CharacterBody3D

## Lantern — the one light. Carried, it follows the player's hand; placed, it
## drops to the ground and lights that spot. Walking into a placed lantern picks
## it up again. Burns oil (3× while raised); its radius shrinks with the oil.
##
## Sends: GameManager.register_light_source(self) / unregister_light_source(self),
##   report_oil_burned(amount), report_lantern_placed(at), report_lantern_picked_up()
## Receives: GameBus.lantern_place_requested → place; GameBus.player_respawned → back to hand;
##   GameManager.input.raise_held, GameManager.get_oil_ratio()
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
## Hand offset from the player's feet; X is mirrored with facing.
@export var carry_offset: Vector3 = Vector3(0.5, 0.95, 0.3)
@export var follow_speed: float = 22.0

@export_group("Placed")
@export var gravity: float = 25.0
@export var max_fall_speed: float = 20.0
## A placed lantern that falls this far is returned to the player.
@export var lost_fall_distance: float = 25.0

@export_group("Flicker")
@export var flicker_strength: float = 0.12
@export var flicker_speed: float = 9.0

var carried: bool = true

var _game: GameManager
var _radius: float = 0.0
var _raised: bool = false
var _awaiting_exit: bool = false
var _placed_y: float = 0.0
var _time: float = 0.0

@onready var _light: OmniLight3D = $Light
@onready var _glow: MeshInstance3D = $Glow
@onready var _glow_material: ShaderMaterial = _glow.material_override
@onready var _dust: CPUParticles3D = $Dust
@onready var _sprite: Sprite3D = $Sprite
@onready var _pickup_area: Area3D = $PickupArea

func _ready() -> void:
	carried = start_carried
	set_physics_process(false)
	set_process(false)
	_pickup_area.body_entered.connect(_on_pickup_body_entered)
	_pickup_area.body_exited.connect(_on_pickup_body_exited)

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.register_light_source(self)
	_game.bus.lantern_place_requested.connect(_on_place_requested)
	_game.bus.player_respawned.connect(_return_to_player)
	_game.bus.level_started.connect(func(_id: String) -> void:
		if carried:
			_snap_to_hand())
	_radius = base_radius
	set_physics_process(true)
	set_process(true)

func _exit_tree() -> void:
	if _game:
		_game.unregister_light_source(self)

# ── Light-source API ──────────────────────────────────────────────────────

func get_light_position() -> Vector3:
	return global_position + Vector3(0.0, 0.35, 0.0)

func get_light_radius() -> float:
	return _radius

func is_light_active() -> bool:
	return _radius > 0.05

# ── Simulation ────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _game.is_playing():
		return
	var oil_ratio := _game.get_oil_ratio()
	_raised = carried and _game.input.raise_held and oil_ratio > 0.0

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
		_follow_hand(delta)
	else:
		_simulate_placed(delta)

func _follow_hand(delta: float) -> void:
	var target := _hand_position()
	global_position = global_position.lerp(target, 1.0 - exp(-follow_speed * delta))

func _hand_position() -> Vector3:
	var facing := _game.get_player_facing()
	var raise := Vector3(0.0, 0.5, 0.0) if _raised else Vector3.ZERO
	return _game.get_player_position() + Vector3(carry_offset.x * facing, carry_offset.y, carry_offset.z) + raise

func _snap_to_hand() -> void:
	global_position = _hand_position()
	reset_physics_interpolation()

func _simulate_placed(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)
	move_and_slide()
	global_position.z = 0.0
	if global_position.y < _placed_y - lost_fall_distance:
		_return_to_player()

# ── Visuals ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time += delta
	var flicker := 1.0 + flicker_strength * (
		sin(_time * flicker_speed) * 0.5
		+ sin(_time * flicker_speed * 2.3 + 1.7) * 0.3
		+ sin(_time * flicker_speed * 5.1 + 0.4) * 0.2)
	var visible_light := _radius > 0.05
	_light.visible = visible_light
	_glow.visible = visible_light
	_dust.emitting = visible_light
	if not visible_light:
		_sprite.modulate = Color(0.35, 0.35, 0.4)
		return
	_light.omni_range = _radius * light_range_scale
	_light.light_energy = light_energy * flicker
	_glow.scale = Vector3(_radius, _radius, 1.0)
	_glow_material.set_shader_parameter(&"flicker", flicker)
	_dust.emission_sphere_radius = _radius * 0.8
	var warmth := clampf(_game.get_oil_ratio() * 1.5, 0.4, 1.0)
	_sprite.modulate = Color(1.0, warmth, warmth * 0.9)

# ── Place / pick up ───────────────────────────────────────────────────────

func _on_place_requested() -> void:
	if not carried:
		return
	carried = false
	_raised = false
	_awaiting_exit = true
	global_position = Vector3(_game.get_player_position().x, _game.get_player_position().y + 0.3, 0.0)
	_placed_y = global_position.y
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_game.report_lantern_placed(global_position)

func _on_pickup_body_entered(body: Node3D) -> void:
	if carried or _awaiting_exit or not body.is_in_group(&"player"):
		return
	if _game and _game.is_playing():
		carried = true
		_game.report_lantern_picked_up()

func _on_pickup_body_exited(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_awaiting_exit = false

func _return_to_player() -> void:
	carried = true
	_awaiting_exit = false
	velocity = Vector3.ZERO
	# Deferred: on respawn the player may teleport after this handler runs.
	_snap_to_hand.call_deferred()
