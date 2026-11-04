class_name UIManager
extends CanvasLayer

# UIManager — screen stack with on-demand instantiation and immediate free
# PDF §5 (Small panels): push_packed() instantiates on demand; pop() calls
#   queue_free() immediately so nothing sits idle in VRAM.
# PDF §5 (Big scenes): large scenes are handled by SceneManager — UIManager
#   manages panels only, not full scene transitions.
# PDF §4 CPU: hidden screens use hide(), reducing draw calls on inactive panels.
#
# Lantern Keeper: every game screen is placed ahead of time in UIRoot.tscn (no runtime
# instancing). register_root() wires them up; show_screen()/hide_screen() toggle them
# and fade_out()/fade_in() drive the full-screen ScreenFade.
# Receives: GameManager.report_player_died → fade_out()/fade_in() (called by GameManager).
# Sends: GameBus.screen_opened / screen_closed.

var _stack: Array[Control] = []
var _logger: Node
var _bus: Node
var _audio: AudioManager
var _game: GameManager
var _root: UIRoot
var _menu_stack: Array[StringName] = []

func configure(logger: Node, bus: Node, audio: AudioManager = null, game: GameManager = null) -> void:
	_logger = logger
	_bus = bus
	_audio = audio
	_game = game

func _ready() -> void:
	pass

# ── Placed screens (UIRoot.tscn) ──────────────────────────────────────────

## Called once by GameService. Injects every UIController screen under the root.
func register_root(root: UIRoot) -> void:
	_root = root
	for screen in root.get_screens():
		_auto_inject_screen(screen)
	# Every button in the UI plays the button sound.
	for button in root.find_children("*", "BaseButton", true, false):
		(button as BaseButton).pressed.connect(_on_any_button_pressed)

func _on_any_button_pressed() -> void:
	if _audio:
		_audio.play_event(&"ui_button")

# ── Menus (a stack of placed screens: open / back / close all) ─────────────

## Opens a menu on top of the current one (the current one hides until you go back).
func open_menu(menu: StringName) -> void:
	if not _menu_stack.is_empty():
		hide_screen(_menu_stack.back())
	_menu_stack.append(menu)
	show_screen(menu)

## Closes the top menu and shows the one under it.
func close_menu() -> void:
	if _menu_stack.is_empty():
		return
	hide_screen(_menu_stack.pop_back())
	if not _menu_stack.is_empty():
		show_screen(_menu_stack.back())

func close_all_menus() -> void:
	while not _menu_stack.is_empty():
		hide_screen(_menu_stack.pop_back())

func top_menu() -> StringName:
	return _menu_stack.back() if not _menu_stack.is_empty() else &""

func get_root() -> UIRoot:
	return _root

func show_screen(screen_name: StringName) -> void:
	var screen := _root.get_screen(screen_name) if _root else null
	if screen and not screen.visible:
		screen.show()
		if _bus:
			_bus.screen_opened.emit(String(screen_name))

func hide_screen(screen_name: StringName) -> void:
	var screen := _root.get_screen(screen_name) if _root else null
	if screen and screen.visible:
		screen.hide()
		if _bus:
			_bus.screen_closed.emit(String(screen_name))

## Fades the whole screen to black. Await it: `await ui.fade_out()`.
func fade_out(duration: float = -1.0) -> void:
	if _root and _root.screen_fade:
		await _root.screen_fade.fade_out(duration)

## Fades back in from black. Await it if you need to know when it is done.
func fade_in(duration: float = -1.0) -> void:
	if _root and _root.screen_fade:
		await _root.screen_fade.fade_in(duration)

# ── Push ──────────────────────────────────────────────────────────────────

## PDF §5: Pass a PackedScene — UIManager owns instantiation and lifetime.
## Use this for all panels (<~10 MB). Instantiated here, freed on pop().
func push_packed(packed: PackedScene) -> void:
	if not _stack.is_empty():
		_stack.back().hide()
	var screen := packed.instantiate() as Control
	_auto_inject_screen(screen)
	add_child(screen)
	_stack.append(screen)
	if _bus:
		_bus.screen_opened.emit(screen.name)
	if _logger:
		_logger.debug("UI push", { "screen": screen.name })

## Legacy: push a pre-instantiated Control (kept for compatibility).
## Prefer push_packed() for all new panels.
func push(screen: Control) -> void:
	if not _stack.is_empty():
		_stack.back().hide()
	_auto_inject_screen(screen)
	if screen.get_parent() == null:
		add_child(screen)
	_stack.append(screen)
	if _bus:
		_bus.screen_opened.emit(screen.name)
	if _logger:
		_logger.debug("UI push", { "screen": screen.name })

func _auto_inject_screen(screen: Control) -> void:
	if screen is UIController:
		screen.inject_dependencies(self, _audio, _game)

# ── Pop ───────────────────────────────────────────────────────────────────

## PDF §5: queue_free() immediately — no idle VRAM from off-screen panels.
func pop() -> void:
	if _stack.is_empty():
		return
	var screen: Control = _stack.pop_back()
	if _bus:
		_bus.screen_closed.emit(screen.name)
	if _logger:
		_logger.debug("UI pop", { "screen": screen.name })
	screen.queue_free()
	if not _stack.is_empty():
		_stack.back().show()

func pop_to_root() -> void:
	while _stack.size() > 1:
		pop()

func replace_packed(packed: PackedScene) -> void:
	pop()
	push_packed(packed)

func replace(screen: Control) -> void:
	pop()
	push(screen)

# ── Queries ───────────────────────────────────────────────────────────────

func current() -> Control:
	return _stack.back() if not _stack.is_empty() else null

func stack_size() -> int:
	return _stack.size()
