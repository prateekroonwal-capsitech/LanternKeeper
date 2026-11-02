@tool
class_name Platform
extends StaticBody3D

## Platform — solid silhouette block. Set `size` in the Inspector; the collision
## box and the visual resize live in the editor. Purely static: no GameManager events.

## Width / height in metres (X / Y). Top surface = position.y + size.y / 2.
@export var size: Vector2 = Vector2(4.0, 1.0):
	set(v):
		size = Vector2(maxf(v.x, 0.1), maxf(v.y, 0.1))
		if is_node_ready():
			_apply_size()
## Depth into the screen; only affects the 2.5D look.
@export var depth: float = 2.0:
	set(v):
		depth = maxf(v, 0.1)
		if is_node_ready():
			_apply_size()

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _visual: MeshInstance3D = $Visual

func _ready() -> void:
	_apply_size()

func _apply_size() -> void:
	(_shape.shape as BoxShape3D).size = Vector3(size.x, size.y, depth)
	_visual.scale = Vector3(size.x, size.y, depth)
