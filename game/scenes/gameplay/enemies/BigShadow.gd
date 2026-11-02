class_name BigShadow
extends Enemy

## BigShadow — a huge creature that chases the child through a whole level. Light does
## not stop it (`ignores_light`); it can only be outrun. It hangs back a little when far
## behind and surges when the child slows. After a respawn it restarts `restart_gap`
## metres behind the checkpoint and wakes again after `rewake_delay`. First appears in
## World 1, level 10. (Replaces the old Dark Tide.)
##
## Sends / receives: see Enemy. The catch zone is its whole front edge (X), within
## `catch_height` of its centre.

@export_group("Chase")
@export var chase_speed: float = 4.2
## Speed multiplier when the child is further ahead than `surge_distance`.
@export var surge_multiplier: float = 1.35
@export var surge_distance: float = 12.0
## Chases along +X (1) or -X (-1).
@export var direction: float = 1.0
## Stops here (world X).
@export var end_x: float = 1000.0
@export var catch_height: float = 9.0
@export var restart_gap: float = 14.0
@export var rewake_delay: float = 1.2
## Height above the child it follows at (it lumbers over terrain).
@export var follow_height: float = 2.5

var _rewake_t: float = -1.0

func _ready() -> void:
	ignores_light = true
	super._ready()

func _reset() -> void:
	super._reset()
	var start := _game.get_respawn_position().x - restart_gap * direction
	if (start - _home.x) * direction > 0.0:
		global_position.x = start
		_rewake_t = rewake_delay
	else:
		_rewake_t = -1.0
	reset_physics_interpolation()

func _physics_process(delta: float) -> void:
	if _rewake_t > 0.0 and _game and _game.is_playing():
		_rewake_t -= delta
		if _rewake_t <= 0.0:
			mode = Mode.DORMANT
			wake()
	super._physics_process(delta)

func _hunt(delta: float) -> void:
	var p := _game.get_player_position()
	var ahead := (p.x - global_position.x) * direction
	var speed := _speed(chase_speed) * (surge_multiplier if ahead > surge_distance else 1.0)
	var x := global_position.x + direction * speed * delta
	x = minf(x, end_x) if direction > 0.0 else maxf(x, end_x)
	var y := lerpf(global_position.y, p.y + follow_height, 1.0 - exp(-1.5 * delta))
	global_position = Vector3(x, y, _home.z)
	_move_dir = direction
	_speed_now = speed * delta

func _check_catch() -> void:
	var p := _game.get_player_position()
	if (p.x - global_position.x) * direction <= catch_radius and absf(p.y - global_position.y) <= catch_height:
		_game.report_player_caught(self)
