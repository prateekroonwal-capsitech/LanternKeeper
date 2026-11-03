class_name Rope
extends Node3D

## Rope — hangs from this node (the pivot) and sways. Jump into its lower part to grab it;
## it swings you in the direction you were moving; press jump to let go, flying off with the
## rope's speed. A rope needs both hands: the child can't grab it while carrying the lantern.
## Optional: wakes an enemy group the first time it's grabbed (`wake_group_on_grab`).
##
## Sends: GameManager.report_rope_touched(self)
## Receives: grab() / release() from GameManager → Player; checkpoint snapshot via
##   capture_checkpoint_state() / reset_to_checkpoint() (group "resettables").

@export var length: float = 5.0
## Gentle sway while nobody holds it (degrees).
@export var idle_sway_degrees: float = 6.0
## Swing amplitude while the child hangs on (degrees).
@export var swing_degrees: float = 52.0
## Seconds for a full swing back and forth.
@export var swing_period: float = 2.4
## Release speed multiplier and extra upward kick.
@export var release_boost: float = 1.25
@export var release_jump: float = 5.0
## Enemy group woken the first time the rope is grabbed (empty = none).
@export var wake_group_on_grab: StringName = &""

## How fast the swing settles back to its idle sway after you let go (radians per second).
@export var amplitude_change_speed: float = 1.2

var _game: GameManager
var _phi: float = 0.0
var _amp: float = 0.0
var _angle: float = 0.0
var _held: bool = false
var _woken: bool = false

@onready var _line: Node3D = $Line
@onready var _grab_zone: Area3D = $GrabZone
@onready var _grab_shape: CollisionShape3D = $GrabZone/CollisionShape3D

func _ready() -> void:
	add_to_group(&"resettables")
	_amp = deg_to_rad(idle_sway_degrees)
	_grab_zone.body_entered.connect(func(b: Node3D) -> void:
		if _game and b.is_in_group(&"player"):
			_game.report_rope_touched(self))

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _physics_process(delta: float) -> void:
	_phi += _w() * delta
	var target := deg_to_rad(swing_degrees if _held else idle_sway_degrees)
	_amp = move_toward(_amp, target, amplitude_change_speed * delta)
	_angle = _amp * sin(_phi)
	_line.rotation.z = _angle
	_line.scale = Vector3(1.0, length, 1.0)
	# Grab zone covers the lower 60 % of the rope.
	_grab_zone.rotation.z = _angle
	(_grab_shape.shape as CapsuleShape3D).height = length * 0.6
	_grab_shape.position = Vector3(0.0, -length * 0.7, 0.0)

func _w() -> float:
	return TAU / maxf(swing_period, 0.1)

## End of the rope in world space (where the child's hands are).
func get_hang_point() -> Vector3:
	return global_position + Vector3(sin(_angle), -cos(_angle), 0.0) * length

## Velocity of the rope end right now.
func get_point_velocity() -> Vector3:
	var omega := _amp * _w() * cos(_phi)
	return Vector3(cos(_angle), sin(_angle), 0.0) * omega * length

## The child grabbed on: swing from the current angle toward `direction` (+1 right, -1 left).
func grab(direction: float) -> void:
	_held = true
	# Jumping onto a rope throws it straight into a full swing (continuous from its angle).
	_amp = maxf(deg_to_rad(swing_degrees), absf(_angle) + 0.05)
	var base := asin(clampf(_angle / _amp, -1.0, 1.0))
	_phi = base if direction >= 0.0 else PI - base
	if not _woken and wake_group_on_grab != &"" and _game:
		_woken = true
		_game.report_wake_trigger(wake_group_on_grab)

## The child let go: returns their launch velocity.
func release() -> Vector3:
	_held = false
	return get_point_velocity() * release_boost + Vector3(0.0, release_jump, 0.0)

func is_held() -> bool:
	return _held

func capture_checkpoint_state() -> Dictionary:
	return { "woken": _woken }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	_held = false
	_woken = state.get("woken", false)
	_phi = 0.0
	_amp = deg_to_rad(idle_sway_degrees)
