@tool
class_name LevelCatalogBuilder
extends RefCounted

## LevelCatalogBuilder — Scans level directories and synchronizes game/resources/level_catalog.tres.
##
## Sends: file updates to game/resources/level_catalog.tres; warnings for out-of-bounds or mismatches.
## Receives: rebuild requests from LevelEditorPlugin, LevelEditorDock, or automated tests.

const _Self = preload("res://addons/level_editor/level_catalog_builder.gd")
const DEFAULT_CATALOG_PATH := "res://game/resources/level_catalog.tres"
const DEFAULT_LEVELS_DIR := "res://game/scenes/gameplay/levels/"

## Scans the levels folder for world subdirectories and W<world>_<##>.tscn files.
## Returns a Dictionary with scan details, warnings, mismatches, and resolved paths.
static func scan_levels(levels_dir: String = DEFAULT_LEVELS_DIR, catalog_path: String = DEFAULT_CATALOG_PATH) -> Dictionary:
	var result: Dictionary = {
		"success": true,
		"discovered": {},       # slot: int -> file_path: String
		"paths": PackedStringArray(),
		"max_slot": -1,
		"warnings": [] as Array[String],
		"mismatches": [] as Array[String],
		"world_counts": {} as Dictionary,
		"total_valid_levels": 0,
		"changed": false,
	}

	var catalog: LevelCatalog = load(catalog_path) as LevelCatalog
	var levels_per_world: int = catalog.levels_per_world if catalog else 10
	var world_names: PackedStringArray = catalog.world_names if catalog else PackedStringArray(["Light", "Oil", "Shadows", "Mirrors"])
	var max_worlds: int = world_names.size()

	var dir := DirAccess.open(levels_dir)
	if not dir:
		var err_msg := "LevelCatalogBuilder: Unable to open levels directory: %s" % levels_dir
		push_warning(err_msg)
		result.warnings.append(err_msg)
		result.success = false
		return result

	var file_regex := RegEx.new()
	file_regex.compile("^W(\\d+)_(\\d{2})\\.tscn$")

	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		# Only inspect subdirectories matching world*
		if dir.current_is_dir() and entry.begins_with("world"):
			var world_dir_path := levels_dir.path_join(entry)
			var wdir := DirAccess.open(world_dir_path)
			if wdir:
				wdir.list_dir_begin()
				var file := wdir.get_next()
				while not file.is_empty():
					if not wdir.current_is_dir() and file.ends_with(".tscn"):
						# Ignore _-prefixed files and TestLevel.tscn
						if file.begins_with("_") or file == "TestLevel.tscn":
							file = wdir.get_next()
							continue

						var match := file_regex.search(file)
						if match:
							var w := match.get_string(1).to_int()
							var n := match.get_string(2).to_int()

							# Validate world index against catalog world_names.size()
							if w < 1 or w > max_worlds:
								var w_warn := "LevelCatalogBuilder: '%s' specifies world %d which exceeds world count (%d); reported and not written." % [file, w, max_worlds]
								push_warning(w_warn)
								result.warnings.append(w_warn)
								file = wdir.get_next()
								continue

							# Validate level index against levels_per_world
							if n < 1 or n > levels_per_world:
								var n_warn := "LevelCatalogBuilder: '%s' specifies level %d which exceeds levels_per_world (%d); reported and not written." % [file, n, levels_per_world]
								push_warning(n_warn)
								result.warnings.append(n_warn)
								file = wdir.get_next()
								continue

							var full_path := world_dir_path.path_join(file)
							var slot := (w - 1) * levels_per_world + (n - 1)

							if result.discovered.has(slot):
								var dup_warn := "LevelCatalogBuilder: Duplicate slot %d collision between '%s' and '%s'." % [slot, result.discovered[slot], full_path]
								push_warning(dup_warn)
								result.warnings.append(dup_warn)

							result.discovered[slot] = full_path
							result.world_counts[w] = result.world_counts.get(w, 0) + 1
							result.total_valid_levels += 1

							# Check scene root for level_id / world mismatch
							_validate_scene_properties(full_path, file, w, n, result)
					file = wdir.get_next()
		entry = dir.get_next()

	# Build slot array up to the highest populated slot, leaving empty slots as ""
	var max_slot := -1
	for slot: int in result.discovered.keys():
		if slot > max_slot:
			max_slot = slot
	result.max_slot = max_slot

	var paths := PackedStringArray()
	if max_slot >= 0:
		paths.resize(max_slot + 1)
		for i in range(max_slot + 1):
			paths[i] = result.discovered.get(i, "")
	result.paths = paths

	if catalog:
		result.changed = (catalog.level_paths != paths)
	else:
		result.changed = true

	return result

## Validates level_id and world properties on the scene root without silently fixing them.
static func _validate_scene_properties(full_path: String, filename: String, expected_world: int, expected_num: int, result: Dictionary) -> void:
	var scn := load(full_path) as PackedScene
	if not scn:
		var err := "LevelCatalogBuilder: Failed to load PackedScene at '%s'" % full_path
		push_warning(err)
		result.warnings.append(err)
		return

	var root := scn.instantiate()
	if not root:
		return

	var expected_id := "w%d_%02d" % [expected_world, expected_num]
	var actual_id := str(root.get("level_id"))
	var actual_world := int(root.get("world"))

	if actual_id != expected_id or actual_world != expected_world:
		var mis_msg := "LevelCatalogBuilder: Mismatch in '%s' — file name implies (world=%d, level_id='%s'), but scene root has (world=%d, level_id='%s')." % [
			filename, expected_world, expected_id, actual_world, actual_id
		]
		push_warning(mis_msg)
		result.mismatches.append(mis_msg)

	root.free()

## Rebuilds the catalog, writing changes to level_catalog.tres.
## If undo_redo (EditorUndoRedoManager) is provided, records an undoable action.
static func rebuild_catalog(levels_dir: String = DEFAULT_LEVELS_DIR, catalog_path: String = DEFAULT_CATALOG_PATH, undo_redo: EditorUndoRedoManager = null) -> Dictionary:
	var scan := scan_levels(levels_dir, catalog_path)
	if not scan.success:
		return scan

	var catalog: LevelCatalog = load(catalog_path) as LevelCatalog
	var old_paths := catalog.level_paths if catalog else PackedStringArray()
	var new_paths: PackedStringArray = scan.paths

	if undo_redo != null:
		undo_redo.create_action("Rebuild Level Catalog")
		undo_redo.add_do_method(_Self, &"apply_catalog_paths", catalog_path, new_paths)
		undo_redo.add_undo_method(_Self, &"apply_catalog_paths", catalog_path, old_paths)
		undo_redo.commit_action()
	else:
		apply_catalog_paths(catalog_path, new_paths)

	return scan

## Writes paths into level_catalog.tres while preserving existing resource formatting and comments.
static func apply_catalog_paths(catalog_path: String, paths: PackedStringArray) -> bool:
	if not FileAccess.file_exists(catalog_path):
		push_error("LevelCatalogBuilder: Catalog file does not exist: %s" % catalog_path)
		return false

	var f := FileAccess.open(catalog_path, FileAccess.READ)
	if not f:
		push_error("LevelCatalogBuilder: Could not open catalog file for reading: %s" % catalog_path)
		return false
	var content := f.get_as_text()
	f.close()

	var formatted_items: Array[String] = []
	for p: String in paths:
		formatted_items.append('"%s"' % p)
	var new_line := 'level_paths = PackedStringArray(%s)' % ", ".join(formatted_items)

	var regex := RegEx.new()
	regex.compile("(?m)^level_paths\\s*=.*$")
	var new_content := ""
	if regex.search(content):
		new_content = regex.sub(content, new_line)
	else:
		new_content = content.strip_edges() + "\n" + new_line + "\n"

	# If identical, skip writing to avoid touching timestamps and triggering unnecessary re-imports
	if new_content != content:
		var fw := FileAccess.open(catalog_path, FileAccess.WRITE)
		if not fw:
			push_error("LevelCatalogBuilder: Could not open catalog file for writing: %s" % catalog_path)
			return false
		fw.store_string(new_content)
		fw.close()

	# Synchronize in-memory resource instance
	var catalog: LevelCatalog = load(catalog_path) as LevelCatalog
	if catalog:
		catalog.level_paths = paths

	return true
