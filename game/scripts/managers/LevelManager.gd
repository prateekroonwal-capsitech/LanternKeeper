class_name LevelManager
extends Node

## LevelManager — loads levels by ID, tracks unlocked / completed levels and
## answers next / previous level. Level data comes from LevelCatalog.
##
## Sends: SceneManager.go_to(path); SaveManager level-progress shortcuts.
## Receives: GameManager.report_level_exit_reached() → mark_completed(id).

const TEST_LEVEL_ID := "test"

var catalog: LevelCatalog

var _logger: Node
var _scene: SceneManager
var _save: SaveManager

func configure(logger: Node, scene: SceneManager, save: SaveManager, catalog_path: String) -> void:
	_logger = logger
	_scene = scene
	_save = save
	catalog = load(catalog_path) as LevelCatalog
	if catalog == null and _logger:
		_logger.error("LevelManager: level catalog missing", { "path": catalog_path })

# ── IDs ───────────────────────────────────────────────────────────────────

func make_id(world: int, number: int) -> String:
	return "w%d_%02d" % [world, number]

## Returns the 0-based catalog index of an id, or -1.
func get_level_index(level_id: String) -> int:
	if catalog == null or not level_id.begins_with("w") or level_id.length() < 5:
		return -1
	var parts := level_id.substr(1).split("_")
	if parts.size() != 2:
		return -1
	var world := parts[0].to_int()
	var number := parts[1].to_int()
	if world < 1 or number < 1 or number > catalog.levels_per_world:
		return -1
	return (world - 1) * catalog.levels_per_world + (number - 1)

func get_id_at(index: int) -> String:
	if catalog == null or index < 0:
		return ""
	var per := catalog.levels_per_world
	return make_id(index / per + 1, index % per + 1)

func get_level_count() -> int:
	return catalog.world_names.size() * catalog.levels_per_world if catalog else 0

func get_level_path(level_id: String) -> String:
	if catalog == null:
		return ""
	if level_id == TEST_LEVEL_ID:
		return catalog.test_level_path
	var i := get_level_index(level_id)
	if i < 0 or i >= catalog.level_paths.size():
		return ""
	return catalog.level_paths[i]

func has_level(level_id: String) -> bool:
	var path := get_level_path(level_id)
	return not path.is_empty() and ResourceLoader.exists(path)

func get_next_level_id(level_id: String) -> String:
	var i := get_level_index(level_id)
	if i < 0 or i + 1 >= get_level_count():
		return ""
	return get_id_at(i + 1)

func get_previous_level_id(level_id: String) -> String:
	var i := get_level_index(level_id)
	return get_id_at(i - 1) if i > 0 else ""

# ── Loading ───────────────────────────────────────────────────────────────

func load_level(level_id: String) -> void:
	if not has_level(level_id):
		if _logger:
			_logger.warn("LevelManager: no scene for level", { "id": level_id })
		return
	_scene.go_to(get_level_path(level_id))

# ── Progress ──────────────────────────────────────────────────────────────

func is_unlocked(level_id: String) -> bool:
	if level_id == TEST_LEVEL_ID:
		return true
	var i := get_level_index(level_id)
	return i >= 0 and _save != null and i < _save.get_unlocked_level_count()

func is_completed(level_id: String) -> bool:
	return _save != null and _save.is_level_completed(level_id)

func mark_completed(level_id: String) -> void:
	if _save == null or level_id == TEST_LEVEL_ID:
		return
	var i := get_level_index(level_id)
	if i < 0:
		return
	_save.mark_level_completed(level_id, i + 2)
