class_name LevelSelect
extends MenuScreen

## LevelSelect — one world at a time (arrows switch worlds), 10 level slots placed
## in the grid. Slots show locked / open / completed from LevelManager + save data.
## Opens on the world of the furthest unlocked level.
##
## Sends: GameManager.start_level(id); UIManager.close_menu() (Back).
## Receives: LevelManager queries via GameManager.level.

@onready var _title: Label = %WorldTitle
@onready var _prev: TextureButton = %PrevWorld
@onready var _next: TextureButton = %NextWorld
@onready var _grid: GridContainer = %Grid
@onready var _back: Button = %BackButton

var _world: int = 1

func _on_menu_ready() -> void:
	_prev.pressed.connect(_change_world.bind(-1))
	_next.pressed.connect(_change_world.bind(1))
	_back.pressed.connect(_ui_manager.close_menu)
	for slot in _grid.get_children():
		(slot as LevelButton).chosen.connect(_game_manager.start_level)

func _on_shown() -> void:
	_world = _furthest_unlocked_world()
	_refresh()
	_focus_first_open_slot.call_deferred()

func _change_world(step: int) -> void:
	_world = clampi(_world + step, 1, _world_count())
	_refresh()

func _refresh() -> void:
	var levels := _game_manager.level
	_title.text = tr("SELECT_WORLD") % [_world, tr("WORLD_NAME_%d" % _world)]
	_prev.disabled = _world <= 1
	_next.disabled = _world >= _world_count()
	_prev.modulate.a = 0.3 if _prev.disabled else 1.0
	_next.modulate.a = 0.3 if _next.disabled else 1.0
	var number := 1
	for slot in _grid.get_children():
		var id := levels.make_id(_world, number)
		var open := levels.is_unlocked(id) and levels.has_level(id)
		(slot as LevelButton).setup(id, number, open, levels.is_completed(id))
		number += 1

func _focus_first_open_slot() -> void:
	for slot in _grid.get_children():
		if not (slot as LevelButton).disabled:
			(slot as LevelButton).grab_focus()
			return
	_back.grab_focus()

func _world_count() -> int:
	var levels := _game_manager.level
	return levels.catalog.world_names.size() if levels and levels.catalog else 1

func _furthest_unlocked_world() -> int:
	var levels := _game_manager.level
	var world := 1
	for w in range(1, _world_count() + 1):
		if levels.is_unlocked(levels.make_id(w, 1)) and levels.has_level(levels.make_id(w, 1)):
			world = w
	return world
