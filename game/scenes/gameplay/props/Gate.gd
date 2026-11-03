class_name Gate
extends AnimatableBody3D

## Gate — solid bars that slide open while the lantern hangs on the hook with the same
## `hook_id` (and/or once the lever with `lever_id` is pulled). When the lantern is taken
## off the hook it waits `close_delay` seconds, then slides shut.
##
## Sends: nothing.
## Receives: GameBus.lantern_hook_changed(hook_id, hung), GameBus.lever_pulled(lever_id);
##   checkpoint snapshot via capture_checkpoint_state() / reset_to_checkpoint().

@export var hook_id: StringName = &"hook_a"
## Optional: a lever that opens it for good (empty = none).
@export var lever_id: StringName = &""
@export var open_offset: Vector3 = Vector3(0.0, 3.2, 0.0)
@export var open_time: float = 0.8
@export var close_time: float = 0.35
## Seconds after the lantern leaves the hook before the gate starts closing.
@export var close_delay: float = 3.0

var _start: Vector3
var _open: float = 0.0          # 0 closed … 1 open
var _want_open: bool = false
var _close_wait: float = 0.0
var _locked_open: bool = false

func _ready() -> void:
	add_to_group(&"resettables")
	_start = global_position

func inject_services(registry: Node) -> void:
	if not registry:
		return
	var game := registry.get_service(&"game") as GameManager
	if game == null:
		return
	game.bus.lantern_hook_changed.connect(_on_hook_changed)
	game.bus.lever_pulled.connect(func(id: StringName) -> void:
		if lever_id != &"" and id == lever_id:
			_locked_open = true)

func _on_hook_changed(id: StringName, hung: bool) -> void:
	if id != hook_id:
		return
	_want_open = hung
	_close_wait = close_delay if not hung else 0.0

func _physics_process(delta: float) -> void:
	var target := 1.0 if (_want_open or _locked_open) else 0.0
	if target < _open and _close_wait > 0.0:
		_close_wait -= delta
		return
	var speed := 1.0 / maxf(open_time if target > _open else close_time, 0.01)
	_open = move_toward(_open, target, speed * delta)
	global_position = _start + open_offset * _open

func is_open() -> bool:
	return _open > 0.95

func capture_checkpoint_state() -> Dictionary:
	return { "open": _open, "want": _want_open, "locked": _locked_open }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	_open = state.get("open", 0.0)
	_want_open = state.get("want", false)
	_locked_open = state.get("locked", false)
	_close_wait = 0.0
	global_position = _start + open_offset * _open
	reset_physics_interpolation()
