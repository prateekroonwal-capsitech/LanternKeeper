class_name FallFX
extends Node3D

## FallFX — the "feel" of something heavy giving way, placed inside every falling or
## collapsing prop's scene (rock on a rope, ceiling slab, cracked planks). The prop drives it:
##   anticipate(target) — creak / crack sound, the target wobbles, dust and pebbles trickle
##   fall()             — the trickle stops, a light debris trail follows it down
##   impact()           — dust burst, debris chunks, heavy thud, camera shake scaled by
##                        `size`, a short dark screen pulse, phone / pad vibration
##   stop()             — everything off and the target back in place (checkpoint reset)
## All particles are children placed in FallFX.tscn; sounds are AudioLibrary events.
##
## Sends: GameManager.report_fall_warning(), report_impact(point, strength).
## Receives: calls from its prop (FallingTrap, CollapsingPlatform).

## How big the object feels: scales the camera shake, the pulse and the debris burst.
@export_range(0.1, 3.0) var size: float = 1.0
## Seconds of warning before the fall (the prop waits this long).
@export var anticipation_time: float = 0.45
@export var wobble_amount: float = 0.05
@export var wobble_speed: float = 38.0
## Camera shake at size 1 (scaled by `size`).
@export var shake_strength: float = 0.3
@export var shake_duration: float = 0.35
## Dark screen pulse alpha at size 1 (0 = none).
@export var pulse_strength: float = 0.22
@export var pulse_time: float = 0.25

var _game: GameManager
var _target: Node3D
var _rest: Vector3
var _wobble_t: float = -1.0
var _pulse_t: float = -1.0

@onready var _trickle: CPUParticles3D = $Trickle
@onready var _pebbles: CPUParticles3D = $Pebbles
@onready var _trail: CPUParticles3D = $Trail
@onready var _dust: CPUParticles3D = $ImpactDust
@onready var _chunks: CPUParticles3D = $ImpactChunks
@onready var _pulse: ColorRect = $Overlay/Pulse

func _ready() -> void:
	_pulse.color.a = 0.0
	_dust.amount = maxi(int(_dust.amount * clampf(size, 0.5, 2.0)), 4)
	_chunks.amount = maxi(int(_chunks.amount * clampf(size, 0.5, 2.0)), 3)
	set_process(false)

func inject_services(registry: Node) -> void:
	if registry:
		_game = registry.get_service(&"game") as GameManager

func anticipate(target: Node3D) -> void:
	stop()
	_target = target
	if _target:
		_rest = _target.position
	_wobble_t = 0.0
	_trickle.emitting = true
	_pebbles.emitting = true
	set_process(true)
	if _game:
		_game.report_fall_warning()

func fall() -> void:
	_end_wobble()
	_trickle.emitting = false
	_pebbles.emitting = false
	_trail.emitting = true

func impact() -> void:
	_trail.emitting = false
	_dust.restart()
	_chunks.restart()
	_pulse_t = 0.0
	set_process(true)
	if _game:
		_game.report_impact(global_position, size)

func stop() -> void:
	_end_wobble()
	for p in [_trickle, _pebbles, _trail]:
		p.emitting = false
	_pulse_t = -1.0
	_pulse.color.a = 0.0
	set_process(false)

func _end_wobble() -> void:
	if _target and _wobble_t >= 0.0:
		_target.position = _rest
	_wobble_t = -1.0

func _process(delta: float) -> void:
	if _wobble_t >= 0.0 and _target:
		_wobble_t += delta
		var k := clampf(_wobble_t / maxf(anticipation_time, 0.01), 0.0, 1.0)   # grows toward the fall
		_target.position = _rest + Vector3(sin(_wobble_t * wobble_speed), cos(_wobble_t * wobble_speed * 1.3) * 0.5, 0.0) * wobble_amount * (0.4 + k)
	if _pulse_t >= 0.0:
		_pulse_t += delta
		var u := clampf(_pulse_t / maxf(pulse_time, 0.01), 0.0, 1.0)
		_pulse.color.a = pulse_strength * clampf(size, 0.3, 1.5) * (1.0 - u)
		if u >= 1.0:
			_pulse_t = -1.0
	if _wobble_t < 0.0 and _pulse_t < 0.0:
		set_process(false)
