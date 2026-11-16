@tool
class_name LevelObjectPicker
extends ScrollContainer

## LevelObjectPicker — The "Objects" grid in the Level tab: every placeable scene as a tile
## with its own sprite as the icon and its name underneath, grouped by folder. Click one, then
## click in the level view to place it (Esc / right-click stops). Uses the same list, hide
## rules and placement as the panel's Palette tab (LevelEditorDock).
##
## Sends: LevelEditorDock.arm_palette(path) / cancel_placing().
## Receives: refresh() from LevelWorkspace (scene change, files changed); the dock's
##           placing_changed signal (to keep the selected tile in sync).

const P = preload("res://addons/level_editor/level_palette.gd")

## Icon size in pixels.
@export var icon_size: int = 44
## Tile width in pixels (names wrap to two lines inside it).
@export var tile_width: int = 92
## Light tile background: the game's art is dark silhouettes.
@export var tile_background := Color(0.62, 0.66, 0.72)
@export var tile_text := Color(0.08, 0.08, 0.1)

var dock: Node = null
var _box: VBoxContainer
var _lists: Array[ItemList] = []
var _icon_cache: Dictionary = {} # path -> Texture2D

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_box)
	if dock:
		dock.placing_changed.connect(_sync_selected)
	refresh()

func refresh() -> void:
	if _box == null or dock == null:
		return
	for c in _box.get_children():
		c.queue_free()
	_lists.clear()
	var root := EditorInterface.get_edited_scene_root() if Engine.is_editor_hint() else null
	var groups := P.scan(dock.palette_folders, dock.palette_hidden_scenes, dock.palette_singletons, root)
	for g: Dictionary in groups:
		var title := Label.new()
		title.text = str(g.group).capitalize()
		title.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
		_box.add_child(title)
		var list := ItemList.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.auto_height = true
		list.max_columns = 0
		list.same_column_width = true
		list.fixed_column_width = tile_width
		list.icon_mode = ItemList.ICON_MODE_TOP
		list.fixed_icon_size = Vector2i(icon_size, icon_size)
		list.max_text_lines = 2
		var bg := StyleBoxFlat.new()
		bg.bg_color = tile_background
		bg.set_corner_radius_all(4)
		bg.set_content_margin_all(4)
		list.add_theme_stylebox_override(&"panel", bg)
		list.add_theme_color_override(&"font_color", tile_text)
		list.add_theme_color_override(&"font_selected_color", Color.BLACK)
		for e: Dictionary in g.items:
			# "CeilingCollapse" -> "Ceiling Collapse" so long names wrap between words.
			var i := list.add_item(str(e.name).capitalize(), _icon_for(e.path))
			list.set_item_metadata(i, e.path)
			list.set_item_tooltip(i, "Place %s: click it, then click in the level view." % e.name)
		list.item_selected.connect(func(i: int) -> void: _on_selected(list, i))
		_box.add_child(list)
		_lists.append(list)
	_sync_selected()

func _on_selected(list: ItemList, index: int) -> void:
	for other in _lists:
		if other != list:
			other.deselect_all()
	dock.arm_palette(str(list.get_item_metadata(index)))

func _sync_selected() -> void:
	var armed: String = dock.get_armed_path() if dock else ""
	for list in _lists:
		list.deselect_all()
		for i in list.item_count:
			if str(list.get_item_metadata(i)) == armed:
				list.select(i)

## The scene's own art: first Sprite3D texture, or first AnimatedSprite3D frame; editor icon otherwise.
func _icon_for(path: String) -> Texture2D:
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = null
	var ps := load(path) as PackedScene
	if ps:
		var inst := ps.instantiate()
		var stack: Array[Node] = [inst]
		while not stack.is_empty() and tex == null:
			var n: Node = stack.pop_front()
			if n is Sprite3D and (n as Sprite3D).texture:
				tex = (n as Sprite3D).texture
			elif n is AnimatedSprite3D and (n as AnimatedSprite3D).sprite_frames:
				var sf := (n as AnimatedSprite3D).sprite_frames
				var anim := (n as AnimatedSprite3D).animation
				if sf.has_animation(anim) and sf.get_frame_count(anim) > 0:
					tex = sf.get_frame_texture(anim, 0)
			for c in n.get_children():
				stack.append(c)
		inst.free()
	if tex == null and Engine.is_editor_hint():
		var theme := EditorInterface.get_editor_theme()
		var name := path.get_file().get_basename()
		var icon_name := "GridMap" if "Platform" in name else ("Area3D" if "Trigger" in name or "Zone" in name else "PackedScene")
		tex = theme.get_icon(icon_name, &"EditorIcons")
	_icon_cache[path] = tex
	return tex
