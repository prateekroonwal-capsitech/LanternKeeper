class_name MainMenu
extends MenuScreen

## MainMenu — title, Play, Settings, Quit (Quit is hidden on mobile and web).
##
## Sends: UIManager.open_menu(&"LevelSelect" / &"Settings"), GameManager.quit_game().
## Receives: nothing.

@onready var _play: Button = %PlayButton
@onready var _settings: Button = %SettingsButton
@onready var _quit: Button = %QuitButton

func _on_menu_ready() -> void:
	_play.pressed.connect(_ui_manager.open_menu.bind(&"LevelSelect"))
	_settings.pressed.connect(_ui_manager.open_menu.bind(&"Settings"))
	_quit.pressed.connect(_game_manager.quit_game)
	_quit.visible = PlatformUtils.is_desktop()
