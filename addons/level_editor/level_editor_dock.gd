@tool
class_name LevelEditorDock
extends VBoxContainer

## LevelEditorDock — Dock UI for level authoring, validation, and catalog management.
##
## Sends: level creation commands to LevelCreator; rebuild requests to LevelCatalogBuilder.
## Receives: button clicks, world selection, and checkbox toggles from the editor user.

const LevelCatalogBuilder = preload("res://addons/level_editor/level_catalog_builder.gd")
const LevelCreator = preload("res://addons/level_editor/level_creator.gd")

@export_file("*.tres") var catalog_path: String = "res://game/resources/level_catalog.tres"
@export_dir var levels_dir_path: String = "res://game/scenes/gameplay/levels/"
@export_file("*.tscn") var template_path: String = "res://addons/level_editor/templates/LevelTemplate.tscn"
@export_file("*.csv") var strings_csv_path: String = "res://game/assets/localization/strings.csv"
@export var auto_rebuild_on_save: bool = true

var undo_redo: EditorUndoRedoManager = null
var _suggested_level_num: int = 1

@onready var _rebuild_btn: Button = %RebuildButton
@onready var _auto_check: CheckBox = %AutoRebuildCheck
@onready var _status_label: Label = %StatusLabel
@onready var _warning_label: Label = %WarningLabel

@onready var _world_option: OptionButton = %WorldOption
@onready var _suggestion_label: Label = %SuggestionLabel
@onready var _new_level_btn: Button = %NewLevelButton
@onready var _creator_status_label: Label = %CreatorStatusLabel

func _ready() -> void:
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
