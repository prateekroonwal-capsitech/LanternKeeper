class_name CameraController3D
extends Camera3D

## CameraController3D — side-on follow camera for the 2.5D levels.
## Background layers at different Z depths give the parallax for free.
## 3D counterpart of CameraController (2D); same idle-when-nothing-to-do idea.
##
## Sends: nothing.
## Receives: GameManager.get_player_position() / get_player_facing() (polled);
##   GameBus.level_started, GameBus.player_respawned → snap to the player.

## Camera position relative to the player's feet.
@export var follow_offset: Vector3 = Vector3(0.0, 2.2, 14.0)
@export var follow_speed: float = 5.0
## How far ahead of the player (in the facing direction) the camera looks.
@export var look_ahead: float = 1.6
@export var look_ahead_speed: float = 2.0
## The camera never goes below this Y, so falls into pits read as falls.
@export var min_y: float = -2.0

var _game: GameManager
var _look: float = 0.0

func _ready() -> void:
	set_process(false)

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.bus.level_started.connect(func(_id: String) -> void: _snap())
	_game.bus.player_respawned.connect(_snap.call_deferred)
	set_process(true)

func _process(delta: float) -> void:
	if not _game.has_player():
		return
	_look = lerpf(_look, look_ahead * _game.get_player_facing(), 1.0 - exp(-look_ahead_speed * delta))
	global_position = global_position.lerp(_target(), 1.0 - exp(-follow_speed * delta))

func _target() -> Vector3:
	var t := _game.get_player_position() + follow_offset + Vector3(_look, 0.0, 0.0)
	t.y = maxf(t.y, min_y)
	t.z = follow_offset.z
	return t

func _snap() -> void:
	if not _game.has_player():
		return
	_look = look_ahead * _game.get_player_facing()
	global_position = _target()
	reset_physics_interpolation()
