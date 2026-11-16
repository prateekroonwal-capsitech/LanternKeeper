@tool
class_name LevelValidator
extends RefCounted

## LevelValidator — Read-only checks that catch broken levels before playing (Prompt 7).
## Never changes the scene. Works on the open level and on catalog levels instanced off-tree.
##
## Sends: nothing (returns issue lists).
## Receives: validate() / validate_all() calls from LevelEditorDock and headless tests.

const Q = preload("res://addons/level_editor/level_query.gd")
const L = preload("res://addons/level_editor/level_links.gd")
const Fit = preload("res://addons/level_editor/level_fit.gd")

const ERROR := "error"
const WARNING := "warning"
const DEFAULT_CATALOG_PATH := "res://game/resources/level_catalog.tres"
const DEFAULT_STRINGS_CSV := "res://game/assets/localization/strings.csv"
const TUTORIAL_MANAGER := "res://game/scripts/managers/TutorialManager.gd"

## Tunables for the warnings (the dock passes its settings).
const DEFAULT_OPTS := {
	"max_checkpoint_gap": 30.0,   # m from the last spawn/shrine to an enemy or dark section
	"plane_tolerance": 0.05,      # m off z = 0 before warning
	"carry_height": 0.64,         # lantern height above a floor while carried
	"wall_min_height": 4.0,
	"wall_tolerance": 1.0,
}

## Issues for one level: [{ severity, message, node_path: String ("" = level root), scene_path }]
static func validate(root: Node, scene_path: String = "", opts: Dictionary = {}) -> Array[Dictionary]:
	var o := DEFAULT_OPTS.duplicate()
	o.merge(opts, true)
	var out: Array[Dictionary] = []
	if root != null and scene_path.is_empty():
		scene_path = root.scene_file_path
	if root == null or root.get("level_id") == null:
		_add(out, ERROR, "Scene root is not a LevelRoot.", root, root, scene_path)
		return out
	_check_spawn(root, out, scene_path)
	_check_required(root, out, scene_path)
	_check_identity(root, out, scene_path)
	_check_links(root, out, scene_path)
	_check_hints(root, out, scene_path)
	_check_ghost_segments(root, out, scene_path)
	_warn_checkpoints(root, out, scene_path, o)
	_warn_ghost_light(root, out, scene_path, o)
	_warn_rope(root, out, scene_path)
	_warn_plane(root, out, scene_path, o)
	_warn_walls(root, out, scene_path, o)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.severity == ERROR and b.severity != ERROR)
	return out

## Validates every level in the catalog. Returns { scene_path: issues }.
static func validate_all(catalog_path: String = DEFAULT_CATALOG_PATH, opts: Dictionary = {}) -> Dictionary:
	var results := {}
	var catalog := load(catalog_path)
	if catalog == null:
		return results
	for path: String in catalog.get("level_paths"):
		if path.is_empty():
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			results[path] = [{ "severity": ERROR, "message": "Can't load scene.", "node_path": "", "scene_path": path }]
			continue
		var root := ps.instantiate()
		results[path] = validate(root, path, opts)
		root.free()
	return results

# ── errors ───────────────────────────────────────────────────────────────

static func _check_spawn(root: Node, out: Array[Dictionary], sp: String) -> void:
	var spawns: Array[Node] = []
	for n in Q.all_nodes(root):
		if n != root and n is Marker3D and String(n.name).begins_with("SpawnPoint"):
			spawns.append(n)
	if spawns.is_empty():
		_add(out, ERROR, "No SpawnPoint.", root, root, sp)
	elif spawns.size() > 1:
		for s in spawns:
			_add(out, ERROR, "More than one SpawnPoint (%d)." % spawns.size(), s, root, sp)
	if root.get("spawn_point") == null:
		_add(out, ERROR, "LevelRoot.spawn_point is not set.", root, root, sp)

static func _check_required(root: Node, out: Array[Dictionary], sp: String) -> void:
	if Q.find_class(root, "ExitPortal").is_empty() and Q.find_class(root, "LevelExit").is_empty():
		_add(out, ERROR, "No ExitPortal.", root, root, sp)
	if Q.find_class(root, "KillZone").is_empty():
		_add(out, ERROR, "No KillZone.", root, root, sp)

static func _check_identity(root: Node, out: Array[Dictionary], sp: String) -> void:
	var file := sp.get_file()
	var m := RegEx.create_from_string("^W(\\d+)_(\\d{2})\\.tscn$").search(file)
	if m == null:
		_add(out, ERROR, "File name '%s' is not W<world>_<##>.tscn." % file, root, root, sp)
	else:
		var w := m.get_string(1).to_int()
		var expected_id := "w%d_%02d" % [w, m.get_string(2).to_int()]
		if str(root.get("level_id")) != expected_id:
			_add(out, ERROR, "level_id is '%s', file name says '%s'." % [root.get("level_id"), expected_id], root, root, sp)
		if int(root.get("world")) != w:
			_add(out, ERROR, "world is %d, file name says %d." % [int(root.get("world")), w], root, root, sp)
	var catalog := load(DEFAULT_CATALOG_PATH)
	if catalog and not (sp in PackedStringArray(catalog.get("level_paths"))):
		_add(out, ERROR, "Level is not in the catalog (Rebuild Catalog).", root, root, sp)
	var key := str(root.get("title_key"))
	if key.is_empty():
		_add(out, ERROR, "title_key is empty.", root, root, sp)
	elif not _csv_keys().has(key):
		_add(out, ERROR, "title_key '%s' is missing from strings.csv." % key, root, root, sp)

static func _check_links(root: Node, out: Array[Dictionary], sp: String) -> void:
	var by_ch := L.ids_by_channel(root)
	# Gates and other lever listeners need a sender; hooks / levers / plates need a listener.
	for ch: String in ["hook", "lever"]:
		for id: String in by_ch[ch].keys():
			var entries: Array = by_ch[ch][id]
			var has_send := entries.any(func(e: Dictionary) -> bool: return e.role == L.SEND)
			var has_listen := entries.any(func(e: Dictionary) -> bool: return e.role == L.LISTEN)
			for e: Dictionary in entries:
				if e.role == L.LISTEN and not has_send:
					if _gate_hook_default(e):
						continue
					_add(out, ERROR, "%s.%s = '%s' but no %s uses it." % [e.node.name, e.field, id,
						"hook" if ch == "hook" else "lever or plate"], e.node, root, sp)
				elif e.role == L.SEND and not has_listen and not _sender_has_own_use(e):
					_add(out, ERROR, "%s.%s = '%s' but nothing listens for it." % [e.node.name, e.field, id], e.node, root, sp)
	# Enemies need something that wakes them (wake_distance > 0 needs none).
	var wake: Dictionary = by_ch["wake"]
	for enemy in Q.find_class(root, "Enemy"):
		if float(enemy.get("wake_distance")) > 0.0:
			continue
		var group := str(enemy.get("wake_group"))
		if Q.has_class(enemy, "BigShadow") and group.is_empty():
			group = "chase" # BigShadow's runtime default
		if Q.has_class(enemy, "Shade"):
			continue # woken through its encounter groups (checked below)
		if group.is_empty():
			_add(out, ERROR, "%s has no wake_group and wake_distance 0: it never wakes." % enemy.name, enemy, root, sp)
		elif not _group_has_sender(wake, group):
			_add(out, ERROR, "%s.wake_group '%s': nothing wakes it (WakeTrigger, wake_group_on_hang, wake_group_on_grab)." % [enemy.name, group], enemy, root, sp)
	for shade in Q.find_class(root, "Shade"):
		for f in ["run_group", "trap_group", "hide_group", "final_group"]:
			var g := str(shade.get(f))
			if not g.is_empty() and not _group_has_sender(wake, g):
				_add(out, ERROR, "%s.%s '%s': no trigger wakes it." % [shade.name, f, g], shade, root, sp)
	for tt in Q.find_class(root, "TutorialTrigger"):
		var g := str(tt.get("on_wake_group"))
		if not g.is_empty() and not _group_has_sender(wake, g):
			_add(out, ERROR, "%s.on_wake_group '%s': nothing wakes that group." % [tt.name, g], tt, root, sp)

static func _check_hints(root: Node, out: Array[Dictionary], sp: String) -> void:
	var hints := _hint_ids()
	for tt in Q.find_class(root, "TutorialTrigger"):
		var id := str(tt.get("hint_id"))
		if not hints.has(id):
			_add(out, ERROR, "%s.hint_id '%s' is not in TutorialManager.HINTS." % [tt.name, id], tt, root, sp)

static func _check_ghost_segments(root: Node, out: Array[Dictionary], sp: String) -> void:
	for ghost in Q.find_class(root, "GhostPlatform"):
		var size: Vector2 = ghost.get("size")
		var seg_len := float(ghost.get("segment_length"))
		var depth := float(ghost.get("depth"))
		var count: int = maxi(1, int(roundf(size.x / maxf(seg_len, 0.1))))
		var seg_w := size.x / float(count)
		var segs: Array[Node] = []
		for c in ghost.get_children():
			if c is StaticBody3D and String(c.name).begins_with("Segment"):
				segs.append(c)
		if segs.size() != count:
			_add(out, ERROR, "%s has %d Segment nodes, its size needs %d (resize it to rebuild)." % [ghost.name, segs.size(), count], ghost, root, sp)
			continue
		for s in segs:
			var col := s.get_node_or_null("CollisionShape3D") as CollisionShape3D
			var box := col.shape as BoxShape3D if col else null
			if box == null or not box.size.is_equal_approx(Vector3(seg_w, size.y, depth)):
				_add(out, ERROR, "%s/%s size doesn't match the platform's size." % [ghost.name, s.name], s, root, sp)
				break

# ── warnings ─────────────────────────────────────────────────────────────

## Enemies and dark sections (a hook that opens a gate = the light stays behind; a rope)
## further than max_checkpoint_gap from the last spawn point / shrine before them.
static func _warn_checkpoints(root: Node, out: Array[Dictionary], sp: String, o: Dictionary) -> void:
	var checkpoints: Array[float] = []
	var spawn := root.get("spawn_point") as Node
	if spawn:
		checkpoints.append(Q.pos(spawn, root).x)
	for s in Q.find_class(root, "Shrine"):
		checkpoints.append(Q.pos(s, root).x)
	var gate_hooks := {}
	for g in Q.find_class(root, "Gate"):
		gate_hooks[str(g.get("hook_id"))] = true
	var subjects: Array = []
	for e in Q.find_class(root, "Enemy"):
		if Q.has_class(e, "Shade"):
			continue # starts off-screen; each encounter has its own shrine + trigger
		subjects.append([e, "Enemy"])
	for h in Q.find_class(root, "LanternHook"):
		if gate_hooks.has(str(h.get("hook_id"))):
			subjects.append([h, "Dark section (lantern left on hook)"])
	for r in Q.find_class(root, "Rope"):
		subjects.append([r, "Dark section (rope)"])
	for s in subjects:
		var x := Q.pos(s[0], root).x
		var best := -INF
		for c in checkpoints:
			if c <= x + 0.5:
				best = maxf(best, c)
		if best == -INF:
			_add(out, WARNING, "%s %s has no shrine before it." % [s[1], s[0].name], s[0], root, sp)
		elif x - best > float(o.max_checkpoint_gap):
			_add(out, WARNING, "%s %s is %.0f m past the last shrine/spawn." % [s[1], s[0].name, x - best], s[0], root, sp)

## A ghost platform that no lantern spot can light: the lantern's start, any hook (and rail end),
## or the lantern carried over any other floor.
static func _warn_ghost_light(root: Node, out: Array[Dictionary], sp: String, o: Dictionary) -> void:
	var radius := Q.lantern_radius(root)
	if Q.is_oil_level(root):
		for l in Q.find_class(root, "Lantern"):
			radius *= float(l.get("raise_radius_multiplier"))
			break
	var fixed: Array[Vector2] = []
	for l in Q.find_class(root, "Lantern"):
		var p := Q.pos(l, root)
		fixed.append(Vector2(p.x, p.y))
	for h in Q.find_class(root, "LanternHook"):
		var hp := Q.hook_point(h, root)
		fixed.append(Vector2(hp.x, hp.y))
		var off: Variant = h.get("travel_offset")
		if off is Vector3:
			fixed.append(Vector2(hp.x + off.x, hp.y + off.y))
	var floors := Q.platforms(root)
	for ghost in Q.find_class(root, "GhostPlatform"):
		var gr := Q.rect_xy(ghost, root)
		var spots := fixed.duplicate()
		for f in floors:
			if f == ghost:
				continue
			var fr := Q.rect_xy(f, root)
			var x := fr.position.x
			while x <= fr.end.x + 0.01:
				spots.append(Vector2(x, fr.end.y + float(o.carry_height)))
				x += 0.5
		var lit := false
		for s: Vector2 in spots:
			# Closest point of the ghost's top edge to the light.
			var cx := clampf(s.x, gr.position.x, gr.end.x)
			if Vector2(cx, gr.end.y).distance_to(s) <= radius + 0.2:
				lit = true
				break
		if not lit:
			_add(out, WARNING, "%s: no lantern spot, hook or rail can light it." % ghost.name, ghost, root, sp)

## A rope takes both hands, so the lantern stays behind; light-only paths after it need a
## lever / rail that brings the lantern over.
static func _warn_rope(root: Node, out: Array[Dictionary], sp: String) -> void:
	for rope in Q.find_class(root, "Rope"):
		var rx := Q.pos(rope, root).x
		var needs_light := false
		for g in Q.find_class(root, "GhostPlatform"):
			if Q.pos(g, root).x > rx + 1.0:
				needs_light = true
		if not needs_light:
			continue
		var brought := false
		for h in Q.find_class(root, "LanternHook"):
			var off: Variant = h.get("travel_offset")
			var has_rail: bool = off is Vector3 and (str(h.get("lever_id")) != "" or bool(h.get("move_when_hung")))
			if has_rail and Q.hook_point(h, root).x + (off as Vector3).x > rx:
				brought = true
		if not brought:
			_add(out, WARNING, "%s: the lantern is left behind (rope needs both hands) and no lever/rail brings it past, but ghost platforms after it need light." % rope.name, rope, root, sp)

static func _warn_plane(root: Node, out: Array[Dictionary], sp: String, o: Dictionary) -> void:
	for n in Q.gameplay_nodes(root):
		# The Lantern sits a few cm in front on purpose (draw order); it is axis-locked in play.
		if not (n is Node3D) or Q.has_class(n, "Lantern"):
			continue
		var z := Q.pos(n, root).z
		if absf(z) > float(o.plane_tolerance):
			_add(out, WARNING, "%s is off the z = 0 plane (z = %.2f)." % [n.name, z], n, root, sp)

static func _warn_walls(root: Node, out: Array[Dictionary], sp: String, o: Dictionary) -> void:
	if Q.platforms(root).is_empty():
		return
	for msg in Fit.wall_reports(root, Fit.platform_bounds(root), float(o.wall_min_height), float(o.wall_tolerance)):
		_add(out, WARNING, msg, root, root, sp)

# ── helpers ──────────────────────────────────────────────────────────────

static func _group_has_sender(wake: Dictionary, group: String) -> bool:
	if not wake.has(group):
		return false
	return (wake[group] as Array).any(func(e: Dictionary) -> bool: return e.role == L.SEND)

## A gate still on the scene default hook_id ("hook_a") but opened another way (lever / defeat)
## is not a broken link.
static func _gate_hook_default(e: Dictionary) -> bool:
	if e.field != "hook_id" or not Q.has_class(e.node, "Gate"):
		return false
	return str(e.node.get("lever_id")) != "" or str(e.node.get("open_on_defeat")) != ""

## A hook whose id nothing listens to is still useful when it is a lift/rail (it carries the lantern).
static func _sender_has_own_use(e: Dictionary) -> bool:
	if not Q.has_class(e.node, "LanternHook") or e.field != "hook_id":
		return false
	var off: Variant = e.node.get("travel_offset")
	return bool(e.node.get("move_when_hung")) or str(e.node.get("lever_id")) != "" \
		or str(e.node.get("wake_group_on_hang")) != "" or (off is Vector3 and (off as Vector3).length() > 0.01)

static func _hint_ids() -> Dictionary:
	var s := load(TUTORIAL_MANAGER) as Script
	if s == null:
		return {}
	return s.get_script_constant_map().get("HINTS", {})

static func _csv_keys() -> Dictionary:
	var keys := {}
	var f := FileAccess.open(DEFAULT_STRINGS_CSV, FileAccess.READ)
	if f == null:
		return keys
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > 0 and not row[0].is_empty():
			keys[row[0]] = true
	return keys

static func _add(out: Array[Dictionary], severity: String, message: String, node: Node, root: Node, sp: String) -> void:
	var path := ""
	if node != null and root != null and node != root:
		path = str(root.get_path_to(node))
	out.append({ "severity": severity, "message": message, "node_path": path, "scene_path": sp })
