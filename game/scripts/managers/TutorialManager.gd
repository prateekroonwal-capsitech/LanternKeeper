class_name TutorialManager
extends Node

## TutorialManager — one-time hints for the first levels of each world.
## A hint is shown once, then its "seen" flag is saved (SaveManager → tutorials bucket).
## The popup scenes themselves live in the UI (Phase 4); this manager only decides.
##
## Sends: GameBus.tutorial_hint_requested(hint_id); SaveManager.mark_tutorial_seen().
## Receives: request_hint(hint_id) — called by TutorialTrigger nodes (Phase 4) via GameManager.

var _logger: Node
var _bus: Node
var _save: SaveManager

func configure(logger: Node, bus: Node, save: SaveManager) -> void:
	_logger = logger
	_bus = bus
	_save = save

## Shows a hint if it has not been seen yet. Returns true if it was shown.
func request_hint(hint_id: String) -> bool:
	if is_seen(hint_id):
		return false
	if _save:
		_save.mark_tutorial_seen(hint_id)
	if _bus:
		_bus.tutorial_hint_requested.emit(hint_id)
	return true

func is_seen(hint_id: String) -> bool:
	return _save != null and _save.is_tutorial_seen(hint_id)
