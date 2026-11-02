class_name LevelButton
extends Button

## LevelButton — one slot in the level-select grid. LevelSelect fills it with a level
## id and its state: locked (lock icon, disabled), open (number) or completed (check).
##
## Sends: `chosen(level_id)` to LevelSelect. Receives: setup() from LevelSelect.

signal chosen(level_id: String)

var level_id: String = ""

@onready var _number: Label = $Number
@onready var _lock: TextureRect = $Lock
@onready var _check: TextureRect = $Check

func _ready() -> void:
	pressed.connect(func() -> void: chosen.emit(level_id))

func setup(id: String, number: int, unlocked: bool, completed: bool) -> void:
	level_id = id
	_number.text = str(number)
	_number.visible = unlocked
	_lock.visible = not unlocked
	_check.visible = unlocked and completed
	disabled = not unlocked
	focus_mode = Control.FOCUS_ALL if unlocked else Control.FOCUS_NONE
