@tool
class_name LevelQuery
extends RefCounted

## LevelQuery — Read-only helpers shared by the level editor tools (fit, links, overlays, validate).
## Works on the open scene AND on scenes instanced off-tree (Validate all), so it never uses
## global_position: positions are accumulated from local transforms up to the level root.
## Gameplay scripts aren't @tool; in the editor their exported values are still readable.
##
## Sends: nothing.
## Receives: queries from LevelFit, LevelLinks, LevelOverlays, LevelValidator.

## Containers / nodes that are not gameplay (ignored by bounds and plane checks).
const NON_GAMEPLAY_ROOT_NODES: PackedStringArray = ["Camera", "Backdrop", "Decor", "WorldEnvironment"]

## Script class names of `node` and all its base scripts, e.g. ["Crawler", "Enemy"].
static func script_classes(node: Object) -> PackedStringArray:
	var out := PackedStringArray()
	var script := node.get_script() as Script if node else null
	while script != null:
		var n := script.get_global_name()
		if n != &"":
			out.append(n)
		script = script.get_base_script()
	return out

static func has_class(node: Object, class_name_: String) -> bool:
	return class_name_ in script_classes(node)

## Transform of `node` in the level root's local space (works for nodes outside the tree).
## Everything the tools compute and draw is in this space.
static func xform_to_root(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

static func pos(node: Node, root: Node) -> Vector3:
	return xform_to_root(node, root).origin

## All descendants of `root` (owned nodes and instance internals).
static func all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

## Every descendant whose script is (or extends) `class_name_`.
static func find_class(root: Node, class_name_: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in all_nodes(root):
		if n != root and has_class(n, class_name_):
			out.append(n)
	return out

## Axis-aligned XY box (Rect2, y up) of a sized node: Platform / GhostPlatform /
## CollapsingPlatform (`size` Vector2, centred) or a box trigger (`size` Vector3, centred).
## Nodes without a size give a zero-size rect at their position.
static func rect_xy(node: Node, root: Node) -> Rect2:
	var p := pos(node, root)
	var s: Variant = node.get("size")
	var half := Vector2.ZERO
	if s is Vector2:
		half = (s as Vector2) * 0.5
	elif s is Vector3:
		half = Vector2((s as Vector3).x, (s as Vector3).y) * 0.5
	return Rect2(Vector2(p.x, p.y) - half, half * 2.0)

## Level-wide gameplay nodes considered for bounds: everything under Geometry and
## GhostPlatforms, plus root children except the non-gameplay ones, containers and KillZone.
static func gameplay_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in root.get_children():
		if c.name in NON_GAMEPLAY_ROOT_NODES or has_class(c, "KillZone"):
			continue
		if c.name == "Geometry" or c.name == "GhostPlatforms" or c.name == "Hints":
			for g in c.get_children():
				out.append(g)
			continue
		if c is Node3D:
			out.append(c)
	return out

## Platforms that make up the level's ground: Geometry children + ghost / collapsing platforms.
static func platforms(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for n in all_nodes(root):
		if n == root:
			continue
		var cls := script_classes(n)
		if "Platform" in cls or "GhostPlatform" in cls or "CollapsingPlatform" in cls:
			out.append(n)
	return out

## The level's lantern light radius (first Lantern's base_radius), or `fallback`.
static func lantern_radius(root: Node, fallback: float = 4.5) -> float:
	for l in find_class(root, "Lantern"):
		return float(l.get("base_radius"))
	return fallback

static func is_oil_level(root: Node) -> bool:
	return int(root.get("lantern_type")) == 1 if root.get("lantern_type") != null else false

## HookPoint position of a LanternHook (falls back to the hook's own position).
static func hook_point(hook: Node, root: Node) -> Vector3:
	var hp := hook.get_node_or_null("HookPoint")
	return pos(hp, root) if hp else pos(hook, root)

## Rect of a node's first BoxShape3D CollisionShape3D child (e.g. a LanternHook's reach box).
static func shape_rect(node: Node, root: Node) -> Rect2:
	for c in node.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var size := ((c as CollisionShape3D).shape as BoxShape3D).size
			var p := pos(c, root)
			return Rect2(Vector2(p.x - size.x * 0.5, p.y - size.y * 0.5), Vector2(size.x, size.y))
	return Rect2()
