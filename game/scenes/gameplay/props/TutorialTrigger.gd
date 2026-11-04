@tool
class_name TutorialTrigger
extends Area3D

## TutorialTrigger — invisible box that asks for a one-time text hint when the player
## walks in. Only ids listed in TutorialManager.HINTS show anything (one line of text via
## GestureHint); other ids are ignored. A trigger the player spawns inside (e.g. the
## level-start hint) fires when play starts.
##
## With `on_wake_group` set it ignores the player and fires when that enemy group wakes
## (e.g. "Stay in the light" when the crawlers come out); its position doesn't matter then.
##
## Sends: GameManager.report_tutorial_trigger(hint_id)
## Receives: GameBus.enemies_wake_requested(group) when on_wake_group is set;
##   GameBus.game_state_changed (PLAYING → checks for a player already inside).

@export var hint_id: String = "move"
## Fire when this enemy group wakes instead of when the player walks in (empty = walk-in).
@export var on_wake_group: StringName = &""
## Only fire if the player does NOT currently carry the lantern.
@export var require_lantern_placed: bool = false
@export var size: Vector3 = Vector3(2.0, 3.0, 2.0):
	set(v):
		size = v
		if is_node_ready():
			_apply_size()

var _game: GameManager

@onready var _shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	_apply_size()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)

func inject_services(registry: Node) -> void:
	if not registry or Engine.is_editor_hint():
		return
	_game = registry.get_service(&"game") as GameManager
	if _game and on_wake_group != &"":
		_game.bus.enemies_wake_requested.connect(func(group: StringName) -> void:
			if group == on_wake_group:
				_game.report_tutorial_trigger(hint_id))
	elif _game:
		_game.bus.game_state_changed.connect(func(state: int) -> void:
			if state == GameManager.State.PLAYING:
				for b in get_overlapping_bodies():
					_on_body_entered(b))
		_game.bus.lantern_placed.connect(func(_at: Vector3) -> void:
			if require_lantern_placed or hint_id == "pickup":
				for b in get_overlapping_bodies():
					_on_body_entered(b))
		_game.bus.lantern_hook_changed.connect(func(_hook_id: StringName, hung: bool) -> void:
			if hung and (require_lantern_placed or hint_id == "pickup"):
				get_tree().create_timer(1.2).timeout.connect(func() -> void:
					if not is_instance_valid(self) or not _game:
						return
					for b in get_overlapping_bodies():
						_on_body_entered(b)))

func _on_body_entered(body: Node3D) -> void:
	if _game and on_wake_group == &"" and body.is_in_group(&"player"):
		if (require_lantern_placed or hint_id == "pickup") and _game.is_lantern_carried():
			return
		_game.report_tutorial_trigger(hint_id)

func _apply_size() -> void:
	(_shape.shape as BoxShape3D).size = size
