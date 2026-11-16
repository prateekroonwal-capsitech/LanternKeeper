@tool
class_name LevelOverlays
extends RefCounted

## LevelOverlays — Editor-only drawings over the open level (Prompts 5 and 6):
##   links: a line between pieces sharing an id, one colour per id;
##   light: lantern circle (base_radius; dotted × raise_radius_multiplier in oil levels), each hook's
##          HookPoint (the level lantern's radius), shrine sanctuary_radius; ghost segments in light filled;
##   jump:  from the selected platform's top edges, the arc the child can reach, computed from the
##          level's Player exports (run_speed, jump_velocity, gravity, fall_gravity_multiplier, coyote_time);
##   paths: hook travel_offset rails, rope swing arcs, crate min_x…max_x, LanternHook reach boxes.
## Geometry is built as plain data (build()) and drawn into one unowned MeshInstance3D that is an
## internal child of the edited scene root, so nothing is ever saved into the level.
##
## Sends: nothing (draws only).
## Receives: build()/render() calls from LevelEditorDock (on edits, selection and toggles).

const Q = preload("res://addons/level_editor/level_query.gd")
const L = preload("res://addons/level_editor/level_links.gd")
const PLAYER_SCENE := "res://game/scenes/gameplay/actors/Player.tscn"
const OVERLAY_META := &"_level_editor_overlay"

const COL_LIGHT := Color(1.0, 0.85, 0.35, 0.9)
const COL_HOOK_LIGHT := Color(1.0, 0.7, 0.25, 0.75)
const COL_SANCTUARY := Color(0.55, 0.85, 1.0, 0.85)
const COL_LIT_FILL := Color(1.0, 0.85, 0.35, 0.35)
const COL_JUMP := Color(0.4, 1.0, 0.5, 0.95)
const COL_JUMP_COYOTE := Color(0.4, 1.0, 0.5, 0.4)
const COL_PATH := Color(0.85, 0.55, 1.0, 0.9)
const COL_REACH := Color(1.0, 1.0, 1.0, 0.45)

## Player jump numbers from the level's Player node (its overrides), else Player.tscn defaults.
static func jump_params(root: Node) -> Dictionary:
	var player: Node = null
	var temp: Node = null
	var found: Array[Node] = []
	if root:
		found = Q.find_class(root, "Player")
	if not found.is_empty():
		player = found[0]
	else:
		var ps := load(PLAYER_SCENE) as PackedScene
		if ps:
			temp = ps.instantiate()
			player = temp
	var d := {
		"run_speed": 5.2, "jump_velocity": 10.8, "gravity": 27.0,
		"fall_gravity_multiplier": 1.35, "coyote_time": 0.12, "max_fall_speed": 20.0,
	}
	if player:
		for k in d.keys():
			var v: Variant = player.get(k)
			if v != null:
				d[k] = float(v)
	if temp:
		temp.free()
	return d

## Peak height and same-height jump distance for the params (no coyote time).
static func jump_reach(p: Dictionary) -> Dictionary:
	var g_up: float = maxf(p.gravity, 0.01)
	var g_down: float = g_up * maxf(p.fall_gravity_multiplier, 0.01)
	var t_up: float = p.jump_velocity / g_up
	var h: float = p.jump_velocity * p.jump_velocity / (2.0 * g_up)
	var t_down := sqrt(2.0 * h / g_down)
	return { "height": h, "distance": p.run_speed * (t_up + t_down), "t_up": t_up }

## Jump arc points from `start` going `dir` (+1 / −1) until `drop` metres below the start.
static func jump_arc(p: Dictionary, start: Vector2, dir: float, drop: float, steps: int = 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var g_up: float = maxf(p.gravity, 0.01)
	var g_down: float = g_up * maxf(p.fall_gravity_multiplier, 0.01)
	var dt := 1.0 / 60.0
	var x := start.x
	var y := start.y
	var vy: float = p.jump_velocity
	pts.append(start)
	for i in 600:
		var g := g_up if vy > 0.0 else g_down
		vy = maxf(vy - g * dt, -p.max_fall_speed)
		x += dir * p.run_speed * dt
		y += vy * dt
		if i % maxi(1, 600 / steps / 4) == 0:
			pts.append(Vector2(x, y))
		if y < start.y - drop:
			break
	pts.append(Vector2(x, y))
	return pts

## Builds all enabled overlays. opts: { links, light, jump, paths: bool, jump_drop: float }
## Returns { lines: PackedVector3Array, line_colors: PackedColorArray, tris: PackedVector3Array, tri_colors }
static func build(root: Node, opts: Dictionary, selected: Array) -> Dictionary:
	var d := { "lines": PackedVector3Array(), "line_colors": PackedColorArray(),
		"tris": PackedVector3Array(), "tri_colors": PackedColorArray() }
	if root == null:
		return d
	if opts.get("links", false):
		_build_links(root, d)
	if opts.get("light", false):
		_build_light(root, d)
	if opts.get("jump", false):
		_build_jump(root, d, selected, float(opts.get("jump_drop", 6.0)))
	if opts.get("paths", false):
		_build_paths(root, d)
	return d

static func _build_links(root: Node, d: Dictionary) -> void:
	var by_ch := L.ids_by_channel(root)
	for ch: String in by_ch.keys():
		for id: String in by_ch[ch].keys():
			var entries: Array = by_ch[ch][id]
			var col := L.id_color(ch, id)
			var senders: Array = entries.filter(func(e: Dictionary) -> bool: return e.role == L.SEND)
			var listeners: Array = entries.filter(func(e: Dictionary) -> bool: return e.role == L.LISTEN)
			if senders.is_empty() or listeners.is_empty():
				for i in range(1, entries.size()):
					_line(d, _anchor(entries[i - 1].node, root), _anchor(entries[i].node, root), col)
				continue
			for s: Dictionary in senders:
				for l: Dictionary in listeners:
					if s.node != l.node:
						_line(d, _anchor(s.node, root), _anchor(l.node, root), col)
						_cross(d, _anchor(l.node, root), 0.25, col)

static func _build_light(root: Node, d: Dictionary) -> void:
	var radius := Q.lantern_radius(root)
	var oil := Q.is_oil_level(root)
	var circles: Array = [] # [centre Vector3, radius]
	for lantern in Q.find_class(root, "Lantern"):
		var c := Q.pos(lantern, root)
		var r := float(lantern.get("base_radius"))
		_circle(d, c, r, COL_LIGHT, false)
		circles.append([c, r])
		if oil:
			_circle(d, c, r * float(lantern.get("raise_radius_multiplier")), COL_LIGHT, true)
	for hook in Q.find_class(root, "LanternHook"):
		var hp := Q.hook_point(hook, root)
		_circle(d, hp, radius, COL_HOOK_LIGHT, false)
		circles.append([hp, radius])
	for shrine in Q.find_class(root, "Shrine"):
		var sr := float(shrine.get("sanctuary_radius"))
		if sr > 0.0:
			_circle(d, Q.pos(shrine, root), sr, COL_SANCTUARY, false)
	# Ghost segments inside a circle drawn filled (same test as GhostPlatform: top centre, padded).
	for ghost in Q.find_class(root, "GhostPlatform"):
		for seg in ghost.get_children():
			if not (seg is StaticBody3D and String(seg.name).begins_with("Segment")):
				continue
			var col := seg.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if col == null or not (col.shape is BoxShape3D):
				continue
			var size := (col.shape as BoxShape3D).size
			var sp := Q.pos(seg, root)
			var top := Vector3(sp.x, sp.y + size.y * 0.5, 0.0)
			for c in circles:
				var dx: float = top.x - c[0].x
				var dy: float = top.y - c[0].y
				var rr: float = c[1] + size.x * 0.5
				if dx * dx + dy * dy <= rr * rr:
					_rect_fill(d, Rect2(sp.x - size.x * 0.5, sp.y - size.y * 0.5, size.x, size.y), COL_LIT_FILL)
					break

static func _build_jump(root: Node, d: Dictionary, selected: Array, drop: float) -> void:
	var p := jump_params(root)
	var reach := jump_reach(p)
	for node in selected:
		if not (node is Node) or node.get("size") == null or not (node.get("size") is Vector2):
			continue
		var rect := Q.rect_xy(node, root)
		var top := rect.end.y
		for side in [-1.0, 1.0]:
			var edge := Vector2(rect.position.x if side < 0.0 else rect.end.x, top)
			_polyline(d, jump_arc(p, edge, side, drop), COL_JUMP)
			var coyote := edge + Vector2(side * p.run_speed * p.coyote_time, 0.0)
			_polyline(d, jump_arc(p, coyote, side, drop), COL_JUMP_COYOTE)
			# Same-height landing mark and peak height mark.
			var land := edge + Vector2(side * reach.distance, 0.0)
			_cross(d, Vector3(land.x, land.y, 0.0), 0.3, COL_JUMP)
		var peak_y: float = top + reach.height
		_line(d, Vector3(rect.position.x, peak_y, 0.0), Vector3(rect.end.x, peak_y, 0.0), COL_JUMP)

static func _build_paths(root: Node, d: Dictionary) -> void:
	for hook in Q.find_class(root, "LanternHook"):
		var off: Variant = hook.get("travel_offset")
		var hp := Q.hook_point(hook, root)
		if off is Vector3 and (off as Vector3).length() > 0.01:
			_line(d, hp, hp + off, COL_PATH)
			_cross(d, hp + off, 0.35, COL_PATH)
		var reach := Q.shape_rect(hook, root)
		if reach.size != Vector2.ZERO:
			_rect_outline(d, reach, COL_REACH)
	for rope in Q.find_class(root, "Rope"):
		var pivot := Q.pos(rope, root)
		var length := float(rope.get("length"))
		var swing := deg_to_rad(float(rope.get("swing_degrees")))
		var pts := PackedVector2Array()
		for i in 25:
			var a := lerpf(-swing, swing, i / 24.0)
			pts.append(Vector2(pivot.x + sin(a) * length, pivot.y - cos(a) * length))
		_polyline(d, pts, COL_PATH)
		_line(d, pivot, Vector3(pts[0].x, pts[0].y, 0.0), COL_PATH)
		_line(d, pivot, Vector3(pts[24].x, pts[24].y, 0.0), COL_PATH)
	for crate in Q.find_class(root, "Crate"):
		var mn := float(crate.get("min_x"))
		var mx := float(crate.get("max_x"))
		if mn <= -999.0 and mx >= 999.0:
			continue # unlimited (defaults)
		var cp := Q.pos(crate, root)
		_line(d, Vector3(mn, cp.y, 0.0), Vector3(mx, cp.y, 0.0), COL_PATH)
		_line(d, Vector3(mn, cp.y - 0.4, 0.0), Vector3(mn, cp.y + 0.4, 0.0), COL_PATH)
		_line(d, Vector3(mx, cp.y - 0.4, 0.0), Vector3(mx, cp.y + 0.4, 0.0), COL_PATH)

# ── primitives (all on the z = 0 plane, level-root space) ────────────────

static func _anchor(node: Node, root: Node) -> Vector3:
	var p := Q.pos(node, root)
	return Vector3(p.x, p.y + 0.6, 0.0)

static func _line(d: Dictionary, a: Vector3, b: Vector3, col: Color) -> void:
	d.lines.append(Vector3(a.x, a.y, 0.0))
	d.lines.append(Vector3(b.x, b.y, 0.0))
	d.line_colors.append(col)
	d.line_colors.append(col)

static func _polyline(d: Dictionary, pts: PackedVector2Array, col: Color) -> void:
	for i in range(1, pts.size()):
		_line(d, Vector3(pts[i - 1].x, pts[i - 1].y, 0.0), Vector3(pts[i].x, pts[i].y, 0.0), col)

static func _cross(d: Dictionary, c: Vector3, s: float, col: Color) -> void:
	_line(d, c + Vector3(-s, -s, 0), c + Vector3(s, s, 0), col)
	_line(d, c + Vector3(-s, s, 0), c + Vector3(s, -s, 0), col)

static func _circle(d: Dictionary, c: Vector3, r: float, col: Color, dotted: bool) -> void:
	if r <= 0.0:
		return
	var n := 72
	for i in n:
		if dotted and i % 2 == 1:
			continue
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		_line(d, c + Vector3(cos(a0), sin(a0), 0) * r, c + Vector3(cos(a1), sin(a1), 0) * r, col)

static func _rect_outline(d: Dictionary, r: Rect2, col: Color) -> void:
	var a := Vector3(r.position.x, r.position.y, 0)
	var b := Vector3(r.end.x, r.position.y, 0)
	var c := Vector3(r.end.x, r.end.y, 0)
	var e := Vector3(r.position.x, r.end.y, 0)
	_line(d, a, b, col)
	_line(d, b, c, col)
	_line(d, c, e, col)
	_line(d, e, a, col)

static func _rect_fill(d: Dictionary, r: Rect2, col: Color) -> void:
	var a := Vector3(r.position.x, r.position.y, 0)
	var b := Vector3(r.end.x, r.position.y, 0)
	var c := Vector3(r.end.x, r.end.y, 0)
	var e := Vector3(r.position.x, r.end.y, 0)
	for v in [a, b, c, a, c, e]:
		d.tris.append(v)
		d.tri_colors.append(col)

# ── rendering ────────────────────────────────────────────────────────────

## Draws `data` into the overlay mesh under `root` (created on first use, never saved).
static func render(root: Node, data: Dictionary) -> void:
	if root == null:
		return
	var mi := get_overlay(root, true)
	var mesh := mi.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var lines: PackedVector3Array = data.get("lines", PackedVector3Array())
	var tris: PackedVector3Array = data.get("tris", PackedVector3Array())
	if not tris.is_empty():
		var tc: PackedColorArray = data.tri_colors
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in tris.size():
			mesh.surface_set_color(tc[i])
			mesh.surface_add_vertex(tris[i])
		mesh.surface_end()
	if not lines.is_empty():
		var lc: PackedColorArray = data.line_colors
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in lines.size():
			mesh.surface_set_color(lc[i])
			mesh.surface_add_vertex(lines[i])
		mesh.surface_end()

## Removes the overlay mesh from `root` (e.g. when every overlay is switched off).
static func clear(root: Node) -> void:
	var mi := get_overlay(root, false)
	if mi:
		mi.get_parent().remove_child(mi)
		mi.queue_free()

static func get_overlay(root: Node, create: bool) -> MeshInstance3D:
	if root == null:
		return null
	for c in root.get_children(true):
		if c.has_meta(OVERLAY_META):
			return c as MeshInstance3D
	if not create:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "_LevelEditorOverlay"
	mi.set_meta(OVERLAY_META, true)
	mi.mesh = ImmediateMesh.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	mi.material_override = mat
	# Internal child: not listed by get_children(), not shown in the Scene dock, never saved.
	root.add_child(mi, false, Node.INTERNAL_MODE_BACK)
	return mi
