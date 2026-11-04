class_name InputManager
extends Node

## InputManager — turns keyboard, controller and touch into the same game actions:
## move, jump, place_lantern, raise_light, pause.
##
## Keyboard / controller come from the InputMap (project.godot). Touch comes from
## TouchControls (UI), which feeds the "virtual" setters below — gestures layout —
## or presses the InputMap actions directly via TouchScreenButtons — classic layout.
## Continuous state is polled by gameplay through GameManager.input
## (move_axis, jump_held, jump_just_pressed, raise_held).
##
## Sends: GameManager.report_place_lantern_pressed(), GameManager.report_pause_pressed(),
##   GameBus.control_layout_changed(layout)
## Receives: set_virtual_axis(), trigger_virtual_jump(), trigger_virtual_place(),
##   set_virtual_raise() from TouchControls; set_control_layout() from Settings (Phase 4).

const LAYOUT_GESTURES := &"gestures"
const LAYOUT_CLASSIC := &"classic"
const _LAYOUT_SAVE_KEY := "control_layout"

## -1..1 horizontal movement for this physics frame.
var move_axis: float = 0.0
var jump_held: bool = false
var jump_just_pressed: bool = false
var raise_held: bool = false

## Active touch layout: LAYOUT_GESTURES or LAYOUT_CLASSIC.
var control_layout: StringName = LAYOUT_GESTURES

var _game: GameManager
var _save: SaveManager
var _bus: Node

# Touch (virtual) inputs from TouchControls
var _virtual_axis: float = 0.0
var _virtual_jump_latch: bool = false
var _virtual_jump_held: bool = false
var _virtual_raise: bool = false

func configure(game: GameManager, save: SaveManager = null, bus: Node = null) -> void:
	_game = game
	_save = save
	_bus = bus

func _ready() -> void:
	# Runs while paused (to unpause) and before every gameplay node in the frame.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	if _save:
		control_layout = StringName(_save.get_value(_LAYOUT_SAVE_KEY, String(LAYOUT_GESTURES)))

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		_clear()
		return
	move_axis = clampf(Input.get_axis(&"move_left", &"move_right") + _virtual_axis, -1.0, 1.0)
	jump_held = Input.is_action_pressed(&"jump") or _virtual_jump_held
	jump_just_pressed = Input.is_action_just_pressed(&"jump") or _virtual_jump_latch
	_virtual_jump_latch = false
	var can_raise := _game == null or _game.uses_raise()
	raise_held = can_raise and (Input.is_action_pressed(&"raise_light") or _virtual_raise)
	if Input.is_action_just_pressed(&"place_lantern") and _game:
		_game.report_place_lantern_pressed()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause") and _game:
		_game.report_pause_pressed()
		get_viewport().set_input_as_handled()

# ── Touch (virtual) inputs ────────────────────────────────────────────────

func set_virtual_axis(value: float) -> void:
	_virtual_axis = clampf(value, -1.0, 1.0)

## A touch jump: triggers a jump press for this physics frame.
func trigger_virtual_jump() -> void:
	_virtual_jump_latch = true

## Holds or releases the virtual jump button (for variable jump height on touch).
func set_virtual_jump_held(held: bool) -> void:
	_virtual_jump_held = held

func trigger_virtual_place() -> void:
	if _game:
		_game.report_place_lantern_pressed()

func set_virtual_raise(held: bool) -> void:
	_virtual_raise = held

func clear_virtual() -> void:
	_virtual_axis = 0.0
	_virtual_jump_latch = false
	_virtual_jump_held = false
	_virtual_raise = false

# ── Control layout ────────────────────────────────────────────────────────

func set_control_layout(layout: StringName) -> void:
	if layout != LAYOUT_GESTURES and layout != LAYOUT_CLASSIC:
		return
	control_layout = layout
	clear_virtual()
	if _save:
		_save.set_value(_LAYOUT_SAVE_KEY, String(layout))
		_save.save_game()
	if _bus:
		_bus.control_layout_changed.emit(layout)

func _clear() -> void:
	move_axis = 0.0
	jump_held = false
	jump_just_pressed = false
	raise_held = false
	_virtual_jump_held = false
	_virtual_raise = false
