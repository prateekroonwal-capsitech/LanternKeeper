class_name DebugOverlay
extends Control

## DebugOverlay — on-screen diagnostics toggled by F3 (disabled in release builds).
## Draws:
##   - Light radius circles around all active light sources.
##   - Enemy states (DORMANT, EMERGING, ACTIVE, FROZEN/REPELLED, RETURNING).
##   - WakeTrigger bounding areas and armed/fired status.
##
## Sends: none
## Receives: input events for KEY_F3 toggle.

@export var show_light_radius: bool = true
@export var show_enemy_states: bool = true
@export var show_triggers: bool = true

var _active: bool = false
var _game: GameManager

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_process(false)
	set_process_unhandled_input(not OS.has_feature("release"))

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _get_game() -> GameManager:
	if _game == null and ServiceRegistry:
		_game = ServiceRegistry.get_service(&"game") as GameManager
	return _game

func _unhandled_input(event: InputEvent) -> void:
	if OS.has_feature("release"):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_active = not _active
		set_process(_active)
		visible = _active
		queue_redraw()

func _process(_delta: float) -> void:
	if _active:
		queue_redraw()

func _draw() -> void:
	if not _active or OS.has_feature("release"):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var font := ThemeDB.fallback_font

	var gm := _get_game()
	# 1. Light radius circles
	if show_light_radius and gm:
		for src in gm._light_sources:
			if not is_instance_valid(src) or not src.is_light_active():
				continue
			var c: Vector3 = src.get_light_position()
			var r: float = src.get_light_radius()
			if camera.is_position_behind(c):
				continue
			var sp0 := camera.unproject_position(c)
			var sp1 := camera.unproject_position(c + Vector3(r, 0, 0))
			var screen_r := sp0.distance_to(sp1)
			draw_arc(sp0, screen_r, 0, TAU, 36, Color(1, 0.85, 0.2, 0.7), 2.0)
			draw_circle(sp0, 4.0, Color(1, 0.9, 0.3, 0.9))
			draw_string(font, sp0 + Vector2(8, -8), "Light r=%.2f" % r, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.3, 0.9))

	# 2. Enemy states
	if show_enemy_states:
		for enemy in get_tree().get_nodes_in_group(&"enemies"):
			if not is_instance_valid(enemy):
				continue
			var pos: Vector3 = enemy.global_position
			if camera.is_position_behind(pos):
				continue
			var sp := camera.unproject_position(pos)
			var m = enemy.get("mode")
			var state_str := "UNKNOWN"
			var col := Color.WHITE
			match m:
				Enemy.Mode.DORMANT:
					state_str = "DORMANT"
					col = Color(0.6, 0.6, 0.6, 0.9)
				Enemy.Mode.EMERGING:
					state_str = "EMERGING"
					col = Color(0.2, 0.8, 1.0, 0.9)
				Enemy.Mode.HUNT:
					state_str = "HUNT"
					col = Color(1.0, 0.2, 0.2, 0.9)
				Enemy.Mode.FROZEN:
					state_str = "FROZEN"
					col = Color(1.0, 0.6, 0.1, 0.9)
				Enemy.Mode.ATTACK:
					state_str = "ATTACK"
					col = Color(1.0, 0.1, 0.5, 1.0)
				Enemy.Mode.RETREAT:
					state_str = "RETREAT"
					col = Color(0.7, 0.7, 0.3, 0.9)
				Enemy.Mode.RETURNING:
					state_str = "RETURNING"
					col = Color(0.8, 0.4, 1.0, 0.9)
			var label := "%s: %s" % [enemy.name, state_str]
			draw_circle(sp, 5.0, col)
			draw_string(font, sp + Vector2(-30, -14), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)

	# 3. Trigger areas
	if show_triggers:
		for trigger in get_tree().get_nodes_in_group(&"wake_triggers"):
			if not is_instance_valid(trigger):
				continue
			var ts: Vector3 = trigger.size if "size" in trigger else Vector3(2, 4, 2)
			var tc: Vector3 = trigger.global_position + Vector3(0, ts.y * 0.5, 0)
			if camera.is_position_behind(tc):
				continue
			var p1 := tc + Vector3(-ts.x * 0.5, ts.y * 0.5, 0)
			var p2 := tc + Vector3(ts.x * 0.5, ts.y * 0.5, 0)
			var p3 := tc + Vector3(ts.x * 0.5, -ts.y * 0.5, 0)
			var p4 := tc + Vector3(-ts.x * 0.5, -ts.y * 0.5, 0)
			var sp1 := camera.unproject_position(p1)
			var sp2 := camera.unproject_position(p2)
			var sp3 := camera.unproject_position(p3)
			var sp4 := camera.unproject_position(p4)
			var pts := PackedVector2Array([sp1, sp2, sp3, sp4, sp1])
			var fired: bool = trigger._fired if "_fired" in trigger else false
			var col := Color(0.3, 0.9, 0.3, 0.8) if not fired else Color(0.5, 0.5, 0.5, 0.4)
			var fill := Color(0.2, 0.8, 0.2, 0.15) if not fired else Color(0.3, 0.3, 0.3, 0.08)
			var poly := PackedVector2Array([sp1, sp2, sp3, sp4])
			draw_colored_polygon(poly, fill)
			draw_polyline(pts, col, 2.0)
			var group_name: String = str(trigger.wake_group) if "wake_group" in trigger else ""
			var status_str := "ARMED" if not fired else "FIRED"
			draw_string(font, sp4 + Vector2(4, -6), "Trigger '%s' [%s]" % [group_name, status_str], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
