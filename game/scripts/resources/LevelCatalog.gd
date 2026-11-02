class_name LevelCatalog
extends Resource

## LevelCatalog — the ordered list of every level scene, edited in the Inspector
## (game/resources/level_catalog.tres). LevelManager reads it; nothing else does.
##
## Level IDs are "w<world>_<level>", e.g. "w1_01" … "w4_10". Slot order in
## level_paths is world-major: index = (world - 1) * levels_per_world + (level - 1).
## Leave a slot empty until that level scene exists.

@export var levels_per_world: int = 10
@export var world_names: PackedStringArray = PackedStringArray(["Light", "Oil", "Shadows", "Mirrors"])
@export var level_paths: PackedStringArray = PackedStringArray()
## Menu backdrop scene (main menu and level select are shown over it).
@export_file("*.tscn") var menu_scene_path: String = "res://game/scenes/Home/Home.tscn"
## Sandbox level loaded with the id "test".
@export_file("*.tscn") var test_level_path: String = ""
