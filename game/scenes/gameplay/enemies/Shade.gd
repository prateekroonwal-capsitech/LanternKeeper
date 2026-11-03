class_name Shade
extends Enemy

## Shade — a massive flying creature of shadow that pursues the child across Level 10.
## Follows a Path3D using a PathFollow3D, maintaining a relentless airborne pursuit.
## Dips and swoops low at marked path gaps with a screech telegraph, and ignores lantern light.
## On player respawn, resets to the active checkpoint's restart path offset and resumes after a delay.
##
## Sends: GameManager.report_player_caught(self), GameManager.report_enemy_woke(self).
## Receives: GameBus signals via Enemy base class.

@export_group("Flight")
## Normal chase speed when following the child (slightly slower than child's 5.2 m/s run).
@export var base_speed: float = 4.6
## Speed when the child is far ahead to prevent falling completely off-screen.
@export var surge_speed: float = 6.0
## Distance ahead before surging kicks in.
@export var surge_distance: float = 16.0
## Desired following gap behind the player.
@export var target_gap: float = 12.0
## Minimum speed when close behind.
@export var catch_speed: float = 4.6
## Amplitude of the gentle sine bob on Y (metres).
@export var bob_amplitude: float = 0.35
## Frequency of the vertical sine bob (radians/sec).
@export var bob_frequency: float = 2.4
## Pitch/tilt angle forward when moving (radians).
@export var tilt_amount: float = 0.12
## Stops chasing here (path progress).
@export var end_offset: float = 330.0

@export_group("Swoop")
## Path progress offsets where the Shade telegraphs and swoops low through gaps.
@export var swoop_offsets: PackedFloat32Array = PackedFloat32Array([84.0, 188.0, 273.0])
## Lead distance before swoop offset to start telegraph (metres).
@export var swoop_trigger_lead: float = 3.0
## Duration of the screech telegraph before diving (seconds).
@export var telegraph_duration: float = 0.4
## Duration of the downward swoop and recovery (seconds).
@export var swoop_duration: float = 1.3
## Maximum depth dipped below normal flight path during swoop (metres).
@export var swoop_depth: float = 2.0
## Extra forward speed boost during swoop dive (metres/sec).
@export var swoop_speed_boost: float = 1.4

@export_group("Checkpoints")
## Path progress restart offsets: [0]=Spawn/Shrine1, [1]=Shrine2 (x=92), [2]=Shrine3 (x=194).
@export var checkpoint_offsets: PackedFloat32Array = PackedFloat32Array([0.0, 116.1, 218.7])
## Seconds to wait after respawning at a checkpoint before resuming chase.
@export var rewake_delay: float = 1.0

@export_group("Path")
## PathFollow3D node driving position along the chase route.
@export var path_follow: PathFollow3D

enum SwoopState { NONE, TELEGRAPH, SWOOPING }

var _progress: float = 0.0
var _bob_t: float = 0.0
var _rewake_t: float = -1.0
var _swoop_state: SwoopState = SwoopState.NONE
var _swoop_timer: float = 0.0
var _swoop_y_offset: float = 0.0
var _triggered_swoops: Array[bool] = []

@onready var _smoke: CPUParticles3D = get_node_or_null("SmokeTrail")
@onready var _eyes_a: Sprite3D = get_node_or_null("Visual/Eyes")
@onready var _eyes_b: Sprite3D = get_node_or_null("Visual/EyesB")
@onready var _eyes_c: Sprite3D = get_node_or_null("Visual/EyesC")

func _ready() -> void:
	ignores_light = true
	enemy_kind = "shade"
	if wake_group == &"":
		wake_group = &"chase"
	_init_swoop_triggers()
	super._ready()
	if path_follow:
		_set_path_progress(path_follow.progress)

func _init_swoop_triggers() -> void:
	_triggered_swoops.clear()
	for i in range(swoop_offsets.size()):
		_triggered_swoops.append(false)

func _reset_swoop_triggers(current_prog: float) -> void:
	for i in range(swoop_offsets.size()):
		_triggered_swoops[i] = (current_prog >= swoop_offsets[i])

func _set_path_progress(p: float) -> void:
	_progress = p
	if path_follow:
		path_follow.progress = p
		# If Shade is a child of PathFollow3D, local position handles bob and swoop
		if get_parent() == path_follow:
			position = Vector3(0.0, _swoop_y_offset + sin(_bob_t) * bob_amplitude, 0.0)
		else:
			global_position = path_follow.global_position + Vector3(0.0, _swoop_y_offset + sin(_bob_t) * bob_amplitude, 0.0)

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

	_swoop_state = SwoopState.NONE
	_swoop_timer = 0.0
	_swoop_y_offset = 0.0
	_restore_eye_glow()
	_reset_swoop_triggers(target_prog)
	_set_path_progress(target_prog)

	mode = Mode.DORMANT
	_rewake_t = rewake_delay
	if _smoke:
		_smoke.emitting = false
	reset_physics_interpolation()

func _reset() -> void:
	super._reset()
	_rewake_t = -1.0
	_swoop_state = SwoopState.NONE
	_swoop_timer = 0.0
	_swoop_y_offset = 0.0
	_restore_eye_glow()
	_init_swoop_triggers()

func _physics_process(delta: float) -> void:
	if _rewake_t > 0.0 and _game and _game.is_playing():
		_rewake_t -= delta
		if _rewake_t <= 0.0:
			mode = Mode.DORMANT
			wake()
			if _smoke:
				_smoke.emitting = true

	super._physics_process(delta)

func _hunt(delta: float) -> void:
	if not _game or not _game.is_playing():
		return

	_bob_t += delta * bob_frequency

	# Process active swoop state
	_update_swoop(delta)

	var p := _game.get_player_position()
	var current_pos := global_position
	var ahead_x := p.x - current_pos.x

	# Determine speed:
	# If player is far ahead, surge. If close or behind target gap, move at base/catch speed.
	var speed := base_speed
	if ahead_x > surge_distance:
		speed = surge_speed
	elif ahead_x > target_gap:
		var t := (ahead_x - target_gap) / maxf(surge_distance - target_gap, 0.1)
		speed = lerpf(base_speed, surge_speed, clampf(t, 0.0, 1.0))
	elif ahead_x < target_gap * 0.5:
		speed = catch_speed

	if _swoop_state == SwoopState.SWOOPING:
		speed += swoop_speed_boost

	# Advance along path
	_progress = minf(_progress + speed * delta, end_offset)
	_set_path_progress(_progress)

	# Forward tilt
	var target_tilt := -tilt_amount if speed > 0.5 else 0.0
	if _swoop_state == SwoopState.SWOOPING:
		# Dive tilt down early, flare up late
		var norm_swoop := _swoop_timer / maxf(swoop_duration, 0.1)
		target_tilt = lerpf(-0.35, 0.2, norm_swoop)
	elif _swoop_state == SwoopState.TELEGRAPH:
		target_tilt = 0.15 # Head reared back

	rotation.z = lerpf(rotation.z, target_tilt, 1.0 - exp(-10.0 * delta))
	_move_dir = 1.0
	_speed_now = speed * delta

	# Check triggers for new swoops
	_check_swoop_triggers()

func _check_swoop_triggers() -> void:
	if _swoop_state != SwoopState.NONE:
		return

	for i in range(swoop_offsets.size()):
		if not _triggered_swoops[i]:
			var trigger_dist := swoop_offsets[i] - swoop_trigger_lead
			if _progress >= trigger_dist and _progress <= swoop_offsets[i] + 5.0:
				_triggered_swoops[i] = true
				_start_swoop_telegraph()
				break

func _start_swoop_telegraph() -> void:
	_swoop_state = SwoopState.TELEGRAPH
	_swoop_timer = 0.0
	# Flare eyes
	_flare_eyes(true)
	# Play screech audio event
	if _game and _game.audio:
		_game.audio.play_event(&"enemy_hiss")

func _update_swoop(delta: float) -> void:
	match _swoop_state:
		SwoopState.TELEGRAPH:
			_swoop_timer += delta
			_swoop_y_offset = lerpf(0.0, 0.4, _swoop_timer / telegraph_duration) # Rears up slightly
			if _swoop_timer >= telegraph_duration:
				_swoop_state = SwoopState.SWOOPING
				_swoop_timer = 0.0
				_restore_eye_glow()

		SwoopState.SWOOPING:
			_swoop_timer += delta
			var norm := clampf(_swoop_timer / maxf(swoop_duration, 0.1), 0.0, 1.0)
			# Sinusoidal dip arc: 0 -> -swoop_depth -> 0
			_swoop_y_offset = -sin(norm * PI) * swoop_depth
			if _swoop_timer >= swoop_duration:
				_swoop_state = SwoopState.NONE
				_swoop_timer = 0.0
				_swoop_y_offset = 0.0

		SwoopState.NONE:
			_swoop_y_offset = 0.0

func _flare_eyes(flare: bool) -> void:
	var color := Color(6.0, 0.45, 0.25, 1.0) if flare else Color(2.6, 0.18, 0.12, 1.0)
	if _eyes_a:
		_eyes_a.modulate = color
	if _eyes_b:
		_eyes_b.modulate = color
	if _eyes_c:
		_eyes_c.modulate = color

func _restore_eye_glow() -> void:
	_flare_eyes(false)

func get_visual_state() -> StringName:
	if mode == Mode.DORMANT:
		return &"idle"
	if mode == Mode.EMERGING:
		return &"emerge"
	if _swoop_state == SwoopState.TELEGRAPH:
		return &"windup"
	if _swoop_state == SwoopState.SWOOPING:
		return &"lunge"
	if mode == Mode.HUNT:
		if _game and (_game.get_player_position().x - global_position.x) < 3.2:
			return &"lunge"
		return &"move"
	return super.get_visual_state()

func _check_catch() -> void:
	if mode == Mode.DORMANT or mode == Mode.RETREAT:
		return
	if not _game or not _game.is_playing():
		return

	var p := _game.get_player_position()
	# Caught if distance is within catch_radius or within front catch box
	var d := global_position.distance_to(p)
	if d <= catch_radius:
		_game.report_player_caught(self)
	elif absf(p.x - global_position.x) <= catch_radius * 1.2 and absf(p.y - global_position.y) <= 3.0:
		_game.report_player_caught(self)

func _on_hurtbox_body_entered(body: Node3D) -> void:
	if mode == Mode.DORMANT or mode == Mode.RETREAT:
		return
	if body.is_in_group(&"player") or body is Player:
		if _game and _game.is_playing():
			_game.report_player_caught(self)
