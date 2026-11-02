@tool
class_name WakeTrigger
extends Area3D

## WakeTrigger — invisible box that wakes every enemy whose `wake_group` matches when the
## child walks in. Fires once; re-arms when the child respawns (enemies go dormant again).
##
## Sends: GameManager.report_wake_trigger(wake_group)
## Receives: GameBus.level_reset → re-arm.

@export var wake_group: StringName = &"group_a"
@export var size: Vector3 = Vector3(2.0, 4.0, 2.0):
	set(v):
		size = v
		if is_node_ready():
			_apply_size()

var _game: GameManager
var _fired: bool = false

@onready var _shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	_apply_size()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)

func inject_services(registry: Node) -> void:
	if not registry or Engine.is_editor_hint():
		return
	_game = registry.get_service(&"game") as GameManager
	if _game:
		_game.bus.level_reset.connect(func(_serial: int) -> void: _fired = false)

func _on_body_entered(body: Node3D) -> void:
	if _fired or _game == null or not body.is_in_group(&"player"):
		return
	_fired = true
	_game.report_wake_trigger(wake_group)

func _apply_size() -> void:
	(_shape.shape as BoxShape3D).size = size
