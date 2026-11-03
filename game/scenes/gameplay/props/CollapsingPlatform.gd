@tool
class_name CollapsingPlatform
extends StaticBody3D

## CollapsingPlatform — a cracked plank bridge. Once the child stands on it, it shakes for
## `crumble_delay` seconds, then falls away (no collision) and stays down. It comes back
## when the child respawns at a checkpoint saved before it fell. Looks cracked so the
## hazard reads before you reach it.
##
## Sends: nothing.
## Receives: checkpoint snapshot via capture_checkpoint_state() / reset_to_checkpoint()
##   (group "resettables").

@export var size: Vector2 = Vector2(3.0, 0.4):
	set(v):
		size = Vector2(maxf(v.x, 0.1), maxf(v.y, 0.1))
		if is_node_ready():
			_apply_size()
@export var depth: float = 2.0
## Seconds between the child stepping on and the planks giving way.
@export var crumble_delay: float = 0.5
@export var shake_amount: float = 0.06
@export var fall_distance: float = 6.0
@export var fall_time: float = 0.7

enum State { INTACT, CRUMBLING, FALLEN }

var _state: State = State.INTACT
var _t: float = 0.0
var _rest: Vector3

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _visual: MeshInstance3D = $Visual
@onready var _feet: Area3D = $FeetCheck
@onready var _feet_shape: CollisionShape3D = $FeetCheck/CollisionShape3D

func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	add_to_group(&"resettables")
	_rest = _visual.position

func _physics_process(delta: float) -> void:
	match _state:
		State.INTACT:
			for b in _feet.get_overlapping_bodies():
				if b.is_in_group(&"player"):
					_state = State.CRUMBLING
					_t = 0.0
		State.CRUMBLING:
			_t += delta
			_visual.position = _rest + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * shake_amount
			if _t >= crumble_delay:
				_state = State.FALLEN
				_t = 0.0
				_shape.set_deferred(&"disabled", true)
		State.FALLEN:
			_t = minf(_t + delta / maxf(fall_time, 0.01), 1.0)
			_visual.position = _rest - Vector3(0.0, fall_distance * _t * _t, 0.0)
			_visual.visible = _t < 1.0

func capture_checkpoint_state() -> Dictionary:
	return { "fallen": _state == State.FALLEN }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	var fallen: bool = state.get("fallen", false)
	_state = State.FALLEN if fallen else State.INTACT
	_t = 1.0 if fallen else 0.0
	_shape.set_deferred(&"disabled", fallen)
	_visual.visible = not fallen
	_visual.position = _rest
	reset_physics_interpolation()

func _apply_size() -> void:
	(_shape.shape as BoxShape3D).size = Vector3(size.x, size.y, depth)
	(_feet_shape.shape as BoxShape3D).size = Vector3(maxf(size.x - 0.1, 0.1), 0.3, depth)
	_feet_shape.position = Vector3(0.0, size.y * 0.5 + 0.15, 0.0)
	_visual.scale = Vector3(size.x, size.y, depth)
