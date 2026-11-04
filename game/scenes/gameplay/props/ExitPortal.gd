class_name ExitPortal
extends Area3D

## ExitPortal — the way out of every level: the old exit gate with a swirl, glow and
## drifting motes. When the child walks in, play stops (input locks), the child and the
## lantern are pulled to the centre and shrink to nothing (`pull_time`, no spin), the
## screen flashes and fades to black, and the level-complete screen opens.
## Nothing is created at runtime: the swirl, particles, light and the flash / fade
## overlays are all in ExitPortal.tscn.
##
## Sends: GameManager.report_level_exit_reached(menu_delay) — the menu waits for the whole
##   sequence.
## Receives: nothing (polls the child and the lantern through GameManager).

## Point the child is pulled into, relative to the portal (the middle of the opening).
@export var center_offset: Vector3 = Vector3(0.0, 1.15, -0.4)
## Seconds the child takes to be pulled in and shrink to nothing.
@export var pull_time: float = 0.8
@export var flash_in_time: float = 0.08
@export var flash_out_time: float = 0.2
@export var fade_time: float = 0.45
## Extra pause on black before the level-complete screen opens.
@export var hold_time: float = 0.1
@export var flash_color: Color = Color(0.85, 0.95, 1.0, 1.0)

var _game: GameManager
var _active: bool = false
var _t: float = 0.0
var _player: Node3D
var _lantern: Node3D
var _player_from: Vector3
var _lantern_from: Vector3
var _lantern_scale: Vector3

@onready var _swirl: MeshInstance3D = $Swirl
@onready var _motes: CPUParticles3D = $Motes
@onready var _light: OmniLight3D = $Light
@onready var _flash: ColorRect = $Overlay/Flash
@onready var _fade: ColorRect = $Overlay/Fade

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_flash.color = Color(flash_color, 0.0)
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	set_process(false)

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func _on_body_entered(body: Node3D) -> void:
	if _active or _game == null or not _game.is_playing() or not body.is_in_group(&"player"):
		return
	_active = true
	_player = body
	_lantern = _game.get_lantern()   # the active lantern: the carried one, else the nearest
	_player_from = _player.global_position
	if is_instance_valid(_lantern):
		_lantern_from = _lantern.global_position
		_lantern_scale = _lantern.scale
	var total := pull_time + flash_in_time + flash_out_time + fade_time + hold_time
	print("[ExitPortal] %s entered — sequence %.2f s" % [owner.name if owner else name, total])
	_game.report_level_exit_reached(total)   # play stops here: input locks
	_t = 0.0
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	var center := global_position + center_offset
	# 1. Pulled in: to the centre, shrinking to nothing (upright, no spin).
	var u := clampf(_t / maxf(pull_time, 0.01), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var size := maxf(1.0 - e, 0.001)
	if is_instance_valid(_player):
		_player.global_position = _player_from.lerp(center - Vector3(0.0, 0.7 * size, 0.0), e)
		_player.scale = Vector3.ONE * size
	if is_instance_valid(_lantern):
		var lantern_carried: bool = _lantern.get("carried") == true
		if not lantern_carried:
			_lantern.global_position = _lantern_from.lerp(center, e)
		_lantern.scale = _lantern_scale * size
	(_swirl.material_override as ShaderMaterial).set_shader_parameter(&"collapse", e)
	_light.light_energy = 1.4 + 2.5 * e
	# 2. Flash, then fade to black.
	var t2 := _t - pull_time
	if t2 >= 0.0:
		if is_instance_valid(_player):
			_player.visible = false
		if is_instance_valid(_lantern):
			_lantern.visible = false
		var f := 0.0
		if t2 < flash_in_time:
			f = t2 / maxf(flash_in_time, 0.01)
		elif t2 < flash_in_time + flash_out_time:
			f = 1.0 - (t2 - flash_in_time) / maxf(flash_out_time, 0.01)
		_flash.color.a = clampf(f, 0.0, 1.0)
		var t3 := t2 - flash_in_time
		_fade.color.a = clampf(t3 / maxf(fade_time, 0.01), 0.0, 1.0)
		if t2 >= flash_in_time + flash_out_time + fade_time:
			_flash.color.a = 0.0
			_fade.color.a = 1.0
			print("[ExitPortal] sequence done (%.2f s) — level-complete screen next" % _t)
			set_process(false)
