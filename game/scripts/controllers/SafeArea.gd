class_name SafeArea
extends MarginContainer

## SafeArea — keeps its children out of notches and rounded corners on phones.
## Put HUD / buttons inside it. On desktop only `base_margin` applies.
##
## Sends: nothing. Receives: viewport size changes (re-applies margins).

## Margin (in base-resolution pixels) on every side, on top of the device safe area.
@export var base_margin: int = 24

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(_apply)
	_apply()

func _apply() -> void:
	var left := 0.0
	var top := 0.0
	var right := 0.0
	var bottom := 0.0
	if PlatformUtils.is_mobile():
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var window := Vector2(DisplayServer.window_get_size())
		var view := get_viewport().get_visible_rect().size
		if window.x > 0.0 and window.y > 0.0:
			var s := view / window
			left = safe.position.x * s.x
			top = safe.position.y * s.y
			right = (window.x - safe.end.x) * s.x
			bottom = (window.y - safe.end.y) * s.y
	add_theme_constant_override(&"margin_left", base_margin + int(maxf(left, 0.0)))
	add_theme_constant_override(&"margin_top", base_margin + int(maxf(top, 0.0)))
	add_theme_constant_override(&"margin_right", base_margin + int(maxf(right, 0.0)))
	add_theme_constant_override(&"margin_bottom", base_margin + int(maxf(bottom, 0.0)))
