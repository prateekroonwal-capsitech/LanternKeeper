@tool
class_name LevelProperties
extends ScrollContainer

## LevelProperties — The "Properties" panel in the Level tab: simple fields for the selected
## object. Name, X / Y, then the object's own gameplay settings (its script's exported values,
## grouped like the script groups them). Numbers, on/off, text / ids, choices, vectors and
## colours are edited here; anything else opens in Godot's Inspector. Every change is undoable.
##
## Sends: undoable property changes via EditorUndoRedoManager; Duplicate / Delete to LevelCanvas;
##        "Inspector" to EditorInterface.edit_node().
## Receives: edit(node) on selection change and refresh_values() after undo / redo from LevelWorkspace.

const Q = preload("res://addons/level_editor/level_query.gd")
const L = preload("res://addons/level_editor/level_links.gd")

## Engine properties that are noise for level design (always hidden).
const SKIP := ["script", "owner", "scene_file_path", "unique_name_in_owner", "editor_description"]

var undo_redo: EditorUndoRedoManager = null
var canvas: Node = null

var _node: Node = null
var _box: VBoxContainer
var _fields: Dictionary = {} # property -> { control(s), type }
var _x: SpinBox
var _y: SpinBox
var _name_edit: LineEdit
var _grid: GridContainer = null
var _updating := false

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override(&"separation", 4)
	add_child(_box)
	var pending := _node
	_node = null
	edit(pending)

## Shows `node`'s fields (null = "nothing selected").
func edit(node: Node) -> void:
	if _box == null:
		_node = node # not ready yet: _ready() builds it
		return
	if node == _node and node != null and _box.get_child_count() > 0:
		refresh_values()
		return
	_node = node
	for c in _box.get_children():
		c.queue_free()
	_fields.clear()
	_grid = null
	_x = null
	_y = null
	_name_edit = null
	if node == null or not is_instance_valid(node):
		_note("Select an object in the level view to edit it here.\nOr pick one in Objects above and click in the view to place it.")
		return

	var title := Label.new()
	var cls := Q.script_classes(node)
	title.text = "%s  (%s)" % [node.name, cls[0] if not cls.is_empty() else node.get_class()]
	title.add_theme_font_size_override(&"font_size", 15)
	_box.add_child(title)

	var actions := HBoxContainer.new()
	_box.add_child(actions)
	_action(actions, "Duplicate", "Copy it one step to the right (Ctrl+D)", func() -> void: canvas.duplicate_selected())
	_action(actions, "Delete", "Remove it (Del)", func() -> void: canvas.delete_selected())
	_action(actions, "Inspector", "All settings in Godot's Inspector", func() -> void: EditorInterface.edit_node(_node))

	_header("Placement")
	_name_edit = LineEdit.new()
	_name_edit.text = str(node.name)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	_row("Name", _name_edit)
	if node is Node3D:
		_x = _spin(-10000, 10000, 0.05)
		_y = _spin(-10000, 10000, 0.05)
		_x.value_changed.connect(func(_v: float) -> void: _commit_xy())
		_y.value_changed.connect(func(_v: float) -> void: _commit_xy())
		_row("X", _x)
		_row("Y", _y)

	# Script settings, in script order, under their @export_group headers.
	var group := ""
	var shown_any := false
	var pending_header := "Settings"
	for p in node.get_property_list():
		if p.usage & PROPERTY_USAGE_CATEGORY:
			pending_header = "Settings" # a new class / script starts: drop the engine group name
			continue
		if p.usage & PROPERTY_USAGE_SUBGROUP:
			continue
		if p.usage & PROPERTY_USAGE_GROUP:
			pending_header = str(p.name) if not str(p.name).is_empty() else "Settings"
			continue
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (p.usage & PROPERTY_USAGE_EDITOR):
			continue
		if p.name in SKIP:
			continue
		if pending_header != group:
			_header(pending_header)
			group = pending_header
		_add_field(p)
		shown_any = true
	if not shown_any:
		_note("No gameplay settings on this object. Use Inspector for everything else.")
	refresh_values()

## Re-reads values into the fields (after undo / redo or a drag in the view).
func refresh_values() -> void:
	if _node == null or not is_instance_valid(_node):
		edit(null)
		return
	_updating = true
	if _name_edit and not _name_edit.has_focus():
		_name_edit.text = str(_node.name)
	if _x and _node is Node3D:
		_x.set_value_no_signal(snappedf((_node as Node3D).position.x, 0.001))
		_y.set_value_no_signal(snappedf((_node as Node3D).position.y, 0.001))
	for prop in _fields.keys():
		var f: Dictionary = _fields[prop]
		var v: Variant = _node.get(prop)
		match f.kind:
			"bool":
				(f.c as CheckBox).set_pressed_no_signal(bool(v))
			"number":
				(f.c as SpinBox).set_value_no_signal(float(v))
			"enum":
				(f.c as OptionButton).select(maxi(0, (f.values as Array).find(int(v))))
			"text":
				if not (f.c as LineEdit).has_focus():
					(f.c as LineEdit).text = str(v)
			"vector":
				for i in (f.c as Array).size():
					(f.c[i] as SpinBox).set_value_no_signal(float(v[i]))
			"color":
				(f.c as ColorPickerButton).color = v
	_updating = false

# ── fields ───────────────────────────────────────────────────────────────

func _add_field(p: Dictionary) -> void:
	var prop: String = p.name
	var label := prop.capitalize()
	var tip := prop
	for lf in L.fields_of(_node):
		if lf.field == prop:
			tip += "\nLink id (%s channel). Tip: Tools → Link Helper sets it for you." % lf.channel
	match p.type:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.toggled.connect(func(on: bool) -> void: _commit(prop, on))
			_fields[prop] = { "kind": "bool", "c": cb }
			_row(label, cb, tip)
		TYPE_INT, TYPE_FLOAT:
			if p.type == TYPE_INT and p.hint == PROPERTY_HINT_ENUM:
				var ob := OptionButton.new()
				var values: Array = []
				var next := 0
				for part in str(p.hint_string).split(","):
					var bits := part.split(":")
					var v := int(bits[1]) if bits.size() > 1 else next
					ob.add_item(bits[0].strip_edges().capitalize())
					values.append(v)
					next = v + 1
				ob.item_selected.connect(func(i: int) -> void: _commit(prop, values[i]))
				_fields[prop] = { "kind": "enum", "c": ob, "values": values }
				_row(label, ob, tip)
			else:
				var lo := -100000.0
				var hi := 100000.0
				var step := 1.0 if p.type == TYPE_INT else 0.05
				if p.hint == PROPERTY_HINT_RANGE:
					var r := str(p.hint_string).split(",")
					if r.size() >= 2:
						lo = float(r[0])
						hi = float(r[1])
					if r.size() >= 3 and r[2].is_valid_float():
						step = float(r[2])
				var sb := _spin(lo, hi, step)
				sb.value_changed.connect(func(v: float) -> void: _commit(prop, int(v) if p.type == TYPE_INT else v))
				_fields[prop] = { "kind": "number", "c": sb }
				_row(label, sb, tip)
		TYPE_STRING, TYPE_STRING_NAME:
			var le := LineEdit.new()
			le.placeholder_text = "(empty)"
			var is_sn: bool = p.type == TYPE_STRING_NAME
			var apply := func() -> void:
				if not _updating:
					_commit(prop, StringName(le.text) if is_sn else le.text)
			le.text_submitted.connect(func(_t: String) -> void: apply.call())
			le.focus_exited.connect(apply)
			_fields[prop] = { "kind": "text", "c": le }
			_row(label, le, tip)
		TYPE_VECTOR2, TYPE_VECTOR3:
			var n := 2 if p.type == TYPE_VECTOR2 else 3
			var hb := HBoxContainer.new()
			var spins: Array = []
			for i in n:
				var s := _spin(-100000, 100000, 0.05)
				s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				s.tooltip_text = ["x", "y", "z"][i]
				s.value_changed.connect(func(_v: float) -> void:
					var vals: Array = spins.map(func(sp: SpinBox) -> float: return sp.value)
					_commit(prop, Vector2(vals[0], vals[1]) if n == 2 else Vector3(vals[0], vals[1], vals[2])))
				hb.add_child(s)
				spins.append(s)
			_fields[prop] = { "kind": "vector", "c": spins }
			_row(label, hb, tip)
		TYPE_COLOR:
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(60, 24)
			cp.color_changed.connect(func(c: Color) -> void: _commit(prop, c))
			_fields[prop] = { "kind": "color", "c": cp }
			_row(label, cp, tip)
		_:
			var b := Button.new()
			b.text = "Edit in Inspector"
			b.tooltip_text = tip
			b.pressed.connect(func() -> void: EditorInterface.edit_node(_node))
			_row(label, b, tip)

## One undoable change. Spin drags merge into a single undo step.
func _commit(prop: String, value: Variant) -> void:
	if _updating or _node == null or not is_instance_valid(_node):
		return
	var old: Variant = _node.get(prop)
	if old == value:
		return
	if undo_redo == null:
		_node.set(prop, value)
		return
	undo_redo.create_action("Set %s.%s" % [_node.name, prop], UndoRedo.MERGE_ENDS, _node.owner if _node.owner else _node)
	undo_redo.add_do_property(_node, prop, value)
	undo_redo.add_undo_property(_node, prop, old)
	undo_redo.commit_action()

func _commit_xy() -> void:
	if _updating or not (_node is Node3D):
		return
	var n := _node as Node3D
	_commit("position", Vector3(_x.value, _y.value, n.position.z))

func _commit_name() -> void:
	if _updating or _node == null or _name_edit == null:
		return
	var new_name := _name_edit.text.strip_edges().validate_node_name()
	if new_name.is_empty() or new_name == str(_node.name):
		_name_edit.text = str(_node.name)
		return
	if _node.get_parent() and _node.get_parent().has_node(NodePath(new_name)):
		_name_edit.text = str(_node.name) # taken
		return
	_commit("name", StringName(new_name))

# ── layout helpers ───────────────────────────────────────────────────────

func _spin(lo: float, hi: float, step: float) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.allow_greater = true
	s.allow_lesser = true
	s.custom_arrow_step = step
	s.select_all_on_focus = true
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

## Label + field in the current section's two-column grid (labels never get cut off; fields line up).
func _row(label: String, control: Control, tip: String = "") -> void:
	if _grid == null:
		_new_grid()
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 90)
	if not tip.is_empty() and control.tooltip_text.is_empty():
		control.tooltip_text = tip
	_grid.add_child(control)

func _header(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.35))
	_box.add_child(HSeparator.new())
	_box.add_child(l)
	_new_grid()

func _new_grid() -> void:
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override(&"h_separation", 8)
	_box.add_child(_grid)

func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))
	_box.add_child(l)

func _action(parent: Control, text: String, tip: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
