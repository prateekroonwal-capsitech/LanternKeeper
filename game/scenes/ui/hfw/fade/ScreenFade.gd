class_name ScreenFade
extends ColorRect

## ScreenFade — full-screen black overlay for the death fade and every scene
## transition. Starts covered, so the game opens with a fade-in. Blocks touches only
## while it is covering the screen.
##
## Sends: nothing. Receives: UIManager.fade_out() / fade_in().

@export var fade_out_time: float = 0.25
@export var fade_in_time: float = 0.35
@export var fade_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## Start fully black (the first scene fades in).
@export var start_covered: bool = true

var _tween: Tween

func _ready() -> void:
	color = Color(fade_color, 1.0 if start_covered else 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP if start_covered else Control.MOUSE_FILTER_IGNORE
	visible = start_covered

func fade_out() -> void:
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	await _fade_to(1.0, fade_out_time)

func fade_in() -> void:
	await _fade_to(0.0, fade_in_time)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func _fade_to(alpha: float, duration: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "color", Color(fade_color, alpha), maxf(duration, 0.01))
	await _tween.finished
