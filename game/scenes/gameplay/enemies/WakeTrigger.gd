@tool
class_name WakeTrigger
extends Area3D

## WakeTrigger — invisible box that wakes every enemy whose `wake_group` matches when the
## child walks in. Fires once; re-arms when the child respawns (enemies go dormant again).
##
## Sends: GameManager.report_wake_trigger(wake_group)
## Receives: GameBus.level_reset → re-arm; GameBus.lantern_placed → trigger if placed inside.

@export var wake_group: StringName = &"group_a"
## If true, wakes when the player enters this area.
@export var trigger_on_player: bool = true
## If true, wakes when the lantern is placed inside this area.
@export var trigger_on_lantern: bool = false
@export var size: Vector3 = Vector3(2.0, 4.0, 2.0):
	set(v):
		size = v
		if is_node_ready():
			_apply_size()

var _game: GameManager
var _fired: bool = false

@onready var _shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	add_to_group(&"wake_triggers")
	_apply_size()
	var mask := 0
	if trigger_on_player:
		mask |= 2
	if trigger_on_lantern:
		mask |= 8
	collision_mask = mask
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)

func inject_services(registry: Node) -> void:
	if not registry or Engine.is_editor_hint():
		return
	_game = registry.get_service(&"game") as GameManager
	if _game:
		_game.bus.lantern_placed.connect(_on_lantern_placed)

func capture_checkpoint_state() -> Dictionary:
	return { "fired": _fired }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	_fired = state.get("fired", false)

func _physics_process(_delta: float) -> void:
	if _fired or _game == null or Engine.is_editor_hint():
		return
	if has_overlapping_bodies():
		for body in get_overlapping_bodies():
			_check_body(body)
			if _fired:
				break

func _on_body_entered(body: Node3D) -> void:
	_check_body(body)

func _check_body(body: Node3D) -> void:
	if _fired or _game == null or not is_instance_valid(body):
		return
	var is_player := body.is_in_group(&"player")
	var is_lantern := body.is_in_group(&"lantern") or body is Lantern
	if (trigger_on_player and is_player) or (trigger_on_lantern and is_lantern):
		if is_lantern and _game.is_lantern_carried():
			return
		_fired = true
		_game.report_wake_trigger(wake_group)

func _on_lantern_placed(at: Vector3) -> void:
	if _fired or not trigger_on_lantern or _game == null:
		return
	var local_at := to_local(at)
	var half := size * 0.5
	var center := _shape.position if _shape else Vector3(0, size.y * 0.5, 0)
	var diff := local_at - center
	if absf(diff.x) <= half.x and absf(diff.y) <= half.y and absf(diff.z) <= half.z:
		_fired = true
		_game.report_wake_trigger(wake_group)

func _apply_size() -> void:
	if _shape and _shape.shape is BoxShape3D:
		(_shape.shape as BoxShape3D).size = size
