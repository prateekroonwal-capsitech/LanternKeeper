class_name GestureHint
extends UIController

## GestureHint — the only tutorial: one short line of light text at the bottom of the
## screen, shown once when something new is introduced. It fades in, stays `display_time`
## seconds or until the player does the hint's action (after `min_time`), then fades out.
## Wording differs for touch gestures (Android default), the classic touch-button layout
## and keyboard / controller; TutorialManager.HINTS holds the data and decides "once only"
## (it saves the seen flag). No popups, no boxes.
##
## Sends: nothing.
## Receives: GameBus.tutorial_hint_requested(hint_id); GameBus.lantern_placed (dismisses the
##   "place" hint); GameBus.game_state_changed (hides). Polls GameManager.input.move_axis.

@export var display_time: float = 3.0
## Seconds the line stays at least, even if the action is done straight away.
@export var min_time: float = 0.8
@export var fade_time: float = 0.4
@export var text_alpha: float = 0.8

@onready var _label: Label = %HintText

var _tween: Tween
var _hint_id: String = ""
var _shown_for: float = 0.0
var _dismissed: bool = false

func _on_ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	set_process(false)
	_game_manager.bus.tutorial_hint_requested.connect(_show_hint)
	_game_manager.bus.lantern_placed.connect(func(_at: Vector3) -> void:
		if _game_manager.tutorial.get_hint_action(_hint_id) == "place_lantern":
			_dismissed = true)
	_game_manager.bus.game_state_changed.connect(func(state: int) -> void:
		if state != GameManager.State.PLAYING:
			_stop())

func _show_hint(hint_id: String) -> void:
	var device := "pc"
	if DisplayServer.is_touchscreen_available():
		device = "classic" if _game_manager.input.control_layout == InputManager.LAYOUT_CLASSIC else "touch"
	var key := _game_manager.tutorial.get_hint_key(hint_id, device)
	if key == "":
		return
	_stop()
	_hint_id = hint_id
	_shown_for = 0.0
	_dismissed = false
	_label.text = tr(key)
	_label.modulate.a = 0.0
	show()
	set_process(true)
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", text_alpha, fade_time)

func _process(delta: float) -> void:
	_shown_for += delta
	if _game_manager.tutorial.get_hint_action(_hint_id) == "move" and absf(_game_manager.input.move_axis) > 0.1:
		_dismissed = true
	if _shown_for >= fade_time + display_time or (_dismissed and _shown_for >= min_time):
		_fade_out()

func _fade_out() -> void:
	set_process(false)
	_hint_id = ""
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_label, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(hide)

func _stop() -> void:
	set_process(false)
	_hint_id = ""
	if _tween:
		_tween.kill()
	hide()
