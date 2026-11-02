class_name SwarmMite
extends Enemy

## SwarmMite — one of a swarm (4–6 small creatures) that pour out of several holes at once
## when their group wakes. A lit hole stays sealed: its mite won't come out until the
## light leaves it. Mites skitter toward the child in the dark and scatter along light
## edges. First appears in World 1, level 9 (see Swarm.tscn for a ready-made group).
##
## Sends / receives: see Enemy.

@export_group("Mite")
@export var skitter_speed: float = 3.6
@export var jitter_amount: float = 0.6
@export var jitter_speed: float = 7.0

var _wake_pending: bool = false

func _can_wake() -> bool:
	if _game.is_point_lit(_home, body_radius):
		_wake_pending = true   # sealed by light — try again when it's dark
		return false
	_wake_pending = false
	return true

func _reset() -> void:
	super._reset()
	_wake_pending = false

func _physics_process(delta: float) -> void:
	if _wake_pending and mode == Mode.DORMANT and _game and _game.is_playing():
		wake()
	super._physics_process(delta)

func _hunt(delta: float) -> void:
	var p := _game.get_player_position() + Vector3(0.0, 0.6, 0.0)
	var jitter := Vector3(sin(_time * jitter_speed), cos(_time * jitter_speed * 1.3), 0.0) * jitter_amount
	_float_toward(p + jitter, _speed(skitter_speed), delta)
