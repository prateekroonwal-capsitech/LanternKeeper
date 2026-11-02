class_name LevelExit
extends Area3D

## LevelExit — the doorway at the end of a level. Touching it completes the level.
##
## Sends: GameManager.report_level_exit_reached()
## Receives: nothing.

var _game: GameManager

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _on_body_entered(body: Node3D) -> void:
	if _game and body.is_in_group(&"player"):
		_game.report_level_exit_reached()
