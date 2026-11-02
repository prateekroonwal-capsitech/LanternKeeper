class_name PauseMenu
extends MenuScreen

## PauseMenu — Resume, Restart level, Settings, Level select, Main menu.
##
## Sends: GameManager.resume() / restart_level() / go_to_level_select() / go_to_main_menu();
##   UIManager.open_menu(&"Settings").
## Receives: opened by GameManager.pause().

@onready var _resume: Button = %ResumeButton
@onready var _restart: Button = %RestartButton
@onready var _settings: Button = %SettingsButton
@onready var _levels: Button = %LevelsButton
@onready var _menu: Button = %MenuButton

func _on_menu_ready() -> void:
	_resume.pressed.connect(_game_manager.resume)
	_restart.pressed.connect(_game_manager.restart_level)
	_settings.pressed.connect(_ui_manager.open_menu.bind(&"Settings"))
	_levels.pressed.connect(_game_manager.go_to_level_select)
	_menu.pressed.connect(_game_manager.go_to_main_menu)
