class_name TouchControls
extends UIController

## TouchControls — on-screen touch input, shown only on touchscreens during a level.
##
## Gestures layout (default):
##   left half  — drag: floating joystick appears where the thumb lands
##   right half — tap: jump (on release) · swipe up: jump (the moment the swipe is long
##   enough) · swipe down: place lantern · hold: raise the light. One touch gives at most
##   one jump.
## Classic layout: visible TouchScreenButtons that press the InputMap actions directly.
## Lantern pick-up is automatic, so there is no button for it.
##
## Sends: InputManager (via GameManager.input) set_virtual_axis, trigger_virtual_jump,
##   trigger_virtual_place, set_virtual_raise.
## Receives: GameBus.game_state_changed, GameBus.control_layout_changed.

@export_group("Joystick")
## Thumb travel (base-resolution px) for full speed.
@export var joystick_radius: float = 110.0
@export_range(0.0, 0.9) var joystick_deadzone: float = 0.2

@export_group("Right-half gestures")
## A touch released before this many seconds (without swiping) is a jump tap;
## a touch held longer becomes "raise the light".
@export var hold_time: float = 0.35
## Movement (px) allowed before a tap stops counting as a tap.
@export var tap_max_distance: float = 70.0
## Downward travel (px) that counts as a swipe.
@export var swipe_min_distance: float = 90.0
@export var swipe_max_time: float = 0.4
## Upward travel (px) that counts as a swipe-up jump…
@export var swipe_up_min_distance: float = 60.0
## …if reached within this many seconds of touching down.
@export var swipe_up_max_time: float = 0.25

@export_group("Layout")
## Touches that start in this many px from the top belong to HUD buttons (pause).
@export var ignore_top_margin: float = 170.0
## Show the controls with a mouse too (for testing on PC).
@export var show_without_touchscreen: bool = false

enum RightMode { NONE, PENDING, HOLD, SWIPED, JUMPED }

@onready var _gestures: Control = $Gestures
@onready var _joystick: Control = $Gestures/Joystick
@onready var _knob: Control = $Gestures/Joystick/Knob
@onready var _classic: Control = $Classic

var _left_index: int = -1
var _left_origin: Vector2
var _right_index: int = -1
var _right_start: Vector2
var _right_time: float = 0.0
var _right_mode: RightMode = RightMode.NONE

func _on_ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_manager.bus.game_state_changed.connect(func(_s: int) -> void: _refresh())
	_game_manager.bus.control_layout_changed.connect(func(_l: StringName) -> void: _refresh())
	_joystick.hide()
	_refresh()

func _refresh() -> void:
	var s := _game_manager.state
	var in_level := s == GameManager.State.PLAYING or s == GameManager.State.DEAD
	visible = in_level and (DisplayServer.is_touchscreen_available() or show_without_touchscreen)
	var gestures := _game_manager.input.control_layout == InputManager.LAYOUT_GESTURES
	_gestures.visible = gestures
	_classic.visible = not gestures
	if not visible or not gestures:
		_release_all()
	set_process(visible and gestures)

func _input(event: InputEvent) -> void:
	if not visible or not _gestures.visible:
		return
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_drag(event)

func _on_touch(e: InputEventScreenTouch) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if e.pressed:
		if e.position.y < ignore_top_margin:
			return
		if e.position.x < half and _left_index == -1:
			_left_index = e.index
			_left_origin = e.position
			_joystick.position = e.position
			_knob.position = Vector2.ZERO
			_joystick.show()
		elif e.position.x >= half and _right_index == -1:
			_right_index = e.index
			_right_start = e.position
			_right_time = 0.0
			_right_mode = RightMode.PENDING
	else:
		if e.index == _left_index:
			_release_left()
		elif e.index == _right_index:
			if _right_mode == RightMode.PENDING and e.position.distance_to(_right_start) <= tap_max_distance:
				_game_manager.input.trigger_virtual_jump()
			_release_right()

func _on_drag(e: InputEventScreenDrag) -> void:
	if e.index == _left_index:
		var v := e.position - _left_origin
		_knob.position = v.limit_length(joystick_radius)
		var axis := clampf(v.x / joystick_radius, -1.0, 1.0)
		if absf(axis) < joystick_deadzone:
			axis = 0.0
		_game_manager.input.set_virtual_axis(axis)
	elif e.index == _right_index and _right_mode == RightMode.PENDING:
		var d := e.position - _right_start
		if d.y >= swipe_min_distance and absf(d.y) > absf(d.x) and _right_time <= swipe_max_time:
			_right_mode = RightMode.SWIPED
			_game_manager.input.trigger_virtual_place()
		elif -d.y >= swipe_up_min_distance and absf(d.y) > absf(d.x) and _right_time <= swipe_up_max_time:
			_right_mode = RightMode.JUMPED      # this touch is a jump now: its release won't tap-jump
			_game_manager.input.trigger_virtual_jump()

func _process(delta: float) -> void:
	if _right_mode != RightMode.PENDING:
		return
	_right_time += delta
	if _right_time >= hold_time:
		_right_mode = RightMode.HOLD
		_game_manager.input.set_virtual_raise(true)

func _release_left() -> void:
	_left_index = -1
	_joystick.hide()
	_game_manager.input.set_virtual_axis(0.0)

func _release_right() -> void:
	if _right_mode == RightMode.HOLD:
		_game_manager.input.set_virtual_raise(false)
	_right_index = -1
	_right_mode = RightMode.NONE

func _release_all() -> void:
	if _left_index != -1:
		_release_left()
	if _right_index != -1:
		_release_right()
