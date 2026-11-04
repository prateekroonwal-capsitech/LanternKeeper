class_name Player
extends CharacterBody3D

## Player — the silhouette child. Run, jump (coyote time, jump buffer, variable height),
## no double jump. Movement is locked to the X/Y plane and happens only in _physics_process
## (physics interpolation smooths the rendering). Tuned to feel soft and weighty: gentle
## acceleration, a short landing recovery, eased squash.
##
## Animation (Body = AnimatedSprite3D, game/assets/sprites/player/player_frames.tres):
##   idle, walk, run, jump_start, jump_rise, fall, land — each with a "_carry" twin drawn
##   where the near arm is drawn into the frames holding the lantern (hand at hip height,
##   always at the same pixel). raise_carry / raise_walk_carry hold it overhead.
##   place, place_feet, pickup, hook_reach: the bends. The lantern leaves or joins the hand at
##   bend_reach_frame (frame_changed signal, not a timer); HandMarker follows the drawn hand.
##   push, push_carry (one arm, lantern hand at the side): shown only with the hands at the
##   box, the Body nudged so they sit on the box edge. pull, death, respawn.
##   rope_grab, rope_hang, rope_let_go: play by themselves on a rope, the Body tilted with the
##   rope and hung from it by the hands. rope_climb_up / rope_climb_down exist as frames only:
##   the rope has no climbing, so nothing plays them yet.
##   HandMarker sits exactly on that hand point (flipped with facing, squashed with the
##   body); the lantern hangs its handle from it.
##
## Sends: GameManager.register_player(self), report_player_jumped(), report_player_landed(speed)
## Receives: input state from GameManager.input; GameManager.is_lantern_carried(),
##   get_lantern_handle_position(), is_lantern_raised() (polled);
##   GameBus.player_respawned → teleport + respawn animation; GameBus.player_died → death pose;
##   GameBus.lantern_place_requested → bend, then Lantern.drop_from_hand() / take_in_hand() at the
##   reach frame (Lantern.can_pick_up(), GameManager.get_lanterns(), get_hook_in_reach() polled).
##   find_lantern_spot() is called by GameManager.
##   set_push_state() is for pushable objects (crates) to drive push / pull.
##   attach_to_rope(rope) is called by GameManager when the child grabs a Rope; jump lets go.

@export_group("Run")
@export var run_speed: float = 5.2
@export var ground_acceleration: float = 24.0
@export var ground_deceleration: float = 30.0
@export var air_acceleration: float = 16.0
@export var air_deceleration: float = 8.0

@export_group("Jump")
@export var jump_velocity: float = 10.8
@export var gravity: float = 27.0
## Gravity multiplier while falling.
@export var fall_gravity_multiplier: float = 1.35
@export var max_fall_speed: float = 20.0
## Upward speed is multiplied by this when jump is released early (variable height).
@export_range(0.0, 1.0) var jump_cut_multiplier: float = 0.5
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
## Input is ignored for this long while the respawn animation plays.
@export var respawn_lock_time: float = 0.1

@export_group("Lantern hand")
## Hand point in the carry frames, metres from the feet (facing right).
## = HAND_CARRY px in tools/generate_player.py × pixel_size 0.009.
@export var hand_carry_point: Vector2 = Vector2(0.135, 0.594)
## Hand point in the raise_* frames.
@export var hand_raise_point: Vector2 = Vector2(0.144, 1.152)
## How far in front of the body the lantern hangs (towards the camera).
@export var hand_depth: float = 0.06

@export_group("Bend")
## Movement is locked this long when the child bends to place or pick up the lantern.
@export var bend_lock_time: float = 0.3
## How far in front of the feet the lantern is set down (facing direction).
@export var place_forward_offset: float = 0.4
## Extra floor needed past the place point, so the lantern isn't left hanging over an edge.
@export var place_edge_margin: float = 0.16
## Height above the feet the front check starts from.
@export var place_probe_height: float = 0.35
## No floor within this far below the feet at the front point: set it down at the feet.
@export var place_max_drop: float = 0.5
## Frame of the bend animations where the hand is at the lantern.
@export var bend_reach_frame: int = 2
## Hand point in each frame of place / pickup, metres from the feet (facing right).
## = BEND_PATH px in tools/generate_player.py × pixel_size 0.009.
@export var bend_hand_path: PackedVector2Array = PackedVector2Array([Vector2(0.135, 0.594), Vector2(0.234, 0.486), Vector2(0.396, 0.423), Vector2(0.234, 0.486), Vector2(0.135, 0.594)])
## Same for place_feet (FEET_PATH).
@export var feet_hand_path: PackedVector2Array = PackedVector2Array([Vector2(0.135, 0.594), Vector2(0.108, 0.486), Vector2(0.09, 0.423), Vector2(0.108, 0.486), Vector2(0.135, 0.594)])
## Same for hook_reach (HOOK_PATH).
@export var hook_hand_path: PackedVector2Array = PackedVector2Array([Vector2(0.135, 0.594), Vector2(0.198, 0.828), Vector2(0.306, 1.062), Vector2(0.198, 0.828), Vector2(0.135, 0.594)])

@export_group("Push")
## Hand point in the push frames (HAND_PUSH px × 0.009).
@export var hand_push_point: Vector2 = Vector2(0.324, 0.63)
## The push pose starts once the hands are this close to the box edge.
@export var push_hand_tolerance: float = 0.12

@export_group("Rope")
## Hand point in the rope frames (HAND_ROPE px × 0.009).
@export var hand_rope_point: Vector2 = Vector2(0.036, 1.368)
## How fast the body straightens after a rope or a box.
@export var body_settle_speed: float = 12.0

@export_group("Lost lantern")
## Side distances tried when putting a lost lantern down beside the child.
@export var lantern_spot_offsets: PackedFloat32Array = PackedFloat32Array([0.8, -0.8, 1.4, -1.4, 0.0])

enum Bend { NONE, PLACE, PICKUP }

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
var _bend: Bend = Bend.NONE
var _bend_anim: StringName = &""
var _bend_path: PackedVector2Array
var _bend_lantern: Node3D = null
var _bend_from: Vector2 = Vector2.ZERO
var _bend_fix: float = 0.0
var _bend_lock: float = 0.0
var _bend_reach_due: bool = false
var _bend_reached: bool = false
var _bend_finished: bool = false
var _respawn_timer: float = 0.0
var _dead_pose: bool = false
var _push_state: int = 0
var _push_crate: Node3D = null
var _rope: Node3D = null
var _rope_cooldown: float = 0.0
var _rope_grabbing: bool = false
var _letting_go: bool = false

@onready var _body: AnimatedSprite3D = $Body
@onready var _body_base_scale: Vector3 = _body.scale
@onready var _probe: RayCast3D = $LanternProbe
@onready var _hand_marker: Marker3D = $HandMarker

func get_hand_marker_position() -> Vector3:
	return _hand_marker.global_position

func is_control_locked() -> bool:
	return _respawn_timer > 0.0

func _ready() -> void:
	set_physics_process(false)
	_body.frame_changed.connect(_on_body_frame_changed)
	_body.animation_finished.connect(_on_body_animation_finished)

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.register_player(self)
	_game.bus.player_respawned.connect(_on_player_respawned)
	_game.bus.player_died.connect(_on_player_died)
	_game.bus.lantern_place_requested.connect(_on_place_requested)
	set_physics_process(true)

## Crates call this: 1 = pushing, -1 = pulling, 0 = neither.
func set_push_state(state: int) -> void:
	_push_state = state
	_push_crate = _find_crate(state) if state != 0 else null

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if not _game.is_playing():
		_update_visual(delta)
		return
	_tick_bend()
	if is_instance_valid(_rope):
		_hang_on_rope(delta)
		return
	var input := _game.input
	var on_floor := is_on_floor()
	var axis := input.move_axis if _respawn_timer <= 0.0 and _bend_lock <= 0.0 else 0.0
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
	if _buffer_timer > 0.0 and _coyote_timer > 0.0 and _bend_lock <= 0.0:
		velocity.y = jump_velocity
		_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_rising = true
		_jump_start_timer = jump_start_time
		_squash_target = -jump_stretch
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
	_rope_grabbing = true
	_letting_go = false
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
		_rope_grabbing = false
		_letting_go = true
		_jump_rising = false
		_game.report_player_jumped()
	_update_visual(delta)

func _tick_timers(delta: float) -> void:
	_rope_cooldown = maxf(_rope_cooldown - delta, 0.0)
	_land_timer = maxf(_land_timer - delta, 0.0)
	_bend_lock = maxf(_bend_lock - delta, 0.0)
	_jump_start_timer = maxf(_jump_start_timer - delta, 0.0)
	_respawn_timer = maxf(_respawn_timer - delta, 0.0)

# ── Visuals (transform changes stay in the physics step) ──────────────────

func _update_visual(delta: float) -> void:
	_squash = lerpf(_squash, _squash_target, 1.0 - exp(-squash_speed * delta))
	_squash_target = lerpf(_squash_target, 0.0, 1.0 - exp(-squash_speed * 0.6 * delta))
	_body.flip_h = facing < 0
	_body.scale = Vector3(_body_base_scale.x * (1.0 + _squash), _body_base_scale.y * (1.0 - _squash), _body_base_scale.z)

	var anim := _pick_animation()
	if _body.animation != anim:
		_body.play(anim)
	var settle := 1.0 - exp(-body_settle_speed * delta)
	if is_instance_valid(_rope):
		_hang_body_from_rope()
	else:
		var shift := _push_body_shift() if anim.begins_with("push") else 0.0
		_body.position = _body.position.lerp(Vector3(shift, 0.0, 0.0), settle)
		_body.rotation.z = lerp_angle(_body.rotation.z, 0.0, settle)
	# The hand is drawn at a fixed pixel in every carry frame — keep the marker on it.
	if _bend != Bend.NONE and anim == _bend_anim:
		var bent := _bend_hand_point()
		_hand_marker.position = Vector3(bent.x * facing, bent.y, hand_depth)
	else:
		var hand := hand_raise_point if anim.begins_with("raise") else hand_carry_point
		_hand_marker.position = Vector3(hand.x * facing * (1.0 + _squash) + _body.position.x, hand.y * (1.0 - _squash), hand_depth)
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
	if _bend != Bend.NONE:
		return _bend_anim
	if is_instance_valid(_rope):
		return &"rope_grab" if _rope_grabbing else &"rope_hang"
	if _letting_go:
		if not is_on_floor():
			return &"rope_let_go"
		_letting_go = false
	var carry := _game.is_lantern_carried()
	if _push_state != 0 and _hands_on_crate():
		return &"push_carry" if carry else &"push"
	var base: String
	if not is_on_floor():
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

# ── Bending to the lantern ────────────────────────────────────────────────

func _on_place_requested() -> void:
	if _bend != Bend.NONE or is_instance_valid(_rope) or _respawn_timer > 0.0 or _dead_pose:
		return
	for lantern in _game.get_lanterns():
		if lantern.can_pick_up():
			_start_pickup(lantern)
			return
	for lantern in _game.get_lanterns():
		if lantern.carried and not lantern.is_retired():
			_start_place(lantern)
			return

func _start_place(lantern: Node3D) -> void:
	var hook := _game.get_hook_in_reach()
	if not is_on_floor():
		lantern.drop_from_hand(_hand_marker.global_position, hook)   # no bend in the air
		return
	var reach := bend_reach_frame
	if is_instance_valid(hook):
		_face(hook.get_hook_point().x)
		_begin_bend(Bend.PLACE, lantern, &"hook_reach", hook_hand_path, 0.0)
	elif _front_spot_is_clear():
		_begin_bend(Bend.PLACE, lantern, &"place", bend_hand_path, place_forward_offset - bend_hand_path[reach].x)
	else:
		_begin_bend(Bend.PLACE, lantern, &"place_feet", feet_hand_path, -feet_hand_path[reach].x)

func _start_pickup(lantern: Node3D) -> void:
	if not is_on_floor():
		lantern.take_in_hand()
		return
	_face(lantern.global_position.x)
	var hung: bool = lantern.is_hung()
	_begin_bend(Bend.PICKUP, lantern, &"hook_reach" if hung else &"pickup", hook_hand_path if hung else bend_hand_path, 0.0)

func _begin_bend(kind: Bend, lantern: Node3D, anim: StringName, path: PackedVector2Array, fix: float) -> void:
	_bend_from = Vector2(_hand_marker.position.x * facing, _hand_marker.position.y)
	_bend = kind
	_bend_lantern = lantern
	_bend_anim = anim
	_bend_path = path
	_bend_fix = fix
	_bend_lock = bend_lock_time
	_bend_reach_due = false
	_bend_reached = false
	_bend_finished = false
	_body.play(anim)

func _face(x: float) -> void:
	if absf(x - global_position.x) > 0.05:
		facing = 1 if x > global_position.x else -1

## Is there floor in front to set the lantern on? Wall, ledge edge or a long drop: no.
func _front_spot_is_clear() -> bool:
	var from := global_position + Vector3(0.0, place_probe_height, 0.0)
	var far := (place_forward_offset + place_edge_margin) * facing
	_probe.global_position = from
	_probe.target_position = Vector3(far, 0.0, 0.0)
	_probe.force_raycast_update()
	if _probe.is_colliding():
		return false
	for side: float in [place_forward_offset * facing, far]:
		_probe.global_position = from + Vector3(side, 0.0, 0.0)
		_probe.target_position = Vector3(0.0, -(place_probe_height + place_max_drop), 0.0)
		_probe.force_raycast_update()
		if not _probe.is_colliding() or _probe.get_collision_normal().y <= 0.7:
			return false
	return true

## The hand drawn right now: between this frame's point and the next, so the light glides.
func _bend_hand_point() -> Vector2:
	var last := _bend_path.size() - 1
	var f := clampi(_body.frame, 0, last)
	var from := _bend_from if f == 0 else _bend_path[f]
	var point := from.lerp(_bend_path[mini(f + 1, last)], _body.frame_progress)
	var toward_reach := clampf((f + _body.frame_progress) / maxf(bend_reach_frame, 1), 0.0, 1.0)
	point.x += _bend_fix * smoothstep(0.0, 1.0, toward_reach)
	return point

## The physics step acts on what the animation signalled.
func _tick_bend() -> void:
	if _bend == Bend.NONE:
		return
	if _bend_reach_due and not _bend_reached:
		_bend_reached = true
		if is_instance_valid(_bend_lantern):
			if _bend == Bend.PLACE:
				var at := _bend_path[bend_reach_frame]
				var spot := global_position + Vector3((at.x + _bend_fix) * facing, at.y, hand_depth)
				_bend_lantern.drop_from_hand(spot, _game.get_hook_in_reach())
			else:
				_bend_lantern.take_in_hand()
	if _bend_finished and _bend_reached:
		_bend = Bend.NONE
		_bend_lantern = null

func _cancel_bend() -> void:
	_bend = Bend.NONE
	_bend_lantern = null
	_bend_lock = 0.0

func _on_body_frame_changed() -> void:
	if _bend != Bend.NONE and _body.animation == _bend_anim and _body.frame >= bend_reach_frame:
		_bend_reach_due = true

func _on_body_animation_finished() -> void:
	var anim := _body.animation
	if _bend != Bend.NONE and anim == _bend_anim:
		_bend_reach_due = true
		_bend_finished = true
	elif anim == &"rope_grab":
		_rope_grabbing = false
	elif anim == &"rope_let_go":
		_letting_go = false

# ── Hands on a box, hands on a rope ───────────────────────────────────────

func _find_crate(direction: int) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for crate: Node3D in get_tree().get_nodes_in_group(&"crates"):
		var dx: float = (crate.global_position.x - global_position.x) * direction
		if dx > 0.0 and dx < best_d:
			best = crate
			best_d = dx
	return best

## World distance from the child to the side of the box they're pushing (signed).
func _crate_edge_offset() -> float:
	var half: float = _push_crate.half_width
	var shape := _push_crate.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape and shape.shape is BoxShape3D:
		half = (shape.shape as BoxShape3D).size.x * 0.5
	var dx := _push_crate.global_position.x - global_position.x
	return dx - signf(dx) * half

func _hands_on_crate() -> bool:
	if not is_instance_valid(_push_crate):
		return false
	var edge := _crate_edge_offset()
	return signf(edge) == facing and absf(edge) <= hand_push_point.x + push_hand_tolerance

## Sideways nudge of the Body that puts the drawn palms on the box edge.
func _push_body_shift() -> float:
	if not is_instance_valid(_push_crate):
		return 0.0
	# The box moves after the child each tick: aim at where it will be.
	var lead: float = _push_state * _push_crate.push_speed * get_physics_process_delta_time()
	return _crate_edge_offset() + lead - hand_push_point.x * facing

## Tilts the Body with the rope and hangs it from the drawn hands, on the rope's real point.
func _hang_body_from_rope() -> void:
	var hang: Vector3 = _rope.get_hang_point()
	var along: Vector3 = hang - _rope.global_position
	var angle := atan2(along.x, -along.y)
	var hands := Vector3(hand_rope_point.x * facing, hand_rope_point.y, 0.0).rotated(Vector3.BACK, angle)
	_body.position = Vector3(hang.x - global_position.x, hang.y - global_position.y, 0.0) - hands
	_body.rotation.z = angle

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
	_cancel_bend()

func _on_player_respawned() -> void:
	_rope = null
	_rope_cooldown = 0.0
	_rope_grabbing = false
	_letting_go = false
	_cancel_bend()
	_body.position = Vector3.ZERO
	_body.rotation.z = 0.0
	global_position = _game.get_respawn_position()
	velocity = Vector3.ZERO
	facing = 1
	_coyote_timer = 0.0
	_buffer_timer = 0.0
	_jump_rising = false
	_squash = 0.0
	_squash_target = 0.0
	_land_timer = 0.0
	_jump_start_timer = 0.0
	_push_state = 0
	_push_crate = null
	_dead_pose = false
	_was_on_floor = true
	_respawn_timer = respawn_lock_time
	_body.play(&"respawn")
	reset_physics_interpolation()
