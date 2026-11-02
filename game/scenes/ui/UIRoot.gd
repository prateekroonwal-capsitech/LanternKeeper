class_name UIRoot
extends CanvasLayer

## UIRoot — the one persistent UI layer. Every screen (HUD, touch controls, fades,
## and the Phase 4 menus) is placed here in the editor; nothing is instanced at runtime.
## Lives under GameService in Boot.tscn, so it survives level changes.
##
## Sends: nothing. Receives: nothing — UIManager.register_root(self) wires it up.

@onready var hud: Control = $HUD
@onready var touch_controls: Control = $TouchControls
@onready var screen_fade: ScreenFade = $ScreenFade

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Every screen UIManager can show / hide, keyed by node name.
func get_screens() -> Array[Control]:
	var screens: Array[Control] = []
	for child in get_children():
		if child is Control:
			screens.append(child)
	return screens

func get_screen(screen_name: StringName) -> Control:
	return get_node_or_null(NodePath(screen_name)) as Control
