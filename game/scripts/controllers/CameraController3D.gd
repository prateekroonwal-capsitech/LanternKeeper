class_name CameraController3D
extends Camera3D

## CameraController3D — side-on follow camera for the 2.5D levels.
## Background layers at different Z depths give the parallax for free.
## 3D counterpart of CameraController (2D).
##
## Smoothness: physics interpolation is on (project setting), the player moves only in
## _physics_process, and this camera runs in _process reading the player's *interpolated*
## transform, so camera and player never step on different clocks. The camera itself is
## excluded from interpolation. All smoothing is frame-rate independent (1 - exp(-k·dt)).
## Vertical dead zone: small jumps don't move the camera; it re-centres when the player
## lands, falls below the zone, or climbs above it.
##
## Sends: nothing.
## Receives: GameManager.get_player_visual_position() / get_player_facing() /
##   is_player_on_floor() (polled); GameBus.level_started, GameBus.player_respawned → snap;
##   GameBus.player_died → light shake; GameBus.camera_focus_requested(point, duration) →
##   frames the child and that point together (pulls back as far as needed), then eases back.

## Camera position relative to the player's feet.
@export var follow_offset: Vector3 = Vector3(0.0, 2.2, 14.0)
@export var horizontal_follow_speed: float = 4.0
@export var vertical_follow_speed: float = 2.5
## How far ahead of the player (in the facing direction) the camera looks.
@export var look_ahead: float = 1.4
@export var look_ahead_speed: float = 1.5
## The camera never goes below this Y, so falls into pits read as falls.
@export var min_y: float = -2.0

@export_group("Vertical dead zone")
## While airborne, the camera ignores the player rising up to this far above the last ground.
@export var dead_zone_up: float = 2.6
## …or dropping up to this far below it.
@export var dead_zone_down: float = 1.0

@export_group("Focus")
## Extra room (m) around the child and the focus point when framing both.
@export var focus_margin: float = 4.5
@export var focus_speed: float = 3.0
@export var focus_max_distance: float = 30.0

@export_group("Death shake")
@export var shake_strength: float = 0.25
@export var shake_duration: float = 0.3

var _game: GameManager
var _look: float = 0.0
var _focus_y: float = 0.0
var _shake_time: float = 0.0
var _shake_amount: float = 0.0
var _shake_length: float = 0.0
var _focus_point: Vector3
var _focus_time: float = 0.0
var _zoom: float = 0.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.bus.level_started.connect(func(_id: String) -> void: _snap())
	_game.bus.player_respawned.connect(_snap.call_deferred)
	_game.bus.player_died.connect(func(_cause: String) -> void: shake(shake_strength, shake_duration))
	_game.bus.camera_focus_requested.connect(func(point: Vector3, duration: float) -> void:
		_focus_point = point
		_focus_time = duration)
	set_process(true)

func _process(delta: float) -> void:
	if not _game.has_player():
		return
	var p := _game.get_player_visual_position()
	_update_focus(p, delta)
	_look = lerpf(_look, look_ahead * _game.get_player_facing(), 1.0 - exp(-look_ahead_speed * delta))
	var target := _target(p)
	var extra := 0.0
	if _focus_time > 0.0:
		# Frame the child and the focus point together: centre between them, pull back to fit.
		_focus_time -= delta
		target.x = (p.x + _focus_point.x) * 0.5 + follow_offset.x
		target.y = maxf((_focus_y + _focus_point.y) * 0.5 + follow_offset.y, min_y)
		var half := absf(_focus_point.x - p.x) * 0.5 + focus_margin
		var aspect := get_viewport().get_visible_rect().size.aspect()
		var need := half / (tan(deg_to_rad(fov * 0.5)) * maxf(aspect, 1.0))
		extra = clampf(need - follow_offset.z, 0.0, focus_max_distance - follow_offset.z)
	_zoom = lerpf(_zoom, extra, 1.0 - exp(-focus_speed * delta))
	var speed := focus_speed if _focus_time > 0.0 or _zoom > 0.05 else horizontal_follow_speed
	var pos := global_position
	pos.x = lerpf(pos.x, target.x, 1.0 - exp(-maxf(speed, horizontal_follow_speed) * delta))
	pos.y = lerpf(pos.y, target.y, 1.0 - exp(-vertical_follow_speed * delta))
	pos.z = target.z + _zoom
	global_position = pos
	_update_shake(delta)

func _update_focus(p: Vector3, delta: float) -> void:
	if _game.is_player_on_floor():
		_focus_y = lerpf(_focus_y, p.y, 1.0 - exp(-8.0 * delta))
	elif p.y < _focus_y - dead_zone_down:
		_focus_y = p.y + dead_zone_down
	elif p.y > _focus_y + dead_zone_up:
		_focus_y = p.y - dead_zone_up

func _target(p: Vector3) -> Vector3:
	var t := Vector3(p.x + _look, _focus_y, 0.0) + follow_offset
	t.y = maxf(t.y, min_y)
	t.z = follow_offset.z
	return t

func _update_shake(delta: float) -> void:
	if _shake_time > 0.0:
		_shake_time -= delta
		var k := clampf(_shake_time / maxf(_shake_length, 0.001), 0.0, 1.0) * _shake_amount
		h_offset = randf_range(-k, k)
		v_offset = randf_range(-k, k)
	else:
		h_offset = 0.0
		v_offset = 0.0

func shake(strength: float, duration: float) -> void:
	_shake_amount = strength
	_shake_length = duration
	_shake_time = duration

func _snap() -> void:
	if not _game.has_player():
		return
	var p := _game.get_player_position()
	_focus_y = p.y
	_look = look_ahead * _game.get_player_facing()
	_focus_time = 0.0
	_zoom = 0.0
	global_position = _target(p)
