class_name Shade
extends Enemy

## Shade — a massive flying creature of shadow that pursues the child across Level 10.
## Follows a Path3D using a PathFollow3D, maintaining a relentless airborne pursuit.
## Executes a telegraphed swoop attack cycle (CHASE -> TELEGRAPH -> DIVE -> RECOVER)
## that leaves the path, swoops through the player's predicted position, and pulls up.
## Eyes are pinned to the head frame-by-frame via EyeAnchor with dedicated shade_eye textures.
##
## Sends: GameManager.report_player_caught(self), GameManager.report_enemy_woke(self).
## Receives: GameBus signals via Enemy base class.

enum AttackState { CHASE, TELEGRAPH, DIVE, RECOVER }

@export_group("Flight")
## Normal chase speed when following the child along the Path3D (m/s).
@export var base_speed: float = 4.6
## Speed when the child is far ahead to prevent falling off-screen (m/s).
@export var surge_speed: float = 6.0
## Distance ahead before surging kicks in (m).
@export var surge_distance: float = 16.0
## Desired following gap behind the player (m).
@export var target_gap: float = 12.0
## Minimum speed when close behind (m/s).
@export var catch_speed: float = 4.6
## Amplitude of the gentle sine bob on Y (metres).
@export var bob_amplitude: float = 0.35
## Frequency of the vertical sine bob (radians/sec).
@export var bob_frequency: float = 2.4
## Pitch/tilt angle forward when cruising (radians).
@export var tilt_amount: float = 0.12
## Stops chasing here (path progress).
@export var end_offset: float = 330.0

@export_group("Attack Cycle")
## Horizontal distance to player that triggers a dive attack (metres).
@export var attack_range: float = 4.5
## Cooldown after recovering before another attack can trigger (seconds).
@export var attack_cooldown: float = 2.5
## Seconds the player's velocity is projected ahead to lead the dive target.
@export var prediction_time: float = 0.3
## Duration of the screech telegraph before diving (seconds).
@export var telegraph_duration: float = 0.5
## Duration of the downward dive arc (seconds).
@export var dive_duration: float = 0.5
## Duration of climbing back onto the path (seconds).
@export var recover_duration: float = 0.6
## Extra forward overshoot distance past the target point before pulling up (metres).
@export var overshoot_distance: float = 2.6
## Path progress offsets where marked gap swoops occur along the path route.
@export var swoop_offsets: PackedFloat32Array = PackedFloat32Array([84.0, 188.0, 273.0])
## Lead distance before marked swoop offset to start telegraph (metres).
@export var swoop_trigger_lead: float = 3.5

@export_group("Checkpoints")
## Path progress restart offsets: [0]=Spawn/Shrine1, [1]=Shrine2 (x=92), [2]=Shrine3 (x=194).
@export var checkpoint_offsets: PackedFloat32Array = PackedFloat32Array([0.0, 116.1, 218.7])
## Seconds to wait after respawning at a checkpoint before resuming chase.
@export var rewake_delay: float = 1.0

@export_group("Path")
## PathFollow3D node driving position along the chase route.
@export var path_follow: PathFollow3D

# Head center offsets in local 3D space per frame of each animation
const HEAD_OFFSETS: Dictionary = {
	&"fly": [
		Vector3(0.696, 0.169, 0.05),
		Vector3(0.703, 0.067, 0.05),
		Vector3(0.706, 0.024, 0.05),
		Vector3(0.703, 0.067, 0.05),
		Vector3(0.696, 0.169, 0.05),
		Vector3(0.687, 0.271, 0.05),
		Vector3(0.682, 0.313, 0.05),
		Vector3(0.687, 0.271, 0.05),
	],
	&"glide": [
		Vector3(0.704, 0.133, 0.05),
		Vector3(0.704, 0.085, 0.05),
		Vector3(0.704, 0.133, 0.05),
		Vector3(0.704, 0.181, 0.05),
	],
	&"swoop": [
		Vector3(0.712, 0.041, 0.05),
		Vector3(0.667, -0.201, 0.05),
		Vector3(0.687, -0.201, 0.05),
		Vector3(0.715, -0.014, 0.05),
	],
	&"screech": [
		Vector3(0.640, 0.382, 0.05),
		Vector3(0.670, 0.313, 0.05),
		Vector3(0.640, 0.382, 0.05),
		Vector3(0.603, 0.447, 0.05),
	],
	&"emerge": [
		Vector3(0.716, -0.150, 0.05),
		Vector3(0.712, -0.043, 0.05),
		Vector3(0.706, 0.063, 0.05),
		Vector3(0.696, 0.169, 0.05),
	],
}

var _progress: float = 0.0
var _bob_t: float = 0.0
var _rewake_t: float = -1.0
var _facing: float = 1.0

# Attack state machine variables
var _attack_state: AttackState = AttackState.CHASE
var _shade_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _dive_start: Vector3 = Vector3.ZERO
var _dive_target: Vector3 = Vector3.ZERO
var _dive_end: Vector3 = Vector3.ZERO
var _dive_ctrl: Vector3 = Vector3.ZERO
var _recover_start: Vector3 = Vector3.ZERO
var _triggered_swoops: Array[bool] = []

@onready var _smoke: CPUParticles3D = get_node_or_null("SmokeTrail")
@onready var _body: AnimatedSprite3D = get_node_or_null("Visual/Body")
@onready var _eye_anchor: Marker3D = get_node_or_null("Visual/EyeAnchor")
@onready var _eye_1: Sprite3D = get_node_or_null("Visual/EyeAnchor/Eye1")
@onready var _eye_2: Sprite3D = get_node_or_null("Visual/EyeAnchor/Eye2")
@onready var _eye_3: Sprite3D = get_node_or_null("Visual/EyeAnchor/Eye3")
@onready var _visual_root: Node3D = get_node_or_null("Visual")

func _ready() -> void:
	ignores_light = true
	enemy_kind = "shade"
	if wake_group == &"":
		wake_group = &"chase"
	_init_swoop_triggers()
	super._ready()

	# Connect frame changes to lock eyes to head
	if _body:
		_body.frame_changed.connect(_sync_eyes_to_head)
		_body.animation_changed.connect(_sync_eyes_to_head)
		_sync_eyes_to_head()

	if path_follow:
		_set_path_progress(path_follow.progress)

	_set_hurtbox_enabled(false)

func _init_swoop_triggers() -> void:
	_triggered_swoops.clear()
	for i in range(swoop_offsets.size()):
		_triggered_swoops.append(false)

func _reset_swoop_triggers(current_prog: float) -> void:
	for i in range(swoop_offsets.size()):
		_triggered_swoops[i] = (current_prog >= swoop_offsets[i])

func _set_facing(f: float) -> void:
	var sign_val := -1.0 if f < 0.0 else 1.0
	if not is_equal_approx(_facing, sign_val):
		_facing = sign_val
		if _visual_root:
			_visual_root.scale.x = _facing
		_sync_eyes_to_head()

func _sync_eyes_to_head() -> void:
	if not _eye_anchor or not _body:
		return
	var anim := _body.animation
	var frames: Array = HEAD_OFFSETS.get(anim, HEAD_OFFSETS[&"fly"])
	var idx := clampi(_body.frame, 0, frames.size() - 1)
	var offset: Vector3 = frames[idx]
	_eye_anchor.position = Vector3(offset.x, offset.y, offset.z)

func _set_path_progress(p: float) -> void:
	_progress = p
	if path_follow:
		path_follow.progress = p

func _get_path_position() -> Vector3:
	if path_follow:
		return path_follow.global_position + Vector3(0.0, sin(_bob_t) * bob_amplitude, 0.0)
	return global_position

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	super.reset_to_checkpoint(state)
	var shrine: Shrine = _game.get_active_shrine() as Shrine if _game else null
	var target_prog: float = 0.0

	if shrine != null:
		if shrine.name == "Shrine3" and checkpoint_offsets.size() > 2:
			target_prog = checkpoint_offsets[2]
		elif shrine.name == "Shrine2" and checkpoint_offsets.size() > 1:
			target_prog = checkpoint_offsets[1]
		elif not checkpoint_offsets.is_empty():
			target_prog = checkpoint_offsets[0]
	elif not checkpoint_offsets.is_empty():
		target_prog = checkpoint_offsets[0]

	_attack_state = AttackState.CHASE
	_shade_timer = 0.0
	_attack_cooldown = 0.0
	_set_hurtbox_enabled(false)
	_restore_eye_flare()
	_reset_swoop_triggers(target_prog)
	_set_path_progress(target_prog)

	var start_pos := _get_path_position()
	global_position = start_pos
	rotation.z = 0.0

	mode = Mode.DORMANT
	_rewake_t = rewake_delay
	if _smoke:
		_smoke.emitting = false
	reset_physics_interpolation()
	print("[Shade] CHECKPOINT RESET to offset=", target_prog, " shrine=", shrine.name if shrine else "none", " attack_state=CHASE cooldown=0 rewake_delay=", rewake_delay)

func _reset() -> void:
	super._reset()
	_rewake_t = -1.0
	_attack_state = AttackState.CHASE
	_shade_timer = 0.0
	_attack_cooldown = 0.0
	_set_hurtbox_enabled(false)
	_restore_eye_flare()
	_init_swoop_triggers()

func _physics_process(delta: float) -> void:
	if _rewake_t > 0.0 and _game and _game.is_playing():
		_rewake_t -= delta
		if _rewake_t <= 0.0:
			mode = Mode.DORMANT
			wake()
			if _smoke:
				_smoke.emitting = true

	if _attack_cooldown > 0.0 and _game and _game.is_playing():
		_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)

	super._physics_process(delta)

func _hunt(delta: float) -> void:
	if not _game or not _game.is_playing():
		return

	_bob_t += delta * bob_frequency

	match _attack_state:
		AttackState.CHASE:
			_update_chase(delta)
		AttackState.TELEGRAPH:
			_update_telegraph(delta)
		AttackState.DIVE:
			_update_dive(delta)
		AttackState.RECOVER:
			_update_recover(delta)

func _update_chase(delta: float) -> void:
	var p := _game.get_player_position()
	var current_pos := global_position
	var ahead_x := p.x - current_pos.x

	# Speed logic: stays slightly slower than player (4.6 vs 5.2 m/s), surges if far behind
	var speed := base_speed
	if ahead_x > surge_distance:
		speed = surge_speed
	elif ahead_x > target_gap:
		var t := (ahead_x - target_gap) / maxf(surge_distance - target_gap, 0.1)
		speed = lerpf(base_speed, surge_speed, clampf(t, 0.0, 1.0))
	elif ahead_x < target_gap * 0.5:
		speed = catch_speed

	_progress = minf(_progress + speed * delta, end_offset)
	_set_path_progress(_progress)

	# Update position to follow path + gentle bob
	var target_pos := _get_path_position()
	global_position = global_position.lerp(target_pos, 1.0 - exp(-12.0 * delta))

	# Banking tilt forward
	var target_tilt := -tilt_amount if speed > 0.5 else 0.0
	rotation.z = lerpf(rotation.z, target_tilt, 1.0 - exp(-8.0 * delta))
	_move_dir = 1.0
	_speed_now = speed * delta
	_set_facing(1.0)

	# Evaluate conditions to attack: proximity OR marked swoop points
	_check_attack_triggers(ahead_x)

func _check_attack_triggers(ahead_x: float) -> void:
	if _attack_cooldown > 0.0:
		return

	# 1. Marked swoop trigger along the path
	for i in range(swoop_offsets.size()):
		if not _triggered_swoops[i]:
			var trigger_dist := swoop_offsets[i] - swoop_trigger_lead
			if _progress >= trigger_dist and _progress <= swoop_offsets[i] + 4.0:
				_triggered_swoops[i] = true
				_start_telegraph()
				return

	# 2. Dynamic proximity attack: triggered when player is within attack_range horizontally
	if ahead_x >= -1.0 and ahead_x <= attack_range:
		_start_telegraph()

func _start_telegraph() -> void:
	_attack_state = AttackState.TELEGRAPH
	_shade_timer = 0.0
	_dive_start = global_position

	# Flare and enlarge eyes
	_flare_eyes(true)

	# Screech audio cue
	if _game and _game.audio:
		_game.audio.play_event(&"enemy_hiss")

	# Lock target point: player position + movement prediction
	var p_pos := _game.get_player_position()
	var p_vel := Vector3.ZERO
	var p_node := _get_player_node()
	if p_node:
		p_vel = p_node.velocity

	var target := p_pos + p_vel * prediction_time

	# Ensure target Y never penetrates solid terrain
	var floor_y := _sample_terrain_floor_y(target.x, target.y)
	target.y = maxf(target.y, floor_y + 0.35)
	_dive_target = target

	# Compute overshoot end point: past target and pulling up
	_dive_end = _dive_target + Vector3(overshoot_distance, 0.7, 0.0)

	# Solve Bezier control point so arc passes through _dive_target at u = 0.62
	var u := 0.62
	var denom := 2.0 * (1.0 - u) * u
	_dive_ctrl = (_dive_target - (1.0 - u) * (1.0 - u) * _dive_start - u * u * _dive_end) / denom
	print("[Shade] TELEGRAPH started: pos=", _dive_start, " locked_target=", _dive_target, " overshoot_end=", _dive_end)

func _update_telegraph(delta: float) -> void:
	_shade_timer += delta
	var progress_norm := clampf(_shade_timer / telegraph_duration, 0.0, 1.0)

	# Pulls up slightly and spreads wings
	var pull_up := sin(progress_norm * PI * 0.5) * 0.4
	global_position = _dive_start + Vector3(0.0, pull_up, 0.0)
	rotation.z = lerpf(rotation.z, 0.18, 1.0 - exp(-10.0 * delta)) # Head and chest reared up

	if _shade_timer >= telegraph_duration:
		_start_dive()

func _start_dive() -> void:
	_attack_state = AttackState.DIVE
	_shade_timer = 0.0
	_restore_eye_flare()
	_set_hurtbox_enabled(true)

	# Strengthen smoke trail
	if _smoke:
		_smoke.amount = 56
		_smoke.initial_velocity_min = 2.4
		_smoke.initial_velocity_max = 4.8
	print("[Shade] DIVE started: pos=", global_position, " hurtbox=ACTIVE")

func _update_dive(delta: float) -> void:
	_shade_timer += delta
	var u := clampf(_shade_timer / dive_duration, 0.0, 1.0)

	# Quadratic Bezier formula: (1-u)^2 * P0 + 2*(1-u)*u * P1 + u^2 * P2
	var inv_u := 1.0 - u
	var arc_pos := inv_u * inv_u * _dive_start + 2.0 * inv_u * u * _dive_ctrl + u * u * _dive_end

	# Terrain safety: never penetrate solid ground or platforms
	var floor_y := _sample_terrain_floor_y(arc_pos.x, arc_pos.y)
	arc_pos.y = maxf(arc_pos.y, floor_y + 0.3)
	global_position = arc_pos

	# Tangent derivative gives trajectory vector for banking tilt
	var tangent := 2.0 * inv_u * (_dive_ctrl - _dive_start) + 2.0 * u * (_dive_end - _dive_ctrl)
	var dive_angle := atan2(tangent.y, tangent.x)
	rotation.z = lerpf(rotation.z, clampf(dive_angle, -0.6, 0.35), 1.0 - exp(-15.0 * delta))

	# Advance path progress under the hood so the path position stays aligned
	_progress = minf(_progress + base_speed * 1.3 * delta, end_offset)
	_set_path_progress(_progress)

	# Check for catch during dive
	_check_catch()

	# If dive finishes without catch, it is a MISS -> recover
	if _shade_timer >= dive_duration:
		_start_recover()

func _start_recover() -> void:
	_attack_state = AttackState.RECOVER
	_shade_timer = 0.0
	_recover_start = global_position
	_set_hurtbox_enabled(false)

	# Restore normal smoke trail
	if _smoke:
		_smoke.amount = 36
		_smoke.initial_velocity_min = 1.2
		_smoke.initial_velocity_max = 2.8
	print("[Shade] DIVE finished (MISS): pos=", global_position, " -> RECOVER started")

func _update_recover(delta: float) -> void:
	_shade_timer += delta
	var norm := clampf(_shade_timer / recover_duration, 0.0, 1.0)

	# Smoothstep ease back to path
	var smooth_t := norm * norm * (3.0 - 2.0 * norm)

	_progress = minf(_progress + base_speed * delta, end_offset)
	_set_path_progress(_progress)
	var path_pos := _get_path_position()

	global_position = _recover_start.lerp(path_pos, smooth_t)
	rotation.z = lerpf(rotation.z, -tilt_amount, 1.0 - exp(-8.0 * delta))

	if _shade_timer >= recover_duration:
		_attack_state = AttackState.CHASE
		_shade_timer = 0.0
		_attack_cooldown = attack_cooldown
		print("[Shade] RECOVER finished -> CHASE resumed (cooldown: ", attack_cooldown, "s)")

func _flare_eyes(flare: bool) -> void:
	var color := Color(6.0, 0.45, 0.25, 1.0) if flare else Color(2.6, 0.18, 0.12, 1.0)
	var scale_target := Vector3.ONE * (1.35 if flare else 1.0)
	if _eye_anchor:
		_eye_anchor.scale = scale_target
	if _eye_1:
		_eye_1.modulate = color
	if _eye_2:
		_eye_2.modulate = color
	if _eye_3:
		_eye_3.modulate = color

func _restore_eye_flare() -> void:
	_flare_eyes(false)

func _set_hurtbox_enabled(active: bool) -> void:
	if is_instance_valid(_hurtbox):
		_hurtbox.set_deferred(&"monitoring", active)
		_hurtbox.set_deferred(&"monitorable", active)
		var col := _hurtbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if col:
			col.set_deferred(&"disabled", not active)

func _sample_terrain_floor_y(x: float, ref_y: float) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space:
		var from := Vector3(x, ref_y + 2.0, 0.0)
		var to := Vector3(x, ref_y - 6.0, 0.0)
		var query := PhysicsRayQueryParameters3D.create(from, to, 1) # Layer 1 = geometry
		var result := space.intersect_ray(query)
		if result:
			return result.position.y
	return -10.0

func _get_player_node() -> CharacterBody3D:
	if _game and _game.current_level:
		return _game.current_level.get_node_or_null("Player") as CharacterBody3D
	return null

func get_visual_state() -> StringName:
	if mode == Mode.DORMANT:
		return &"idle"
	if mode == Mode.EMERGING:
		return &"emerge"
	match _attack_state:
		AttackState.TELEGRAPH:
			return &"windup"
		AttackState.DIVE:
			return &"lunge"
		AttackState.RECOVER:
			return &"idle"
		AttackState.CHASE:
			return &"move"
	return super.get_visual_state()

func _check_catch() -> void:
	if mode == Mode.DORMANT or mode == Mode.RETREAT:
		return
	if not _game or not _game.is_playing():
		return
	if _attack_state != AttackState.DIVE:
		return

	var p := _game.get_player_position()
	var d := global_position.distance_to(p)
	if d <= catch_radius:
		print("[Shade] DIVE HIT! Caught player at pos=", global_position, " dist=", d)
		_game.report_player_caught(self)
	elif absf(p.x - global_position.x) <= catch_radius * 1.1 and absf(p.y - global_position.y) <= 2.2:
		print("[Shade] DIVE HIT! Caught player at pos=", global_position, " proximity match")
		_game.report_player_caught(self)

func _on_hurtbox_body_entered(body: Node3D) -> void:
	if mode == Mode.DORMANT or mode == Mode.RETREAT:
		return
	if _attack_state != AttackState.DIVE:
		return
	if body.is_in_group(&"player") or body is Player:
		if _game and _game.is_playing():
			print("[Shade] DIVE HIT! Hurtbox touched player at pos=", global_position)
			_game.report_player_caught(self)
