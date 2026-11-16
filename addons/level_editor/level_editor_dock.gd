@tool
class_name LevelEditorDock
extends VBoxContainer

## LevelEditorDock — Dock UI for level authoring, validation, catalog management and the object palette.
##
## Sends: level creation commands to LevelCreator; rebuild requests to LevelCatalogBuilder;
##        placement requests to LevelPalette (undoable via EditorUndoRedoManager).
## Receives: button clicks, world selection, checkbox toggles; forwarded 3D viewport input
##           from LevelEditorPlugin (handle_viewport_input); scene/filesystem change notices.

const LevelCatalogBuilder = preload("res://addons/level_editor/level_catalog_builder.gd")
const LevelCreator = preload("res://addons/level_editor/level_creator.gd")
const LevelPalette = preload("res://addons/level_editor/level_palette.gd")
const LevelFit = preload("res://addons/level_editor/level_fit.gd")
const LevelLinks = preload("res://addons/level_editor/level_links.gd")
const LevelOverlays = preload("res://addons/level_editor/level_overlays.gd")
const LevelValidator = preload("res://addons/level_editor/level_validator.gd")

@export_file("*.tres") var catalog_path: String = "res://game/resources/level_catalog.tres"
@export_dir var levels_dir_path: String = "res://game/scenes/gameplay/levels/"
@export_file("*.tscn") var template_path: String = "res://addons/level_editor/templates/LevelTemplate.tscn"
@export_file("*.csv") var strings_csv_path: String = "res://game/assets/localization/strings.csv"
@export var auto_rebuild_on_save: bool = true

@export_group("Palette")
## Folders scanned for placeable .tscn files (one palette group per folder).
@export var palette_folders: PackedStringArray = LevelPalette.DEFAULT_FOLDERS
## Scenes never shown (they live inside other scenes).
@export var palette_hidden_scenes: PackedStringArray = LevelPalette.DEFAULT_HIDDEN
## Scenes shown only while the open level does not contain one yet.
@export var palette_singletons: PackedStringArray = LevelPalette.DEFAULT_SINGLETONS
## Scene file name -> container node under the level root.
@export var palette_parent_rules: Dictionary = LevelPalette.DEFAULT_PARENT_RULES
## Scene base name -> node name prefix (e.g. "LanternHook": "Hook" gives Hook1, Hook2 …).
@export var palette_name_aliases: Dictionary = {}
## Snap step on the z = 0 plane, in metres.
@export var grid_size: float = 0.5
@export var snap_enabled: bool = true
## Thumbnail width in the palette list, in pixels.
@export var thumbnail_size: int = 48

@export_group("Fit level")
## Run Fit level automatically right before a level scene is saved.
@export var fit_on_save: bool = false
## kill_y = lowest floor − this (m).
@export var fit_kill_margin: float = 8.0
## The kill zone reaches this far past each end of the level (m).
@export var fit_end_margin: float = 20.0
## Never raise kill_y or shrink the kill zone (existing levels only ever grow).
@export var fit_grow_only: bool = true

@export_group("Overlays")
## Seconds between overlay redraws while any overlay is on.
@export var overlay_refresh_interval: float = 0.25
## How far below the take-off height the jump arcs are drawn (m).
@export var jump_drop_depth: float = 6.0

@export_group("Validate")
## Warn when an enemy / dark section is further than this past the last spawn or shrine (m).
@export var validate_max_checkpoint_gap: float = 30.0
## Warn when a gameplay node is further than this off the z = 0 plane (m).
@export var validate_plane_tolerance: float = 0.05

## Palette item armed or disarmed (the Level tab's view shows a placement cursor).
signal placing_changed
## An overlay toggle changed (the Level tab's view redraws).
signal overlays_changed

var undo_redo: EditorUndoRedoManager = null
var _suggested_level_num: int = 1
var _armed_path: String = ""
var _palette_refresh_queued: bool = false
var _singleton_signature: String = ""

@onready var _snap_check: CheckBox = %SnapCheck
@onready var _grid_spin: SpinBox = %GridSpin
@onready var _refresh_palette_btn: Button = %RefreshPaletteButton
@onready var _placing_label: Label = %PlacingLabel
@onready var _palette_tree: Tree = %PaletteTree

@onready var _fit_btn: Button = %FitButton
@onready var _fit_on_save_check: CheckBox = %FitOnSaveCheck
@onready var _grow_only_check: CheckBox = %GrowOnlyCheck
@onready var _kill_margin_spin: SpinBox = %KillMarginSpin
@onready var _end_margin_spin: SpinBox = %EndMarginSpin
@onready var _fit_result_label: Label = %FitResultLabel

@onready var _link_status_label: Label = %LinkStatusLabel
@onready var _link_candidate_option: OptionButton = %LinkCandidateOption
@onready var _link_id_option: OptionButton = %LinkIdOption
@onready var _link_btn: Button = %LinkButton
@onready var _unlink_btn: Button = %UnlinkButton

@onready var _show_links_check: CheckBox = %ShowLinksCheck
@onready var _show_light_check: CheckBox = %ShowLightCheck
@onready var _show_jump_check: CheckBox = %ShowJumpCheck
@onready var _show_paths_check: CheckBox = %ShowPathsCheck
@onready var _jump_reach_label: Label = %JumpReachLabel

@onready var _validate_btn: Button = %ValidateButton
@onready var _validate_all_btn: Button = %ValidateAllButton
@onready var _validate_summary_label: Label = %ValidateSummaryLabel
@onready var _validate_tree: Tree = %ValidateTree

var _link_nodes: Array[Node] = []
var _link_candidates: Array[Dictionary] = []
var _overlay_timer: Timer = null
var _overlay_root: Node = null

@onready var _rebuild_btn: Button = %RebuildButton
@onready var _auto_check: CheckBox = %AutoRebuildCheck
@onready var _status_label: Label = %StatusLabel
@onready var _warning_label: Label = %WarningLabel

@onready var _world_option: OptionButton = %WorldOption
@onready var _suggestion_label: Label = %SuggestionLabel
@onready var _new_level_btn: Button = %NewLevelButton
@onready var _creator_status_label: Label = %CreatorStatusLabel

func _ready() -> void:
	# Editor-only panel. If the scene is ever run as a game (e.g. F6 on this .tscn), EditorInterface
	# has no editor behind it, so do nothing instead of throwing errors.
	if not Engine.is_editor_hint():
		set_process(false)
		for c in get_children():
			c.hide()
		var note := Label.new()
		note.text = "The Level Editor panel only works inside the Godot editor."
		add_child(note)
		return
	if _rebuild_btn and not _rebuild_btn.pressed.is_connected(_on_rebuild_pressed):
		_rebuild_btn.pressed.connect(_on_rebuild_pressed)
	if _auto_check and not _auto_check.toggled.is_connected(_on_auto_check_toggled):
		_auto_check.button_pressed = auto_rebuild_on_save
		_auto_check.toggled.connect(_on_auto_check_toggled)

	_setup_world_options()
	if _world_option and not _world_option.item_selected.is_connected(_on_world_selected):
		_world_option.item_selected.connect(_on_world_selected)
	if _new_level_btn and not _new_level_btn.pressed.is_connected(_on_new_level_pressed):
		_new_level_btn.pressed.connect(_on_new_level_pressed)

	refresh_status()
	_update_next_free_suggestion()
	_setup_palette()
	_setup_tools()

func _setup_palette() -> void:
	if _snap_check:
		_snap_check.button_pressed = snap_enabled
		if not _snap_check.toggled.is_connected(_on_snap_toggled):
			_snap_check.toggled.connect(_on_snap_toggled)
	if _grid_spin:
		_grid_spin.value = grid_size
		if not _grid_spin.value_changed.is_connected(_on_grid_changed):
			_grid_spin.value_changed.connect(_on_grid_changed)
	if _refresh_palette_btn and not _refresh_palette_btn.pressed.is_connected(refresh_palette):
		_refresh_palette_btn.pressed.connect(refresh_palette)
	if _palette_tree and not _palette_tree.item_selected.is_connected(_on_palette_item_selected):
		_palette_tree.item_selected.connect(_on_palette_item_selected)
	refresh_palette()

func _on_snap_toggled(pressed: bool) -> void:
	snap_enabled = pressed

func _on_grid_changed(value: float) -> void:
	grid_size = value

func _setup_world_options() -> void:
	if not _world_option:
		return
	_world_option.clear()
	var catalog: LevelCatalog = load(catalog_path) as LevelCatalog
	var names: PackedStringArray = catalog.world_names if catalog else PackedStringArray(["Light", "Oil", "Shadows", "Mirrors"])
	for i in range(names.size()):
		var world_num := i + 1
		_world_option.add_item("World %d: %s" % [world_num, names[i]], world_num)

func _on_world_selected(_index: int) -> void:
	_update_next_free_suggestion()

func _on_rebuild_pressed() -> void:
	rebuild(true)

func _on_auto_check_toggled(pressed: bool) -> void:
	auto_rebuild_on_save = pressed

func _on_new_level_pressed() -> void:
	create_suggested_level()

## Returns the currently selected world in the world dropdown (1-based).
func get_selected_world() -> int:
	if not _world_option or _world_option.selected < 0:
		return 1
	return _world_option.get_item_id(_world_option.selected)

## Updates the suggestion label and button state for the next free level in the chosen world.
func _update_next_free_suggestion() -> void:
	if not _suggestion_label or not _new_level_btn:
		return
	var world := get_selected_world()
	var free_num := LevelCreator.get_next_free_level(world, levels_dir_path, catalog_path)
	if free_num > 0:
		_suggested_level_num = free_num
		_suggestion_label.text = "Next free slot: W%d_%02d" % [world, free_num]
		_new_level_btn.disabled = false
		_new_level_btn.text = "Create W%d_%02d" % [world, free_num]
	else:
		_suggested_level_num = -1
		_suggestion_label.text = "World %d is full (all slots taken)" % world
		_new_level_btn.disabled = true
		_new_level_btn.text = "World Full"

## Creates the suggested level from the template.
func create_suggested_level() -> Dictionary:
	var world := get_selected_world()
	if _suggested_level_num <= 0:
		var err_res := { "success": false, "error": "No free slot available in World %d" % world }
		_show_creator_error(err_res.error)
		return err_res

	var result := LevelCreator.create_level(
		world,
		_suggested_level_num,
		template_path,
		levels_dir_path,
		strings_csv_path,
		catalog_path,
		undo_redo
	)

	if result.success:
		if _creator_status_label:
			_creator_status_label.text = "Created %s successfully!" % result.path
			_creator_status_label.modulate = Color(0.4, 1.0, 0.4, 1.0)
		refresh_status()
		_update_next_free_suggestion()
	else:
		_show_creator_error(result.error)

	return result

func _show_creator_error(msg: String) -> void:
	if _creator_status_label:
		_creator_status_label.text = msg
		_creator_status_label.modulate = Color(1.0, 0.4, 0.4, 1.0)
	if _warning_label:
		_warning_label.visible = true
		_warning_label.text = "Error: %s" % msg

## Scans levels and rebuilds the catalog.
func rebuild(use_undo_redo: bool = true) -> Dictionary:
	var ur: EditorUndoRedoManager = undo_redo if use_undo_redo else null
	var result := LevelCatalogBuilder.rebuild_catalog(levels_dir_path, catalog_path, ur)
	_update_ui_from_result(result, true)
	_update_next_free_suggestion()
	return result

## Refreshes the display without modifying the catalog file.
func refresh_status() -> Dictionary:
	var result := LevelCatalogBuilder.scan_levels(levels_dir_path, catalog_path)
	_update_ui_from_result(result, false)
	return result

func _update_ui_from_result(result: Dictionary, just_rebuilt: bool) -> void:
	if not _status_label:
		return

	var text_lines: Array[String] = []
	if just_rebuilt:
		text_lines.append("Catalog rebuilt successfully.")
	else:
		if result.changed:
			text_lines.append("Catalog status: Changes detected (press Rebuild).")
		else:
			text_lines.append("Catalog status: Up to date.")

	var world_counts: Dictionary = result.get("world_counts", {})
	if world_counts.is_empty():
		text_lines.append("No levels found in world directories.")
	else:
		for w: int in world_counts.keys():
			text_lines.append("  • World %d: %d levels" % [w, world_counts[w]])
	text_lines.append("Total registered: %d levels (max slot: %d)" % [result.get("total_valid_levels", 0), result.get("max_slot", -1)])

	_status_label.text = "\n".join(text_lines)

	var warnings: Array[String] = result.get("warnings", [])
	var mismatches: Array[String] = result.get("mismatches", [])
	var all_issues: Array[String] = []
	all_issues.append_array(warnings)
	all_issues.append_array(mismatches)

	if _warning_label:
		if all_issues.is_empty():
			_warning_label.text = ""
			_warning_label.visible = false
		else:
			_warning_label.visible = true
			_warning_label.text = "Issues Detected:\n• " + "\n• ".join(all_issues)

# ── Object palette ───────────────────────────────────────────────────────

## Coalesces several change notices (filesystem, scene switch, undo history) into one refresh.
func queue_palette_refresh() -> void:
	if _palette_refresh_queued:
		return
	_palette_refresh_queued = true
	refresh_palette.call_deferred()

## Rebuilds the palette list from palette_folders, keeping the armed item if it still exists.
func refresh_palette() -> void:
	_palette_refresh_queued = false
	if not _palette_tree:
		return
	var scene_root := EditorInterface.get_edited_scene_root()
	_singleton_signature = _compute_singleton_signature(scene_root)
	var groups := LevelPalette.scan(palette_folders, palette_hidden_scenes, palette_singletons, scene_root)

	_palette_tree.clear()
	var root := _palette_tree.create_item()
	var fallback_icon: Texture2D = EditorInterface.get_editor_theme().get_icon(&"PackedScene", &"EditorIcons")
	var previewer := EditorInterface.get_resource_previewer()
	var still_armed := false

	for group: Dictionary in groups:
		var group_item := _palette_tree.create_item(root)
		group_item.set_text(0, str(group.group).capitalize())
		group_item.set_selectable(0, false)
		for entry: Dictionary in group.items:
			var item := _palette_tree.create_item(group_item)
			item.set_text(0, entry.name)
			item.set_tooltip_text(0, entry.path)
			item.set_metadata(0, entry.path)
			item.set_icon(0, fallback_icon)
			item.set_icon_max_width(0, thumbnail_size)
			previewer.queue_resource_preview(entry.path, self, &"_on_palette_preview_ready", item)
			if entry.path == _armed_path:
				item.select(0)
				still_armed = true

	if not _armed_path.is_empty() and not still_armed:
		cancel_placing()

func _on_palette_preview_ready(_path: String, preview: Texture2D, _thumbnail: Texture2D, item: Variant) -> void:
	if preview != null and is_instance_valid(item):
		(item as TreeItem).set_icon(0, preview)

func _on_palette_item_selected() -> void:
	var item := _palette_tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return
	_armed_path = str(item.get_metadata(0))
	_set_placing_text("Placing %s: click in the level view (or the 3D viewport). Esc or right-click to stop." % item.get_text(0))
	placing_changed.emit()

## Stops placement mode and clears the palette selection.
func cancel_placing() -> void:
	_armed_path = ""
	if _palette_tree:
		_palette_tree.deselect_all()
	_set_placing_text("Pick an object, then click in the level view (or the 3D viewport).")
	placing_changed.emit()

func is_placing() -> bool:
	return not _armed_path.is_empty()

## Called by LevelEditorPlugin._forward_3d_gui_input. Returns true when the event was consumed.
func handle_viewport_input(camera: Camera3D, event: InputEvent) -> bool:
	if _armed_path.is_empty():
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_placing()
		return true
	var mb := event as InputEventMouseButton
	if mb == null:
		return false
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			cancel_placing()
		return true
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return false
	if not mb.pressed:
		return true # swallow the release so the viewport doesn't box-select

	var hit: Variant = Plane(Vector3.BACK, 0.0).intersects_ray(
		camera.project_ray_origin(mb.position), camera.project_ray_normal(mb.position))
	if hit == null:
		_set_placing_text("The camera isn't looking at the z = 0 plane.")
		return true
	var node := place_armed_at(hit)
	if node:
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(node)
	return true

func get_armed_path() -> String:
	return _armed_path

## Arms a palette item by path (used by the Level tab's Objects grid); keeps the Palette tab in sync.
func arm_palette(path: String) -> void:
	_armed_path = path
	if _palette_tree:
		var root := _palette_tree.get_root()
		var found := false
		if root:
			for g in root.get_children():
				for it in g.get_children():
					if str(it.get_metadata(0)) == path:
						it.select(0)
						found = true
		if not found:
			_palette_tree.deselect_all()
	_set_placing_text("Placing %s: click in the level view. Esc or right-click to stop." % path.get_file().get_basename())
	placing_changed.emit()

## Places the armed palette item at a world point (snapped) in the open LEVEL.
## Used by the 3D viewport and by the Level tab's side view. Returns the new node or null.
func place_armed_at(world_point: Vector3) -> Node3D:
	if _armed_path.is_empty():
		return null
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null or scene_root.get("kill_y") == null:
		_set_placing_text("Open a level scene first (placing only works in levels).")
		return null
	var point := LevelPalette.snap_point(world_point, grid_size if snap_enabled else 0.0)
	var node := LevelPalette.place(_armed_path, point, scene_root, undo_redo, palette_parent_rules, palette_name_aliases)
	if node == null:
		_set_placing_text("Could not place %s (see Output)." % _armed_path.get_file())
		return null
	_set_placing_text("Placed %s under %s at (%.2f, %.2f). Click again, or Esc to stop." % [
		node.name, scene_root.get_path_to(node.get_parent()), point.x, point.y])
	# A singleton (Player, Lantern) disappears from the list once placed.
	if _armed_path in palette_singletons:
		cancel_placing()
	queue_palette_refresh()
	return node

## Overlay toggles, for the Level tab's side view.
func get_overlay_options() -> Dictionary:
	return _overlay_opts()

## Refreshes only when a singleton's presence changed (e.g. Player placed or undone).
func on_history_changed() -> void:
	if _compute_singleton_signature(EditorInterface.get_edited_scene_root()) != _singleton_signature:
		queue_palette_refresh()

func _compute_singleton_signature(scene_root: Node) -> String:
	if scene_root == null:
		return ""
	var parts: PackedStringArray = []
	for path: String in palette_singletons:
		parts.append("1" if LevelPalette.scene_contains_instance(scene_root, path) else "0")
	return "".join(parts)

func _set_placing_text(text: String) -> void:
	if _placing_label:
		_placing_label.text = text

# ── Tools tab: Fit level, Link helper, Overlays ──────────────────────────

func _setup_tools() -> void:
	_connect(_fit_btn, &"pressed", fit_level)
	if _fit_on_save_check:
		_fit_on_save_check.button_pressed = fit_on_save
		_connect(_fit_on_save_check, &"toggled", func(v: bool) -> void: fit_on_save = v)
	if _grow_only_check:
		_grow_only_check.button_pressed = fit_grow_only
		_connect(_grow_only_check, &"toggled", func(v: bool) -> void: fit_grow_only = v)
	if _kill_margin_spin:
		_kill_margin_spin.value = fit_kill_margin
		_connect(_kill_margin_spin, &"value_changed", func(v: float) -> void: fit_kill_margin = v)
	if _end_margin_spin:
		_end_margin_spin.value = fit_end_margin
		_connect(_end_margin_spin, &"value_changed", func(v: float) -> void: fit_end_margin = v)

	_connect(_link_btn, &"pressed", _on_link_pressed)
	_connect(_unlink_btn, &"pressed", _on_unlink_pressed)
	_connect(_link_candidate_option, &"item_selected", func(_i: int) -> void: _fill_link_ids())

	for cb: CheckBox in [_show_links_check, _show_light_check, _show_jump_check, _show_paths_check]:
		_connect(cb, &"toggled", func(_v: bool) -> void: _update_overlay_timer())
	_overlay_timer = Timer.new()
	_overlay_timer.wait_time = maxf(overlay_refresh_interval, 0.05)
	_overlay_timer.timeout.connect(redraw_overlays)
	add_child(_overlay_timer)

	_connect(_validate_btn, &"pressed", validate_open_level)
	_connect(_validate_all_btn, &"pressed", validate_all_levels)
	_connect(_validate_tree, &"item_selected", _on_validate_item_selected)

	on_selection_changed()
	_update_jump_label()

func _connect(obj: Object, sig: StringName, c: Callable) -> void:
	if obj and not obj.is_connected(sig, c):
		obj.connect(sig, c)

## Runs Fit level on the open scene (one undoable action) and shows what changed.
func fit_level() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var fit := LevelFit.compute(root, fit_end_margin, fit_kill_margin, fit_grow_only)
	LevelFit.apply(root, fit, undo_redo)
	if _fit_result_label:
		_fit_result_label.text = LevelFit.describe(fit)
	return fit

## Called by the plugin right before the editor saves (EditorPlugin._apply_changes).
func before_save() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if fit_on_save and root and root.get("kill_y") != null \
			and root.scene_file_path.begins_with(levels_dir_path):
		fit_level()

## Refreshes the link helper for the current selection (and the jump overlay target).
func on_selection_changed() -> void:
	if not _link_candidate_option:
		return
	_link_nodes.clear()
	for n in EditorInterface.get_selection().get_top_selected_nodes():
		_link_nodes.append(n)
	_link_candidate_option.clear()
	_link_id_option.clear()
	_link_candidates.clear()
	if _link_nodes.size() == 2:
		_link_candidates = LevelLinks.candidates(_link_nodes[0], _link_nodes[1])
		for c in _link_candidates:
			_link_candidate_option.add_item(c.label)
		if _link_candidates.is_empty():
			_link_status_label.text = "%s and %s have no ids that connect." % [_link_nodes[0].name, _link_nodes[1].name]
		else:
			_link_status_label.text = "Link %s ↔ %s:" % [_link_nodes[0].name, _link_nodes[1].name]
	elif _link_nodes.size() == 1 and not LevelLinks.fields_of(_link_nodes[0]).is_empty():
		var parts: Array[String] = []
		for f in LevelLinks.fields_of(_link_nodes[0]):
			parts.append("%s = '%s'" % [f.field, _link_nodes[0].get(f.field)])
		_link_status_label.text = "%s: %s. Select a second piece to link, or Unlink to clear all." % [_link_nodes[0].name, ", ".join(parts)]
	else:
		_link_status_label.text = "Select two puzzle pieces (Ctrl+click)."
	_fill_link_ids()
	_link_btn.disabled = _link_candidates.is_empty()
	_unlink_btn.disabled = _link_candidates.is_empty() and not (_link_nodes.size() == 1 and not LevelLinks.fields_of(_link_nodes[0]).is_empty())

func _fill_link_ids() -> void:
	_link_id_option.clear()
	var c := _current_candidate()
	if c.is_empty():
		return
	var root := EditorInterface.get_edited_scene_root()
	var fresh := LevelLinks.new_id(root, c.channel)
	_link_id_option.add_item("New id: %s" % fresh)
	_link_id_option.set_item_metadata(0, fresh)
	# Existing ids of this channel; an id one of the pair already has comes first.
	var existing: Array[String] = []
	for v in [str(_link_nodes[0].get(c.field_a)), str(_link_nodes[1].get(c.field_b))]:
		if not v.is_empty() and not existing.has(v):
			existing.append(v)
	var ids: Array = LevelLinks.ids_by_channel(root).get(c.channel, {}).keys()
	ids.sort()
	for id in ids:
		if not existing.has(str(id)):
			existing.append(str(id))
	for id in existing:
		_link_id_option.add_item("Use: %s" % id)
		_link_id_option.set_item_metadata(_link_id_option.item_count - 1, id)
	# Prefer re-using an id the pair already carries (e.g. a new gate on an existing hook).
	if not existing.is_empty() and (str(_link_nodes[0].get(c.field_a)) == existing[0] or str(_link_nodes[1].get(c.field_b)) == existing[0]):
		_link_id_option.select(1)

func _current_candidate() -> Dictionary:
	if _link_candidates.is_empty() or _link_candidate_option.selected < 0:
		return {}
	return _link_candidates[_link_candidate_option.selected]

func _on_link_pressed() -> void:
	var c := _current_candidate()
	if c.is_empty() or _link_id_option.selected < 0:
		return
	var id := str(_link_id_option.get_item_metadata(_link_id_option.selected))
	LevelLinks.link(_link_nodes[0], _link_nodes[1], c, id, undo_redo)
	_link_status_label.text = "Linked %s.%s and %s.%s = '%s'." % [_link_nodes[0].name, c.field_a, _link_nodes[1].name, c.field_b, id]
	_fill_link_ids()

func _on_unlink_pressed() -> void:
	var c := _current_candidate()
	if not c.is_empty():
		LevelLinks.unlink(_link_nodes[0], _link_nodes[1], c, undo_redo)
		_link_status_label.text = "Cleared %s.%s and %s.%s." % [_link_nodes[0].name, c.field_a, _link_nodes[1].name, c.field_b]
	elif _link_nodes.size() == 1:
		LevelLinks.unlink_all(_link_nodes[0], undo_redo)
		_link_status_label.text = "Cleared every link id on %s." % _link_nodes[0].name
	_fill_link_ids()

func _overlay_opts() -> Dictionary:
	return {
		"links": _show_links_check != null and _show_links_check.button_pressed,
		"light": _show_light_check != null and _show_light_check.button_pressed,
		"jump": _show_jump_check != null and _show_jump_check.button_pressed,
		"paths": _show_paths_check != null and _show_paths_check.button_pressed,
		"jump_drop": jump_drop_depth,
	}

func _any_overlay_on() -> bool:
	var o := _overlay_opts()
	return o.links or o.light or o.jump or o.paths

func _update_overlay_timer() -> void:
	if not _overlay_timer:
		return
	if _any_overlay_on():
		if _overlay_timer.is_stopped():
			_overlay_timer.start()
		redraw_overlays()
	else:
		_overlay_timer.stop()
		_clear_overlay()
	overlays_changed.emit()

## Rebuilds the overlay drawing for the open level (called on a short timer while on).
func redraw_overlays() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root != _overlay_root:
		_clear_overlay()
		_overlay_root = root
	if root == null or not _any_overlay_on():
		return
	var selected: Array = EditorInterface.get_selection().get_top_selected_nodes()
	LevelOverlays.render(root, LevelOverlays.build(root, _overlay_opts(), selected))
	_update_jump_label()

func _clear_overlay() -> void:
	if is_instance_valid(_overlay_root):
		LevelOverlays.clear(_overlay_root)
	_overlay_root = null

func _update_jump_label() -> void:
	if not _jump_reach_label:
		return
	var p := LevelOverlays.jump_params(EditorInterface.get_edited_scene_root())
	var r := LevelOverlays.jump_reach(p)
	_jump_reach_label.text = "Jump (from Player exports): %.2f m up, %.2f m across (+%.2f m coyote)." % [
		r.height, r.distance, p.run_speed * p.coyote_time]

func on_scene_changed() -> void:
	cancel_placing()
	queue_palette_refresh()
	_clear_overlay()
	on_selection_changed()
	if _any_overlay_on():
		redraw_overlays.call_deferred()

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		_clear_overlay()

# ── Validate tab ─────────────────────────────────────────────────────────

func _validate_opts() -> Dictionary:
	return { "max_checkpoint_gap": validate_max_checkpoint_gap, "plane_tolerance": validate_plane_tolerance }

## Checks the open level (read-only) and lists the issues.
func validate_open_level() -> Array[Dictionary]:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_validate_summary_label.text = "Open a level scene first."
		return []
	var issues := LevelValidator.validate(root, root.scene_file_path, _validate_opts())
	_show_issues({ root.scene_file_path: issues })
	return issues

## Checks every level in the catalog (read-only) and lists the issues per level.
func validate_all_levels() -> Dictionary:
	var results := LevelValidator.validate_all(catalog_path, _validate_opts())
	_show_issues(results)
	return results

func _show_issues(results: Dictionary) -> void:
	_validate_tree.clear()
	var tree_root := _validate_tree.create_item()
	var errors := 0
	var warnings := 0
	var theme := EditorInterface.get_editor_theme()
	for path: String in results.keys():
		var issues: Array = results[path]
		var level_item := _validate_tree.create_item(tree_root)
		level_item.set_text(0, "%s — %s" % [path.get_file(), "OK" if issues.is_empty() else "%d issue(s)" % issues.size()])
		level_item.set_metadata(0, { "scene_path": path, "node_path": "" })
		for i: Dictionary in issues:
			var item := _validate_tree.create_item(level_item)
			var is_err: bool = i.severity == LevelValidator.ERROR
			item.set_text(0, "%s%s" % [i.message, "" if i.node_path.is_empty() else "  (%s)" % i.node_path])
			item.set_icon(0, theme.get_icon(&"StatusError" if is_err else &"StatusWarning", &"EditorIcons"))
			item.set_custom_color(0, Color(1, 0.45, 0.45) if is_err else Color(1, 0.8, 0.35))
			item.set_tooltip_text(0, "%s\n%s" % [path, i.message])
			item.set_metadata(0, i)
			if is_err:
				errors += 1
			else:
				warnings += 1
	_validate_summary_label.text = "%d level(s): %d error(s), %d warning(s). Click a line to select its node." % [results.size(), errors, warnings]

func _on_validate_item_selected() -> void:
	var item := _validate_tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != meta.scene_path:
		EditorInterface.open_scene_from_path(meta.scene_path)
		_select_issue_node.call_deferred(meta.node_path)
	else:
		_select_issue_node(meta.node_path)

func _select_issue_node(node_path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var node := root if node_path.is_empty() else root.get_node_or_null(NodePath(node_path))
	if node:
		var sel := EditorInterface.get_selection()
		sel.clear()
		sel.add_node(node)
		EditorInterface.edit_node(node)
