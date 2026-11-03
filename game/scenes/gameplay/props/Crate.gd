class_name Crate
extends AnimatableBody3D

## Crate — a heavy box the child can push along the floor (walk into it and keep going).
## It moves at `push_speed` between `min_x` and `max_x` (world) and sits on the floor; it
## can't be pushed while the child is in the air. Pressure plates look for the "crates"
## group. Resets with the checkpoint.
##
## Sends: GameManager.report_player_pushing(direction) (drives the push animation).
## Receives: polls the child's position and input through GameManager; checkpoint snapshot.

@export var push_speed: float = 2.0
@export var min_x: float = -1000.0
@export var max_x: float = 1000.0
@export var half_width: float = 0.6
## How close (m) the child's centre must be to the crate's side to push it.
@export var reach: float = 0.95

var _game: GameManager
var _pushing: int = 0
var _home_x: float = 0.0

func _ready() -> void:
	add_to_group(&"crates")
	add_to_group(&"resettables")
	_home_x = global_position.x

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _physics_process(delta: float) -> void:
	var dir := 0
	if _game and _game.is_playing() and _game.has_player() and _game.is_player_on_floor():
		var p := _game.get_player_position()
		var axis: float = _game.input.move_axis
		var dx := global_position.x - p.x
		if absf(p.y - (global_position.y - half_width)) < 0.7 and absf(dx) <= half_width + reach:
			if dx > 0.0 and axis > 0.2 and global_position.x < max_x:
				dir = 1
			elif dx < 0.0 and axis < -0.2 and global_position.x > min_x:
				dir = -1
	if dir != 0:
		global_position.x = clampf(global_position.x + dir * push_speed * delta, min_x, max_x)
	if dir != _pushing:
		_pushing = dir
		if _game:
			_game.report_player_pushing(dir)

## Back to where it was placed in the level (a trap that missed re-arms this way).
func return_home() -> void:
	global_position.x = _home_x
	reset_physics_interpolation()

func capture_checkpoint_state() -> Dictionary:
	return { "x": global_position.x }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	if state.has("x"):
		global_position.x = state["x"]
	_pushing = 0
	reset_physics_interpolation()
