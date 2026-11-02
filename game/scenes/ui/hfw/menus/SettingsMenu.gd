class_name SettingsMenu
extends MenuScreen

## SettingsMenu — Master / Music / SFX volume, touch-control layout (gestures or
## buttons) and language. Every change is applied and saved immediately.
## Languages are whatever translations are loaded (game/assets/localization/strings.csv).
##
## Sends: GameManager.set_volume(), set_control_layout(), set_locale();
##   UIManager.close_menu() (Back).
## Receives: GameManager.get_volume(), GameManager.input.control_layout (on open).

@onready var _master: HSlider = %MasterSlider
@onready var _music: HSlider = %MusicSlider
@onready var _sfx: HSlider = %SfxSlider
@onready var _gestures: Button = %GesturesButton
@onready var _classic: Button = %ClassicButton
@onready var _language: OptionButton = %LanguageOption
@onready var _back: Button = %BackButton

var _locales: PackedStringArray = PackedStringArray()
var _filling: bool = false

func _on_menu_ready() -> void:
	_master.value_changed.connect(_on_volume.bind(&"Master"))
	_music.value_changed.connect(_on_volume.bind(&"Music"))
	_sfx.value_changed.connect(_on_volume.bind(&"SFX"))
	_gestures.pressed.connect(_game_manager.set_control_layout.bind(InputManager.LAYOUT_GESTURES))
	_classic.pressed.connect(_game_manager.set_control_layout.bind(InputManager.LAYOUT_CLASSIC))
	_language.item_selected.connect(_on_language_selected)
	_back.pressed.connect(_ui_manager.close_menu)

func _on_shown() -> void:
	_filling = true
	_master.value = _game_manager.get_volume(&"Master")
	_music.value = _game_manager.get_volume(&"Music")
	_sfx.value = _game_manager.get_volume(&"SFX")
	var classic := _game_manager.input.control_layout == InputManager.LAYOUT_CLASSIC
	_classic.button_pressed = classic
	_gestures.button_pressed = not classic
	_language.clear()
	_locales = TranslationServer.get_loaded_locales()
	var current := TranslationServer.get_locale()
	for i in _locales.size():
		_language.add_item(TranslationServer.get_locale_name(_locales[i]))
		if current.begins_with(_locales[i]):
			_language.select(i)
	_filling = false

func _on_volume(value: float, bus_name: StringName) -> void:
	if not _filling:
		_game_manager.set_volume(bus_name, value)

func _on_language_selected(index: int) -> void:
	if not _filling and index >= 0 and index < _locales.size():
		_game_manager.set_locale(_locales[index])
