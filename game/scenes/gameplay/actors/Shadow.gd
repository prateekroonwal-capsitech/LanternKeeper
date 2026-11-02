class_name Shadow
extends Area3D

## Shadow — creature of the dark. Floats freely (passes through terrain).
##   Player in darkness → creeps toward the player (if within notice_radius).
##   Dark meter empty   → rushes the player (if within rush_radius).
##   Player in light    → freezes.
##   Shadow itself lit  → retreats away from the light. It never steps into light.
## Red eyes are always visible. Touching it kills the player.
##
## Sends: GameManager.report_player_died("shadow")
## Receives: GameManager.player_lit / is_dark_meter_empty() / is_point_lit() /
##   get_nearest_light_position() (polled); GameBus.level_reset → back to its home spot.

@export_group("Movement")
@export var creep_speed: float = 1.6
@export var rush_speed: float = 7.5
@export var retreat_speed: float = 4.0
## Starts creeping when the player (in darkness) is this close.
@export var notice_radius: float = 9.0
## Rushes when the dark meter is empty and the player is this close.
@export var rush_radius: float = 14.0
## Never wanders further than this from where it was placed (rushes ignore it).
@export var territory_radius: float = 8.0
## Body size used for the "is the shadow in light?" test.
@export var body_radius: float = 0.4

@export_group("Look")
@export var idle_pulse_speed: float = 1.5
@export var move_stretch: float = 0.15
## Eye colour (values > 1 make the eyes bloom).
@export var eye_color: Color = Color(2.6, 0.18, 0.12, 1.0)

var _game: GameManager
var _home: Vector3
var _time: float = 0.0
var _speed_now: float = 0.0

@onready var _body: Sprite3D = $Body
@onready var _eyes: Sprite3D = $Eyes
@onready var _body_base_scale: Vector3 = _body.scale

func _ready() -> void:
	_home = global_position
	_eyes.modulate = eye_color
	body_entered.connect(_on_body_entered)
	set_physics_process(false)
	_time = randf() * TAU

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.bus.level_reset.connect(_on_level_reset)
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_time += delta
	_speed_now = 0.0
	if _game.is_playing():
		_think(delta)
	_animate(delta)

func _think(delta: float) -> void:
	var pos := global_position
	if _game.is_point_lit(pos, body_radius):
		var away := _flat(pos - _game.get_nearest_light_position(pos))
		if away.length_squared() < 0.0001:
			away = Vector3.UP
		_step(away.normalized() * retreat_speed * delta)
		return
	if _game.player_lit:
		return
	var target := _game.get_player_position() + Vector3(0.0, 0.8, 0.0)
	var to_player := _flat(target - pos)
	var dist := to_player.length()
	var speed := 0.0
	var leashed := true
	if _game.is_dark_meter_empty() and dist <= rush_radius:
		speed = rush_speed
		leashed = false
	elif dist <= notice_radius:
		speed = creep_speed
	if speed <= 0.0 or dist < 0.01:
		return
	var next := pos + to_player / dist * minf(speed * delta, dist)
	if leashed and _flat(next - _home).length() > territory_radius:
		return
	if _game.is_point_lit(next, body_radius):
		return
	_step(next - pos)

func _step(motion: Vector3) -> void:
	global_position += motion
	global_position.z = _home.z
	_speed_now = motion.length()

func _animate(delta: float) -> void:
	var pulse := 1.0 + 0.06 * sin(_time * idle_pulse_speed * TAU)
	var stretch := clampf(_speed_now / maxf(rush_speed * delta, 0.0001), 0.0, 1.0) * move_stretch
	_body.scale = Vector3(_body_base_scale.x * (pulse + stretch), _body_base_scale.y * (pulse - stretch * 0.5), _body_base_scale.z)
	_body.modulate.a = 0.85 + 0.15 * sin(_time * 3.1)

func _on_body_entered(body: Node3D) -> void:
	if _game and body.is_in_group(&"player"):
		_game.report_player_died("shadow")

func _on_level_reset(_checkpoint_serial: int) -> void:
	global_position = _home
	reset_physics_interpolation()

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y, 0.0)
