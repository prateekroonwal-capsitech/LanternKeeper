@tool
class_name LevelCanvas
extends Control

## LevelCanvas — Side view of the open level for the "Level" tab: the gameplay plane (z = 0)
## drawn flat, X right / Y up, with the real sprites, platforms, ghost platforms, triggers,
## kill zone and the overlays. Edit directly: place from the palette, select, drag to move,
## drag edge handles to resize, Delete, Ctrl+D duplicate. Every change goes through
## EditorUndoRedoManager (Ctrl+Z). Nothing here is saved into the level except your edits.
##
## Sends: undoable edits (position / size / add / remove) via EditorUndoRedoManager;
##        placement requests to LevelEditorDock.place_armed_at(); selection to EditorSelection;
##        status text via `status_changed`.
## Receives: mouse / keyboard input; redraw requests from LevelWorkspace (history, selection,
##           scene change); the level root via set_level_root().

signal status_changed(text: String)

const Q = preload("res://addons/level_editor/level_query.gd")
const O = preload("res://addons/level_editor/level_overlays.gd")
const P = preload("res://addons/level_editor/level_palette.gd")

@export_group("View")
@export var min_zoom: float = 4.0
@export var max_zoom: float = 200.0
## Pixels per metre when a level is framed but very small.
@export var default_zoom: float = 28.0
@export var show_labels: bool = true
@export var handle_size: float = 9.0

@export_group("Colours")
## Light sky-like background: the game's art is dark silhouettes.
@export var col_background := Color(0.62, 0.66, 0.72)
@export var col_grid_minor := Color(0, 0, 0, 0.06)
@export var col_grid_major := Color(0, 0, 0, 0.14)
@export var col_axis := Color(0, 0, 0, 0.3)
@export var col_platform := Color(0.24, 0.22, 0.21)
@export var col_platform_edge := Color(0.1, 0.09, 0.09)
@export var col_ghost := Color(0.25, 0.45, 1.0, 0.25)
@export var col_ghost_edge := Color(0.15, 0.3, 0.9, 0.95)
@export var col_collapse := Color(0.55, 0.36, 0.18)
@export var col_kill := Color(0.9, 0.1, 0.1, 0.16)
@export var col_kill_edge := Color(0.8, 0.05, 0.05, 0.9)
@export var col_trigger := Color(0.5, 0.2, 0.85, 0.9)
@export var col_marker := Color(0.1, 0.1, 0.12, 0.9)
@export var col_select := Color(1.0, 0.75, 0.0)
@export var col_hover := Color(1.0, 1.0, 1.0, 0.8)
@export var col_label := Color(1, 1, 1, 0.95)

## LevelEditorDock (palette arming, snap, overlays, undo). May be null in tests.
var dock: Node = null
var undo_redo: EditorUndoRedoManager = null

var _root: Node = null
var _zoom: float = 28.0
var _origin: Vector2 = Vector2(200, 400) # screen position of world (0, 0)
var _objects: Array[Dictionary] = []     # built each redraw: { node, rect, kind, sprites }
var _hover: Node = null
var _drag: Dictionary = {}
var _mouse_world := Vector2.ZERO
var _selected_override: Array = []       # used when EditorInterface isn't available (tests)

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

# ── level / view ─────────────────────────────────────────────────────────

func set_level_root(root: Node) -> void:
	var changed := root != _root
	_root = root
	_hover = null
	_drag.clear()
	if changed:
		frame_level()
	queue_redraw()

func get_level_root() -> Node:
	return _root if is_instance_valid(_root) else null

## Untyped on purpose: a closed scene leaves a freed object here, which a typed Node arg rejects.
func is_level(root) -> bool:
	return is_instance_valid(root) and root.get("kill_y") != null

func world_to_screen(p: Vector2) -> Vector2:
	return Vector2(_origin.x + p.x * _zoom, _origin.y - p.y * _zoom)

func screen_to_world(s: Vector2) -> Vector2:
	return Vector2((s.x - _origin.x) / _zoom, (_origin.y - s.y) / _zoom)

func world_rect_to_screen(r: Rect2) -> Rect2:
	var tl := world_to_screen(Vector2(r.position.x, r.end.y))
	return Rect2(tl, r.size * _zoom)

## Fits the whole level in view (F).
func frame_level() -> void:
	if not is_level(_root) or size.x < 10.0 or size.y < 10.0:
		_zoom = default_zoom
		_origin = Vector2(80, size.y * 0.7 if size.y > 10.0 else 400.0)
		return
	var have := false
	var b := Rect2()
	for n in Q.gameplay_nodes(_root):
		var r := _pick_rect(n)
		b = r if not have else b.merge(r)
		have = true
	if not have:
		b = Rect2(-10, -5, 40, 15)
	b = b.grow(2.0)
	_zoom = clampf(minf(size.x / maxf(b.size.x, 1.0), size.y / maxf(b.size.y, 1.0)), min_zoom, max_zoom)
	var centre := b.get_center()
	_origin = size * 0.5 - Vector2(centre.x * _zoom, -centre.y * _zoom)
	queue_redraw()

## Centres the view on `node` without changing zoom.
func center_on(node: Node) -> void:
	if node == null or not is_level(_root) or not _root.is_ancestor_of(node):
		return
	var c := _pick_rect(node).get_center()
	_origin = size * 0.5 - Vector2(c.x * _zoom, -c.y * _zoom)
	queue_redraw()

func zoom_by(factor: float, around: Vector2 = Vector2(-1, -1)) -> void:
	if around.x < 0.0:
		around = size * 0.5
	var w := screen_to_world(around)
	_zoom = clampf(_zoom * factor, min_zoom, max_zoom)
	_origin = around - Vector2(w.x * _zoom, -w.y * _zoom)
	queue_redraw()

# ── drawing ──────────────────────────────────────────────────────────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), col_background)
	if not is_level(_root):
		_draw_center_text("Open a level from the list above,\nor make one in the panel: Levels → New Level.")
		return
	_draw_grid()
	_build_objects()
	_draw_kill_line()

	# Back to front: shapes (platforms, zones), then sprites sorted by depth, then markers.
	for o in _objects:
		_draw_shape(o)
	var sprites: Array = []
	for o in _objects:
		for s in o.sprites:
			sprites.append(s)
	sprites.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.z < b.z)
	for s in sprites:
		_draw_sprite(s)
	for o in _objects:
		if o.sprites.is_empty() and o.kind == "object":
			_draw_marker(o)
	_draw_overlays()
	_draw_selection()
	if show_labels:
		_draw_labels()
	_draw_placement_ghost()

func _draw_grid() -> void:
	var tl := screen_to_world(Vector2.ZERO)
	var br := screen_to_world(size)
	var minor := 1.0 if _zoom >= 10.0 else 5.0
	var x := floorf(tl.x / minor) * minor
	while x <= br.x:
		var sx := world_to_screen(Vector2(x, 0)).x
		var major := is_zero_approx(fposmod(x, 5.0))
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), col_grid_major if major else col_grid_minor)
		x += minor
	var y := floorf(br.y / minor) * minor
	while y <= tl.y:
		var sy := world_to_screen(Vector2(0, y)).y
		var major := is_zero_approx(fposmod(y, 5.0))
		draw_line(Vector2(0, sy), Vector2(size.x, sy), col_grid_major if major else col_grid_minor)
		y += minor
	var o := world_to_screen(Vector2.ZERO)
	draw_line(Vector2(0, o.y), Vector2(size.x, o.y), col_axis)
	draw_line(Vector2(o.x, 0), Vector2(o.x, size.y), col_axis)

func _draw_kill_line() -> void:
	var ky := float(_root.get("kill_y"))
	var sy := world_to_screen(Vector2(0, ky)).y
	_dashed(Vector2(0, sy), Vector2(size.x, sy), col_kill_edge, 10.0)
	_text(Vector2(6, sy - 4), "kill_y %.1f" % ky, col_kill_edge)

func _draw_shape(o: Dictionary) -> void:
	var sr := world_rect_to_screen(o.rect)
	match o.kind:
		"platform":
			draw_rect(sr, col_platform)
			draw_rect(sr, col_platform_edge, false, 1.0)
		"ghost":
			draw_rect(sr, col_ghost)
			_dashed_rect(sr, col_ghost_edge)
			# Segment ticks so you see how it is split.
			for seg in o.node.get_children():
				if seg is StaticBody3D and String(seg.name).begins_with("Segment"):
					var sx := world_to_screen(Vector2(Q.pos(seg, _root).x, 0)).x
					draw_line(Vector2(sx, sr.position.y), Vector2(sx, sr.end.y), Color(col_ghost_edge, 0.25))
		"collapse":
			draw_rect(sr, Color(col_collapse, 0.85))
			_dashed_rect(sr, col_collapse.lightened(0.4))
		"kill":
			draw_rect(sr, col_kill)
			draw_rect(sr, col_kill_edge, false, 1.0)
		"trigger":
			draw_rect(sr, Color(col_trigger, 0.08))
			_dashed_rect(sr, col_trigger)

func _draw_sprite(s: Dictionary) -> void:
	var sr := world_rect_to_screen(s.rect)
	if s.flip:
		draw_set_transform(Vector2(sr.position.x * 2.0 + sr.size.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(s.tex, sr, s.src, s.modulate)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(s.tex, sr, s.src, s.modulate)

func _draw_marker(o: Dictionary) -> void:
	var c := world_to_screen(Vector2(Q.pos(o.node, _root).x, Q.pos(o.node, _root).y))
	var col := col_marker
	if String(o.node.name).begins_with("SpawnPoint"):
		col = Color(0.4, 1.0, 0.5)
		draw_line(c, c + Vector2(0, -26), col, 2.0)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -26), c + Vector2(14, -21), c + Vector2(0, -16)]), col)
		return
	draw_circle(c, 7.0, Color(col, 0.25))
	draw_arc(c, 7.0, 0, TAU, 20, col, 1.5)

func _draw_overlays() -> void:
	if dock == null or not dock.has_method(&"get_overlay_options"):
		return
	var opts: Dictionary = dock.get_overlay_options()
	if not (opts.links or opts.light or opts.jump or opts.paths):
		return
	var d := O.build(_root, opts, _selected())
	var tris: PackedVector3Array = d.tris
	for i in range(0, tris.size() - 2, 3):
		var poly := PackedVector2Array([_w3(tris[i]), _w3(tris[i + 1]), _w3(tris[i + 2])])
		draw_colored_polygon(poly, d.tri_colors[i])
	var lines: PackedVector3Array = d.lines
	for i in range(0, lines.size() - 1, 2):
		draw_line(_w3(lines[i]), _w3(lines[i + 1]), d.line_colors[i], 1.5, true)

func _draw_selection() -> void:
	if _hover and is_instance_valid(_hover) and not (_hover in _selected()):
		draw_rect(world_rect_to_screen(_pick_rect(_hover)).grow(2), col_hover, false, 1.0)
	for n in _selected():
		if not (n is Node) or not is_instance_valid(n) or not _root.is_ancestor_of(n):
			continue
		var sr := world_rect_to_screen(_pick_rect(n)).grow(3)
		draw_rect(sr, col_select, false, 2.0)
		if _resizable(n):
			for h in _handles(n):
				draw_rect(Rect2(h.pos - Vector2.ONE * handle_size * 0.5, Vector2.ONE * handle_size), col_select)

func _draw_labels() -> void:
	if _zoom < 14.0:
		return
	for o in _objects:
		var is_decor: bool = o.node.get_parent() != null and o.node.get_parent().name == "Decor"
		if (o.kind == "platform" or o.kind == "kill" or is_decor) and not (o.node in _selected()):
			continue
		var r := world_rect_to_screen(o.rect)
		var col := col_select if o.node in _selected() else col_label
		_text(Vector2(r.position.x, r.end.y + 12), str(o.node.name), col)

func _draw_placement_ghost() -> void:
	if dock == null or not dock.has_method(&"is_placing") or not dock.is_placing():
		return
	var p := _snap(_mouse_world)
	var c := world_to_screen(p)
	draw_line(c + Vector2(-10, 0), c + Vector2(10, 0), col_select, 1.5)
	draw_line(c + Vector2(0, -10), c + Vector2(0, 10), col_select, 1.5)
	_text(c + Vector2(10, -8), "%s  (%.1f, %.1f)" % [str(dock.get_armed_path()).get_file().get_basename(), p.x, p.y], col_select)

func _draw_center_text(t: String) -> void:
	var font := get_theme_default_font()
	var lines := t.split("\n")
	for i in lines.size():
		var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(Vector2((size.x - w) * 0.5, size.y * 0.45 + i * 24), lines[i], col_label, 16)

# ── objects in the level ─────────────────────────────────────────────────

## One entry per placeable object: gameplay nodes, the SpawnPoint, decor sprites.
func _build_objects() -> void:
	_objects.clear()
	var nodes: Array[Node] = Q.gameplay_nodes(_root)
	var decor := _root.get_node_or_null("Decor")
	if decor:
		for d in decor.get_children():
			nodes.append(d)
	for n in nodes:
		if not (n is Node3D):
			continue
		var kind := "object"
		var cls := Q.script_classes(n)
		if "GhostPlatform" in cls:
			kind = "ghost"
		elif "CollapsingPlatform" in cls:
			kind = "collapse"
		elif "Platform" in cls:
			kind = "platform"
		elif "KillZone" in cls:
			kind = "kill"
		elif "WakeTrigger" in cls or "TutorialTrigger" in cls:
			kind = "trigger"
		_objects.append({ "node": n, "kind": kind, "rect": _pick_rect(n), "sprites": _sprites_of(n) })
	# Root KillZone isn't in gameplay_nodes; draw it too.
	for k in Q.find_class(_root, "KillZone"):
		_objects.push_front({ "node": k, "kind": "kill", "rect": _pick_rect(k), "sprites": [] })

## The node's box on the plane: its `size`, else its sprites, else its collision box, else a dot.
func _pick_rect(n: Node) -> Rect2:
	var s: Variant = n.get("size")
	if s is Vector2 or s is Vector3:
		return Q.rect_xy(n, _root)
	var have := false
	var r := Rect2()
	for sp in _sprites_of(n):
		r = sp.rect if not have else r.merge(sp.rect)
		have = true
	if have:
		return r
	var box := Q.shape_rect(n, _root)
	if box.size != Vector2.ZERO:
		return box
	var p := Q.pos(n, _root)
	return Rect2(p.x - 0.3, p.y - 0.3, 0.6, 0.6)

## Visible Sprite3D / AnimatedSprite3D under `n`, as world rects with their texture region.
func _sprites_of(n: Node) -> Array:
	var out: Array = []
	for c in Q.all_nodes(n):
		if not (c is SpriteBase3D):
			continue
		if c is Node3D and c.is_inside_tree() and not (c as Node3D).is_visible_in_tree():
			continue
		var tex: Texture2D = null
		var src := Rect2()
		if c is Sprite3D:
			var sp := c as Sprite3D
			tex = sp.texture
			if tex == null:
				continue
			src = Rect2(Vector2.ZERO, tex.get_size())
			if sp.region_enabled:
				src = sp.region_rect
			if sp.hframes > 1 or sp.vframes > 1:
				var fs := src.size / Vector2(sp.hframes, sp.vframes)
				src = Rect2(src.position + Vector2(sp.frame % sp.hframes, sp.frame / sp.hframes) * fs, fs)
		elif c is AnimatedSprite3D:
			var asp := c as AnimatedSprite3D
			if asp.sprite_frames == null or not asp.sprite_frames.has_animation(asp.animation):
				continue
			if asp.sprite_frames.get_frame_count(asp.animation) == 0:
				continue
			tex = asp.sprite_frames.get_frame_texture(asp.animation, 0)
			if tex == null:
				continue
			src = Rect2(Vector2.ZERO, tex.get_size())
		var sb := c as SpriteBase3D
		var xf := Q.xform_to_root(c, _root)
		var scale := Vector2(xf.basis.x.length(), xf.basis.y.length())
		var world_size := src.size * sb.pixel_size * scale
		var centre := Vector2(xf.origin.x, xf.origin.y) + Vector2(sb.offset.x, sb.offset.y) * sb.pixel_size * scale
		if not sb.centered:
			centre += world_size * Vector2(0.5, -0.5)
		out.append({
			"tex": tex, "src": src, "z": xf.origin.z, "flip": sb.flip_h,
			"modulate": sb.modulate,
			"rect": Rect2(centre - world_size * 0.5, world_size),
		})
	return out

func _resizable(n: Node) -> bool:
	var s: Variant = n.get("size")
	return s is Vector2 or s is Vector3

## Edge handles of a sized node: [{ edge: "l"/"r"/"t"/"b", pos: screen }]
func _handles(n: Node) -> Array:
	var r := world_rect_to_screen(_pick_rect(n))
	return [
		{ "edge": "l", "pos": Vector2(r.position.x, r.get_center().y) },
		{ "edge": "r", "pos": Vector2(r.end.x, r.get_center().y) },
		{ "edge": "t", "pos": Vector2(r.get_center().x, r.position.y) },
		{ "edge": "b", "pos": Vector2(r.get_center().x, r.end.y) },
	]

## Topmost object under a screen point (small objects win over platforms and zones).
func pick(screen: Vector2) -> Node:
	if not is_level(_root):
		return null
	if _objects.is_empty():
		_build_objects()
	var w := screen_to_world(screen)
	var best: Node = null
	var best_area := INF
	for o in _objects:
		var r: Rect2 = o.rect
		if o.kind == "kill":
			continue # select the kill zone from the Scene dock; it's fitted by "Fit"
		if r.grow(2.0 / _zoom).has_point(w):
			var area := r.get_area()
			if o.kind in ["platform", "ghost", "collapse", "trigger"]:
				area += 1e6 # prefer objects sitting on platforms
			if area < best_area:
				best_area = area
				best = o.node
	return best

# ── input ────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if not is_level(_root):
		return
	var mb := event as InputEventMouseButton
	var mm := event as InputEventMouseMotion
	var key := event as InputEventKey

	if mb:
		_mouse_world = screen_to_world(mb.position)
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15, mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_RIGHT and not _placing()):
			_drag = { "mode": "pan" } if mb.pressed else {}
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _placing():
			dock.cancel_placing()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_on_left_press(mb)
			else:
				_on_left_release()
		accept_event()
		queue_redraw()
	elif mm:
		_mouse_world = screen_to_world(mm.position)
		match _drag.get("mode", ""):
			"pan":
				_origin += mm.relative
			"move":
				_drag_move()
			"resize":
				_drag_resize()
			_:
				var h := pick(mm.position)
				if h != _hover:
					_hover = h
		_emit_status()
		queue_redraw()
	elif key and key.pressed and not key.echo:
		if key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
			delete_selected()
		elif key.keycode == KEY_D and key.is_command_or_control_pressed():
			duplicate_selected()
		elif key.keycode == KEY_ESCAPE:
			if _placing():
				dock.cancel_placing()
			else:
				_select([])
		elif key.keycode == KEY_F:
			frame_level()
		else:
			return
		accept_event()
		queue_redraw()

func _on_left_press(mb: InputEventMouseButton) -> void:
	if _placing():
		var node: Node = dock.place_armed_at(Vector3(_snap(_mouse_world).x, _snap(_mouse_world).y, 0.0))
		if node:
			_select([node])
		return
	# Resize handle of the selected node?
	for n in _selected():
		if n is Node and is_instance_valid(n) and _resizable(n):
			for h in _handles(n):
				if h.pos.distance_to(mb.position) <= handle_size:
					_drag = { "mode": "resize", "node": n, "edge": h.edge, "old_size": n.get("size"),
						"old_pos": (n as Node3D).position, "rect": _pick_rect(n) }
					return
	var hit := pick(mb.position)
	if hit == null:
		_select([])
		return
	_select([hit])
	_drag = { "mode": "move", "node": hit, "old_pos": (hit as Node3D).position,
		"start_world": _mouse_world, "start_node": Q.pos(hit, _root) }

func _drag_move() -> void:
	var n: Node3D = _drag.node
	var start: Vector3 = _drag.start_node
	var delta: Vector2 = _mouse_world - _drag.start_world
	var target := _snap(Vector2(start.x, start.y) + delta)
	_set_world_xy(n, target)

func _drag_resize() -> void:
	var n: Node3D = _drag.node
	var r: Rect2 = _drag.rect
	var w := _snap(_mouse_world)
	var left := r.position.x
	var right := r.end.x
	var bottom := r.position.y
	var top := r.end.y
	match _drag.edge:
		"l": left = minf(w.x, right - 0.1)
		"r": right = maxf(w.x, left + 0.1)
		"t": top = maxf(w.y, bottom + 0.1)
		"b": bottom = minf(w.y, top - 0.1)
	var old: Variant = _drag.old_size
	if old is Vector2:
		n.set("size", Vector2(right - left, top - bottom))
	else:
		n.set("size", Vector3(right - left, top - bottom, (old as Vector3).z))
	_set_world_xy(n, Vector2((left + right) * 0.5, (bottom + top) * 0.5))

func _on_left_release() -> void:
	var mode: String = _drag.get("mode", "")
	if mode == "move" or mode == "resize":
		var n: Node3D = _drag.node
		var new_pos := n.position
		var moved := not new_pos.is_equal_approx(_drag.old_pos)
		var resized: bool = mode == "resize" and n.get("size") != _drag.old_size
		if (moved or resized) and undo_redo:
			var new_size: Variant = n.get("size")
			# Put the old values back, then let the action apply the new ones (clean undo).
			n.position = _drag.old_pos
			if resized:
				n.set("size", _drag.old_size)
			undo_redo.create_action(("Resize %s" if resized else "Move %s") % n.name, UndoRedo.MERGE_DISABLE, _root)
			undo_redo.add_do_property(n, &"position", new_pos)
			undo_redo.add_undo_property(n, &"position", _drag.old_pos)
			if resized:
				undo_redo.add_do_property(n, &"size", new_size)
				undo_redo.add_undo_property(n, &"size", _drag.old_size)
			undo_redo.commit_action()
	_drag.clear()

## Places `n` so its origin sits at world `p` (converts through its parent's transform).
func _set_world_xy(n: Node3D, p: Vector2) -> void:
	var parent_xf := Q.xform_to_root(n.get_parent(), _root) if n.get_parent() != _root else Transform3D.IDENTITY
	var world := Vector3(p.x, p.y, Q.pos(n, _root).z)
	n.position = parent_xf.affine_inverse() * world

# ── edit commands ────────────────────────────────────────────────────────

func delete_selected() -> void:
	for n in _selected():
		if not (n is Node) or not is_instance_valid(n) or n == _root or not _root.is_ancestor_of(n):
			continue
		if n.name in ["Geometry", "GhostPlatforms", "Decor", "Hints"]:
			continue
		var parent: Node = n.get_parent()
		var owned: Array[Node] = []
		for d in Q.all_nodes(n):
			if d != n and d.owner == _root:
				owned.append(d)
		if undo_redo == null:
			parent.remove_child(n)
			n.queue_free()
			continue
		undo_redo.create_action("Delete %s" % n.name, UndoRedo.MERGE_DISABLE, _root)
		undo_redo.add_do_method(parent, &"remove_child", n)
		undo_redo.add_undo_method(parent, &"add_child", n)
		undo_redo.add_undo_method(parent, &"move_child", n, n.get_index())
		undo_redo.add_undo_method(n, &"set_owner", _root)
		for d in owned:
			undo_redo.add_undo_method(d, &"set_owner", _root)
		undo_redo.add_undo_reference(n)
		undo_redo.commit_action()
	_select([])

## Copies the selected object one grid step to the right (instanced scenes are re-instanced
## and keep their settings; ghost platforms rebuild their segments).
func duplicate_selected() -> void:
	var made: Array = []
	for n in _selected():
		if not (n is Node3D) or n == _root or not _root.is_ancestor_of(n):
			continue
		var src := n as Node3D
		var copy: Node3D
		if not src.scene_file_path.is_empty():
			copy = (load(src.scene_file_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
			for p in src.get_property_list():
				if p.usage & PROPERTY_USAGE_STORAGE and not (p.name in ["owner", "name", "script", "scene_file_path", "unique_name_in_owner"]):
					copy.set(p.name, src.get(p.name))
		else:
			copy = src.duplicate() as Node3D
		var base := String(src.name).rstrip("0123456789")
		copy.name = P.unique_name(base if not base.is_empty() else "Node", _root)
		var step := _grid() if _grid() > 0.0 else 1.0
		copy.position = src.position + Vector3(step * 2.0, 0, 0)
		var parent := src.get_parent()
		if undo_redo == null:
			parent.add_child(copy)
			copy.owner = _root
		else:
			undo_redo.create_action("Duplicate %s" % src.name, UndoRedo.MERGE_DISABLE, _root)
			undo_redo.add_do_method(parent, &"add_child", copy, true)
			undo_redo.add_do_method(copy, &"set_owner", _root)
			if copy.has_method(&"regenerate_segments"):
				undo_redo.add_do_method(copy, &"regenerate_segments")
			undo_redo.add_do_reference(copy)
			undo_redo.add_undo_method(parent, &"remove_child", copy)
			undo_redo.commit_action()
		made.append(copy)
	if not made.is_empty():
		_select(made)

# ── helpers ──────────────────────────────────────────────────────────────

func _placing() -> bool:
	return dock != null and dock.has_method(&"is_placing") and dock.is_placing()

func _grid() -> float:
	if dock and dock.get("snap_enabled") and dock.get("grid_size") != null:
		return float(dock.get("grid_size"))
	return 0.0

func _snap(p: Vector2) -> Vector2:
	var g := _grid()
	if g <= 0.0:
		return p
	return Vector2(snappedf(p.x, g), snappedf(p.y, g))

func _selected() -> Array:
	if Engine.is_editor_hint() and dock != null:
		return EditorInterface.get_selection().get_top_selected_nodes()
	return _selected_override

func _select(nodes: Array) -> void:
	if Engine.is_editor_hint() and dock != null:
		var sel := EditorInterface.get_selection()
		sel.clear()
		for n in nodes:
			sel.add_node(n)
		if nodes.size() == 1:
			EditorInterface.edit_node(nodes[0])
	else:
		_selected_override = nodes
	queue_redraw()

func _emit_status() -> void:
	# Fixed width so the bar doesn't jump while the mouse moves.
	status_changed.emit("x %8.2f    y %8.2f" % [_mouse_world.x, _mouse_world.y])

func _w3(v: Vector3) -> Vector2:
	return world_to_screen(Vector2(v.x, v.y))

func _text(pos: Vector2, t: String, col: Color, font_size: int = 12) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.75))
	draw_string(font, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

func _dashed(a: Vector2, b: Vector2, col: Color, dash: float = 6.0) -> void:
	draw_dashed_line(a, b, col, 1.0, dash)

func _dashed_rect(r: Rect2, col: Color) -> void:
	_dashed(r.position, Vector2(r.end.x, r.position.y), col)
	_dashed(Vector2(r.end.x, r.position.y), r.end, col)
	_dashed(r.end, Vector2(r.position.x, r.end.y), col)
	_dashed(Vector2(r.position.x, r.end.y), r.position, col)
