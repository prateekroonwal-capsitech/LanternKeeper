class_name Shrine
extends Area3D

## Shrine — checkpoint. Touching it refills the oil completely (every time) and
## makes it the respawn point. The active shrine glows; others stay dim.
##
## Sends: GameManager.report_shrine_reached(self)
## Receives: GameBus.checkpoint_activated(shrine) → active / dormant look.

@export_group("Look")
@export var dormant_light_energy: float = 0.35
@export var active_light_energy: float = 1.8
@export var dormant_tint: Color = Color(0.45, 0.5, 0.6, 1.0)
@export var active_tint: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var glow_change_speed: float = 3.0

var _game: GameManager
var _active: bool = false

@onready var _sprite: Sprite3D = $Sprite
@onready var _light: OmniLight3D = $Light
@onready var _burst: CPUParticles3D = $Burst
@onready var _respawn_point: Marker3D = $RespawnPoint

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_light.light_energy = dormant_light_energy
	_sprite.modulate = dormant_tint

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game:
		_game.bus.checkpoint_activated.connect(_on_checkpoint_activated)

func get_respawn_position() -> Vector3:
	return _respawn_point.global_position

func _process(delta: float) -> void:
	var target := active_light_energy if _active else dormant_light_energy
	_light.light_energy = move_toward(_light.light_energy, target, delta * glow_change_speed)
	_sprite.modulate = _sprite.modulate.lerp(active_tint if _active else dormant_tint, 1.0 - exp(-glow_change_speed * delta))

func _on_body_entered(body: Node3D) -> void:
	if _game and body.is_in_group(&"player"):
		_game.report_shrine_reached(self)

func _on_checkpoint_activated(shrine: Node3D) -> void:
	var was_active := _active
	_active = shrine == self
	if _active and not was_active:
		_burst.restart()
