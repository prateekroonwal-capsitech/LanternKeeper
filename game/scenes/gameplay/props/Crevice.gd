class_name Crevice
extends Area3D

## Crevice — a dark crack in the cave wall the child can hide in. While the child is inside,
## creatures that hunt by sight (the Shade in level 10) can't see them, unless they carry
## the light.
##
## Sends: GameManager.report_hiding_spot(self, inside).
## Receives: nothing.

var _game: GameManager

func _ready() -> void:
	body_entered.connect(func(b: Node3D) -> void: _report(b, true))
	body_exited.connect(func(b: Node3D) -> void: _report(b, false))

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _report(body: Node3D, inside: bool) -> void:
	if _game and body.is_in_group(&"player"):
		_game.report_hiding_spot(self, inside)
