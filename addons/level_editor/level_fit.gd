@tool
class_name LevelFit
extends RefCounted

## LevelFit — Fits the level's safety net to what is placed (Prompt 4, "Fit level").
## Only touches the root `KillZone` (position + size) and `LevelRoot.kill_y`. Never moves or
## scales placed objects, the camera or the Backdrop. Reports (doesn't fix) missing end walls
## and the level running past the Backdrop panels.
##
## Sends: undoable property changes through EditorUndoRedoManager (or direct sets when none).
## Receives: compute()/apply() calls from LevelEditorDock and LevelEditorPlugin (fit on save).

const Q = preload("res://addons/level_editor/level_query.gd")

## Computes the fit without changing anything. Returns:
## { ok, error, bounds: Rect2, kill_y_old, kill_y_new, kill_pos_old, kill_pos_new,
##   kill_size_old, kill_size_new, changed: bool, reports: Array[String] }
## margin_x: extra metres of kill zone past each end; kill_margin: kill_y below the lowest floor.
## grow_only: never raise kill_y or shrink / shift the kill zone so it covers less than before.
static func compute(root: Node, margin_x: float = 20.0, kill_margin: float = 8.0, grow_only: bool = true,
		wall_min_height: float = 4.0, wall_tolerance: float = 1.0) -> Dictionary:
	var r := { "ok": false, "error": "", "reports": [] as Array[String], "changed": false }
	if root == null or root.get("kill_y") == null:
		r.error = "Open a level scene (LevelRoot) first."
		return r
	var kz := root.get_node_or_null("KillZone") as Node3D
	if kz == null or kz.get("size") == null:
		r.error = "This level has no root KillZone node."
		return r

	var have := false
	var bounds := Rect2()
	for n in Q.gameplay_nodes(root):
		var rect := Q.rect_xy(n, root)
		bounds = rect if not have else bounds.merge(rect)
		have = true
	if not have:
		r.error = "Nothing placed yet."
		return r

	# Lowest floor = the lowest walkable surface (top of any platform).
	var lowest_floor := INF
	for p in Q.platforms(root):
		lowest_floor = minf(lowest_floor, Q.rect_xy(p, root).end.y)
	if lowest_floor == INF:
		lowest_floor = bounds.position.y

	var old_kill_y: float = float(root.get("kill_y"))
	var new_kill_y := lowest_floor - kill_margin
	if grow_only:
		new_kill_y = minf(new_kill_y, old_kill_y)

	var old_size: Vector3 = kz.get("size")
	var old_pos: Vector3 = kz.position
	var left := bounds.position.x - margin_x
	var right := bounds.end.x + margin_x
	if grow_only:
		left = minf(left, old_pos.x - old_size.x * 0.5)
		right = maxf(right, old_pos.x + old_size.x * 0.5)
	var new_size := Vector3(snappedf(right - left, 0.01), old_size.y, old_size.z)
	# The kill zone's top sits on kill_y, like the template (kill_y -12, box top -12).
	var new_pos := Vector3(snappedf((left + right) * 0.5, 0.01), snappedf(new_kill_y - old_size.y * 0.5, 0.01), old_pos.z)
	if grow_only and old_pos.y + old_size.y * 0.5 < new_kill_y:
		new_pos.y = old_pos.y # already lower than needed: keep it

	r.bounds = bounds
	r.kill_y_old = old_kill_y
	r.kill_y_new = snappedf(new_kill_y, 0.01)
	r.kill_pos_old = old_pos
	r.kill_pos_new = new_pos
	r.kill_size_old = old_size
	r.kill_size_new = new_size
	r.changed = not is_equal_approx(r.kill_y_new, old_kill_y) or not new_pos.is_equal_approx(old_pos) \
		or not new_size.is_equal_approx(old_size)

	r.reports.append_array(wall_reports(root, platform_bounds(root), wall_min_height, wall_tolerance))
	r.reports.append_array(backdrop_reports(root, bounds))
	r.ok = true
	return r

## Applies a computed fit as one undoable action ("Fit level").
static func apply(root: Node, fit: Dictionary, undo_redo: EditorUndoRedoManager) -> void:
	if not fit.get("ok", false) or not fit.get("changed", false):
		return
	var kz := root.get_node("KillZone") as Node3D
	if undo_redo == null:
		root.set("kill_y", fit.kill_y_new)
		kz.position = fit.kill_pos_new
		kz.set("size", fit.kill_size_new)
		return
	undo_redo.create_action("Fit level", UndoRedo.MERGE_DISABLE, root)
	undo_redo.add_do_property(root, &"kill_y", fit.kill_y_new)
	undo_redo.add_undo_property(root, &"kill_y", fit.kill_y_old)
	undo_redo.add_do_property(kz, &"position", fit.kill_pos_new)
	undo_redo.add_undo_property(kz, &"position", fit.kill_pos_old)
	undo_redo.add_do_property(kz, &"size", fit.kill_size_new)
	undo_redo.add_undo_property(kz, &"size", fit.kill_size_old)
	undo_redo.commit_action()

## Human-readable summary of a fit result.
static func describe(fit: Dictionary) -> String:
	if not fit.get("ok", false):
		return fit.get("error", "Fit failed.")
	var lines: Array[String] = []
	var b: Rect2 = fit.bounds
	lines.append("Level spans x %.1f … %.1f, y %.1f … %.1f" % [b.position.x, b.end.x, b.position.y, b.end.y])
	if not fit.changed:
		lines.append("Kill zone and kill_y already fit: nothing changed.")
	else:
		if not is_equal_approx(fit.kill_y_new, fit.kill_y_old):
			lines.append("kill_y: %.2f → %.2f" % [fit.kill_y_old, fit.kill_y_new])
		var po: Vector3 = fit.kill_pos_old
		var pn: Vector3 = fit.kill_pos_new
		var so: Vector3 = fit.kill_size_old
		var sn: Vector3 = fit.kill_size_new
		if not po.is_equal_approx(pn):
			lines.append("KillZone position: (%.2f, %.2f) → (%.2f, %.2f)" % [po.x, po.y, pn.x, pn.y])
		if not so.is_equal_approx(sn):
			lines.append("KillZone width: %.2f → %.2f" % [so.x, sn.x])
	for rep: String in fit.reports:
		lines.append("⚠ " + rep)
	return "\n".join(lines)

## Bounds of the walkable geometry only (platforms), used to judge the level's ends.
static func platform_bounds(root: Node) -> Rect2:
	var have := false
	var b := Rect2()
	for p in Q.platforms(root):
		var r := Q.rect_xy(p, root)
		b = r if not have else b.merge(r)
		have = true
	return b

## A wall at an end = a Geometry platform at least `min_height` tall whose box touches that end.
static func wall_reports(root: Node, bounds: Rect2, min_height: float = 4.0, tolerance: float = 1.0) -> Array[String]:
	var out: Array[String] = []
	var has_left := false
	var has_right := false
	var geo := root.get_node_or_null("Geometry")
	if geo:
		for p in geo.get_children():
			var rect := Q.rect_xy(p, root)
			if rect.size.y < min_height:
				continue
			if rect.position.x <= bounds.position.x + tolerance:
				has_left = true
			if rect.end.x >= bounds.end.x - tolerance:
				has_right = true
	if not has_left:
		out.append("No wall at the left end (x %.1f)." % bounds.position.x)
	if not has_right:
		out.append("No wall at the right end (x %.1f)." % bounds.end.x)
	return out

## Reports when the level reaches past the narrowest Backdrop panel.
static func backdrop_reports(root: Node, bounds: Rect2) -> Array[String]:
	var out: Array[String] = []
	var bd := root.get_node_or_null("Backdrop")
	if bd == null:
		out.append("No Backdrop node.")
		return out
	for c in bd.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get("size") == null:
			continue
		var half_w: float = (mi.mesh.get("size") as Vector2).x * 0.5 * absf(mi.scale.x)
		var cx := Q.pos(mi, root).x
		if bounds.position.x < cx - half_w or bounds.end.x > cx + half_w:
			out.append("Level (x %.1f … %.1f) reaches past Backdrop panel '%s' (x %.1f … %.1f)." % [
				bounds.position.x, bounds.end.x, mi.name, cx - half_w, cx + half_w])
	return out
