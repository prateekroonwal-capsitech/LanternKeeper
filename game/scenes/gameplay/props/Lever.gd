class_name Lever
extends Area3D

## Lever — walk into it to pull it (once). Rail hooks and gates with the same
## `lever_id` react. Resets with the checkpoint.
##
## Sends: GameManager.report_lever_pulled(lever_id)
## Receives: checkpoint snapshot via capture_checkpoint_state() / reset_to_checkpoint().

@export var lever_id: StringName = &"lever_a"
@export var pulled_angle_degrees: float = -60.0

var _game: GameManager
var _pulled: bool = false

@onready var _handle: Node3D = $HandlePivot

func _ready() -> void:
	add_to_group(&"resettables")
	body_entered.connect(_on_body_entered)

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _on_body_entered(body: Node3D) -> void:
	if _pulled or _game == null or not _game.is_playing() or not body.is_in_group(&"player"):
		return
	_set_pulled(true)
	_game.report_lever_pulled(lever_id)

func _set_pulled(v: bool) -> void:
	_pulled = v
	_handle.rotation.z = deg_to_rad(pulled_angle_degrees if v else 0.0)

func capture_checkpoint_state() -> Dictionary:
	return { "pulled": _pulled }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	_set_pulled(state.get("pulled", false))
