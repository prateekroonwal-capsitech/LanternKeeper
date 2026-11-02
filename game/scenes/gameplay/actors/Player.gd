class_name Player
extends CharacterBody3D

## Player — the silhouette figure. Run, jump with coyote time, jump buffer and
## variable height. Movement is locked to the X/Y plane. No double jump.
##
## Sends: GameManager.register_player(self)
## Receives: input state from GameManager.input (move_axis, jump_held, jump_just_pressed);
##   GameBus.player_respawned → teleports to GameManager.get_respawn_position().

@export_group("Run")
@export var run_speed: float = 6.5
@export var ground_acceleration: float = 60.0
@export var ground_deceleration: float = 70.0
@export var air_acceleration: float = 40.0
@export var air_deceleration: float = 20.0

@export_group("Jump")
@export var jump_velocity: float = 12.0
@export var gravity: float = 32.0
## Gravity multiplier while falling, for a snappier arc.
@export var fall_gravity_multiplier: float = 1.5
@export var max_fall_speed: float = 22.0
## Upward speed is multiplied by this when jump is released early (variable height).
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.45
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.1

@export_group("Feel")
@export var land_squash: float = 0.18
@export var jump_stretch: float = 0.12
@export var squash_recovery: float = 12.0

## +1 facing right, -1 facing left. Read by GameManager.get_player_facing().
var facing: int = 1

var _game: GameManager
var _coyote_timer: float = 0.0
var _buffer_timer: float = 0.0
var _jump_rising: bool = false
var _was_on_floor: bool = true
var _squash: float = 0.0

@onready var _sprite: Sprite3D = $Sprite
@onready var _sprite_base_scale: Vector3 = _sprite.scale

func _ready() -> void:
	set_physics_process(false)

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.register_player(self)
	_game.bus.player_respawned.connect(_on_player_respawned)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not _game.is_playing():
		return
	var input := _game.input
	var on_floor := is_on_floor()

	# Horizontal
	var target := input.move_axis * run_speed
	var rate: float
	if absf(input.move_axis) > 0.01:
		rate = ground_acceleration if on_floor else air_acceleration
		facing = 1 if input.move_axis > 0.0 else -1
	else:
		rate = ground_deceleration if on_floor else air_deceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)

	# Coyote time + jump buffer
	_coyote_timer = coyote_time if on_floor else _coyote_timer - delta
	_buffer_timer = jump_buffer_time if input.jump_just_pressed else _buffer_timer - delta
	if _buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_rising = true
		_squash = -jump_stretch

	# Variable jump height
	if _jump_rising and not input.jump_held and velocity.y > 0.0:
		velocity.y *= jump_cut_multiplier
		_jump_rising = false
	if velocity.y <= 0.0:
		_jump_rising = false

	# Gravity
	if not on_floor:
		var g := gravity * (fall_gravity_multiplier if velocity.y < 0.0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)

	velocity.z = 0.0
	move_and_slide()
	global_position.z = 0.0

	if is_on_floor() and not _was_on_floor:
		_squash = land_squash
	_was_on_floor = is_on_floor()
	_update_visual(delta)

func _update_visual(delta: float) -> void:
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-squash_recovery * delta))
	_sprite.flip_h = facing < 0
	_sprite.scale = Vector3(
		_sprite_base_scale.x * (1.0 + _squash),
		_sprite_base_scale.y * (1.0 - _squash),
		_sprite_base_scale.z)

func _on_player_respawned() -> void:
	global_position = _game.get_respawn_position()
	velocity = Vector3.ZERO
	facing = 1
	_coyote_timer = 0.0
	_buffer_timer = 0.0
	_jump_rising = false
	_squash = 0.0
	reset_physics_interpolation()
