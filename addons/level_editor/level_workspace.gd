@tool
class_name LevelWorkspace
extends VBoxContainer

## LevelWorkspace — The "Level" main-screen tab: a toolbar and the side view of the open level
## (LevelCanvas). The Level Editor panel (palette, tools, validate) stays in the right dock.
##
## Sends: open / save / play scene requests to EditorInterface; Fit / Validate / overlay
##        toggles to LevelEditorDock; redraw requests to LevelCanvas.
## Receives: refresh() from LevelEditorPlugin on scene change, selection change, undo history
##           and filesystem changes; the dock's placing_changed / overlays_changed signals.

const LevelCanvasScript = preload("res://addons/level_editor/level_canvas.gd")
const LevelObjectPickerScript = preload("res://addons/level_editor/level_object_picker.gd")
const LevelPropertiesScript = preload("res://addons/level_editor/level_properties.gd")

## Seconds between redraws while visible (catches Inspector edits and animations).
@export var redraw_interval: float = 0.3
## Width of the Objects / Properties column (px).
@export var side_width: int = 330
var dock: Control = null
var undo_redo: EditorUndoRedoManager = null
var canvas: LevelCanvas = null
var picker: LevelObjectPicker = null
var properties: LevelProperties = null

var _level_option: OptionButton
var _status: Label
var _overlay_buttons: Dictionary = {}
var _snap_button: CheckButton
var _timer: Timer
var _level_paths: PackedStringArray = []

func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override(&"separation", 4)
	_build_toolbar()

	canvas = LevelCanvasScript.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(300, 200)
	canvas.dock = dock
	canvas.undo_redo = undo_redo
	canvas.status_changed.connect(func(t: String) -> void: _status.text = t)

	# View on the left; Objects (top) and Properties (bottom) on the right.
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	split.add_child(canvas)

	var side := VSplitContainer.new()
	side.custom_minimum_size = Vector2(side_width, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(side)

	var objects_box := VBoxContainer.new()
	objects_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	objects_box.add_child(_section_title("Objects  (click one, then click in the view)"))
	picker = LevelObjectPickerScript.new()
	picker.dock = dock
	picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picker.custom_minimum_size = Vector2(0, 160)
	objects_box.add_child(picker)
	side.add_child(objects_box)

	var props_box := VBoxContainer.new()
	props_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	props_box.add_child(_section_title("Properties"))
	properties = LevelPropertiesScript.new()
	properties.undo_redo = undo_redo
	properties.canvas = canvas
	properties.size_flags_vertical = Control.SIZE_EXPAND_FILL
	properties.custom_minimum_size = Vector2(0, 200)
	props_box.add_child(properties)
	side.add_child(props_box)

	# Mouse position only, monospace so the numbers don't shift; the controls are in the tooltip.
	_status = Label.new()
	_status.text = "x     0.00    y     0.00"
	_status.tooltip_text = _help()
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	_status.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.6))
	if Engine.is_editor_hint():
		var mono := EditorInterface.get_editor_theme().get_font(&"source", &"EditorFonts")
		if mono:
			_status.add_theme_font_override(&"font", mono)
	add_child(_status)

	_timer = Timer.new()
	_timer.wait_time = maxf(redraw_interval, 0.05)
	_timer.timeout.connect(func() -> void:
		if is_visible_in_tree() and canvas:
			canvas.queue_redraw())
	add_child(_timer)
	_timer.start()

	if dock:
		dock.placing_changed.connect(func() -> void: canvas.queue_redraw())
		dock.overlays_changed.connect(_sync_toggles)
	refresh(true)

func _section_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", 14)
	return l

func _help() -> String:
	return "Click = select\nDrag = move\nEdge handles = resize\nWheel = zoom\nMiddle / right drag = pan\nDel = delete\nCtrl+D = duplicate\nF = frame level\nEsc = stop placing"

func _build_toolbar() -> void:
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override(&"h_separation", 6)
	add_child(bar)

	_level_option = OptionButton.new()
	_level_option.custom_minimum_size = Vector2(170, 0)
	_level_option.tooltip_text = "Open a level"
	_level_option.item_selected.connect(_on_level_picked)
	bar.add_child(_level_option)

	_button(bar, "Save", "Save", "Save the level (Ctrl+S)", func() -> void: EditorInterface.save_scene())
	_button(bar, "Play", "PlayScene", "Save and play this level", _play)
	bar.add_child(VSeparator.new())
	_button(bar, "Frame", "CenterView", "Fit the whole level in view (F)", func() -> void: canvas.frame_level())
	_button(bar, "−", "", "Zoom out", func() -> void: canvas.zoom_by(1.0 / 1.25))
	_button(bar, "+", "", "Zoom in", func() -> void: canvas.zoom_by(1.25))

	_snap_button = CheckButton.new()
	_snap_button.text = "Snap"
	_snap_button.tooltip_text = "Snap to the grid set in the Palette tab"
	_snap_button.toggled.connect(func(on: bool) -> void:
		if dock:
			dock.snap_enabled = on
			var cb: CheckBox = dock.get_node_or_null("%SnapCheck")
			if cb:
				cb.set_pressed_no_signal(on))
	bar.add_child(_snap_button)
	bar.add_child(VSeparator.new())

	for key in ["Links", "Light", "Jump", "Paths"]:
		var b := Button.new()
		b.text = key
		b.toggle_mode = true
		b.tooltip_text = {
			"Links": "Lines between pieces that share an id",
			"Light": "What the lantern, hooks and shrines light",
			"Jump": "Where the child can jump from the selected platform",
			"Paths": "Hook rails, rope swings, crate ranges, hook reach",
		}[key]
		b.toggled.connect(func(on: bool) -> void: _set_overlay(key, on))
		bar.add_child(b)
		_overlay_buttons[key] = b
	bar.add_child(VSeparator.new())
	_button(bar, "Fit", "", "Fit the kill zone and kill_y to the level", func() -> void:
		if dock:
			var fit: Dictionary = dock.fit_level()
			_status.text = String(fit.get("error", "")) if not fit.get("ok", false) else ("Fit: " + ("changed" if fit.changed else "nothing to change") + " (details in Tools tab)"))
	_button(bar, "Validate", "", "Check this level (results in the Validate tab)", func() -> void:
		if dock:
			var issues: Array = dock.validate_open_level()
			var errs := issues.filter(func(i: Dictionary) -> bool: return i.severity == "error").size()
			_status.text = "Validate: %d error(s), %d warning(s) (see Validate tab)" % [errs, issues.size() - errs]
			var tabs := dock.get_node_or_null("Tabs") as TabContainer
			if tabs:
				tabs.current_tab = 3)

func _button(bar: Control, text: String, icon: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	if not icon.is_empty() and Engine.is_editor_hint():
		var theme := EditorInterface.get_editor_theme()
		if theme.has_icon(icon, &"EditorIcons"):
			b.icon = theme.get_icon(icon, &"EditorIcons")
	b.pressed.connect(cb)
	bar.add_child(b)
	return b

## Re-reads the open scene and the level list (scene change, history, selection).
func refresh(reframe: bool = false) -> void:
	if canvas == null:
		return
	var root := EditorInterface.get_edited_scene_root()
	if root != canvas.get_level_root():
		canvas.set_level_root(root)
		_fill_levels()
		if picker:
			picker.refresh()
		on_selection_changed()
	elif reframe:
		canvas.frame_level()
	if properties:
		properties.refresh_values()
	_sync_toggles()
	canvas.queue_redraw()

func on_selection_changed() -> void:
	if canvas == null:
		return
	var sel := EditorInterface.get_selection().get_top_selected_nodes()
	# Picked from the Validate list or the Scene dock: bring it into view.
	if sel.size() == 1 and not canvas.get_global_rect().has_point(get_global_mouse_position()):
		canvas.center_on(sel[0])
	if properties:
		var root := canvas.get_level_root()
		properties.edit(sel[0] if sel.size() == 1 and root and root.is_ancestor_of(sel[0]) else null)
	canvas.queue_redraw()

## Files changed (scenes added / removed): rebuild the Objects grid.
func on_filesystem_changed() -> void:
	if picker:
		picker.refresh()

func _fill_levels() -> void:
	_level_option.clear()
	_level_paths = PackedStringArray()
	var root := EditorInterface.get_edited_scene_root()
	var current := root.scene_file_path if root else ""
	var catalog = load(dock.catalog_path) if dock else null
	var paths := PackedStringArray()
	if catalog:
		for p: String in catalog.get("level_paths"):
			if not p.is_empty():
				paths.append(p)
	if not current.is_empty() and not (current in paths):
		paths.append(current)
	_level_option.add_item("— open a level —")
	_level_paths.append("")
	for p in paths:
		_level_option.add_item(p.get_file().get_basename())
		_level_paths.append(p)
		if p == current:
			_level_option.select(_level_option.item_count - 1)

func _on_level_picked(index: int) -> void:
	var path := _level_paths[index] if index < _level_paths.size() else ""
	if path.is_empty():
		return
	EditorInterface.open_scene_from_path(path)
	refresh.call_deferred(true)

func _play() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path.is_empty():
		_status.text = "Save the level first."
		return
	EditorInterface.save_scene()
	EditorInterface.play_custom_scene(root.scene_file_path)

func _set_overlay(key: String, on: bool) -> void:
	if dock == null:
		return
	var cb: CheckBox = dock.get_node_or_null("%%Show%sCheck" % key)
	if cb and cb.button_pressed != on:
		cb.button_pressed = on # triggers the dock's own toggle handling
	canvas.queue_redraw()

func _sync_toggles() -> void:
	if dock == null:
		return
	for key in _overlay_buttons.keys():
		var cb: CheckBox = dock.get_node_or_null("%%Show%sCheck" % key)
		if cb:
			(_overlay_buttons[key] as Button).set_pressed_no_signal(cb.button_pressed)
	_snap_button.set_pressed_no_signal(bool(dock.snap_enabled))
	if canvas:
		canvas.queue_redraw()
