class_name Player
extends CharacterBody3D

## Player — the silhouette child. Run, jump (coyote time, jump buffer, one fixed height:
## holding or releasing the button early changes nothing), no double jump. Movement is locked to the X/Y plane and happens only in _physics_process
## (physics interpolation smooths the rendering). Tuned to feel soft and weighty: gentle
## acceleration, a short landing recovery, eased squash.
##
## Animation (Body = AnimatedSprite3D, game/assets/sprites/player/player_frames.tres):
##   idle, walk, run, jump_start, jump_rise, fall, land — each with a "_carry" twin drawn
##   where the near arm is drawn into the frames holding the lantern (hand at hip height,
##   always at the same pixel). raise_carry / raise_walk_carry hold it overhead.
##   place, push, pull, death, respawn.
##   HandMarker sits exactly on that hand point (flipped with facing, squashed with the
##   body); the lantern hangs its handle from it.
##
## Sends: GameManager.register_player(self), report_player_jumped(), report_player_landed(speed)
## Receives: input state from GameManager.input; GameManager.is_lantern_carried(),
##   get_lantern_handle_position(), is_lantern_raised() (polled);
##   GameBus.player_respawned → teleport + respawn animation; GameBus.player_died → death pose;
##   GameBus.lantern_placed → place pose. find_lantern_spot() is called by GameManager.
##   set_push_state() is for pushable objects (crates) to drive push / pull.
##   attach_to_rope(rope) is called by GameManager when the child grabs a Rope; jump lets go.

@export_group("Run")
@export var run_speed: float = 5.2
@export var ground_acceleration: float = 24.0
@export var ground_deceleration: float = 30.0
@export var air_acceleration: float = 16.0
@export var air_deceleration: float = 8.0

@export_group("Jump")
## Every jump rises exactly this high (m), whatever the control or how long it is held.
@export var jump_height: float = 2.16
@export var gravity: float = 27.0
## Gravity multiplier while falling.
@export var fall_gravity_multiplier: float = 1.35
@export var max_fall_speed: float = 20.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.2

@export_group("Landing")
## Falls faster than this (m/s) play the land crouch and slow the child briefly.
@export var land_min_fall_speed: float = 5.0
@export var land_recovery_time: float = 0.12
## Speed multiplier during the landing recovery.
@export_range(0.0, 1.0) var land_recovery_speed_scale: float = 0.45
@export var land_squash: float = 0.1
@export var jump_stretch: float = 0.06
## How fast squash eases in and out.
@export var squash_speed: float = 14.0

@export_group("Animation")
@export var walk_anim_threshold: float = 0.35
@export var run_anim_threshold: float = 3.4
@export var walk_anim_reference_speed: float = 2.2
@export var run_anim_reference_speed: float = 5.2
@export var jump_start_time: float = 0.1
@export var place_anim_time: float = 0.3
## Input is ignored for this long while the respawn animation plays.
@export var respawn_lock_time: float = 0.3

@export_group("Lantern hand")
## Hand point in the carry frames, metres from the feet (facing right).
## = HAND_CARRY px in tools/generate_player.py × pixel_size 0.009.
@export var hand_carry_point: Vector2 = Vector2(0.135, 0.594)
## Hand point in the raise_* frames.
@export var hand_raise_point: Vector2 = Vector2(0.144, 1.152)
## How far in front of the body the lantern hangs (towards the camera).
@export var hand_depth: float = 0.06

@export_group("Lost lantern")
## Side distances tried when putting a lost lantern down beside the child.
@export var lantern_spot_offsets: PackedFloat32Array = PackedFloat32Array([0.8, -0.8, 1.4, -1.4, 0.0])

## +1 facing right, -1 facing left. Read by GameManager.get_player_facing().
var facing: int = 1

var _game: GameManager
var _coyote_timer: float = 0.0
var _buffer_timer: float = 0.0
var _jump_rising: bool = false
var _was_on_floor: bool = true
var _squash: float = 0.0
var _squash_target: float = 0.0
var _land_timer: float = 0.0
var _jump_start_timer: float = 0.0
var _place_timer: float = 0.0
var _respawn_timer: float = 0.0
var _dead_pose: bool = false
var _push_state: int = 0
var _rope: Node3D = null
var _rope_cooldown: float = 0.0

@onready var _body: AnimatedSprite3D = $Body
@onready var _body_base_scale: Vector3 = _body.scale
@onready var _probe: RayCast3D = $LanternProbe
@onready var _hand_marker: Marker3D = $HandMarker

func get_hand_marker_position() -> Vector3:
	return _hand_marker.global_position

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

## Crates call this: 1 = pushing, -1 = pulling, 0 = neither.
func set_push_state(state: int) -> void:
	_push_state = state

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not _game.is_playing():
		_update_visual(delta)
		return
	if is_instance_valid(_rope):
		_hang_on_rope(delta)
		return
	var input := _game.input
	var on_floor := is_on_floor()
	var axis := input.move_axis if _respawn_timer <= 0.0 else 0.0
	var jump_pressed := input.jump_just_pressed and _respawn_timer <= 0.0

	# Horizontal — soft acceleration, briefly slowed after a hard landing
	var speed_scale := land_recovery_speed_scale if _land_timer > 0.0 else 1.0
	var target := axis * run_speed * speed_scale
	var rate: float
	if absf(axis) > 0.01:
		rate = ground_acceleration if on_floor else air_acceleration
		facing = 1 if axis > 0.0 else -1
	else:
		rate = ground_deceleration if on_floor else air_deceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)

	# Coyote time + jump buffer
	_coyote_timer = coyote_time if on_floor else _coyote_timer - delta
	_buffer_timer = jump_buffer_time if jump_pressed else _buffer_timer - delta
	if _buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = sqrt(2.0 * gravity * jump_height)
		_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_rising = true
		_jump_start_timer = jump_start_time
		_squash_target = -jump_stretch
		_game.report_player_jumped()

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
		_game.report_player_landed(fall_speed)
		if fall_speed >= land_min_fall_speed:
			_land_timer = land_recovery_time
			_squash_target = land_squash
	_was_on_floor = is_on_floor()
	_update_visual(delta)

## Called by GameManager when the child jumps into a rope (and isn't carrying the lantern).
func can_grab_rope() -> bool:
	return _rope == null and _rope_cooldown <= 0.0 and not is_on_floor()

func attach_to_rope(rope: Node3D) -> void:
	_rope = rope
	rope.grab(float(facing))
	velocity = Vector3.ZERO

## Hands at the rope end; the body hangs below. Jump lets go with the rope's speed.
func _hang_on_rope(delta: float) -> void:
	global_position = _rope.get_hang_point() - Vector3(0.0, 1.25, 0.0)
	global_position.z = 0.0
	if _game.input.jump_just_pressed:
		velocity = _rope.release()
		_rope = null
		_rope_cooldown = 0.4
		_jump_rising = false
		_game.report_player_jumped()
	_update_visual(delta)

func _tick_timers(delta: float) -> void:
	_rope_cooldown = maxf(_rope_cooldown - delta, 0.0)
	_land_timer = maxf(_land_timer - delta, 0.0)
	_place_timer = maxf(_place_timer - delta, 0.0)
	_jump_start_timer = maxf(_jump_start_timer - delta, 0.0)
	_respawn_timer = maxf(_respawn_timer - delta, 0.0)

# ── Visuals (transform changes stay in the physics step) ──────────────────

func _update_visual(delta: float) -> void:
	_squash = lerpf(_squash, _squash_target, 1.0 - exp(-squash_speed * delta))
	_squash_target = lerpf(_squash_target, 0.0, 1.0 - exp(-squash_speed * 0.6 * delta))
	_body.flip_h = facing < 0
	_body.scale = Vector3(_body_base_scale.x * (1.0 + _squash), _body_base_scale.y * (1.0 - _squash), _body_base_scale.z)

	var anim := _pick_animation()
	# The hand is drawn at a fixed pixel in every carry frame — keep the marker on it.
	var hand := hand_raise_point if anim.begins_with("raise") else hand_carry_point
	_hand_marker.position = Vector3(hand.x * facing * (1.0 + _squash), hand.y * (1.0 - _squash), hand_depth)
	if _body.animation != anim:
		_body.play(anim)
	var speed := absf(velocity.x)
	if anim.begins_with("walk"):
		_body.speed_scale = clampf(speed / walk_anim_reference_speed, 0.5, 1.6)
	elif anim.begins_with("run"):
		_body.speed_scale = clampf(speed / run_anim_reference_speed, 0.6, 1.4)
	else:
		_body.speed_scale = 1.0

func _pick_animation() -> StringName:
	if _game and not _game.is_playing():
		return &"idle_carry" if _game.is_lantern_carried() else &"idle"
	if _dead_pose:
		return &"death"
	if _respawn_timer > 0.0:
		return &"respawn"
	if _place_timer > 0.0:
		return &"place"
	var carry := _game.is_lantern_carried()
	if _push_state != 0 and not carry:
		return &"push" if _push_state > 0 else &"pull"
	var base: String
	if is_instance_valid(_rope):
		base = "fall"          # arms up, hanging on
	elif not is_on_floor():
		if _jump_start_timer > 0.0:
			base = "jump_start"
		elif velocity.y > 0.3:
			base = "jump_rise"
		else:
			base = "fall"
	elif _land_timer > 0.0:
		base = "land"
	else:
		var speed := absf(velocity.x)
		if carry and _game.is_lantern_raised():
			base = "raise" if speed < walk_anim_threshold else "raise_walk"
		elif speed < walk_anim_threshold:
			base = "idle"
		elif speed < run_anim_threshold:
			base = "walk"
		else:
			base = "run"
	if carry:
		base += "_carry"
	return StringName(base)

# ── Lost lantern: find solid ground beside the child ──────────────────────

## Returns a ground point beside the child where a lost lantern can sit, or null.
func find_lantern_spot() -> Variant:
	for offset in lantern_spot_offsets:
		var side := offset * facing
		var start := global_position + Vector3(side, 1.0, 0.0)
		# Don't put it on the far side of a wall.
		_probe.global_position = global_position + Vector3(0.0, 1.0, 0.0)
		_probe.target_position = Vector3(side, 0.0, 0.0)
		_probe.force_raycast_update()
		if _probe.is_colliding():
			continue
		_probe.global_position = start
		_probe.target_position = Vector3(0.0, -2.5, 0.0)
		_probe.force_raycast_update()
		if _probe.is_colliding() and _probe.get_collision_normal().y > 0.7:
			return _probe.get_collision_point()
	return null

# ── Events ────────────────────────────────────────────────────────────────

func _on_player_died(cause: String) -> void:
	_dead_pose = cause != "fall" and cause != "platform_lost"

func _on_player_respawned() -> void:
	_rope = null
	_rope_cooldown = 0.0
	global_position = _game.get_respawn_position()
	velocity = Vector3.ZERO
	facing = 1
	_coyote_timer = 0.0
	_buffer_timer = 0.0
	_jump_rising = false
	_squash = 0.0
	_squash_target = 0.0
	_land_timer = 0.0
	_place_timer = 0.0
	_jump_start_timer = 0.0
	_push_state = 0
	_dead_pose = false
	_was_on_floor = true
	_respawn_timer = respawn_lock_time
	_body.play(&"respawn")
	reset_physics_interpolation()
