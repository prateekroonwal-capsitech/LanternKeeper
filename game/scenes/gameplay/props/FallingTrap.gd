class_name FallingTrap
extends Node3D

## FallingTrap — something heavy held up until a lever / plate releases it: a rock on a rope
## (RockTrap.tscn) or a cracked ceiling slab (CeilingCollapse.tscn). When `lever_id` fires it
## drops `drop_height` metres in `fall_time`; anything under it is hit. The child is crushed;
## creatures ask is_in_kill_zone() when they hear trap_sprung. If `rearm_time` > 0 and nothing
## was caught, it is hauled back up and `rearm_lever` is reset so it can be tried again.
## Resets with the checkpoint.
##
## Sends: GameManager.report_trap_sprung(self), report_player_died("crushed"),
##   report_camera_focus(landing point, fall + `focus_hold`) so the hit is seen on screen.
## Receives: GameBus.lever_pulled(lever_id); checkpoint snapshot (group "resettables").

@export var lever_id: StringName = &"trap_a"
@export var drop_height: float = 5.0
@export var fall_time: float = 0.4
## Kill box under the resting place, centred on the trap's x (half width, height).
@export var kill_half_width: float = 1.0
@export var kill_height: float = 2.2
## > 0: haul back up this many seconds after landing if nothing was caught (0 = stays down).
@export var rearm_time: float = 0.0
@export var rearm_lever: Lever
## Seconds the camera keeps the landing spot in view after the fall (0 = no camera focus).
@export var focus_hold: float = 2.6

enum State { HELD, FALLING, DOWN, RISING }

var _game: GameManager
var _state: State = State.HELD
var _t: float = 0.0
var _caught: bool = false
var _rest_y: float = 0.0

@onready var _block: AnimatableBody3D = $Block
@onready var _rope: Node3D = get_node_or_null("Rope")

func _ready() -> void:
	add_to_group(&"resettables")
	_rest_y = _block.position.y

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager
		if _game:
			_game.bus.lever_pulled.connect(_on_lever_pulled)

## The landing spot (world): ground level under the trap.
func get_ground_point() -> Vector3:
	return global_position + Vector3(0.0, _rest_y - drop_height, 0.0)

## True if `point` is under the falling block (the kill box at the bottom of its drop).
func is_in_kill_zone(point: Vector3) -> bool:
	var g := get_ground_point()
	return absf(point.x - g.x) <= kill_half_width and point.y >= g.y - 0.3 and point.y <= g.y + kill_height

## A creature tells the trap it was caught (so it doesn't re-arm).
func mark_caught() -> void:
	_caught = true

func _on_lever_pulled(id: StringName) -> void:
	if id != lever_id or _state != State.HELD:
		return
	_state = State.FALLING
	_t = 0.0
	_caught = false
	print("[FallingTrap] %s released" % name)
	if _game and focus_hold > 0.0:
		_game.report_camera_focus(get_ground_point() + Vector3(0.0, 1.2, 0.0), fall_time + focus_hold)

func _physics_process(delta: float) -> void:
	match _state:
		State.FALLING:
			_t += delta
			var u := clampf(_t / maxf(fall_time, 0.01), 0.0, 1.0)
			_block.position.y = _rest_y - drop_height * u * u
			if _rope:
				_rope.visible = false
			if _game and _game.is_playing() and _game.has_player():
				var p := _game.get_player_position()
				var bottom := _block.global_position.y - 0.6
				if absf(p.x - _block.global_position.x) <= kill_half_width * 0.8 and p.y < bottom and p.y > bottom - 1.6:
					_game.report_player_died("crushed")
			if u >= 1.0:
				_state = State.DOWN
				_t = 0.0
				print("[FallingTrap] %s landed" % name)
				if _game:
					_game.report_trap_sprung(self)
		State.DOWN:
			_t += delta
			if rearm_time > 0.0 and not _caught and _t >= rearm_time:
				_state = State.RISING
				_t = 0.0
		State.RISING:
			_t += delta
			var u := clampf(_t / 1.2, 0.0, 1.0)
			_block.position.y = _rest_y - drop_height * (1.0 - u)
			if u >= 1.0:
				_state = State.HELD
				if _rope:
					_rope.visible = true
				if is_instance_valid(rearm_lever):
					rearm_lever.reset_to_checkpoint({})
				print("[FallingTrap] %s hauled back up (missed)" % name)

func capture_checkpoint_state() -> Dictionary:
	return { "state": _state, "caught": _caught }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	_state = State.DOWN if state.get("state", State.HELD) == State.DOWN else State.HELD
	_caught = state.get("caught", false)
	_t = 0.0
	_block.position.y = _rest_y - (drop_height if _state == State.DOWN else 0.0)
	if _rope:
		_rope.visible = _state == State.HELD
	reset_physics_interpolation()
