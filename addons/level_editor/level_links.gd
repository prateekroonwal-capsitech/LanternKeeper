@tool
class_name LevelLinks
extends RefCounted

## LevelLinks — How puzzle pieces connect by shared ids, and the Link / Unlink edits (Prompt 5).
## Channels (senders → listeners):
##   hook:  LanternHook.hook_id → Gate.hook_id, Shade.bait_hook_id
##   lever: Lever.lever_id, PressurePlate.plate_id → Gate.lever_id, LanternHook.lever_id, FallingTrap.lever_id
##   wake:  WakeTrigger.wake_group, LanternHook.wake_group_on_hang, Rope.wake_group_on_grab
##          → Enemy.wake_group, Shade encounter groups, TutorialTrigger.on_wake_group
##
## Sends: undoable property changes through EditorUndoRedoManager.
## Receives: collect / candidates / link / unlink calls from LevelEditorDock, LevelOverlays, LevelValidator.

const Q = preload("res://addons/level_editor/level_query.gd")

const SEND := "send"
const LISTEN := "listen"

## [script class, field, channel, role]
const FIELDS: Array = [
	["LanternHook", "hook_id", "hook", SEND],
	["Gate", "hook_id", "hook", LISTEN],
	["Shade", "bait_hook_id", "hook", LISTEN],
	["Lever", "lever_id", "lever", SEND],
	["PressurePlate", "plate_id", "lever", SEND],
	["Gate", "lever_id", "lever", LISTEN],
	["LanternHook", "lever_id", "lever", LISTEN],
	["FallingTrap", "lever_id", "lever", LISTEN],
	["WakeTrigger", "wake_group", "wake", SEND],
	["LanternHook", "wake_group_on_hang", "wake", SEND],
	["Rope", "wake_group_on_grab", "wake", SEND],
	["Enemy", "wake_group", "wake", LISTEN],
	["Shade", "run_group", "wake", LISTEN],
	["Shade", "run_end_group", "wake", LISTEN],
	["Shade", "trap_group", "wake", LISTEN],
	["Shade", "hide_group", "wake", LISTEN],
	["Shade", "hide_end_group", "wake", LISTEN],
	["Shade", "final_group", "wake", LISTEN],
	["TutorialTrigger", "on_wake_group", "wake", LISTEN],
]

## Prefix for new ids per channel.
const NEW_ID_PREFIX := { "hook": "hook_", "lever": "lever_", "wake": "wake_" }

## Link fields `node` has: [{ field, channel, role }]. A field appears once even if two base
## classes declare it (e.g. Shade inherits Enemy.wake_group).
static func fields_of(node: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var classes := Q.script_classes(node)
	for f in FIELDS:
		if f[0] in classes and not seen.has(f[1]) and node.get(f[1]) != null:
			seen[f[1]] = true
			out.append({ "field": f[1], "channel": f[2], "role": f[3] })
	return out

## Every link field in the level with a non-empty id:
## [{ node, field, channel, role, id: String }]
static func collect(root: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in Q.all_nodes(root):
		if n == root:
			continue
		for f in fields_of(n):
			var id := str(n.get(f.field))
			if id.is_empty():
				continue
			out.append({ "node": n, "field": f.field, "channel": f.channel, "role": f.role, "id": id })
	return out

## Ids in use per channel: { channel: { id: [entries] } }
static func ids_by_channel(root: Node) -> Dictionary:
	var out := { "hook": {}, "lever": {}, "wake": {} }
	for e in collect(root):
		var ch: Dictionary = out[e.channel]
		if not ch.has(e.id):
			ch[e.id] = []
		(ch[e.id] as Array).append(e)
	return out

## Ways to link `a` and `b`: [{ channel, field_a, field_b, label }]. Sender↔listener pairs
## first, then same-role pairs (two gates on one hook, two triggers waking one group).
static func candidates(a: Node, b: Node) -> Array[Dictionary]:
	var cross: Array[Dictionary] = []
	var same: Array[Dictionary] = []
	for fa in fields_of(a):
		for fb in fields_of(b):
			if fa.channel != fb.channel:
				continue
			var c := { "channel": fa.channel, "field_a": fa.field, "field_b": fb.field,
				"label": "%s.%s ↔ %s.%s" % [a.name, fa.field, b.name, fb.field] }
			if fa.role != fb.role:
				cross.append(c)
			else:
				same.append(c)
	cross.append_array(same)
	return cross

## A new id for `channel` that nothing in the level uses yet (hook_1, lever_2 …).
static func new_id(root: Node, channel: String) -> String:
	var used: Dictionary = ids_by_channel(root).get(channel, {})
	var n := 1
	while used.has("%s%d" % [NEW_ID_PREFIX.get(channel, "id_"), n]):
		n += 1
	return "%s%d" % [NEW_ID_PREFIX.get(channel, "id_"), n]

## Sets the candidate's fields on `a` and `b` to `id` (one undoable action).
static func link(a: Node, b: Node, candidate: Dictionary, id: String, undo_redo: EditorUndoRedoManager) -> void:
	_set_fields([[a, candidate.field_a], [b, candidate.field_b]], StringName(id), "Link %s ↔ %s" % [a.name, b.name], undo_redo)

## Clears the candidate's fields on both nodes (one undoable action).
static func unlink(a: Node, b: Node, candidate: Dictionary, undo_redo: EditorUndoRedoManager) -> void:
	_set_fields([[a, candidate.field_a], [b, candidate.field_b]], &"", "Unlink %s ↔ %s" % [a.name, b.name], undo_redo)

## Clears every link field on one node (one undoable action).
static func unlink_all(node: Node, undo_redo: EditorUndoRedoManager) -> void:
	var pairs: Array = []
	for f in fields_of(node):
		pairs.append([node, f.field])
	_set_fields(pairs, &"", "Unlink %s" % node.name, undo_redo)

static func _set_fields(pairs: Array, value: StringName, action: String, undo_redo: EditorUndoRedoManager) -> void:
	if undo_redo == null:
		for p in pairs:
			p[0].set(p[1], value)
		return
	undo_redo.create_action(action)
	for p in pairs:
		undo_redo.add_do_property(p[0], p[1], value)
		undo_redo.add_undo_property(p[0], p[1], p[0].get(p[1]))
	undo_redo.commit_action()

## Stable colour per id (same id → same colour everywhere).
static func id_color(channel: String, id: String) -> Color:
	var h := float(absi(hash(channel + ":" + id)) % 997) / 997.0
	return Color.from_hsv(h, 0.75, 1.0, 0.95)
