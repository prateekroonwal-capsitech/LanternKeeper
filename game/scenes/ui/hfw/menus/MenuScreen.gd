class_name MenuScreen
extends UIController

## MenuScreen — base for every menu placed in UIRoot. When the menu becomes visible
## it refreshes itself and focuses its first button, so keyboard / controller work.
## Menus are opened and closed by UIManager.open_menu() / close_menu().
##
## Sends / receives: see each menu. All game actions go through GameManager.

## Control that receives focus when the menu opens (usually the first button).
@export var focus_on_show: Control

func _on_ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_menu_ready()

func _on_visibility_changed() -> void:
	if not visible:
		return
	_on_shown()
	if focus_on_show and focus_on_show.is_visible_in_tree():
		focus_on_show.grab_focus.call_deferred()

## Override: connect buttons (called once, services are injected).
func _on_menu_ready() -> void:
	pass

## Override: refresh contents each time the menu opens.
func _on_shown() -> void:
	pass
