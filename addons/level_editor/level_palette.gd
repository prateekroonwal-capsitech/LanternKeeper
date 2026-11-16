@tool
class_name LevelPalette
extends RefCounted

## LevelPalette — Finds placeable scenes and instances them into the open level (editor only).
##
## Sends: undoable "Place <Name>" actions through EditorUndoRedoManager (add_child, set_owner,
##        regenerate_segments for scenes that have it, e.g. GhostPlatform).
## Receives: scan requests and placement requests from LevelEditorDock.

const DEFAULT_FOLDERS: PackedStringArray = [
	"res://game/scenes/gameplay/props/",
	"res://game/scenes/gameplay/enemies/",
	"res://game/scenes/gameplay/actors/",
	"res://game/scenes/gameplay/environment/",
]
## Scenes that only live inside other scenes, hidden from the palette by default.
const DEFAULT_HIDDEN: PackedStringArray = ["res://game/scenes/gameplay/props/FallFX.tscn"]
## Scenes a level has exactly once; hidden while the open level already contains them.
const DEFAULT_SINGLETONS: PackedStringArray = [
	"res://game/scenes/gameplay/actors/Player.tscn",
	"res://game/scenes/gameplay/actors/Lantern.tscn",
]
## Scene file name -> standard container under the level root.
const DEFAULT_PARENT_RULES: Dictionary = {
	"Platform.tscn": "Geometry",
	"GhostPlatform.tscn": "GhostPlatforms",
	"TutorialTrigger.tscn": "Hints",
}
const DECOR_CONTAINER := "Decor"
const HIDDEN_META := "palette_hidden"
const PARENT_META := "palette_parent"

## Returns [{ "group": String, "items": [{ "path", "name" }] }] for every placeable .tscn.
## Hidden: "_"-prefixed files, `palette_hidden` metadata on the scene root, `hidden` paths,
## and `singletons` already present in `scene_root`.
static func scan(folders: PackedStringArray, hidden: PackedStringArray, singletons: PackedStringArray, scene_root: Node) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for folder: String in folders:
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		var items: Array[Dictionary] = []
		var files := dir.get_files()
		files.sort()
		for file: String in files:
			# Exported builds list "X.tscn.remap"; this is editor-only, but be strict anyway.
			if not file.ends_with(".tscn") or file.begins_with("_"):
				continue
			var path := folder.path_join(file)
			if path in hidden:
				continue
			if path in singletons and scene_root != null and scene_contains_instance(scene_root, path):
				continue
			if _has_root_meta(path, HIDDEN_META):
				continue
			items.append({ "path": path, "name": file.get_basename() })
		if not items.is_empty():
			groups.append({ "group": folder.trim_suffix("/").get_file(), "items": items })
	return groups

## Snaps a world point onto the z = 0 gameplay plane (and to the grid when grid_size > 0).
static func snap_point(point: Vector3, grid_size: float) -> Vector3:
	var p := Vector3(point.x, point.y, 0.0)
	if grid_size > 0.0:
		p.x = snappedf(p.x, grid_size)
		p.y = snappedf(p.y, grid_size)
	return p

## Picks the standard parent: `palette_parent` metadata, then the file-name rule,
## then a "decor" folder → Decor; anything else (or a missing container) → level root.
static func resolve_parent(scene_path: String, scene_root: Node, parent_rules: Dictionary) -> Node:
	var container := str(_get_root_meta(scene_path, PARENT_META, ""))
	if container.is_empty():
		container = str(parent_rules.get(scene_path.get_file(), ""))
	if container.is_empty() and scene_path.get_base_dir().get_file().to_lower() == "decor":
		container = DECOR_CONTAINER
	if container.is_empty():
		return scene_root
	var node := scene_root.get_node_or_null(NodePath(container))
	return node if node != null else scene_root

## First free "<base><n>" (n ≥ 1) anywhere in the open scene, e.g. Shrine1, Crawler2.
static func unique_name(base: String, scene_root: Node) -> String:
	var n := 1
	while _name_taken("%s%d" % [base, n], scene_root):
		n += 1
	return "%s%d" % [base, n]

static func _name_taken(candidate: String, scene_root: Node) -> bool:
	return scene_root.name == candidate or scene_root.find_child(candidate, true, false) != null

## Instances `scene_path` at `world_point` under its standard parent as one undoable action.
## Returns the new node (already in the tree), or null on failure.
static func place(scene_path: String, world_point: Vector3, scene_root: Node, undo_redo: EditorUndoRedoManager,
		parent_rules: Dictionary, name_aliases: Dictionary) -> Node3D:
	var packed := load(scene_path) as PackedScene
	if packed == null or scene_root == null or undo_redo == null:
		return null
	var node := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	if node == null:
		push_warning("LevelPalette: '%s' has no Node3D root; not placed." % scene_path)
		return null

	var parent := resolve_parent(scene_path, scene_root, parent_rules)
	var base := str(name_aliases.get(scene_path.get_file().get_basename(), scene_path.get_file().get_basename()))
	node.name = unique_name(base, scene_root)
	var parent_3d := parent as Node3D
	var local: Vector3 = world_point
	if parent_3d != null:
		local = parent_3d.global_transform.affine_inverse() * world_point
	node.position = local

	undo_redo.create_action("Place %s" % node.name, UndoRedo.MERGE_DISABLE, scene_root)
	undo_redo.add_do_method(parent, &"add_child", node, true)
	undo_redo.add_do_method(node, &"set_owner", scene_root)
	# Ghost platforms build Segment* children from `owner`: owner first, THEN regenerate,
	# so every segment is owned by the level root and saved in the .tscn.
	if node.has_method(&"regenerate_segments"):
		undo_redo.add_do_method(node, &"regenerate_segments")
	undo_redo.add_do_reference(node)
	undo_redo.add_undo_method(parent, &"remove_child", node)
	undo_redo.commit_action()
	return node

## True when any descendant of `root` is an instance of `scene_path`.
static func scene_contains_instance(root: Node, scene_path: String) -> bool:
	for child in root.get_children():
		if child.scene_file_path == scene_path or scene_contains_instance(child, scene_path):
			return true
	return false

static func _has_root_meta(scene_path: String, key: String) -> bool:
	return bool(_get_root_meta(scene_path, key, false))

## Reads metadata from a scene's root node without instancing it.
static func _get_root_meta(scene_path: String, key: String, default_value: Variant) -> Variant:
	if not ResourceLoader.exists(scene_path):
		return default_value
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return default_value
	var state := packed.get_state()
	if state.get_node_count() == 0:
		return default_value
	var prop := "metadata/" + key
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == prop:
			return state.get_node_property_value(0, i)
	return default_value
