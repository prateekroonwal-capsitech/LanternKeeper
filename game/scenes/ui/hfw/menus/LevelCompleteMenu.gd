class_name LevelCompleteMenu
extends MenuScreen

## LevelCompleteMenu — shown after the exit: Next level (hidden on the last level),
## Replay, Level select.
##
## Sends: GameManager.go_to_next_level() / restart_level() / go_to_level_select().
## Receives: opened by GameManager after report_level_exit_reached().

@onready var _next: Button = %NextButton
@onready var _replay: Button = %ReplayButton
@onready var _levels: Button = %LevelsButton

func _on_menu_ready() -> void:
	_next.pressed.connect(_game_manager.go_to_next_level)
	_replay.pressed.connect(_game_manager.restart_level)
	_levels.pressed.connect(_game_manager.go_to_level_select)

func _on_shown() -> void:
	_next.visible = _game_manager.has_next_level()
	focus_on_show = _next if _next.visible else _levels
