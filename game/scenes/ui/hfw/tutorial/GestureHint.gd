class_name GestureHint
extends UIController

## GestureHint — the only tutorial: a wordless, one-time hint for the controls in the
## first levels. Touch (gestures layout): a ghost hand shows the gesture on screen.
## Keyboard / controller: a key icon. Classic touch buttons need no hint.
## Hint ids: "move", "jump", "place", "raise" (TutorialTrigger.hint_id). Any other id is ignored.
## TutorialManager decides "once only" and saves the seen flag.
##
## Sends: nothing.
## Receives: GameBus.tutorial_hint_requested(hint_id); GameBus.game_state_changed (hides).

@export var display_time: float = 3.6
@export var fade_time: float = 0.35
@export var hand_alpha: float = 0.55
## Key icons, one per hint id (PC / controller).
@export var key_icons: Dictionary = {}

@onready var _hand: TextureRect = %Hand
@onready var _key: TextureRect = %KeyIcon

var _tween: Tween

const _HINTS := ["move", "jump", "place", "raise"]

func _on_ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	_game_manager.bus.tutorial_hint_requested.connect(_show_hint)
	_game_manager.bus.game_state_changed.connect(func(state: int) -> void:
		if state != GameManager.State.PLAYING:
			_stop())

func _show_hint(hint_id: String) -> void:
	if not _HINTS.has(hint_id):
		return
	var touch := DisplayServer.is_touchscreen_available()
	if touch and _game_manager.input.control_layout == InputManager.LAYOUT_CLASSIC:
		return
	_stop()
	show()
	if touch:
		_play_hand(hint_id)
	else:
		_play_key(hint_id)

func _play_key(hint_id: String) -> void:
	var tex: Texture2D = key_icons.get(hint_id)
	if tex == null:
		hide()
		return
	_key.texture = tex
	_key.show()
	_hand.hide()
	_key.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_key, "modulate:a", 0.85, fade_time)
	_tween.tween_interval(display_time)
	_tween.tween_property(_key, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(hide)

func _play_hand(hint_id: String) -> void:
	_key.hide()
	_hand.show()
	var view := get_viewport_rect().size
	var left := Vector2(view.x * 0.22, view.y * 0.68)
	var right := Vector2(view.x * 0.75, view.y * 0.62)
	var half := _hand.size * 0.5
	_hand.modulate.a = 0.0
	_hand.scale = Vector2.ONE
	_hand.pivot_offset = half
	_tween = create_tween()
	match hint_id:
		"move":
			_hand.position = left - half
			_tween.tween_property(_hand, "modulate:a", hand_alpha, fade_time)
			for i in 2:
				_tween.tween_property(_hand, "position:x", left.x - half.x + 140.0, 0.5).set_trans(Tween.TRANS_SINE)
				_tween.tween_property(_hand, "position:x", left.x - half.x - 140.0, 0.8).set_trans(Tween.TRANS_SINE)
			_tween.tween_property(_hand, "position:x", left.x - half.x, 0.4)
		"jump":
			_hand.position = right - half
			_tween.tween_property(_hand, "modulate:a", hand_alpha, fade_time)
			for i in 3:
				_tween.tween_property(_hand, "scale", Vector2(0.82, 0.82), 0.12)
				_tween.tween_property(_hand, "scale", Vector2.ONE, 0.25)
				_tween.tween_interval(0.35)
		"place":
			_hand.position = right - half - Vector2(0.0, 90.0)
			_tween.tween_property(_hand, "modulate:a", hand_alpha, fade_time)
			for i in 2:
				_tween.tween_property(_hand, "position:y", right.y - half.y + 110.0, 0.35).set_ease(Tween.EASE_IN)
				_tween.tween_interval(0.3)
				_tween.tween_property(_hand, "position:y", right.y - half.y - 90.0, 0.01)
				_tween.tween_interval(0.3)
		"raise":
			_hand.position = right - half
			_tween.tween_property(_hand, "modulate:a", hand_alpha, fade_time)
			for i in 2:
				_tween.tween_property(_hand, "scale", Vector2(0.82, 0.82), 0.15)
				_tween.tween_interval(0.9)
				_tween.tween_property(_hand, "scale", Vector2.ONE, 0.2)
				_tween.tween_interval(0.3)
	_tween.tween_property(_hand, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(hide)

func _stop() -> void:
	if _tween:
		_tween.kill()
	hide()
