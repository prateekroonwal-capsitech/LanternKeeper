class_name PressurePlate
extends Area3D

## PressurePlate — a stone plate in the floor. When a crate (group "crates") comes to rest on
## it, it sinks and fires `plate_id`, like a lever (traps and gates listen for that id). It rises
## when the crate leaves, and fires again the next time a crate arrives.
## Resets with the checkpoint.
##
## Sends: GameManager.report_lever_pulled(plate_id).
## Receives: checkpoint snapshot via capture_checkpoint_state() / reset_to_checkpoint().

@export var plate_id: StringName = &"plate_a"
## The crate's centre must be within this distance (m) of the plate's centre.
@export var half_width: float = 0.5
@export var press_depth: float = 0.08

var _game: GameManager
var _pressed: bool = false

@onready var _plate: Node3D = $Plate

func _ready() -> void:
	add_to_group(&"resettables")

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _physics_process(_delta: float) -> void:
	if _game == null or not _game.is_playing():
		return
	var on := false
	for body in get_overlapping_bodies():
		if body.is_in_group(&"crates") and absf(body.global_position.x - global_position.x) <= half_width:
			on = true
	if on and not _pressed:
		_set_pressed(true)
		print("[PressurePlate] %s pressed" % plate_id)
		_game.report_lever_pulled(plate_id)
	elif not on and _pressed:
		_set_pressed(false)
		print("[PressurePlate] %s released" % plate_id)

func _set_pressed(v: bool) -> void:
	_pressed = v
	_plate.position.y = -press_depth if v else 0.0

func capture_checkpoint_state() -> Dictionary:
	return { "pressed": _pressed }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	_set_pressed(state.get("pressed", false))
