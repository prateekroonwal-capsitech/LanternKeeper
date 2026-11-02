class_name HUD
extends UIController

## HUD — Limbo-style: nothing on screen during play. State shows through the world:
## low oil = the lantern flickers and its light shrinks (Lantern.gd); a running-out dark
## meter = DarkOverlay closes a vignette in from the edges and drains colour (plus the
## heartbeat from AudioManager). Only a faint pause button remains, on touch screens.
##
## Sends: GameManager.report_pause_pressed() (pause button).
## Receives: GameBus.dark_meter_changed, game_state_changed.

## How quickly the overlay follows the dark meter.
@export var darkness_smoothing: float = 4.0
## Pause button opacity (touch screens only).
@export_range(0.0, 1.0) var pause_button_alpha: float = 0.35

@onready var _overlay: ColorRect = %DarkOverlay
@onready var _overlay_material: ShaderMaterial = _overlay.material
@onready var _pause_button: TextureButton = %PauseButton

var _target_darkness: float = 0.0
var _darkness: float = 0.0

func _on_ready() -> void:
	var bus: Node = _game_manager.bus
	bus.dark_meter_changed.connect(func(ratio: float) -> void: _target_darkness = 1.0 - ratio)
	bus.game_state_changed.connect(_on_game_state_changed)
	_pause_button.pressed.connect(_game_manager.report_pause_pressed)
	_pause_button.visible = DisplayServer.is_touchscreen_available()
	_pause_button.modulate.a = pause_button_alpha
	_on_game_state_changed(_game_manager.state)
	set_process(true)

func _process(delta: float) -> void:
	_darkness = lerpf(_darkness, _target_darkness, 1.0 - exp(-darkness_smoothing * delta))
	_overlay.visible = _darkness > 0.01
	_overlay_material.set_shader_parameter(&"darkness", _darkness)

func _on_game_state_changed(state: int) -> void:
	visible = state in [GameManager.State.PLAYING, GameManager.State.PAUSED, GameManager.State.DEAD]
	if state == GameManager.State.MENU:
		_target_darkness = 0.0
		_darkness = 0.0
