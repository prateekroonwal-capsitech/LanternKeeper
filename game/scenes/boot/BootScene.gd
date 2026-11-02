class_name BootScene
extends Node

## BootScene — Entry point bootstrap scene
## Initializes core services and transitions to Home.
## Dev shortcut: a level run directly (F6) stores its path as ServiceRegistry meta
## "dev_boot_scene" and restarts here; Boot then loads that level instead of Home.

const DEV_BOOT_META := &"dev_boot_scene"

@export var next_scene_path: String = "res://game/scenes/Home/Home.tscn"
@onready var services: Node = $GameService

func _ready() -> void:
	if services and services.logger:
		services.logger.info("Bootstrap sequence started...")
	
	# Transition to initial game scene / Home
	_transition_to_game()

func _transition_to_game() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry and registry.has_meta(DEV_BOOT_META):
		next_scene_path = registry.get_meta(DEV_BOOT_META)
		registry.remove_meta(DEV_BOOT_META)
	if services and services.scene and ResourceLoader.exists(next_scene_path):
		services.scene.go_to(next_scene_path)
	elif services and services.logger:
		services.logger.info("Bootstrap complete. Ready for gameplay scenes.")
