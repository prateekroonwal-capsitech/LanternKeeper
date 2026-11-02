extends Node
# Temporary scenario bot for the polish pass — deleted after verification.
const OUT := "C:/Users/CT_USER/AppData/Local/Temp/claude/C--Users-CT-USER--claude-spares-spare-CXh7jY/3b2ea652-6e7f-45c0-965b-8a4e82acea82/scratchpad/sc_"
var reg
var game
var lvl
var step := 0
var st := 0.0
var t := 0.0
var events: Array = []
var notes := {}
var screen_x: Array = []
var measuring := false
var min_gap := {}
var deaths: Array = []

func _ready() -> void:
	reg = get_node("/root/ServiceRegistry")
	reg.set_meta(&"dev_boot_scene", "res://game/scenes/gameplay/levels/TestLevel.tscn")
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -200
	_log("start")
	_go.call_deferred()

func _go() -> void:
	var boot = load("res://game/scenes/boot/Boot.tscn").instantiate()
	get_tree().root.add_child(boot)
	get_tree().current_scene = boot

func _log(s: String) -> void:
	print(s)
	var f := FileAccess.open(OUT + "log.txt", FileAccess.READ_WRITE if FileAccess.file_exists(OUT + "log.txt") else FileAccess.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func check(name: String, ok: bool, info: Variant = "") -> void:
	_log(("PASS " if ok else "FAIL ") + name + " " + str(info))

func shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + n + ".png")

func P() -> Vector3: return game.get_player_position()
func L(): return lvl.get_node("Lantern")
func hold(a: String, on: bool) -> void:
	if on: Input.action_press(a)
	else: Input.action_release(a)
func stop_move() -> void:
	hold("move_left", false); hold("move_right", false)
func go(x: float) -> bool:
	if absf(P().x - x) < 0.3:
		stop_move(); return absf(lvl.get_node("Player").velocity.x) < 0.2
	hold("move_right", x > P().x); hold("move_left", x < P().x)
	return false
func press_place() -> void:
	Input.action_press("place_lantern")
	get_tree().create_timer(0.06).timeout.connect(func(): Input.action_release("place_lantern"))
func press_jump() -> void:
	Input.action_press("jump")
	get_tree().create_timer(0.3).timeout.connect(func(): Input.action_release("jump"))

func _process(_d: float) -> void:
	if measuring and game and game.has_player():
		var cam: Camera3D = lvl.get_node("Camera")
		screen_x.append(cam.unproject_position(lvl.get_node("Player").get_global_transform_interpolated().origin).x)

func _track_gaps() -> void:
	# How deep any awake enemy ever got into the carried light (should stay outside).
	if not game.is_lantern_carried(): return
	var c: Vector3 = L().get_light_position()
	var r: float = L().get_light_radius()
	for n in ["Crawler", "Dropper", "Stalker"]:
		var e = lvl.get_node(n)
		var inside: bool = e.mode == e.Mode.ACTIVE and Vector2(e.global_position.x - c.x, e.global_position.y - c.y).length() < r
		var k: String = n + "_t"
		notes[k] = (notes.get(k, 0.0) + get_physics_process_delta_time()) if inside else 0.0
		min_gap[n] = maxf(min_gap.get(n, 0.0), notes[k])

func _physics_process(delta: float) -> void:
	t += delta
	if game == null:
		game = reg.get_service(&"game")
		if game:
			game.bus.player_died.connect(func(c): deaths.append(c); _log("  died: " + c))
			game.bus.enemy_woke.connect(func(e): _log("  woke: " + e.name))
			game.bus.lantern_returned.connect(func(): _log("  lantern returned"))
		return
	if not game.has_player() or game.current_level == null: return
	lvl = game.current_level
	st += delta
	_track_gaps()
	var nxt := false
	match step:
		0:
			if st > 1.0:
				check("HUD has no meters", lvl != null and not reg.get_service(&"ui").get_root().hud.get_node("%DarkOverlay").visible)
				Engine.max_fps = 144
				get_tree().physics_interpolation = false
				screen_x.clear(); measuring = true; nxt = true
		1:
			hold("move_right", true)
			if st > 2.0:
				measuring = false; stop_move()
				notes["jit_off"] = _jitter(); nxt = true
		2:
			if go(-8.0):
				get_tree().physics_interpolation = true
				screen_x.clear(); measuring = true; nxt = true
		3:
			hold("move_right", true)
			if st > 2.0:
				measuring = false; stop_move()
				var j := _jitter()
				check("jitter reduced (interp on vs off)", j < notes["jit_off"] * 0.5, "off=%.3f px  on=%.3f px" % [notes["jit_off"], j])
				Engine.max_fps = 0
				nxt = true
		4: if go(-8.0): press_place(); nxt = true
		5: if st > 0.3 and go(-1.0): nxt = true          # passes shrine A at -4 with the lantern placed
		6: game.report_player_died("test"); nxt = true
		7:
			if game.state == game.State.PLAYING and st > 0.3:
				check("respawn: placed lantern stays placed", not game.is_lantern_carried() and absf(L().global_position.x + 8.0) < 0.3, L().global_position)
				check("respawn at shrine A", absf(P().x + 3.1) < 0.3, P())
				nxt = true
		8: if go(-8.0): nxt = true                         # walk into it → pick up
		9:
			if st > 0.3:
				check("pick up", game.is_lantern_carried())
				nxt = true
		10: if go(-1.0): nxt = true                        # shrine A again (refresh: carried)
		11: game.report_player_died("test"); nxt = true
		12:
			if game.state == game.State.PLAYING and st > 0.3:
				check("respawn: carried snapshot → carried", game.is_lantern_carried())
				nxt = true
		13:   # carry through the crawler / dropper / stalker zones (safe), touching shrine B
			hold("move_right", true)
			if P().x > 19.6 and P().x < 20.2 and game.is_player_on_floor(): pass
			if P().x > 59.0:
				stop_move(); nxt = true
		14:
			if st > 1.0:
				check("no enemy lingers in carried light (>1.5 s)", min_gap.get("Crawler", 0.0) < 1.5 and min_gap.get("Dropper", 0.0) < 1.5 and min_gap.get("Stalker", 0.0) < 1.5, min_gap)
				check("no deaths while carrying", deaths.size() == 2, deaths)
				shot("01_carried_safe")
				nxt = true
		15: if go(56.0): nxt = true
		16:
			hold("move_right", true)
			if P().x > 59.5: press_jump(); nxt = true
		17:
			if P().x > 60.7 and not notes.has("placed_air"):
				notes["placed_air"] = true; press_place()
			if st > 1.8:
				stop_move()
				var ln = L()
				check("lost lantern returned beside child", not game.is_lantern_carried() and absf(ln.global_position.x - P().x) < 2.0 and absf(ln.global_position.y - 0.0) < 0.6, [ln.global_position, P()])
				shot("02_lantern_returned")
				nxt = true
		18:   # leave the lantern, walk into the dark and stand still → stalker attacks
			if P().x < 67.0: hold("move_right", true)
			else: stop_move()
			if deaths.size() > 2 or st > 12.0:
				stop_move()
				check("stalker catches child in darkness", deaths.size() > 2 and str(deaths.back()).begins_with("caught_"), deaths)
				nxt = true
		19:
			if game.state == game.State.PLAYING and st > 0.5:
				check("respawn at shrine B with lantern (carried at B)", absf(P().x - 54.9) < 0.4 and game.is_lantern_carried(), [P(), game.is_lantern_carried()])
				nxt = true
		20:
			hold("move_right", true)
			if P().x > 59.5 and P().x < 60.0 and game.is_player_on_floor(): press_jump()
			if P().x > 63.0: nxt = true
		200: pass
		21: if go(69.5): press_place(); nxt = true
		22: if st > 0.3 and go(77.0): nxt = true
		23:
			if st > 1.5:
				var dormant := 0
				for m in lvl.get_node("Swarm").get_children():
					if m.mode == m.Mode.DORMANT: dormant += 1
				check("lit holes stay sealed", dormant == 5, "%d/5 dormant" % dormant)
				nxt = true
		24: if go(69.5): nxt = true
		25: if st > 0.3 and go(84.0): nxt = true
		26:
			if st > 2.5:
				var awake := 0
				for m in lvl.get_node("Swarm").get_children():
					if m.mode != m.Mode.DORMANT: awake += 1
				check("swarm pours out once holes are dark", awake == 5, "%d/5" % awake)
				check("swarm can't touch carried child", deaths.size() == 3, deaths)
				shot("03_swarm")
				nxt = true
		27: if go(97.0): nxt = true
		28:
			if deaths.size() > 3 or st > 15.0:
				check("big shadow catches even with lantern", deaths.size() > 3 and deaths.back() == "caught_big_shadow", deaths)
				nxt = true
		29:
			if game.state == game.State.PLAYING and st > 0.5:
				nxt = true
		30: if go(52.5): press_place(); nxt = true       # leave the light at 52.5
		31: if st > 0.3 and go(46.0): nxt = true          # walk under the dropper in darkness
		32:
			if deaths.size() > 4 or st > 6.0:
				check("dropper drops on child in darkness", deaths.size() > 4 and deaths.back() == "caught_dropper", deaths)
				nxt = true
		33:
			_log("DONE")
			get_tree().quit()
	if nxt:
		step += 1; st = 0.0
	if t > 240:
		_log("TIMEOUT at step %d" % step); get_tree().quit()

func _jitter() -> float:
	# Mean |second difference| of the player's screen x — 0 for perfectly smooth motion.
	var s := 0.0
	var n := 0
	for i in range(30, screen_x.size() - 2):
		s += absf(screen_x[i + 2] - 2.0 * screen_x[i + 1] + screen_x[i])
		n += 1
	return s / maxf(n, 1)
