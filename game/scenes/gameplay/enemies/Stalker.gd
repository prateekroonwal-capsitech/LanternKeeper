class_name Stalker
extends Enemy

## Stalker — a tall shape that follows the child from behind, hovering just outside the
## light around them. As the oil runs down the light shrinks and it drifts closer; the
## moment the child is in darkness it comes straight for them. First appears in World 1,
## level 7.
##
## Sends / receives: see Enemy.

@export_group("Stalker")
@export var drift_speed: float = 2.4
@export var attack_speed: float = 4.2
## Extra distance it keeps beyond the edge of the child's light.
@export var stalk_gap: float = 0.6
## Height above the child's feet it floats at.
@export var hover_height: float = 0.9
@export var bob_amount: float = 0.15

func _hunt(delta: float) -> void:
	var p := _game.get_player_position()
	var target: Vector3
	var speed: float
	if _game.player_lit:
		var light_c := _game.get_nearest_light_position(p + Vector3(0.0, 0.8, 0.0))
		var radius := _light_radius_at(light_c)
		var side := signf(global_position.x - p.x)
		if side == 0.0:
			side = -float(_game.get_player_facing())
		target = Vector3(light_c.x + side * (radius + body_radius + light_margin + stalk_gap), p.y + hover_height, 0.0)
		speed = _speed(drift_speed)
	else:
		target = p + Vector3(0.0, hover_height, 0.0)
		speed = _speed(attack_speed)
	target.y += sin(_time * 1.7) * bob_amount
	_float_toward(target, speed, delta)

func _light_radius_at(center: Vector3) -> float:
	# Radius of the light around `center`: grow outward until the point is no longer lit.
	var r := 0.5
	while r < 12.0 and _game.is_point_lit(center + Vector3(r, 0.0, 0.0)):
		r += 0.25
	return r

func _is_lit(point: Vector3) -> bool:
	if ignores_light or _game == null:
		return false
	if _game.player_lit:
		return _game.is_point_lit(point, body_radius + light_margin)
	for source in _game.get_light_sources():
		if not is_instance_valid(source) or not source.is_light_active():
			continue
		if source is Lantern and source.is_hung():
			continue
		var c: Vector3 = source.get_light_position()
		var r: float = source.get_light_radius() + body_radius + light_margin
		if Vector2(point.x - c.x, point.y - c.y).length_squared() <= r * r:
			return true
	return false

func _perform_lunge_step(spd: float, delta: float) -> void:
	var target := _game.get_player_position() + Vector3(0.0, hover_height * 0.5, 0.0)
	var to := _flat(target - global_position)
	if to.length_squared() > 0.001:
		_float_step(to.normalized() * spd * delta)

func _perform_retreat_step(away: float, spd: float, delta: float) -> void:
	_float_step(Vector3(away * spd * delta, 0.5 * delta, 0.0))
