class_name Player
extends CharacterBody3D

## Player — the silhouette boy. Run, jump with coyote time, jump buffer and
## variable height. Movement is locked to the X/Y plane. No double jump.
##
## Animation (Body = AnimatedSprite3D, frames in player_frames.tres):
##   idle / walk / run / jump / fall / land — each has a "_carry" twin drawn without
##   the lantern arm; while carrying, ArmPivot/Arm is aimed at the lantern handle so
##   the hand stays on the lantern in every pose (including raised).
##   place — one-shot crouch when the lantern is set down.
##   death — one-shot collapse when caught by a shadow (falls keep the fall pose).
##
## Sends: GameManager.register_player(self), report_player_jumped(), report_player_landed(speed)
## Receives: input state from GameManager.input (move_axis, jump_held, jump_just_pressed);
##   GameManager.is_lantern_carried() / get_lantern_handle_position() (polled);
##   GameBus.player_respawned → teleport to the checkpoint; GameBus.player_died → death pose;
##   GameBus.lantern_placed → place pose.

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
@export var land_squash: float = 0.14
@export var jump_stretch: float = 0.1
@export var squash_recovery: float = 12.0

@export_group("Animation")
## Horizontal speed below which the boy idles.
@export var walk_anim_threshold: float = 0.4
## Horizontal speed above which walk becomes run.
@export var run_anim_threshold: float = 4.0
## Speeds at which walk / run animations play at their authored rate.
@export var walk_anim_reference_speed: float = 2.6
@export var run_anim_reference_speed: float = 6.5
## Falls faster than this (m/s) play the land crouch.
@export var land_anim_min_fall_speed: float = 6.0
@export var land_anim_time: float = 0.16
@export var place_anim_time: float = 0.28

@export_group("Lantern arm")
## Shoulder position relative to the feet (metres, facing right).
@export var shoulder_offset: Vector2 = Vector2(0.006, 0.918)
## Arm length in metres at scale 1 (player_arm.png).
@export var arm_length: float = 0.4
## The arm stretches/shortens within this range to reach the handle.
@export var arm_stretch_range: Vector2 = Vector2(0.7, 1.25)

## +1 facing right, -1 facing left. Read by GameManager.get_player_facing().
var facing: int = 1

var _game: GameManager
var _coyote_timer: float = 0.0
var _buffer_timer: float = 0.0
var _jump_rising: bool = false
var _was_on_floor: bool = true
var _squash: float = 0.0
var _land_timer: float = 0.0
var _place_timer: float = 0.0
var _dead_pose: bool = false

@onready var _body: AnimatedSprite3D = $Body
@onready var _body_base_scale: Vector3 = _body.scale
@onready var _arm_pivot: Node3D = $ArmPivot

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
	_game.bus.player_died.connect(_on_player_died)
	_game.bus.lantern_placed.connect(func(_at: Vector3) -> void: _place_timer = place_anim_time)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not _game.is_playing():
		_update_visual(delta)
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
		_game.report_player_jumped()

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
	var fall_speed := -velocity.y
	move_and_slide()
	global_position.z = 0.0

	if is_on_floor() and not _was_on_floor:
		_squash = land_squash
		_game.report_player_landed(fall_speed)
		if fall_speed >= land_anim_min_fall_speed:
			_land_timer = land_anim_time
	_was_on_floor = is_on_floor()
	_update_visual(delta)

# ── Visuals ───────────────────────────────────────────────────────────────

func _update_visual(delta: float) -> void:
	_land_timer = maxf(_land_timer - delta, 0.0)
	_place_timer = maxf(_place_timer - delta, 0.0)
	_squash = lerpf(_squash, 0.0, 1.0 - exp(-squash_recovery * delta))
	_body.flip_h = facing < 0
	_body.scale = Vector3(
		_body_base_scale.x * (1.0 + _squash),
		_body_base_scale.y * (1.0 - _squash),
		_body_base_scale.z)

	var anim := _pick_animation()
	if _body.animation != anim:
		_body.play(anim)
	var speed := absf(velocity.x)
	if anim.begins_with("walk"):
		_body.speed_scale = clampf(speed / walk_anim_reference_speed, 0.5, 1.6)
	elif anim.begins_with("run"):
		_body.speed_scale = clampf(speed / run_anim_reference_speed, 0.6, 1.4)
	else:
		_body.speed_scale = 1.0
	_update_arm()

func _pick_animation() -> StringName:
	if _dead_pose:
		return &"death"
	if _place_timer > 0.0:
		return &"place"
	var base: String
	if not is_on_floor():
		base = "jump" if velocity.y > 0.5 else "fall"
	elif _land_timer > 0.0:
		base = "land"
	else:
		var speed := absf(velocity.x)
		if speed < walk_anim_threshold:
			base = "idle"
		elif speed < run_anim_threshold:
			base = "walk"
		else:
			base = "run"
	if _game.is_lantern_carried():
		base += "_carry"
	return StringName(base)

func _update_arm() -> void:
	var show := _game.is_lantern_carried() and not _dead_pose and _place_timer <= 0.0
	_arm_pivot.visible = show
	if not show:
		return
	_arm_pivot.position = Vector3(shoulder_offset.x * facing, shoulder_offset.y * (1.0 - _squash), _arm_pivot.position.z)
	var to := _game.get_lantern_handle_position() - _arm_pivot.global_position
	var reach := Vector2(to.x, to.y)
	_arm_pivot.rotation.z = atan2(reach.y, reach.x)
	var stretch := clampf(reach.length() / maxf(arm_length, 0.01), arm_stretch_range.x, arm_stretch_range.y)
	_arm_pivot.scale = Vector3(stretch, 1.0, 1.0)

# ── Events ────────────────────────────────────────────────────────────────

func _on_player_died(cause: String) -> void:
	_dead_pose = cause != "fall" and cause != "platform_lost"

func _on_player_respawned() -> void:
	global_position = _game.get_respawn_position()
	velocity = Vector3.ZERO
	facing = 1
	_coyote_timer = 0.0
	_buffer_timer = 0.0
	_jump_rising = false
	_squash = 0.0
	_land_timer = 0.0
	_place_timer = 0.0
	_dead_pose = false
	_was_on_floor = true
	reset_physics_interpolation()
