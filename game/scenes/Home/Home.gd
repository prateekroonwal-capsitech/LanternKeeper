class_name HomeScene
extends Node3D

## HomeScene — the menu backdrop: the boy on a ledge with his lantern, parallax
## background, menu music. The main menu / level select (UIRoot screens) open over it.
## BootScene transitions here; GameManager returns here from levels.
##
## Sends: GameManager.report_menu_ready()
## Receives: nothing.

const BOOT_SCENE := "res://game/scenes/boot/Boot.tscn"
const DEV_BOOT_META := &"dev_boot_scene"

var _game: GameManager

func _ready() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry and not registry.has_service(&"game"):
		# Started with F6: boot the services first, then come back here.
		registry.set_meta(DEV_BOOT_META, scene_file_path)
		get_tree().change_scene_to_file.call_deferred(BOOT_SCENE)

## Convention-based auto-wiring for visually placed scenes (Pattern 2).
func inject_services(registry: Node) -> void:
	if not registry:
		return
	_game = registry.get_service(&"game") as GameManager
	if _game:
		_game.report_menu_ready.call_deferred()
