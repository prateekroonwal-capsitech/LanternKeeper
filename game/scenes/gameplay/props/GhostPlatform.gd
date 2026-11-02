@tool
class_name GhostPlatform
extends StaticBody3D

## GhostPlatform — solid only while any part of it is inside a light radius.
## In the dark it is a faint dashed outline with no collision. When it loses
## light it fades over `fade_out_time`, then drops whatever stands on it.
## It never turns solid while the player is inside its volume.
##
## Sends: GameManager.report_platform_lost() when it vanishes under the player.
## Receives: GameManager.is_box_lit(), GameManager.get_player_position() (polled).
## Look: shader parameters live on Visual → material_override (ghost_platform.gdshader).

@export var size: Vector2 = Vector2(3.0, 0.5):
	set(v):
		size = Vector2(maxf(v.x, 0.1), maxf(v.y, 0.1))
		if is_node_ready():
			_apply_size()
@export var depth: float = 2.0:
	set(v):
		depth = maxf(v, 0.1)
		if is_node_ready():
			_apply_size()

@export_group("Fade")
## Seconds a platform keeps its collision after the light leaves it.
@export var fade_out_time: float = 0.35
@export var fade_in_time: float = 0.15
## Extra reach added to light radii when testing this platform.
@export var lit_padding: float = 0.0

@export_group("Editor")
## Solidity shown in the editor viewport (0 = outline, 1 = solid). Runtime ignores it.
@export_range(0.0, 1.0) var editor_preview_solidity: float = 0.6:
	set(v):
		editor_preview_solidity = v
		if is_node_ready() and Engine.is_editor_hint():
			_set_solidity_visual(v)

var _game: GameManager
var _solidity: float = 0.0
var _solid: bool = false

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _visual: MeshInstance3D = $Visual
@onready var _occupancy: Area3D = $Occupancy
@onready var _occupancy_shape: CollisionShape3D = $Occupancy/CollisionShape3D

func _ready() -> void:
	_apply_size()
	if Engine.is_editor_hint():
		_set_solidity_visual(editor_preview_solidity)
		set_physics_process(false)
		return
	_set_solid(false)
	_set_solidity_visual(0.0)
	set_physics_process(false)

func inject_services(registry: Node) -> void:
	if not registry or Engine.is_editor_hint():
		return
	_game = registry.get_service(&"game") as GameManager
	if _game:
		set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _game.state == GameManager.State.PAUSED:
		return
	var lit := _game.is_box_lit(global_position, size * 0.5, lit_padding)
	if lit:
		_solidity = move_toward(_solidity, 1.0, delta / maxf(fade_in_time, 0.001))
		if not _solid and not _player_inside():
			_set_solid(true)
	else:
		_solidity = move_toward(_solidity, 0.0, delta / maxf(fade_out_time, 0.001))
		if _solid and _solidity <= 0.0:
			if _player_standing_on():
				_game.report_platform_lost()
			_set_solid(false)
	_set_solidity_visual(_solidity)

func _player_inside() -> bool:
	for body in _occupancy.get_overlapping_bodies():
		if body.is_in_group(&"player"):
			return true
	return false

func _player_standing_on() -> bool:
	var p := _game.get_player_position()
	var top := global_position.y + size.y * 0.5
	return absf(p.y - top) < 0.2 and absf(p.x - global_position.x) <= size.x * 0.5 + 0.4

func _set_solid(value: bool) -> void:
	_solid = value
	_shape.set_deferred(&"disabled", not value)

func _set_solidity_visual(value: float) -> void:
	(_visual.material_override as ShaderMaterial).set_shader_parameter(&"solidity", value)

func _apply_size() -> void:
	(_shape.shape as BoxShape3D).size = Vector3(size.x, size.y, depth)
	(_occupancy_shape.shape as BoxShape3D).size = Vector3(maxf(size.x - 0.1, 0.05), maxf(size.y - 0.05, 0.05), depth)
	_visual.scale = Vector3(size.x, size.y, 1.0)
