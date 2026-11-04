@tool
class_name GhostPlatform
extends Node3D

## GhostPlatform — solid only where active light reaches it.
## Segments are split into ~0.4 m blocks (StaticBody3D + CollisionShape3D).
## A segment is solid if its top centre (padded by half its length) is inside ANY active light.
## Segments retain collision for `fade_out_time` (0.35 s) after light leaves them.
## Shader smoothly renders solid shimmering surface inside light circles and faint outline outside.

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

@export_group("Segments")
## Target length of each collision segment (default 0.4 m).
@export var segment_length: float = 0.4:
	set(v):
		segment_length = maxf(v, 0.1)
		if is_node_ready():
			_apply_size()

@export_group("Fade")
## Seconds a platform segment keeps its collision after the light leaves it.
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

var _game: Variant
var _segment_bodies: Array[StaticBody3D] = []
var _segment_shapes: Array[CollisionShape3D] = []
var _segment_centers_x: Array[float] = []
var _segment_widths: Array[float] = []
var _segment_timers: Array[float] = []
var _segment_solid: Array[bool] = []

@onready var _visual: MeshInstance3D = $Visual
@onready var _occupancy: Area3D = get_node_or_null("Occupancy")
@onready var _occupancy_shape: CollisionShape3D = get_node_or_null("Occupancy/CollisionShape3D")

func _ready() -> void:
	_collect_segments()
	_apply_visual_size()
	if Engine.is_editor_hint():
		if _segment_shapes.is_empty():
			regenerate_segments()
		_set_solidity_visual(editor_preview_solidity)
		set_physics_process(false)
		return
	_set_all_solid(false)
	_update_shader_lights([])
	set_physics_process(false)

func inject_services(registry: Node) -> void:
	if not registry or Engine.is_editor_hint():
		return
	_game = registry.get_service(&"game")
	if _game:
		if _game.get("bus") and _game.bus != null and _game.bus.has_signal(&"level_reset"):
			_game.bus.level_reset.connect(func(_serial: int) -> void:
				_set_all_solid(false)
				_update_shader_lights([])
			)
		set_physics_process(true)

func _physics_process(delta: float) -> void:
	if _game == null or _game.state == GameManager.State.PAUSED:
		return

	var platform_pos: Vector3 = global_position
	var half_w: float = size.x * 0.5
	var lights: Array[Node3D] = _game.get_light_sources()
	
	# Performance: skip per-segment checks when no light is within (platform half-width + max light radius)
	var near_lights: Array[Node3D] = []
	var any_light_near: bool = false
	
	for source in lights:
		if not is_instance_valid(source) or not source.is_light_active():
			continue
		var light_pos: Vector3 = source.get_light_position()
		var r: float = float(source.get_light_radius())
		var max_reach: float = half_w + r + lit_padding
		var dx: float = light_pos.x - platform_pos.x
		var dy: float = light_pos.y - platform_pos.y
		if dx * dx + dy * dy <= max_reach * max_reach:
			any_light_near = true
			near_lights.append(source)

	# Update collision segments
	var top_y: float = platform_pos.y + size.y * 0.5
	for i in range(_segment_shapes.size()):
		var shape: CollisionShape3D = _segment_shapes[i]
		if not is_instance_valid(shape):
			continue
			
		var is_lit: bool = false
		if any_light_near:
			var test_point := Vector3(platform_pos.x + _segment_centers_x[i], top_y, platform_pos.z)
			var pad: float = _segment_widths[i] * 0.5 + lit_padding
			is_lit = _is_point_in_sources(test_point, pad, near_lights)
		
		if is_lit:
			_segment_timers[i] = fade_out_time
			if not _segment_solid[i]:
				_segment_solid[i] = true
				shape.set_deferred(&"disabled", false)
		else:
			if _segment_timers[i] > 0.0:
				_segment_timers[i] -= delta
				if _segment_timers[i] <= 0.0 and _segment_solid[i]:
					_segment_solid[i] = false
					shape.set_deferred(&"disabled", true)
			elif _segment_solid[i]:
				_segment_solid[i] = false
				shape.set_deferred(&"disabled", true)

	# Update visual shader uniforms
	_update_shader_lights(near_lights)

func _is_point_in_sources(point: Vector3, pad: float, sources: Array[Node3D]) -> bool:
	for source in sources:
		var c: Vector3 = source.get_light_position()
		var r: float = float(source.get_light_radius()) + pad
		var dx: float = point.x - c.x
		var dy: float = point.y - c.y
		if dx * dx + dy * dy <= r * r:
			return true
	return false

func _set_all_solid(value: bool) -> void:
	for i in range(_segment_shapes.size()):
		_segment_solid[i] = value
		_segment_timers[i] = fade_out_time if value else 0.0
		var shape: CollisionShape3D = _segment_shapes[i]
		if is_instance_valid(shape):
			shape.set_deferred(&"disabled", not value)

func _update_shader_lights(sources: Array[Node3D]) -> void:
	if not is_instance_valid(_visual):
		return
	var mat := _visual.material_override as ShaderMaterial
	if mat == null:
		return
	
	var count: int = mini(sources.size(), 4)
	var centers := PackedVector3Array()
	centers.resize(4)
	var radii := PackedFloat32Array()
	radii.resize(4)
	
	for i in range(count):
		var source: Node3D = sources[i]
		centers[i] = source.get_light_position()
		radii[i] = float(source.get_light_radius())
		
	mat.set_shader_parameter(&"light_count", count)
	mat.set_shader_parameter(&"light_centers", centers)
	mat.set_shader_parameter(&"light_radii", radii)

func _set_solidity_visual(value: float) -> void:
	if not is_instance_valid(_visual):
		return
	var mat := _visual.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter(&"editor_solidity", value)
		mat.set_shader_parameter(&"solidity", value)

func _apply_visual_size() -> void:
	if is_instance_valid(_visual):
		_visual.scale = Vector3(size.x, size.y, 1.0)
	if is_instance_valid(_occupancy_shape) and _occupancy_shape.shape is BoxShape3D:
		(_occupancy_shape.shape as BoxShape3D).size = Vector3(maxf(size.x - 0.1, 0.05), maxf(size.y - 0.05, 0.05), depth)

func _apply_size() -> void:
	_apply_visual_size()
	if Engine.is_editor_hint():
		regenerate_segments()

## Re-creates all segment StaticBody3D + CollisionShape3D children in editor mode.
## The output is saved into the .tscn; no nodes are created at runtime.
func regenerate_segments() -> void:
	# Remove old single shape if present
	var old_shape := get_node_or_null("CollisionShape3D")
	if old_shape:
		remove_child(old_shape)
		old_shape.queue_free()

	# Remove existing segment nodes
	var to_remove: Array[Node] = []
	for child in get_children():
		if child is StaticBody3D and child.name.begins_with("Segment"):
			to_remove.append(child)
	for child in to_remove:
		remove_child(child)
		child.queue_free()

	var count: int = maxi(1, int(roundf(size.x / segment_length)))
	var seg_w: float = size.x / float(count)
	var seg_h: float = size.y
	var seg_d: float = depth
	var scene_owner: Node = owner if owner != null else self

	for i in range(count):
		var local_x: float = -size.x * 0.5 + (float(i) + 0.5) * seg_w
		var seg := StaticBody3D.new()
		seg.name = "Segment%d" % i
		seg.collision_layer = 4
		seg.collision_mask = 0
		seg.position = Vector3(local_x, 0.0, 0.0)
		
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(seg_w, seg_h, seg_d)
		col.shape = box
		col.disabled = true
		
		seg.add_child(col)
		add_child(seg)
		
		if scene_owner:
			seg.owner = scene_owner
			col.owner = scene_owner

	_collect_segments()

func _collect_segments() -> void:
	_segment_bodies.clear()
	_segment_shapes.clear()
	_segment_centers_x.clear()
	_segment_widths.clear()
	_segment_timers.clear()
	_segment_solid.clear()
	
	# Collect and sort segments by name / index
	var seg_nodes: Array[StaticBody3D] = []
	for child in get_children():
		if child is StaticBody3D and child.name.begins_with("Segment"):
			seg_nodes.append(child)
			
	seg_nodes.sort_custom(func(a: Node, b: Node) -> bool:
		var idx_a: int = a.name.trim_prefix("Segment").to_int()
		var idx_b: int = b.name.trim_prefix("Segment").to_int()
		return idx_a < idx_b
	)

	for child in seg_nodes:
		var shape := child.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape and shape.shape is BoxShape3D:
			var box := shape.shape as BoxShape3D
			_segment_bodies.append(child)
			_segment_shapes.append(shape)
			_segment_centers_x.append(child.position.x)
			_segment_widths.append(box.size.x)
			_segment_timers.append(0.0)
			_segment_solid.append(not shape.disabled)

# ── Query API for tests & debug ──────────────────────────────────────────

func get_segment_count() -> int:
	return _segment_shapes.size()

func get_solid_segment_count() -> int:
	var count: int = 0
	for s in _segment_solid:
		if s:
			count += 1
	return count

func is_segment_solid(index: int) -> bool:
	if index >= 0 and index < _segment_solid.size():
		return _segment_solid[index]
	return false

func get_segment_center(index: int) -> Vector3:
	if index >= 0 and index < _segment_centers_x.size():
		return global_position + Vector3(_segment_centers_x[index], size.y * 0.5, 0.0)
	return global_position
