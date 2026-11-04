class_name Crawler
extends Enemy

## Crawler — comes out of a wall or floor crack and follows the child along the ground
## through the dark. It stops dead at a light's edge (hissing, pacing) and never walks
## off ledges. First appears in World 1, level 3.
##
## Sends / receives: see Enemy.

@export_group("Crawler")
@export var crawl_speed: float = 2.2
@export var gravity: float = 25.0
## Stops following when the child is further than this.
@export var lose_interest_distance: float = 18.0

@onready var _edge_probe: RayCast3D = $EdgeProbe

func _hunt(delta: float) -> void:
	var pos := global_position
	var probe_point := pos + Vector3(0.0, 0.35, 0.0)
	var vx := 0.0
	var to_player := _game.get_player_position().x - pos.x
	if absf(to_player) > 0.15 and absf(to_player) < lose_interest_distance:
		var dir := signf(to_player)
		var ahead := probe_point + Vector3(dir * (body_radius + 0.25), 0.0, 0.0)
		if _is_lit(ahead):
			_repelled()
		elif _has_floor_ahead(dir):
			vx = dir * _speed(crawl_speed)
	velocity.x = vx
	velocity.y -= gravity * delta
	velocity.z = 0.0
	move_and_slide()
	apply_floor_snap()
	global_position.z = _home.z
	_speed_now = absf(vx) * delta
	if absf(vx) > 0.01:
		_move_dir = signf(vx)

func _has_floor_ahead(dir: float) -> bool:
	_edge_probe.position = Vector3(dir * 0.5, 0.3, 0.0)
	_edge_probe.force_raycast_update()
	return _edge_probe.is_colliding()

func _animate(delta: float) -> void:
	super._animate(delta)
	if _hiss_timer > 0.5:
		_visual.position.x = sin(_time * 60.0) * 0.03
	else:
		_visual.position.x = 0.0
