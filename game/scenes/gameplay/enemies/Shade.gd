class_name Shade
extends Enemy

## Shade — a massive flying creature of shadow that pursues the child across Level 10.
## Follows a Path3D using a PathFollow3D, pacing itself to the player's path progress
## to maintain a steady chase gap behind the child without attacking as long as they advance.
##
## It never closes the gap on its own: while the child keeps moving forward it holds
## `chase_gap` behind them and never attacks. It attacks ONLY when the child is stuck:
## stopped (less than `min_progress` gained in `stuck_time`; time in the air doesn't count),
## gone back more than `backtrack_limit`, or closer than `danger_gap`.
## Escalation: WARNING (`warning_time`: screech, eye flare, closes in a little; cancelled the
## moment the child moves forward again) -> TELEGRAPH (`telegraph_time`: pulls up with wings
## spread, then locks onto the child's position + velocity x `predict_factor`) -> DIVE
## (`dive_time`: a curved arc that overshoots slightly and never goes below the ground; the
## hurtbox is live only here) -> RECOVER (smooth climb back onto the path, then
## `attack_cooldown` before another warning).
##
## Scripted swoops: when the child reaches a marked path offset the Shade sweeps forward
## and dips lowest at that offset. A moving child is already past it; only a child standing
## still inside that swoop's danger zone (an Area3D in the level) is caught.
##
## Sends: GameManager.report_player_caught(self), GameManager.report_enemy_woke(self).
## Receives: GameBus signals via Enemy base class.

enum AttackState { CHASE, WARNING, TELEGRAPH, DIVE, RECOVER, SWOOP }

@export_group("Paced Chase")
## Desired following gap behind the player along the path (metres).
@export var chase_gap: float = 6.0
## Distance threshold where player has fallen dangerously close to Shade (metres).
@export var danger_gap: float = 2.0
## Minimum forward progress required to reset the stuck timer (metres).
@export var min_progress: float = 1.0
## Seconds with less than min_progress before warning triggers (stopping time).
@export var stuck_time: float = 3.0
## Distance player can backtrack from their max forward progress before warning triggers (metres).
@export var backtrack_limit: float = 2.0
## Duration of the warning phase before an attack launches (seconds).
@export var warning_time: float = 1.5
## Cooldown after recovering before another warning/attack can trigger (seconds).
@export var attack_cooldown: float = 2.5
## Normal flight speed when matching pace along the path (m/s).
@export var base_speed: float = 4.6
## Maximum surge speed when player pulls far ahead (m/s).
@export var surge_speed: float = 6.5
## Amplitude of the gentle sine bob on Y (metres).
@export var bob_amplitude: float = 0.35
## Frequency of the vertical sine bob (radians/sec).
@export var bob_frequency: float = 2.4
## Pitch/tilt angle forward when cruising (radians).
@export var tilt_amount: float = 0.12
## Stops chasing here (path progress).
@export var end_offset: float = 330.0

@export_group("Attack Cycle")
## Seconds the player's velocity is projected ahead to lead the dive target.
@export var predict_factor: float = 0.3
## Duration of the pull-up telegraph before diving (seconds).
@export var telegraph_time: float = 0.5
## Duration of the dive arc (seconds, 0.4-0.6).
@export var dive_time: float = 0.5
## Duration of climbing back onto the path (seconds).
@export var recover_duration: float = 0.6
## Extra forward overshoot distance past the target point before pulling up (metres).
@export var overshoot_distance: float = 2.6
## Path offsets of the scripted swoops (where the dip is deepest, over each danger zone).
@export var swoop_offsets: PackedFloat32Array = PackedFloat32Array([84.0, 188.0, 273.0])
## The swoop starts when the child's progress is this close before its offset (metres).
@export var swoop_trigger_lead: float = 2.0
## How far past the swoop offset the sweep carries on before climbing back (metres).
@export var swoop_exit: float = 3.0
## Duration of the dramatic fly-by swoop (seconds).
@export var swoop_duration: float = 1.4
## Maximum depth dipped below normal flight path during scripted swoop (metres).
@export var swoop_depth: float = 1.8
## Half-length of the dip along the path, centred on the swoop offset (metres).
@export var swoop_dip_width: float = 5.0
## Pre-placed Area3D danger zones in the level corresponding to each marked swoop offset.
@export var swoop_danger_zones: Array[NodePath] = []

@export_group("Checkpoints")
## Path progress restart offsets: [0]=Spawn/Shrine1, [1]=Shrine2 (x=92), [2]=Shrine3 (x=194).
@export var checkpoint_offsets: PackedFloat32Array = PackedFloat32Array([0.0, 116.1, 218.7])
## Delay after respawn before the Shade resumes chasing (seconds).
@export var rewake_delay: float = 1.0

@export_group("References")
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

# Progress and stuck tracking
var _player_progress: float = 0.0
var _last_progress_checkpoint: float = 0.0
var _max_player_progress: float = 0.0
var _stuck_timer: float = 0.0

# Attack state machine variables
var _attack_state: AttackState = AttackState.CHASE
var _shade_timer: float = 0.0
var _attack_cooldown: float = 0.0
var _warning_start_prog: float = 0.0
var _swoop_index: int = -1
var _swoop_phase: int = 0 # 0=telegraph, 1=flyby
var _dive_start: Vector3 = Vector3.ZERO
var _dive_target: Vector3 = Vector3.ZERO
var _dive_end: Vector3 = Vector3.ZERO
var _dive_ctrl: Vector3 = Vector3.ZERO
var _recover_start: Vector3 = Vector3.ZERO
var _swoop_from: float = 0.0
var _triggered_swoops: Array[bool] = []
var _danger_zones: Array[Area3D] = []

@onready var _smoke: CPUParticles3D = get_node_or_null("SmokeTrail")
@onready var _body: AnimatedSprite3D = get_node_or_null("Visual/Body")
@onready var _eye_anchor: Marker3D = get_node_or_null("Visual/EyeAnchor")
@onready var _eye_1: Sprite3D = get_node_or_null("Visual/EyeAnchor/Eye1")
@onready var _eye_2: Sprite3D = get_node_or_null("Visual/EyeAnchor/Eye2")
@onready var _eye_3: Sprite3D = get_node_or_null("Visual/EyeAnchor/Eye3")
@onready var _visual_root: Node3D = get_node_or_null("Visual")
@onready var _vignette: ColorRect = get_node_or_null("VignetteUI/Vignette")
@onready var _debug_ui: CanvasLayer = get_node_or_null("DebugUI")
@onready var _debug_label: Label = get_node_or_null("DebugUI/Panel/Margin/Label")

func _ready() -> void:
	ignores_light = true
	enemy_kind = "shade"
	if wake_group == &"":
		wake_group = &"chase"
	_init_swoop_triggers()
	_init_danger_zones()
	super._ready()

	# Connect frame changes to lock eyes to head
	if _body:
		_body.frame_changed.connect(_sync_eyes_to_head)
		_body.animation_changed.connect(_sync_eyes_to_head)
		_sync_eyes_to_head()

	if _debug_ui:
		_debug_ui.visible = false
	if _vignette:
		_vignette.modulate.a = 0.0

func _init_danger_zones() -> void:
	_danger_zones.clear()
	for p in swoop_danger_zones:
		var zone := get_node_or_null(p) as Area3D
		if zone:
			_danger_zones.append(zone)

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			if _debug_ui:
				_debug_ui.visible = not _debug_ui.visible

func _init_swoop_triggers() -> void:
	_triggered_swoops.clear()
	_triggered_swoops.resize(swoop_offsets.size())
	_triggered_swoops.fill(false)

func _reset_swoop_triggers(current_prog: float) -> void:
	for i in range(swoop_offsets.size()):
		_triggered_swoops[i] = current_prog >= swoop_offsets[i]

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

func _get_path_curve() -> Curve3D:
	if path_follow and path_follow.get_parent() is Path3D:
		return (path_follow.get_parent() as Path3D).curve
	return null

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

	_clear_chase_state()
	var curve := _get_path_curve()
	var respawn_prog := curve.get_closest_offset(_game.get_respawn_position()) if curve and _game else target_prog
	_player_progress = respawn_prog
	_last_progress_checkpoint = respawn_prog
	_max_player_progress = respawn_prog
	_reset_swoop_triggers(respawn_prog)
	_set_path_progress(target_prog)

	var start_pos := _get_path_position()
	global_position = start_pos
	_home = start_pos   # it emerges here, not back at the level start
	rotation.z = 0.0

	mode = Mode.DORMANT
	_rewake_t = rewake_delay
	if _smoke:
		_smoke.emitting = false
	reset_physics_interpolation()
	print("[Shade] CHECKPOINT RESET to offset %.1f (child at %.1f, %s): state CHASE, timers cleared, resumes in %.1f s" % [target_prog, respawn_prog, shrine.name if shrine else "start", rewake_delay])

func _reset() -> void:
	super._reset()
	_rewake_t = -1.0
	_clear_chase_state()
	_last_progress_checkpoint = 0.0
	_max_player_progress = 0.0
	_init_swoop_triggers()

## Every attack / swoop state, timer and effect back to a calm chase.
func _clear_chase_state() -> void:
	_attack_state = AttackState.CHASE
	_shade_timer = 0.0
	_stuck_timer = 0.0
	_attack_cooldown = 0.0
	_warning_start_prog = 0.0
	_swoop_index = -1
	_swoop_phase = 0
	_set_hurtbox_enabled(false)
	_restore_eye_flare()
	if _vignette:
		_vignette.modulate.a = 0.0
	if _smoke:
		_smoke.amount = 36
		_smoke.initial_velocity_min = 1.2
		_smoke.initial_velocity_max = 2.8

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

	if _debug_ui and _debug_ui.visible:
		_update_debug_readout()

func _update_debug_readout() -> void:
	if not _debug_label:
		return
	var state_str: String = String(AttackState.keys()[_attack_state])
	_debug_label.text = "SHADE CHASE (F3)\nPlayer Prog: %.1f m\nShade Prog:  %.1f m\nCurrent Gap:  %.1f m\nStuck Timer:  %.2f s / %.1f s\nState:        %s" % [
		_player_progress,
		_progress,
		_player_progress - _progress,
		_stuck_timer,
		stuck_time,
		state_str
	]

func _hunt(delta: float) -> void:
	if not _game or not _game.is_playing():
		return

	_bob_t += delta * bob_frequency

	match _attack_state:
		AttackState.CHASE:
			_update_chase(delta)
		AttackState.WARNING:
			_update_warning(delta)
		AttackState.TELEGRAPH:
			_update_telegraph(delta)
		AttackState.DIVE:
			_update_dive(delta)
		AttackState.RECOVER:
			_update_recover(delta)
		AttackState.SWOOP:
			_update_scripted_swoop(delta)

func _update_chase(delta: float) -> void:
	var curve := _get_path_curve()
	var p_pos := _game.get_player_position()
	_player_progress = curve.get_closest_offset(p_pos) if curve else p_pos.x
	var gap := _player_progress - _progress

	# Pacing: target position is (player_progress - chase_gap)
	var desired_progress := _player_progress - chase_gap
	var dist_to_target := desired_progress - _progress

	# Holds the gap: full pace when behind its spot, surging when far behind, easing to a
	# hover at its spot. It never closes in by itself (a stopped child is handled by the
	# stuck check) and never passes the child.
	var speed := 0.0
	if dist_to_target > 2.0:
		var t := clampf((dist_to_target - 2.0) / 8.0, 0.0, 1.0)
		speed = lerpf(base_speed, surge_speed, t)
	elif dist_to_target > 0.0:
		speed = base_speed * dist_to_target / 2.0

	var limit := minf(_player_progress - (danger_gap + 0.5), end_offset)
	_progress = clampf(_progress + speed * delta, minf(_progress, limit), limit)
	_set_path_progress(_progress)

	var target_pos := _get_path_position()
	global_position = global_position.lerp(target_pos, 1.0 - exp(-12.0 * delta))

	var target_tilt := -tilt_amount if speed > 0.5 else 0.0
	rotation.z = lerpf(rotation.z, target_tilt, 1.0 - exp(-8.0 * delta))
	_move_dir = 1.0
	_speed_now = speed * delta
	_set_facing(1.0)

	# Scripted swoops: start when the child reaches a marked point
	for i in range(swoop_offsets.size()):
		if not _triggered_swoops[i] and _player_progress >= swoop_offsets[i] - swoop_trigger_lead:
			_triggered_swoops[i] = true
			if _progress < swoop_offsets[i]:
				_start_scripted_swoop(i)
				return

	# Evaluate stuck conditions
	_check_stuck_conditions(delta, gap)

func _check_stuck_conditions(delta: float, gap: float) -> void:
	if _attack_cooldown > 0.0:
		return

	# Exclusions: do not count as stuck if mid-air during jump, respawning, or cutscene
	var p_node := _get_player_node()
	var is_midair := false
	if p_node:
		is_midair = not p_node.is_on_floor()

	if _rewake_t > 0.0 or not _game or not _game.is_playing():
		_last_progress_checkpoint = _player_progress
		_max_player_progress = maxf(_max_player_progress, _player_progress)
		return

	# 1. Stopped: progress increased by less than min_progress in the last stuck_time
	if _player_progress >= _last_progress_checkpoint + min_progress:
		_stuck_timer = 0.0
		_last_progress_checkpoint = _player_progress
	elif not is_midair:
		_stuck_timer += delta   # a normal jump pauses the timer (it neither counts nor resets it)
	_max_player_progress = maxf(_max_player_progress, _player_progress)

	var is_stopped := _stuck_timer >= stuck_time

	# 2. Going backwards: progress decreased by more than backtrack_limit
	var is_backtracking := (_max_player_progress - _player_progress) > backtrack_limit

	# 3. Fell behind gap: closer to Shade than danger_gap
	var is_danger_gap := gap < danger_gap and not is_midair

	if is_stopped or is_backtracking or is_danger_gap:
		var reason := "STOPPED (%.1fs)" % _stuck_timer if is_stopped else ("BACKTRACK (%.1fm)" % (_max_player_progress - _player_progress) if is_backtracking else "DANGER_GAP (%.1fm)" % gap)
		_start_warning(reason)

func _start_warning(reason: String) -> void:
	_attack_state = AttackState.WARNING
	_shade_timer = 0.0
	_warning_start_prog = _player_progress
	_flare_eyes(true)
	if _game and _game.audio:
		_game.audio.play_event(&"enemy_hiss")
	print("[Shade] WARNING triggered! Reason: ", reason, " PlayerProg: ", _player_progress, " ShadeProg: ", _progress)

func _update_warning(delta: float) -> void:
	_shade_timer += delta

	# Screen vignette pulse
	if _vignette:
		var pulse := 0.25 + 0.2 * sin(_shade_timer * 14.0)
		_vignette.modulate.a = clampf(pulse, 0.0, 0.6)

	# Closes the gap slightly
	var p_pos := _game.get_player_position()
	var curve := _get_path_curve()
	_player_progress = curve.get_closest_offset(p_pos) if curve else p_pos.x
	var target_prog := minf(_player_progress - maxf(danger_gap + 1.0, chase_gap * 0.5), end_offset)
	if _progress < target_prog:
		_progress = minf(_progress + (base_speed * 1.35) * delta, target_prog)
		_set_path_progress(_progress)
		global_position = global_position.lerp(_get_path_position(), 1.0 - exp(-12.0 * delta))

	# Forgiveness check: Did player resume forward running during warning?
	var p_node := _get_player_node()
	var resumed_moving := false
	if p_node and p_node.is_on_floor():
		if p_node.velocity.x > 0.5 or _player_progress > _warning_start_prog + 0.35:
			resumed_moving = true

	if resumed_moving:
		print("[Shade] WARNING CANCELLED: Player resumed moving forward! (Prog: ", _player_progress, ")")
		_cancel_warning()
		return

	# If warning expires and player is still stuck -> Attack!
	if _shade_timer >= warning_time:
		print("[Shade] WARNING EXPIRED -> Escalating to TELEGRAPH -> DIVE!")
		if _vignette:
			_vignette.modulate.a = 0.0
		_start_telegraph()

func _cancel_warning() -> void:
	_attack_state = AttackState.CHASE
	_shade_timer = 0.0
	_stuck_timer = 0.0
	_last_progress_checkpoint = _player_progress
	_max_player_progress = _player_progress   # forgiven: any new backtrack is measured from here
	_attack_cooldown = 0.5                    # short grace so it doesn't re-warn the same frame
	_restore_eye_flare()
	if _vignette:
		_vignette.modulate.a = 0.0

func _start_telegraph() -> void:
	_attack_state = AttackState.TELEGRAPH
	_shade_timer = 0.0
	_dive_start = global_position
	_flare_eyes(true)
	if _game and _game.audio:
		_game.audio.play_event(&"enemy_hiss")
	print("[Shade] TELEGRAPH: pulling up at ", global_position)

func _update_telegraph(delta: float) -> void:
	_shade_timer += delta
	var progress_norm := clampf(_shade_timer / telegraph_time, 0.0, 1.0)
	var pull_up := sin(progress_norm * PI * 0.5) * 0.6
	global_position = _dive_start + Vector3(0.0, pull_up, 0.0)
	rotation.z = lerpf(rotation.z, 0.18, 1.0 - exp(-10.0 * delta))
	if _shade_timer >= telegraph_time:
		_start_dive()

func _start_dive() -> void:
	# The target is locked now, at the end of the telegraph: the child's position plus
	# velocity x predict_factor.
	_attack_state = AttackState.DIVE
	_shade_timer = 0.0
	_dive_start = global_position
	var p_pos := _game.get_player_position()
	var p_node := _get_player_node()
	var p_vel := p_node.velocity if p_node else Vector3.ZERO
	var target := p_pos + Vector3(p_vel.x, 0.0, 0.0) * predict_factor
	target.y = maxf(target.y, _sample_terrain_floor_y(target.x, target.y) + 0.35)
	_dive_target = target
	var side := 1.0 if _dive_target.x >= _dive_start.x else -1.0
	_dive_end = _dive_target + Vector3(overshoot_distance * side, 0.7, 0.0)
	var u := 0.62
	_dive_ctrl = (_dive_target - (1.0 - u) * (1.0 - u) * _dive_start - u * u * _dive_end) / (2.0 * (1.0 - u) * u)
	_restore_eye_flare()
	_set_hurtbox_enabled(true)
	if _smoke:
		_smoke.amount = 56
		_smoke.initial_velocity_min = 2.4
		_smoke.initial_velocity_max = 4.8
	print("[Shade] DIVE: from ", _dive_start, " at locked target ", _dive_target, ", hurtbox on")

func _update_dive(delta: float) -> void:
	_shade_timer += delta
	var u := clampf(_shade_timer / dive_time, 0.0, 1.0)

	var inv_u := 1.0 - u
	var arc_pos := inv_u * inv_u * _dive_start + 2.0 * inv_u * u * _dive_ctrl + u * u * _dive_end

	var floor_y := _sample_terrain_floor_y(arc_pos.x, arc_pos.y)
	arc_pos.y = maxf(arc_pos.y, floor_y + 0.3)
	global_position = arc_pos

	var tangent := 2.0 * inv_u * (_dive_ctrl - _dive_start) + 2.0 * u * (_dive_end - _dive_ctrl)
	var dive_angle := atan2(tangent.y, tangent.x)
	rotation.z = lerpf(rotation.z, clampf(dive_angle, -0.6, 0.35), 1.0 - exp(-15.0 * delta))

	_check_catch()

	if _shade_timer >= dive_time:
		_start_recover()

func _start_recover() -> void:
	_attack_state = AttackState.RECOVER
	_shade_timer = 0.0
	_recover_start = global_position
	_set_hurtbox_enabled(false)

	if _smoke:
		_smoke.amount = 36
		_smoke.initial_velocity_min = 1.2
		_smoke.initial_velocity_max = 2.8
	print("[Shade] DIVE missed at ", global_position, " -> RECOVER")

func _update_recover(delta: float) -> void:
	_shade_timer += delta
	var norm := clampf(_shade_timer / recover_duration, 0.0, 1.0)
	var smooth_t := norm * norm * (3.0 - 2.0 * norm)

	var curve := _get_path_curve()
	if curve:
		_player_progress = curve.get_closest_offset(_game.get_player_position())
	_progress = maxf(minf(_progress, _player_progress - (danger_gap + 0.5)), 0.0)
	_set_path_progress(_progress)
	var path_pos := _get_path_position()

	global_position = _recover_start.lerp(path_pos, smooth_t)
	rotation.z = lerpf(rotation.z, -tilt_amount, 1.0 - exp(-8.0 * delta))

	if _shade_timer >= recover_duration:
		_attack_state = AttackState.CHASE
		_shade_timer = 0.0
		_stuck_timer = 0.0
		_attack_cooldown = attack_cooldown
		_last_progress_checkpoint = _player_progress
		_max_player_progress = _player_progress
		print("[Shade] RECOVER done -> CHASE (cooldown %.1f s)" % attack_cooldown)

func _start_scripted_swoop(idx: int) -> void:
	_attack_state = AttackState.SWOOP
	_swoop_index = idx
	_shade_timer = 0.0
	_swoop_phase = 0
	_swoop_from = _progress
	_flare_eyes(true)
	if _game and _game.audio:
		_game.audio.play_event(&"enemy_hiss")
	print("[Shade] SWOOP %d: screech at progress %.1f (child at %.1f), dip at %.1f" % [idx + 1, _progress, _player_progress, swoop_offsets[idx]])

func _update_scripted_swoop(delta: float) -> void:
	_shade_timer += delta
	if _swoop_phase == 0:
		# Swoop telegraph: pull up slightly and spread wings for 0.4s
		var u := clampf(_shade_timer / 0.4, 0.0, 1.0)
		var pull_up := sin(u * PI * 0.5) * 0.4
		var path_pos := _get_path_position()
		global_position = path_pos + Vector3(0.0, pull_up, 0.0)
		rotation.z = lerpf(rotation.z, 0.18, 1.0 - exp(-10.0 * delta))
		if _shade_timer >= 0.4:
			_swoop_phase = 1
			_shade_timer = 0.0
			_restore_eye_flare()
			if _smoke:
				_smoke.amount = 56
	else:
		# Fly-by: sweeps from where it was to just past the marked point, deepest over the zone
		var u := clampf(_shade_timer / swoop_duration, 0.0, 1.0)
		var off := swoop_offsets[_swoop_index]
		var curve := _get_path_curve()
		if curve:
			_player_progress = curve.get_closest_offset(_game.get_player_position())
		_progress = minf(lerpf(_swoop_from, off + swoop_exit, smoothstep(0.0, 1.0, u)), end_offset)
		_set_path_progress(_progress)

		var path_pos := _get_path_position()
		var k := clampf(1.0 - absf(_progress - off) / swoop_dip_width, 0.0, 1.0)
		var dip := -swoop_depth * k * k * (3.0 - 2.0 * k)
		var floor_y := _sample_terrain_floor_y(path_pos.x, path_pos.y)
		global_position = Vector3(path_pos.x, maxf(path_pos.y + dip, floor_y + 0.6), path_pos.z)

		var tilt := -0.35 * k * (1.0 if off > _progress else -1.0)
		rotation.z = lerpf(rotation.z, tilt, 1.0 - exp(-12.0 * delta))

		_check_swoop_danger_zone(_swoop_index)

		if _shade_timer >= swoop_duration:
			if _smoke:
				_smoke.amount = 36
			_attack_state = AttackState.CHASE
			_shade_timer = 0.0
			print("[Shade] SWOOP %d done -> CHASE" % [_swoop_index + 1])

func _check_swoop_danger_zone(idx: int) -> void:
	# Only near the bottom of the dip, and only a child standing still inside the zone.
	if idx < 0 or idx >= _danger_zones.size() or absf(_progress - swoop_offsets[idx]) > swoop_dip_width * 0.6:
		return
	var zone := _danger_zones[idx]
	var p_node := _get_player_node()
	if not is_instance_valid(zone) or not p_node:
		return
	var standing: bool = p_node.is_on_floor() and absf(p_node.velocity.x) < 0.5
	if standing and zone.overlaps_body(p_node):
		print("[Shade] SWOOP %d HIT: the child stood still in its danger zone at %s" % [idx + 1, p_node.global_position])
		_game.report_player_caught(self)

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
		var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4) # level geometry + solid ghost platforms
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
		AttackState.WARNING:
			return &"windup"
		AttackState.TELEGRAPH:
			return &"windup"
		AttackState.DIVE:
			return &"lunge"
		AttackState.SWOOP:
			return &"windup" if _swoop_phase == 0 else &"lunge"
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

	var chest := _game.get_player_position() + Vector3(0.0, 0.7, 0.0)
	var d := global_position.distance_to(chest)
	if d <= catch_radius:
		print("[Shade] DIVE HIT at ", global_position, " (%.2f m from the child)" % d)
		_game.report_player_caught(self)

func _on_hurtbox_body_entered(body: Node3D) -> void:
	if mode == Mode.DORMANT or mode == Mode.RETREAT:
		return
	if _attack_state != AttackState.DIVE:
		return
	if body.is_in_group(&"player") or body is Player:
		if _game and _game.is_playing():
			print("[Shade] DIVE HIT: hurtbox touched the child at ", global_position)
			_game.report_player_caught(self)
