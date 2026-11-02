class_name TutorialPopup
extends UIController

## TutorialPopup — a short hint banner at the top of the screen. Text comes from the
## translation table: "HINT_<ID>_KEYS" / "_TOUCH" / "_CLASSIC" for control-specific
## hints, falling back to "HINT_<ID>". Shown once per hint (TutorialManager decides).
##
## Sends: nothing.
## Receives: GameBus.tutorial_hint_requested(hint_id); GameBus.game_state_changed (hides
##   outside levels).

## Seconds a hint stays on screen.
@export var display_time: float = 5.0
@export var fade_time: float = 0.35

@onready var _panel: Control = %HintPanel
@onready var _label: Label = %HintText

var _tween: Tween

func _on_ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	hide()
	_game_manager.bus.tutorial_hint_requested.connect(_show_hint)
	_game_manager.bus.game_state_changed.connect(func(state: int) -> void:
		if state == GameManager.State.MENU:
			_hide_now())

func _show_hint(hint_id: String) -> void:
	_label.text = _resolve_text(hint_id)
	show()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, fade_time)
	_tween.tween_interval(display_time)
	_tween.tween_property(_panel, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(hide)

func _resolve_text(hint_id: String) -> String:
	var base := "HINT_" + hint_id.to_upper()
	var suffix := "_KEYS"
	if DisplayServer.is_touchscreen_available():
		var classic := _game_manager.input.control_layout == InputManager.LAYOUT_CLASSIC
		suffix = "_CLASSIC" if classic else "_TOUCH"
	var specific := base + suffix
	if tr(specific) != specific:
		return tr(specific)
	return tr(base)

func _hide_now() -> void:
	if _tween:
		_tween.kill()
	_panel.modulate.a = 0.0
	hide()
