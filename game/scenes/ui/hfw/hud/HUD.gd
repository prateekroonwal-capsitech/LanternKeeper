class_name HUD
extends UIController

## HUD — Limbo-style: nothing on screen during play. State shows through the world:
## in OIL mode, low oil flickers and shrinks the lantern (Lantern.gd); running out of dark meter
## closes DarkOverlay's vignette in from screen edges without dimming the light circle, draining
## colour outside (plus the heartbeat from AudioManager). Only a faint pause button remains, on touch screens.
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
	if _overlay.visible:
		_update_light_uniforms()

func _update_light_uniforms() -> void:
	if not is_instance_valid(_game_manager):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if viewport_size.y <= 0.0:
		return

	var active_lights := _game_manager.get_active_light_sources()
	var count := mini(active_lights.size(), 4)

	for i in range(4):
		var pos_param := StringName("light%d_pos" % (i + 1))
		var rad_param := StringName("light%d_radius" % (i + 1))
		if i < count:
			var light: Node3D = active_lights[i]
			var pos_3d: Vector3 = light.get_light_position()
			var radius_3d: float = light.get_light_radius()
			if not camera.is_position_behind(pos_3d) and radius_3d > 0.05:
				var center_2d := camera.unproject_position(pos_3d)
				var edge_3d := pos_3d + camera.global_transform.basis.x * radius_3d
				var edge_2d := camera.unproject_position(edge_3d)
				var radius_screen := (edge_2d - center_2d).length() / viewport_size.y
				var uv := center_2d / viewport_size
				_overlay_material.set_shader_parameter(pos_param, uv)
				_overlay_material.set_shader_parameter(rad_param, radius_screen)
			else:
				_overlay_material.set_shader_parameter(pos_param, Vector2(-1.0, -1.0))
				_overlay_material.set_shader_parameter(rad_param, 0.0)
		else:
			_overlay_material.set_shader_parameter(pos_param, Vector2(-1.0, -1.0))
			_overlay_material.set_shader_parameter(rad_param, 0.0)

func _on_game_state_changed(state: int) -> void:
	visible = state in [GameManager.State.PLAYING, GameManager.State.PAUSED, GameManager.State.DEAD]
	if state == GameManager.State.MENU:
		_target_darkness = 0.0
		_darkness = 0.0
