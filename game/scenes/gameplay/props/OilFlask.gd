class_name OilFlask
extends Area3D

## OilFlask — pickup that refills the lantern. If the player dies, flasks taken
## since the active checkpoint come back.
##
## Sends: GameManager.report_oil_collected(amount)
## Receives: GameBus.level_reset(checkpoint_serial) → restore if taken after that checkpoint.

@export var oil_amount: float = 35.0

@export_group("Bob")
@export var bob_height: float = 0.12
@export var bob_speed: float = 2.2

var _game: GameManager
var _collected: bool = false
var _collected_serial: int = -1
var _time: float = 0.0

@onready var _visual: Node3D = $Visual
@onready var _base_y: float = _visual.position.y

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_time = randf() * TAU

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game:
		_game.bus.level_reset.connect(_on_level_reset)

func _process(delta: float) -> void:
	_time += delta
	_visual.position.y = _base_y + sin(_time * bob_speed) * bob_height

func _on_body_entered(body: Node3D) -> void:
	if _collected or _game == null or not _game.is_playing() or not body.is_in_group(&"player"):
		return
	_collected = true
	_collected_serial = _game.checkpoint_serial
	_set_present(false)
	_game.report_oil_collected(oil_amount)

func _on_level_reset(checkpoint_serial: int) -> void:
	if _collected and _collected_serial == checkpoint_serial:
		_collected = false
		_set_present(true)

func _set_present(present: bool) -> void:
	visible = present
	set_deferred(&"monitoring", present)
