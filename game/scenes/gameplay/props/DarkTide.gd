class_name DarkTide
extends Area3D

## DarkTide — a wall of darkness that sweeps left → right after the level starts.
## Touching it kills. It only moves while the game is PLAYING; after a respawn it
## restarts `restart_gap` metres behind the checkpoint (never behind where it was placed).
## Used by chase levels (World 1-10).
##
## Sends: GameManager.report_player_died("tide")
## Receives: GameBus.level_started (start), GameBus.level_reset (rewind behind checkpoint);
##   GameManager.get_respawn_position() (polled on reset).

@export var speed: float = 4.0
## Seconds before the tide starts moving (after the level starts or after a respawn).
@export var start_delay: float = 1.5
## How far behind the checkpoint the tide restarts after a death.
@export var restart_gap: float = 14.0
## The tide stops here (world X).
@export var end_x: float = 1000.0

@export_group("Look")
@export var wobble_speed: float = 1.3
@export var wobble_amount: float = 0.06

var _game: GameManager
var _start_x: float = 0.0
var _delay_left: float = 0.0
var _time: float = 0.0

@onready var _edge: Sprite3D = $Edge
@onready var _edge_base_scale: Vector3 = _edge.scale

func _ready() -> void:
	_start_x = global_position.x
	_delay_left = start_delay
	body_entered.connect(_on_body_entered)
	set_physics_process(false)

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game == null:
		return
	_game.bus.level_started.connect(func(_id: String) -> void: _rewind(_start_x))
	_game.bus.level_reset.connect(func(_serial: int) -> void:
		_rewind(maxf(_start_x, _game.get_respawn_position().x - restart_gap)))
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	_time += delta
	_edge.scale = Vector3(_edge_base_scale.x * (1.0 + sin(_time * wobble_speed * TAU) * wobble_amount),
		_edge_base_scale.y, _edge_base_scale.z)
	if not _game.is_playing():
		return
	if _delay_left > 0.0:
		_delay_left -= delta
		return
	global_position.x = minf(global_position.x + speed * delta, end_x)

func _rewind(x: float) -> void:
	global_position.x = x
	_delay_left = start_delay
	reset_physics_interpolation()

func _on_body_entered(body: Node3D) -> void:
	if _game and body.is_in_group(&"player"):
		_game.report_player_died("tide")
