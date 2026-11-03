class_name LanternHook
extends Area3D

## LanternHook — a hook the lantern can hang on. Set the lantern down while standing in
## this area and it hangs from HookPoint instead of dropping to the ground; walk into it
## to take it back. While it hangs, gates with the same `hook_id` stay open.
## Optional: wakes an enemy group when the lantern is hung (`wake_group_on_hang`), and
## rides a rail to `travel_offset` when the lever with `lever_id` is pulled — or, with
## `move_when_hung`, as soon as the lantern is hung (a lift / cradle). The lantern rides along.
##
## Sends: GameManager.register_hook(self) / unregister_hook(self), report_hook_reach(self, inside)
## Receives: GameBus.lever_pulled(lever_id) / lantern_hook_changed (move_when_hung) → ride
##   the rail; checkpoint snapshot via
##   capture_checkpoint_state() / reset_to_checkpoint() (group "resettables").

@export var hook_id: StringName = &"hook_a"
## Enemy group woken the first time the lantern is hung here (empty = none).
@export var wake_group_on_hang: StringName = &""

@export_group("Rail")
## Lever that sends the hook along its rail (empty = fixed hook).
@export var lever_id: StringName = &""
## Start riding the rail as soon as the lantern is hung (a moving lift / cradle).
@export var move_when_hung: bool = false
## Where the rail ends, relative to the hook's start.
@export var travel_offset: Vector3 = Vector3.ZERO
@export var travel_time: float = 4.0

var _game: GameManager
var _start: Vector3
var _t: float = 0.0
var _moving: bool = false

@onready var _point: Marker3D = $HookPoint
@onready var _rail: Node3D = get_node_or_null("Rail")

func _ready() -> void:
	add_to_group(&"resettables")
	_start = global_position
	body_entered.connect(func(b: Node3D) -> void: _reach(b, true))
	body_exited.connect(func(b: Node3D) -> void: _reach(b, false))
	if _rail:
		# A thin rail from start to end, drawn once in world space.
		_rail.top_level = true
		var length := travel_offset.length()
		_rail.visible = length > 0.01
		_rail.global_position = _start + _point.position + travel_offset * 0.5 + Vector3(0, 0.55, -0.1)
		_rail.rotation.z = atan2(travel_offset.y, travel_offset.x) - PI / 2.0 if length > 0.01 else 0.0
		_rail.scale = Vector3(1.0, maxf(length, 0.01), 1.0)

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.register_hook(self)
	_game.bus.lever_pulled.connect(func(id: StringName) -> void:
		if lever_id != &"" and id == lever_id and _t < 1.0:
			_moving = true)
	_game.bus.lantern_hook_changed.connect(func(id: StringName, hung: bool) -> void:
		if move_when_hung and hung and id == hook_id and _t < 1.0:
			_moving = true)

func _exit_tree() -> void:
	if _game:
		_game.unregister_hook(self)

## True while riding its rail — a lantern can't be taken off a moving hook.
func is_moving() -> bool:
	return _moving

func get_hook_point() -> Vector3:
	return _point.global_position

func _reach(body: Node3D, inside: bool) -> void:
	if _game and body.is_in_group(&"player"):
		_game.report_hook_reach(self, inside)

func _physics_process(delta: float) -> void:
	if not _moving:
		return
	_t = minf(_t + delta / maxf(travel_time, 0.01), 1.0)
	global_position = _start + travel_offset * smoothstep(0.0, 1.0, _t)
	if _t >= 1.0:
		_moving = false

func capture_checkpoint_state() -> Dictionary:
	return { "t": _t, "moving": _moving }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	_t = state.get("t", 0.0)
	_moving = state.get("moving", false)
	global_position = _start + travel_offset * smoothstep(0.0, 1.0, _t)
	reset_physics_interpolation()
