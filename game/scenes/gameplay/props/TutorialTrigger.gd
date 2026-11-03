@tool
class_name TutorialTrigger
extends Area3D

## TutorialTrigger — invisible box that asks for a one-time hint when the player
## walks in. Place it in the first levels of a world. Only "move", "jump", "place",
## "raise" show anything (wordless ghost-hand / key-icon hint via GestureHint).
## Other ids are ignored.
##
## Sends: GameManager.report_tutorial_trigger(hint_id)
## Receives: nothing.

@export var hint_id: String = "move"
@export var size: Vector3 = Vector3(2.0, 3.0, 2.0):
	set(v):
		size = v
		if is_node_ready():
			_apply_size()

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
		_game.report_tutorial_trigger(hint_id)

func _apply_size() -> void:
	(_shape.shape as BoxShape3D).size = size
