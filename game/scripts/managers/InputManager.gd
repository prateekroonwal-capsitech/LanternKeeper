class_name InputManager
extends Node

## InputManager — turns keyboard / controller input (and touch gestures, Phase 3)
## into the same game actions: move, jump, place_lantern, raise_light, pause.
##
## Continuous actions are exposed as state that gameplay polls through
## GameManager.input (move_axis, jump_held, jump_just_pressed, raise_held).
## One-shot actions are reported to the hub.
##
## Sends: GameManager.report_place_lantern_pressed(), GameManager.report_pause_pressed()
## Receives: nothing (reads the InputMap actions defined in project.godot).

## -1..1 horizontal movement for this physics frame.
var move_axis: float = 0.0
var jump_held: bool = false
var jump_just_pressed: bool = false
var raise_held: bool = false

var _game: GameManager

func configure(game: GameManager) -> void:
	_game = game

func _ready() -> void:
	# Runs while paused (to unpause) and before every gameplay node in the frame.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100

func _physics_process(_delta: float) -> void:
	if get_tree().paused:
		_clear()
		return
	move_axis = Input.get_axis(&"move_left", &"move_right")
	jump_held = Input.is_action_pressed(&"jump")
	jump_just_pressed = Input.is_action_just_pressed(&"jump")
	raise_held = Input.is_action_pressed(&"raise_light")
	if Input.is_action_just_pressed(&"place_lantern") and _game:
		_game.report_place_lantern_pressed()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and _game:
		_game.report_pause_pressed()
		get_viewport().set_input_as_handled()

func _clear() -> void:
	move_axis = 0.0
	jump_held = false
	jump_just_pressed = false
	raise_held = false
