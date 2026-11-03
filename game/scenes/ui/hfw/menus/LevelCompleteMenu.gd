class_name LevelCompleteMenu
extends MenuScreen

## LevelCompleteMenu — shown after the exit: "Level N complete" (N from the level id, e.g.
## w1_03 → 3), then Next level (hidden on the last level), Replay, Level select.
##
## Sends: GameManager.go_to_next_level() / restart_level() / go_to_level_select().
## Receives: opened by GameManager after report_level_exit_reached().

@onready var _title: Label = $Center/Panel/Column/Title
@onready var _next: Button = %NextButton
@onready var _replay: Button = %ReplayButton
@onready var _levels: Button = %LevelsButton

func _on_menu_ready() -> void:
	_next.pressed.connect(_game_manager.go_to_next_level)
	_replay.pressed.connect(_game_manager.restart_level)
	_levels.pressed.connect(_game_manager.go_to_level_select)

func _on_shown() -> void:
	var number := _game_manager.current_level_id.get_slice("_", 1).to_int()
	_title.text = tr(&"COMPLETE_TITLE_N") % number if number > 0 else tr(&"COMPLETE_TITLE")
	_next.visible = _game_manager.has_next_level()
	focus_on_show = _next if _next.visible else _levels
