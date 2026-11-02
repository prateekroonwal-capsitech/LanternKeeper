class_name HUD
extends UIController

## HUD — minimal in-level display: oil bar, dark meter (only shown while it drains),
## a darkness vignette that closes in as the meter empties, a pause button, and the
## level's title card ("1-3  Sinking Light") that fades in and out when a level starts.
## Visible only while a level is running.
##
## Sends: GameManager.report_pause_pressed() (pause button).
## Receives: GameBus.oil_changed, dark_meter_changed, game_state_changed, level_started
##   (hides the oil bar / dark meter in levels that don't use them).

## Oil ratio below which the oil bar pulses.
@export_range(0.0, 1.0) var low_oil_ratio: float = 0.2
@export var low_oil_pulse_speed: float = 6.0
@export var low_oil_color: Color = Color(1.0, 0.45, 0.35)
## Darkest the vignette gets when the dark meter is empty.
@export_range(0.0, 1.0) var vignette_max_alpha: float = 0.9
## How fast the dark meter fades in/out.
@export var dark_meter_fade_speed: float = 6.0
## Title card timing (seconds).
@export var title_fade_time: float = 0.6
@export var title_hold_time: float = 1.8

@onready var _oil_row: Control = %OilBar.get_parent()
@onready var _oil_bar: TextureProgressBar = %OilBar
@onready var _dark_meter: Control = %DarkMeter
@onready var _dark_ring: TextureProgressBar = %DarkRing
@onready var _vignette: TextureRect = %DarkVignette
@onready var _pause_button: TextureButton = %PauseButton
@onready var _title: Label = %LevelTitle
var _title_tween: Tween

var _oil_ratio: float = 1.0
var _dark_ratio: float = 1.0
var _time: float = 0.0

func _on_ready() -> void:
	var bus: Node = _game_manager.bus
	bus.oil_changed.connect(_on_oil_changed)
	bus.dark_meter_changed.connect(_on_dark_meter_changed)
	bus.game_state_changed.connect(_on_game_state_changed)
	bus.level_started.connect(func(_id: String) -> void:
		_oil_row.visible = _game_manager.uses_oil()
		_dark_meter.visible = _game_manager.uses_dark_meter()
		_show_title())
	_pause_button.pressed.connect(_game_manager.report_pause_pressed)
	_dark_meter.modulate.a = 0.0
	_vignette.modulate.a = 0.0
	_title.modulate.a = 0.0
	_on_game_state_changed(_game_manager.state)
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	var target := 1.0 if _dark_ratio < 0.999 else 0.0
	_dark_meter.modulate.a = move_toward(_dark_meter.modulate.a, target, delta * dark_meter_fade_speed)
	if _oil_ratio < low_oil_ratio and _oil_ratio > 0.0:
		var pulse := 0.5 + 0.5 * sin(_time * low_oil_pulse_speed)
		_oil_bar.tint_progress = Color.WHITE.lerp(low_oil_color, pulse)
	else:
		_oil_bar.tint_progress = Color.WHITE

func _show_title() -> void:
	var level := _game_manager.current_level
	if level == null or level.title_key.is_empty():
		_title.modulate.a = 0.0
		return
	var number := _game_manager.level.get_level_index(level.level_id) % _game_manager.level.catalog.levels_per_world + 1
	_title.text = "%d-%d   %s" % [level.world, number, tr(level.title_key)]
	if _title_tween:
		_title_tween.kill()
	_title.modulate.a = 0.0
	_title_tween = create_tween()
	_title_tween.tween_property(_title, "modulate:a", 1.0, title_fade_time)
	_title_tween.tween_interval(title_hold_time)
	_title_tween.tween_property(_title, "modulate:a", 0.0, title_fade_time)

func _on_oil_changed(oil: float, max_oil: float) -> void:
	_oil_bar.max_value = max_oil
	_oil_bar.value = oil
	_oil_ratio = oil / max_oil if max_oil > 0.0 else 0.0

func _on_dark_meter_changed(ratio: float) -> void:
	_dark_ratio = ratio
	_dark_ring.value = ratio * _dark_ring.max_value
	_vignette.modulate.a = (1.0 - ratio) * vignette_max_alpha

func _on_game_state_changed(state: int) -> void:
	visible = state in [GameManager.State.PLAYING, GameManager.State.PAUSED, GameManager.State.DEAD]
