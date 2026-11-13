@tool
class_name LevelEditorPlugin
extends EditorPlugin

## LevelEditorPlugin — Main EditorPlugin registering dock panels, menu commands, and scene save hooks.
##
## Sends: rebuild commands to LevelCatalogBuilder on scene_saved and menu selection.
## Receives: EditorPlugin.scene_saved signals from Godot editor.

const LevelCatalogBuilder = preload("res://addons/level_editor/level_catalog_builder.gd")
const LevelEditorDockScript = preload("res://addons/level_editor/level_editor_dock.gd")

var dock: Control = null

func _enter_tree() -> void:
	var dock_scene: PackedScene = load("res://addons/level_editor/level_editor_dock.tscn") as PackedScene
	if dock_scene:
		dock = dock_scene.instantiate() as LevelEditorDock
		if dock:
			dock.undo_redo = get_undo_redo()
			add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

	add_tool_menu_item("Rebuild Level Catalog", Callable(self, "_on_rebuild_catalog_menu"))
	if not scene_saved.is_connected(_on_scene_saved):
		scene_saved.connect(_on_scene_saved)

func _exit_tree() -> void:
	remove_tool_menu_item("Rebuild Level Catalog")

	if scene_saved.is_connected(_on_scene_saved):
		scene_saved.disconnect(_on_scene_saved)

	if dock:
		remove_control_from_docks(dock)
		dock.free()
		dock = null

func _on_scene_saved(filepath: String) -> void:
	if dock and not dock.auto_rebuild_on_save:
		return

	# Rebuild whenever any scene inside the levels directory is saved
	if filepath.begins_with("res://game/scenes/gameplay/levels/"):
		LevelCatalogBuilder.rebuild_catalog()
		if dock:
			dock.refresh_status()

func _on_rebuild_catalog_menu() -> void:
	if dock:
		dock.rebuild(true)
	else:
		LevelCatalogBuilder.rebuild_catalog(
			LevelCatalogBuilder.DEFAULT_LEVELS_DIR,
			LevelCatalogBuilder.DEFAULT_CATALOG_PATH,
			get_undo_redo()
		)
