@tool
class_name LevelEditorPlugin
extends EditorPlugin

## LevelEditorPlugin — Main EditorPlugin registering dock panels, menu commands, and scene save hooks.
##
## Sends: rebuild commands to LevelCatalogBuilder on scene_saved and menu selection;
##        3D viewport input to LevelEditorDock.handle_viewport_input (object palette placement);
##        palette refresh requests on scene switch, filesystem change and undo history change;
##        selection changes (link helper, jump overlay) and before-save (fit on save) to the dock.
## Receives: EditorPlugin.scene_saved / scene_changed / _apply_changes, EditorFileSystem.filesystem_changed,
##           EditorUndoRedoManager.history_changed, EditorSelection.selection_changed,
##           and forwarded 3D viewport input.

const LevelCatalogBuilder = preload("res://addons/level_editor/level_catalog_builder.gd")
const LevelEditorDockScript = preload("res://addons/level_editor/level_editor_dock.gd")
const LevelWorkspaceScript = preload("res://addons/level_editor/level_workspace.gd")

## Name of the main-screen tab (next to 2D / 3D / Script / Game / Asset Store).
const MAIN_SCREEN_NAME := "Level"

var dock: Control = null
## The "Level" tab: toolbar + side view of the level + the panel.
var workspace: LevelWorkspace = null

func _enter_tree() -> void:
	var dock_scene: PackedScene = load("res://addons/level_editor/level_editor_dock.tscn") as PackedScene
	if dock_scene:
		dock = dock_scene.instantiate() as LevelEditorDock
		if is_instance_valid(dock):
			dock.undo_redo = get_undo_redo()
			add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

	workspace = LevelWorkspaceScript.new()
	workspace.dock = dock
	workspace.undo_redo = get_undo_redo()
	workspace.hide()
	EditorInterface.get_editor_main_screen().add_child(workspace)

	add_tool_menu_item("Rebuild Level Catalog", Callable(self, "_on_rebuild_catalog_menu"))
	if not scene_saved.is_connected(_on_scene_saved):
		scene_saved.connect(_on_scene_saved)
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)

	var efs := EditorInterface.get_resource_filesystem()
	if efs and not efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.connect(_on_filesystem_changed)
	var ur := get_undo_redo()
	if ur and not ur.history_changed.is_connected(_on_history_changed):
		ur.history_changed.connect(_on_history_changed)
	var sel := EditorInterface.get_selection()
	if sel and not sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.connect(_on_selection_changed)

	# Palette placement needs viewport clicks even when no node is selected.
	set_input_event_forwarding_always_enabled()

func _exit_tree() -> void:
	remove_tool_menu_item("Rebuild Level Catalog")

	if scene_saved.is_connected(_on_scene_saved):
		scene_saved.disconnect(_on_scene_saved)
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	var efs := EditorInterface.get_resource_filesystem()
	if efs and efs.filesystem_changed.is_connected(_on_filesystem_changed):
		efs.filesystem_changed.disconnect(_on_filesystem_changed)
	var ur := get_undo_redo()
	if ur and ur.history_changed.is_connected(_on_history_changed):
		ur.history_changed.disconnect(_on_history_changed)
	var sel := EditorInterface.get_selection()
	if sel and sel.selection_changed.is_connected(_on_selection_changed):
		sel.selection_changed.disconnect(_on_selection_changed)

	if is_instance_valid(workspace):
		workspace.queue_free()
	workspace = null
	if is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()
	dock = null

# ── "Level" main-screen tab ──────────────────────────────────────────────
# Toolbar + side view of the open level. The Level Editor panel stays in the right dock.

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return MAIN_SCREEN_NAME

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"GridMap", &"EditorIcons")

## The panel never moves: editor docks stay visible next to every main tab, so it sits on the
## right of the Level view too. Only the workspace is shown / hidden here.
func _make_visible(visible: bool) -> void:
	if not is_instance_valid(workspace):
		return
	workspace.visible = visible
	if visible:
		workspace.refresh(true)
		workspace.on_selection_changed()

func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if is_instance_valid(dock) and dock.is_placing() and dock.handle_viewport_input(viewport_camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _on_scene_saved(filepath: String) -> void:
	if is_instance_valid(dock) and not dock.auto_rebuild_on_save:
		return

	# Rebuild whenever any scene inside the levels directory is saved
	if filepath.begins_with("res://game/scenes/gameplay/levels/"):
		LevelCatalogBuilder.rebuild_catalog()
		if is_instance_valid(dock):
			dock.refresh_status()

func _on_scene_changed(_scene_root: Node) -> void:
	if is_instance_valid(dock):
		dock.on_scene_changed()
	if is_instance_valid(workspace):
		workspace.refresh(true)

func _on_selection_changed() -> void:
	if is_instance_valid(dock):
		dock.on_selection_changed()
	if is_instance_valid(workspace) and workspace.visible:
		workspace.on_selection_changed()

## Called by the editor right before saving (and before running the project).
func _apply_changes() -> void:
	if is_instance_valid(dock):
		dock.before_save()

func _on_filesystem_changed() -> void:
	if is_instance_valid(dock):
		dock.queue_palette_refresh()
	if is_instance_valid(workspace):
		workspace.on_filesystem_changed()

func _on_history_changed() -> void:
	if is_instance_valid(dock):
		dock.on_history_changed()
		dock.on_selection_changed() # link ids may have changed
	if is_instance_valid(workspace) and workspace.visible:
		workspace.refresh(false)

func _on_rebuild_catalog_menu() -> void:
	if is_instance_valid(dock):
		dock.rebuild(true)
	else:
		LevelCatalogBuilder.rebuild_catalog(
			LevelCatalogBuilder.DEFAULT_LEVELS_DIR,
			LevelCatalogBuilder.DEFAULT_CATALOG_PATH,
			get_undo_redo()
		)
