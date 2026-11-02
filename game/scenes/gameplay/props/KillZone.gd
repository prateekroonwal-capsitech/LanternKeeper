@tool
class_name KillZone
extends Area3D

## KillZone — invisible box below the level (or in pits). The player touching it dies.
##
## Sends: GameManager.report_player_died(cause)
## Receives: nothing.

@export var size: Vector3 = Vector3(200.0, 4.0, 4.0):
	set(v):
		size = v
		if is_node_ready():
			_apply_size()
## Death cause reported to GameManager.
@export var cause: String = "fall"

var _game: GameManager

@onready var _shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	_apply_size()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _on_body_entered(body: Node3D) -> void:
	if _game and body.is_in_group(&"player"):
		_game.report_player_died(cause)

func _apply_size() -> void:
	(_shape.shape as BoxShape3D).size = size
