class_name Shade
extends Enemy

## Shade — the flying shadow of level 10. It meets the child in four encounters; each one is
## started by a WakeTrigger group and played out on paths / markers placed in the level.
## Touching its body is death. Lantern light means nothing to it — only the level's traps
## (FallingTrap) can hurt it. It comes back from each encounter more damaged:
## after encounter 2 one wing is torn, from encounter 4 it also smokes and sparks.
##
##  1 RUN    (`run_group`): bursts in and follows `run_follow` (PathFollow3D) at `run_speed`,
##           a little slower than the child, never waiting. `run_end_group` → it loses the
##           child and flies off to `run_exit`.
##  2 TRAP   (`trap_group`): perches at `perch_point`; anything within `reach` is attacked.
##           It is drawn to the light: a lantern set down within `lure_range` lures it (after
##           `lure_delay`) — hung on hook `bait_hook_id` it hovers at `lure_point` (under the
##           rock trap), anywhere else it hovers over the lantern. If the rock lands on it:
##           pinned, wing torn, screech, then it flees to `flee_point`. Lantern picked up →
##           back to the perch.
##  3 HIDE   (`hide_group`): sweeps `patrol_follow` back and forth (`patrol_speed`, pausing
##           `patrol_pause` at each end). It spots the child in the open within
##           `spot_range`, or carrying the light within `light_spot_range` → attack.
##           `hide_end_group` → flies off to `hide_exit`.
##  4 FINAL  (`final_group`): flies to `hover_point`, then repeats: hover `hover_time`,
##           screech `screech_time` (eyes flare), dive to `low_point` (`dive_time`, under the
##           cracked ceiling), search there for `hold_time`, then lunge at the child.
##           If the ceiling trap lands on it: crushed, eyes fade, it reports itself defeated.
##
## Sends: GameManager.report_player_caught(self), report_enemy_woke(self),
##   report_enemy_defeated(self) (the exit gate listens for "shade").
## Receives: GameBus.enemies_wake_requested(group), lantern_hook_changed(id, hung),
##   trap_sprung(trap); GameManager.is_player_hidden() / is_lantern_carried() (polled);
##   checkpoint snapshot (group "enemies").

enum Act { IDLE, ARRIVE, RUN, FLY_OFF, PERCH, LURE, ATTACK, PINNED, PATROL, HOVER, SCREECH, DIVE, HOLD, CRUSHED }

@export_group("1 Run")
@export var run_group: StringName = &"shade_run"
@export var run_end_group: StringName = &"shade_run_end"
@export var run_follow: PathFollow3D
@export var run_speed: float = 4.6
@export var run_exit: Marker3D

@export_group("2 Trap")
@export var trap_group: StringName = &"shade_trap"
@export var perch_point: Marker3D
@export var lure_point: Marker3D
@export var flee_point: Marker3D
@export var bait_hook_id: StringName = &"shade_bait"
@export var lure_delay: float = 1.0
## A lantern set down (not carried) this close to the perch draws it in.
@export var lure_range: float = 30.0
## Anything this close (m) to it while it perches or hovers at the bait is attacked.
@export var reach: float = 4.5
@export var pinned_time: float = 1.6

@export_group("3 Hide")
@export var hide_group: StringName = &"shade_hide"
@export var hide_end_group: StringName = &"shade_hide_end"
@export var patrol_follow: PathFollow3D
@export var patrol_speed: float = 7.0
@export var patrol_pause: float = 1.2
## It starts sweeping from this end of the path (true = the far end).
@export var patrol_start_at_end: bool = true
@export var spot_range: float = 3.5
@export var light_spot_range: float = 12.0
@export var hide_exit: Marker3D

@export_group("4 Final")
@export var final_group: StringName = &"shade_final"
@export var hover_point: Marker3D
@export var low_point: Marker3D
@export var hover_time: float = 2.2
@export var screech_time: float = 0.8
@export var dive_time: float = 0.5
@export var hold_time: float = 1.1
@export var eye_fade_time: float = 1.5
## Slow motion when it is crushed (time scale, real seconds).
@export var crush_slow_scale: float = 0.4
@export var crush_slow_time: float = 0.3

@export_group("Flight")
@export var fly_speed: float = 9.0
@export var attack_speed: float = 11.0
@export var bob_amplitude: float = 0.2
@export var bob_frequency: float = 2.4

var act: Act = Act.IDLE
## Visible damage: 0 whole, 1 torn wing, 2 torn wing + smoke and sparks.
var damage: int = 0
var _t: float = 0.0
var _bob_t: float = 0.0
var _facing: float = 1.0
var _target: Vector3
var _after_arrive: Act = Act.IDLE
var _patrol_dir: float = -1.0
var _patrol_wait: float = 0.0
var _bait_hung: bool = false
var _dive_from: Vector3
var _encounter: int = 0
var _defeated: bool = false

@onready var _smoke: CPUParticles3D = get_node_or_null("SmokeTrail")
@onready var _body: AnimatedSprite3D = get_node_or_null("Visual/Body")
@onready var _eye_anchor: Node3D = get_node_or_null("Visual/EyeAnchor")
@onready var _damage_smoke: CPUParticles3D = get_node_or_null("DamageSmoke")
@onready var _sparks: CPUParticles3D = get_node_or_null("Sparks")
@onready var _debug_ui: CanvasLayer = get_node_or_null("DebugUI")
@onready var _debug_label: Label = get_node_or_null("DebugUI/Panel/Margin/Label")

func _ready() -> void:
	ignores_light = true
	enemy_kind = "shade"
	super._ready()
	if _debug_ui:
		_debug_ui.visible = false
	_go_idle()

func inject_services(registry: Node) -> void:
	super.inject_services(registry)
	if _game:
		_game.bus.lantern_hook_changed.connect(_on_hook_changed)
		_game.bus.trap_sprung.connect(_on_trap_sprung)

func _unhandled_input(event: InputEvent) -> void:
	if OS.is_debug_build() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3 and _debug_ui:
		_debug_ui.visible = not _debug_ui.visible

# ── Encounter starts / ends (WakeTrigger groups) ──────────────────────────

func _on_wake_requested(group: StringName) -> void:
	if group == &"":
		return
	print("[Shade] heard %s while %s" % [group, Act.keys()[act]])
	if _defeated:
		return
	# An encounter start always takes over, whatever it is still doing (e.g. flying off from
	# the last encounter) — otherwise the one-shot trigger is lost and the level soft-locks.
	match group:
		run_group:
			if run_follow and act != Act.RUN:
				_begin(1)
				run_follow.progress = 0.0
				global_position = run_follow.global_position
				_set_act(Act.RUN)
		run_end_group:
			if act == Act.RUN:
				_fly_off(run_exit)
		trap_group:
			if perch_point and _encounter != 2:
				_begin(2)
				global_position = perch_point.global_position + Vector3(0.0, 8.0, 0.0)
				_arrive(perch_point.global_position, Act.PERCH)
		hide_group:
			if patrol_follow and _encounter != 3:
				_begin(3)
				var length := _path_length(patrol_follow)
				patrol_follow.progress = length if patrol_start_at_end else 0.0
				_patrol_dir = -1.0 if patrol_start_at_end else 1.0
				global_position = patrol_follow.global_position + Vector3(0.0, 6.0, 0.0)
				_arrive(patrol_follow.global_position, Act.PATROL)
		hide_end_group:
			if act == Act.PATROL:
				_fly_off(hide_exit)
		final_group:
			if hover_point and _encounter != 4:
				_begin(4)
				set_damage(2)
				global_position = hover_point.global_position + Vector3(-12.0, 3.0, 0.0)
				_arrive(hover_point.global_position, Act.HOVER)

func _begin(encounter: int) -> void:
	_encounter = encounter
	mode = Mode.HUNT
	_visual.visible = true
	_set_body_visible(true)
	_set_hurtbox_active(true)
	if _smoke:
		_smoke.emitting = true
	_eye_alpha(1.0)
	_game.report_enemy_woke(self)
	print("[Shade] encounter %d starts" % encounter)

func _go_idle() -> void:
	act = Act.IDLE
	mode = Mode.DORMANT
	_visual.visible = false
	_set_body_visible(false)
	_set_hurtbox_active(false)
	if _smoke:
		_smoke.emitting = false
	set_damage(damage)

func _set_act(a: Act) -> void:
	if a != act:
		print("[Shade] %s -> %s" % [Act.keys()[act], Act.keys()[a]])
	act = a
	_t = 0.0

func _arrive(target: Vector3, then: Act) -> void:
	_target = target
	_after_arrive = then
	_set_act(Act.ARRIVE)

func _fly_off(exit: Marker3D) -> void:
	_target = exit.global_position if exit else global_position + Vector3(0.0, 15.0, 0.0)
	_set_act(Act.FLY_OFF)

## Visible damage: 0 = whole, 1 = torn wing, 2 = torn wing + smoke and sparks.
func set_damage(level: int) -> void:
	damage = clampi(level, 0, 2)
	if _body:
		_body.set(&"anim_suffix", "_torn" if damage >= 1 else "")
	var smoking := damage >= 2 and act != Act.IDLE
	if _damage_smoke:
		_damage_smoke.emitting = smoking
	if _sparks:
		_sparks.emitting = smoking

# ── Bait and traps ────────────────────────────────────────────────────────

func _on_hook_changed(hook_id: StringName, hung: bool) -> void:
	if hook_id == bait_hook_id:
		_bait_hung = hung

## The light it is drawn to: the nearest lantern to the perch that is set down and in play.
func _lure_target() -> Variant:
	var target: Variant = null
	var best := lure_range
	for lantern in _game.get_lanterns():
		if not is_instance_valid(lantern) or lantern.carried or lantern.is_retired():
			continue
		var d: float = lantern.global_position.distance_to(perch_point.global_position)
		if d <= best:
			best = d
			target = lure_point.global_position if _bait_hung and lantern.is_hung() else lantern.global_position + Vector3(0.0, 1.4, 0.0)
	return target

func _on_trap_sprung(trap: Node3D) -> void:
	if act == Act.IDLE or act == Act.CRUSHED or act == Act.PINNED:
		return
	if not trap.has_method("is_in_kill_zone") or not trap.is_in_kill_zone(global_position):
		print("[Shade] trap %s missed it (at %s)" % [trap.name, global_position])
		return
	trap.mark_caught()
	if _encounter == 4:
		_set_act(Act.CRUSHED)
		_set_hurtbox_active(false)
		print("[Shade] CRUSHED under %s, its eyes fade" % trap.name)
		if _game.audio:
			_game.audio.play_event(&"shade_screech")
		if _damage_smoke:
			_damage_smoke.direction = Vector3(0.0, 1.0, 0.0)   # smoke rising from under the rubble
			_damage_smoke.emitting = true
		global_position.z = -0.6   # under the slab: the rubble covers it, its eyes and smoke show
		_game.report_slow_motion(crush_slow_scale, crush_slow_time)
	else:
		global_position.y = trap.get_ground_point().y + 0.9
		_set_act(Act.PINNED)
		_set_hurtbox_active(false)
		set_damage(maxi(damage, 1))
		_flare(true)
		if _game.audio:
			_game.audio.play_event(&"enemy_hiss")
		print("[Shade] PINNED under %s: wing torn, screeching" % trap.name)

# ── Frame update ──────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	_time += delta
	_t += delta
	_bob_t += delta * bob_frequency
	_speed_now = 0.0
	if _game == null or not _game.is_playing() or act == Act.IDLE or _defeated:
		return
	var p := _game.get_player_position()
	var chest := p + Vector3(0.0, 0.7, 0.0)
	match act:
		Act.ARRIVE:
			if _fly_to(_target, fly_speed, delta):
				_set_act(_after_arrive)
		Act.RUN:
			run_follow.progress += run_speed * delta
			_move_to(run_follow.global_position + _bob(), delta)
			if run_follow.progress_ratio >= 0.999:
				_fly_off(run_exit)
		Act.FLY_OFF:
			if _fly_to(_target, fly_speed * 1.2, delta):
				print("[Shade] gone (encounter %d over)" % _encounter)
				_go_idle()
		Act.PERCH:
			_hover_at(perch_point.global_position, delta)
			_face(p.x - global_position.x)
			if global_position.distance_to(chest) <= reach:
				_attack()
			elif _lure_target() != null:
				print("[Shade] drawn to the light (%s)" % ("bait hook" if _bait_hung else "lantern on the ground"))
				_set_act(Act.LURE)         # _t counts the lure delay, then it flies over
		Act.LURE:
			var lure = _lure_target()
			if lure == null:
				_arrive(perch_point.global_position, Act.PERCH)   # the light was picked up
			elif _t < lure_delay:
				_hover_at(perch_point.global_position, delta)
			elif _fly_to(lure + _bob(), fly_speed, delta) and global_position.distance_to(chest) <= reach:
				_attack()
		Act.ATTACK:
			_fly_to(chest, attack_speed, delta)
		Act.PINNED:
			if _t >= pinned_time:
				_flare(false)
				_fly_off(flee_point)
		Act.PATROL:
			_patrol(delta)
			if not _game.is_player_hidden():
				var dist := global_position.distance_to(chest)
				var seen_close := dist <= spot_range or absf(p.x - global_position.x) <= spot_range
				var seen_light := _game.player_lit and dist <= light_spot_range
				if seen_close or seen_light:
					print("[Shade] SPOTTED the child (%s) at x=%.1f" % [
						"in the light" if seen_light else "up close", p.x])
					_attack()
		Act.HOVER:
			_hover_at(hover_point.global_position, delta)
			_face(p.x - global_position.x)
			if _t >= hover_time:
				_set_act(Act.SCREECH)
				_flare(true)
				if _game.audio:
					_game.audio.play_event(&"enemy_hiss")
		Act.SCREECH:
			_hover_at(hover_point.global_position + Vector3(0.0, 0.4, 0.0), delta)
			if _t >= screech_time:
				_flare(false)
				_dive_from = global_position
				_set_act(Act.DIVE)
		Act.DIVE:
			var u := clampf(_t / maxf(dive_time, 0.01), 0.0, 1.0)
			var to := low_point.global_position
			global_position = _dive_from.lerp(to, u * u * (3.0 - 2.0 * u)) + Vector3(0.0, sin(u * PI) * 0.6, 0.0)
			_face(to.x - _dive_from.x)
			if u >= 1.0:
				_set_act(Act.HOLD)
		Act.HOLD:
			_hover_at(low_point.global_position, delta)
			_face(p.x - global_position.x)
			if _t >= hold_time:
				_attack()
		Act.CRUSHED:
			_eye_alpha(1.0 - clampf(_t / maxf(eye_fade_time, 0.01), 0.0, 1.0))
			if _t >= eye_fade_time:
				print("[Shade] defeated: the way out opens")
				_defeated = true    # stays defeated (hidden) until a checkpoint before it
				_game.report_enemy_defeated(self)
				_go_idle()
				act = Act.CRUSHED
	_check_catch()
	_animate(delta)
	if _debug_ui and _debug_ui.visible and _debug_label:
		_debug_label.text = "SHADE (F3)\nEncounter: %d\nAct: %s\nDamage: %d\nHidden: %s" % [_encounter, Act.keys()[act], damage, _game.is_player_hidden()]

func _attack() -> void:
	if act != Act.ATTACK:
		print("[Shade] ATTACK from %s" % Act.keys()[act])
		_set_act(Act.ATTACK)

func _patrol(delta: float) -> void:
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		_move_to(patrol_follow.global_position + _bob(), delta)
		return
	var length := _path_length(patrol_follow)
	patrol_follow.progress = clampf(patrol_follow.progress + _patrol_dir * patrol_speed * delta, 0.0, length)
	if patrol_follow.progress <= 0.0 or patrol_follow.progress >= length:
		_patrol_dir = -_patrol_dir
		_patrol_wait = patrol_pause
	_move_to(patrol_follow.global_position + _bob(), delta)

# ── Movement helpers ──────────────────────────────────────────────────────

func _bob() -> Vector3:
	return Vector3(0.0, sin(_bob_t) * bob_amplitude, 0.0)

func _hover_at(point: Vector3, delta: float) -> void:
	_move_to(point + _bob(), delta)

func _move_to(point: Vector3, delta: float) -> void:
	var before := global_position
	global_position = global_position.lerp(point, 1.0 - exp(-10.0 * delta))
	var dx := global_position.x - before.x
	if absf(dx) > 0.002:
		_face(dx)
	_speed_now = (global_position - before).length()

## Straight flight; true once there.
func _fly_to(point: Vector3, speed: float, delta: float) -> bool:
	var to := point - global_position
	var dist := to.length()
	if dist < 0.15:
		return true
	var step := minf(speed * delta, dist)
	global_position += to / dist * step
	if absf(to.x) > 0.05:
		_face(to.x)
	_speed_now = step
	return dist - step < 0.15

func _face(dx: float) -> void:
	if absf(dx) < 0.01:
		return
	_facing = 1.0 if dx > 0.0 else -1.0
	_move_dir = _facing

func _path_length(f: PathFollow3D) -> float:
	var path := f.get_parent() as Path3D
	return path.curve.get_baked_length() if path and path.curve else 0.0

func _flare(on: bool) -> void:
	if not _eye_anchor:
		return
	_eye_anchor.scale = Vector3.ONE * (1.35 if on else 1.0)
	for e in _eye_anchor.get_children():
		if e is Sprite3D:
			var a: float = e.modulate.a
			e.modulate = Color(6.0, 0.45, 0.25, a) if on else Color(2.6, 0.18, 0.12, a)

func _eye_alpha(a: float) -> void:
	if not _eye_anchor:
		return
	for e in _eye_anchor.get_children():
		if e is Sprite3D:
			e.modulate.a = a

# ── Catching the child ────────────────────────────────────────────────────

func _check_catch() -> void:
	if act in [Act.IDLE, Act.PINNED, Act.CRUSHED, Act.FLY_OFF] or not _game.is_playing():
		return
	if global_position.distance_to(_game.get_player_position() + Vector3(0.0, 0.7, 0.0)) <= catch_radius:
		print("[Shade] caught the child (%s)" % Act.keys()[act])
		_game.report_player_caught(self)

func _on_hurtbox_body_entered(body: Node3D) -> void:
	if act in [Act.IDLE, Act.PINNED, Act.CRUSHED, Act.FLY_OFF] or _game == null or not _game.is_playing():
		return
	if body.is_in_group(&"player"):
		print("[Shade] hurtbox touched the child (%s)" % Act.keys()[act])
		_game.report_player_caught(self)

# ── Visual state for EnemyVisual ──────────────────────────────────────────

func get_visual_state() -> StringName:
	match act:
		Act.SCREECH, Act.PINNED:
			return &"windup"            # screech
		Act.DIVE, Act.ATTACK:
			return &"lunge"             # swoop
		Act.PERCH, Act.HOVER, Act.HOLD, Act.LURE:
			return &"idle"              # glide
		Act.ARRIVE:
			return &"emerge" if _t < 0.4 else &"move"
	return &"move"                      # fly

# ── Checkpoints: each encounter fully resets ──────────────────────────────

func capture_checkpoint_state() -> Dictionary:
	return { "act": act, "damage": damage, "encounter": _encounter }

func reset_to_checkpoint(state: Dictionary = {}) -> void:
	var a: int = state.get("act", Act.IDLE)
	damage = state.get("damage", 0)
	_encounter = state.get("encounter", 0)
	_t = 0.0
	_bait_hung = false
	_patrol_wait = 0.0
	_flare(false)
	_eye_alpha(1.0)
	_go_idle()
	_defeated = a == Act.CRUSHED
	if _defeated:
		act = Act.CRUSHED
	print("[Shade] checkpoint reset: %s, damage %d" % [Act.keys()[act], damage])
	reset_physics_interpolation()

func _reset() -> void:
	reset_to_checkpoint({})
