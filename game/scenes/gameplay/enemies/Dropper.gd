class_name Dropper
extends Enemy

## Dropper — hangs from the ceiling on a thread. When the child passes underneath in the
## dark, it drops. Carrying the lantern under it is safe (it won't drop into light — it
## pulls up and hisses). After a drop it scuttles after the child for a while, then climbs
## back up its thread. First appears in World 1, level 5.
##
## The scene's root sits at the ceiling anchor; `emerge_offset` is how far it lowers when
## it wakes (usually straight down).
##
## Sends / receives: see Enemy.

enum Phase { HANGING, DROPPING, GROUNDED, CLIMBING }

@export_group("Dropper")
## Drops when the child is within this horizontal distance below it.
@export var drop_range: float = 1.0
## Seconds between sensing the child below and letting go. Once primed it drops even if the
## child has moved on, so a child who keeps running gets past (it lands behind them).
@export var drop_delay: float = 0.0
@export var drop_gravity: float = 40.0
## Seconds it hunts on the ground before climbing back.
@export var ground_time: float = 3.0
@export var crawl_speed: float = 2.0
@export var climb_speed: float = 3.0
## How far it pulls up toward the anchor when light reaches it while hanging.
@export var retract_distance: float = 0.6

var _phase: Phase = Phase.HANGING
var _phase_t: float = 0.0
var _primed: float = -1.0

@onready var _thread: Node3D = $Thread

func _on_woke() -> void:
	_phase = Phase.HANGING

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	super.reset_to_checkpoint(state)
	_phase = Phase.HANGING
	_primed = -1.0

func _reset() -> void:
	super._reset()
	_phase = Phase.HANGING
	_primed = -1.0

func _hunt(delta: float) -> void:
	_phase_t += delta
	var hang_point := _home + emerge_offset
	match _phase:
		Phase.HANGING:
			var p := _game.get_player_position()
			var lit_here := _is_lit(global_position)
			var target := hang_point + (Vector3(0.0, retract_distance, 0.0) if lit_here else Vector3.ZERO)
			global_position = global_position.lerp(target, 1.0 - exp(-6.0 * delta))
			if lit_here:
				_repelled()
				return
			if _primed >= 0.0:
				_primed += delta
				if _primed >= drop_delay:
					_primed = -1.0
					_phase = Phase.DROPPING
					_phase_t = 0.0
					velocity = Vector3.ZERO
					_dbg("drop")
				return
			var below := p.y < global_position.y - 0.5
			if below and absf(p.x - global_position.x) <= drop_range:
				if _game.player_lit:
					_repelled()
				else:
					_primed = 0.0
					_dbg("child below in darkness → primed")
		Phase.DROPPING:
			velocity.y -= drop_gravity * delta
			velocity.x = 0.0
			move_and_slide()
			global_position.z = _home.z
			if is_on_floor() or _phase_t > 2.5:
				_phase = Phase.GROUNDED
				_phase_t = 0.0
		Phase.GROUNDED:
			var probe := global_position + Vector3(0.0, 0.3, 0.0)
			var vx := 0.0
			if _is_lit(probe):
				vx = signf(global_position.x - _game.get_nearest_light_position(probe).x) * crawl_speed * 1.5
				_repelled()
			else:
				var dir := signf(_game.get_player_position().x - global_position.x)
				if not _is_lit(probe + Vector3(dir * 0.6, 0.0, 0.0)):
					vx = dir * _speed(crawl_speed)
			velocity.x = vx
			velocity.y = 0.0 if is_on_floor() else velocity.y - drop_gravity * delta
			move_and_slide()
			global_position.z = _home.z
			if absf(vx) > 0.01:
				_move_dir = signf(vx)
			if _phase_t > ground_time:
				_phase = Phase.CLIMBING
		Phase.CLIMBING:
			var to := hang_point - global_position
			if to.length() < 0.1:
				_phase = Phase.HANGING
				_phase_t = 0.0
			else:
				global_position += to.normalized() * minf(climb_speed * delta, to.length())

## Visual state: hanging / dropping / on the ground (see Enemy.get_visual_state).
func get_visual_state() -> StringName:
	if mode == Mode.ATTACK:
		return super.get_visual_state()
	match _phase:
		Phase.DROPPING:
			return &"drop"
		Phase.GROUNDED:
			return &"flinch" if mode == Mode.FROZEN else &"ground"
	return &"hang"

func _perform_lunge_step(spd: float, delta: float) -> void:
	if _phase == Phase.GROUNDED:
		super._perform_lunge_step(spd, delta)
	else:
		velocity.y = -drop_gravity
		move_and_slide()
		global_position.z = _home.z

func _animate(delta: float) -> void:
	super._animate(delta)
	# Thread from the anchor down to the body.
	var top := _home
	var length := maxf(top.y - global_position.y, 0.01)
	_thread.visible = mode != Mode.DORMANT and _phase != Phase.GROUNDED
	_thread.global_position = Vector3(global_position.x, top.y - length * 0.5, global_position.z - 0.05)
	_thread.scale = Vector3(1.0, length, 1.0)
	if (mode == Mode.HUNT or mode == Mode.FROZEN) and _phase == Phase.HANGING:
		_visual.rotation.z = sin(_time * 1.3) * 0.08
	else:
		_visual.rotation.z = 0.0
