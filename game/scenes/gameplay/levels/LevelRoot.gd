class_name LevelRoot
extends Node3D

## LevelRoot — root script of every hand-built level scene.
## Holds the per-level tunables (oil, dark meter, respawn) and the spawn point,
## and tells GameManager when the level is ready / unloaded.
##
## Sends: GameManager.report_level_ready(self), GameManager.report_level_unloaded(self)
## Receives: nothing. GameManager reads the exported values below.
##
## Running a level directly (F6) restarts through Boot so the managers exist.

const BOOT_SCENE := "res://game/scenes/boot/Boot.tscn"
const DEV_BOOT_META := &"dev_boot_scene"

## ID used by LevelManager and the save file, e.g. "w1_01". Use "test" for sandboxes.
@export var level_id: String = "test"
## Where the player starts and respawns until a shrine is lit.
@export var spawn_point: Marker3D

@export_group("Oil")
@export var max_oil: float = 100.0
@export var start_oil: float = 100.0

@export_group("Darkness")
## Seconds the player can stay outside all light before the shadows rush.
@export var dark_meter_time: float = 5.0
## Dark-meter seconds regained per second while in light.
@export var dark_meter_refill_rate: float = 2.0

@export_group("Death")
## Seconds between a death and the respawn.
@export var respawn_delay: float = 0.6

var _game: GameManager

func _ready() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry and not registry.has_service(&"game"):
		# Started with F6: boot the services first, then come back here.
		registry.set_meta(DEV_BOOT_META, scene_file_path)
		get_tree().change_scene_to_file.call_deferred(BOOT_SCENE)

func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game:
		# Deferred so every child has been injected before the level starts.
		_game.report_level_ready.call_deferred(self)

func _exit_tree() -> void:
	if _game:
		_game.report_level_unloaded(self)

func get_spawn_position() -> Vector3:
	return spawn_point.global_position if spawn_point else global_position
