@tool
class_name LevelCreator
extends RefCounted

## LevelCreator — Creates new level scenes from LevelTemplate.tscn and registers localization.
##
## Sends: creates levels/world<N>/W<N>_<##>.tscn, updates strings.csv, triggers LevelCatalogBuilder.
## Receives: level creation requests from LevelEditorDock.

const LevelCatalogBuilder = preload("res://addons/level_editor/level_catalog_builder.gd")

const DEFAULT_TEMPLATE_PATH := "res://addons/level_editor/templates/LevelTemplate.tscn"
const DEFAULT_LEVELS_DIR := "res://game/scenes/gameplay/levels/"
const DEFAULT_STRINGS_CSV_PATH := "res://game/assets/localization/strings.csv"
const DEFAULT_CATALOG_PATH := "res://game/resources/level_catalog.tres"

## Finds the next free level number (1..levels_per_world) in the specified world.
## Returns -1 if the world has no free slots within levels_per_world.
static func get_next_free_level(world: int, levels_dir: String = DEFAULT_LEVELS_DIR, catalog_path: String = DEFAULT_CATALOG_PATH) -> int:
	var catalog: LevelCatalog = load(catalog_path) as LevelCatalog
	var levels_per_world: int = catalog.levels_per_world if catalog else 10

	var world_dir_path := levels_dir.path_join("world%d" % world)
	var dir := DirAccess.open(world_dir_path)

	# If the world directory does not exist yet, the first slot (1) is free
	if not dir:
		return 1

	for n in range(1, levels_per_world + 1):
		var file_name := "W%d_%02d.tscn" % [world, n]
		if not dir.file_exists(file_name):
			return n

	return -1

## Creates a new level scene from the template, sets its exports, registers strings.csv,
## rebuilds the catalog, and opens the scene in the editor.
## Aborts if the target file already exists.
static func create_level(
	world: int,
	level_number: int,
	template_path: String = DEFAULT_TEMPLATE_PATH,
	levels_dir: String = DEFAULT_LEVELS_DIR,
	strings_csv_path: String = DEFAULT_STRINGS_CSV_PATH,
	catalog_path: String = DEFAULT_CATALOG_PATH,
	undo_redo: EditorUndoRedoManager = null
) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"path": "",
		"level_id": "",
		"world": world,
		"title_key": "",
		"error": "",
	}

	if world < 1:
		result.error = "Invalid world number: %d" % world
		return result
	if level_number < 1:
		result.error = "Invalid level number: %d" % level_number
		return result

	var world_dir_path := levels_dir.path_join("world%d" % world)
	var file_name := "W%d_%02d.tscn" % [world, level_number]
	var target_path := world_dir_path.path_join(file_name)

	# Rule: Never overwrite an existing file (abort)
	if FileAccess.file_exists(target_path):
		result.error = "Aborted: level file already exists at '%s'" % target_path
		push_warning(result.error)
		return result

	# Ensure world directory exists
	if not DirAccess.dir_exists_absolute(world_dir_path):
		var err := DirAccess.make_dir_recursive_absolute(world_dir_path)
		if err != OK:
			result.error = "Failed to create directory '%s' (Error %d)" % [world_dir_path, err]
			push_error(result.error)
			return result

	# Read template file
	if not FileAccess.file_exists(template_path):
		result.error = "Level template missing at '%s'" % template_path
		push_error(result.error)
		return result

	var tf := FileAccess.open(template_path, FileAccess.READ)
	if not tf:
		result.error = "Could not open template file: %s" % template_path
		push_error(result.error)
		return result
	var content := tf.get_as_text()
	tf.close()

	var new_name := "W%d_%02d" % [world, level_number]
	var new_id := "w%d_%02d" % [world, level_number]
	var new_title := "LEVEL_W%d_%02d" % [world, level_number]

	# Give the new scene its own UID: drop any uid the template carries (Godot may add one
	# when it re-saves the template) and write a freshly generated one, so levels never share it.
	var uid_regex := RegEx.new()
	uid_regex.compile('^\\[gd_scene([^\\]]*?) uid="[^"]*"')
	content = uid_regex.sub(content, "[gd_scene$1")
	var new_uid_id := ResourceUID.create_id()
	var new_uid_text := ResourceUID.id_to_text(new_uid_id)
	content = content.replace("[gd_scene format=3", '[gd_scene format=3 uid="%s"' % new_uid_text)

	# Customize root node in scene text
	var root_regex := RegEx.new()
	root_regex.compile('\\[node name="[^"]+" type="Node3D"')
	content = root_regex.sub(content, '[node name="%s" type="Node3D"' % new_name)

	var id_regex := RegEx.new()
	id_regex.compile('(?m)^level_id\\s*=.*$')
	content = id_regex.sub(content, 'level_id = "%s"' % new_id)

	var world_regex := RegEx.new()
	world_regex.compile('(?m)^world\\s*=.*$')
	if world_regex.search(content):
		content = world_regex.sub(content, 'world = %d' % world)
	else:
		content = content.replace('level_id = "%s"' % new_id, 'level_id = "%s"\nworld = %d' % [new_id, world])

	var title_regex := RegEx.new()
	title_regex.compile('(?m)^title_key\\s*=.*$')
	content = title_regex.sub(content, 'title_key = "%s"' % new_title)

	# Each world can have its own look: Backdrop_World<N>.tscn and world<N>_environment.tres.
	var world_backdrop := "res://game/scenes/gameplay/environment/Backdrop_World%d.tscn" % world
	if ResourceLoader.exists(world_backdrop):
		content = content.replace("res://game/scenes/gameplay/environment/Backdrop.tscn", world_backdrop)
	var world_env := "res://game/assets/materials/world%d_environment.tres" % world
	if ResourceLoader.exists(world_env):
		content = content.replace("res://game/assets/materials/world_environment.tres", world_env)

	# Write customized level scene
	var wf := FileAccess.open(target_path, FileAccess.WRITE)
	if not wf:
		result.error = "Could not open target path for writing: %s" % target_path
		push_error(result.error)
		return result
	wf.store_string(content)
	wf.close()
	if not ResourceUID.has_id(new_uid_id):
		ResourceUID.add_id(new_uid_id, target_path)

	# Add row to strings.csv if missing
	var placeholder_title := "Level %d-%02d" % [world, level_number]
	add_strings_row_if_missing(strings_csv_path, new_title, placeholder_title)

	# Rebuild catalog
	LevelCatalogBuilder.rebuild_catalog(levels_dir, catalog_path, undo_redo)

	# Open the new scene in editor if running inside Godot Editor
	if Engine.is_editor_hint():
		if ClassDB.class_exists(&"EditorInterface"):
			var ei := Engine.get_singleton(&"EditorInterface")
			if ei and ei.has_method(&"open_scene_from_path"):
				ei.call(&"open_scene_from_path", target_path)

	result.success = true
	result.path = target_path
	result.level_id = new_id
	result.world = world
	result.title_key = new_title
	return result

## Adds a localization row to strings.csv if the key does not exist yet.
static func add_strings_row_if_missing(csv_path: String, key: String, placeholder: String) -> bool:
	if not FileAccess.file_exists(csv_path):
		return false

	var rf := FileAccess.open(csv_path, FileAccess.READ)
	if not rf:
		return false
	var text := rf.get_as_text()
	rf.close()

	# Check if key is already present
	var key_regex := RegEx.new()
	key_regex.compile("(?m)^" + key + ",")
	if key_regex.search(text):
		return false

	var new_line := '%s,"%s"' % [key, placeholder]
	var updated_text := text.strip_edges() + "\n" + new_line + "\n"

	var wf := FileAccess.open(csv_path, FileAccess.WRITE)
	if not wf:
		return false
	wf.store_string(updated_text)
	wf.close()
	return true
