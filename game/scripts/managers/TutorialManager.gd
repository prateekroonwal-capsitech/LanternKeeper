class_name TutorialManager
extends Node

## TutorialManager — one short line of text, only when something new is introduced.
## HINTS below is the data: per hint, the translation key for touch (Android gestures),
## the classic touch-button layout and PC (strings.csv) and the action that dismisses it early. A hint is shown once per save,
## then its "seen" flag is saved (SaveManager → tutorials bucket). GestureHint (UIRoot)
## draws it; this manager only decides. Unknown ids are ignored (and not marked seen).
##
## Sends: GameBus.tutorial_hint_requested(hint_id); SaveManager.mark_tutorial_seen().
## Receives: request_hint(hint_id) — TutorialTrigger nodes via GameManager.report_tutorial_trigger().

## id → { touch, classic, pc: translation keys (classic falls back to touch); action: InputMap action that hides it early ("" = none) }.
## Placed by TutorialTrigger nodes (hint_id), in the level where the thing is introduced.
const HINTS := {
	"move":              { "touch": "HINT_MOVE_TOUCH", "classic": "HINT_MOVE_CLASSIC", "pc": "HINT_MOVE_PC", "action": "move" },      # 1-1 start
	"ghost":             { "touch": "HINT_GHOST", "pc": "HINT_GHOST", "action": "" },                 # 1-1 first ghost platform
	"place":             { "touch": "HINT_PLACE_TOUCH", "classic": "HINT_PLACE_CLASSIC", "pc": "HINT_PLACE_PC", "action": "place_lantern" },  # 1-2 first place spot
	"stay_in_light":     { "touch": "HINT_STAY_IN_LIGHT", "pc": "HINT_STAY_IN_LIGHT", "action": "" }, # 1-3 crawlers wake
	"danger_above":      { "touch": "HINT_DANGER_ABOVE", "pc": "HINT_DANGER_ABOVE", "action": "" },   # 1-5 first dropper
	"something_follows": { "touch": "HINT_SOMETHING_FOLLOWS", "pc": "HINT_SOMETHING_FOLLOWS", "action": "" },  # 1-7 Stalker wakes
	"seal_holes":        { "touch": "HINT_SEAL_HOLES", "pc": "HINT_SEAL_HOLES", "action": "" },       # 1-9 swarm wakes
	"run":               { "touch": "HINT_RUN", "pc": "HINT_RUN", "action": "" },                     # (old 1-10 chase, unused)
	"shade_rule":        { "touch": "HINT_SHADE_RULE", "pc": "HINT_SHADE_RULE", "action": "", "time": 5.0 }, # 1-10 spawn
	"shade_light":       { "touch": "HINT_SHADE_LIGHT", "pc": "HINT_SHADE_LIGHT", "action": "" },     # 1-10 Shade appears (run)
	"shade_bait":        { "touch": "HINT_SHADE_BAIT", "pc": "HINT_SHADE_BAIT", "action": "" },       # 1-10 Shade perches (trap)
	"shade_hide":        { "touch": "HINT_SHADE_HIDE", "pc": "HINT_SHADE_HIDE", "action": "" },       # 1-10 Shade sweeps (hide)
	"shade_ceiling":     { "touch": "HINT_SHADE_CEILING", "pc": "HINT_SHADE_CEILING", "action": "" }, # 1-10 into the cavern (final)
}

var _logger: Node
var _bus: Node
var _save: SaveManager

func configure(logger: Node, bus: Node, save: SaveManager) -> void:
	_logger = logger
	_bus = bus
	_save = save

## Shows a hint if it has not been seen yet. Returns true if it was shown.
func request_hint(hint_id: String) -> bool:
	if not HINTS.has(hint_id) or is_seen(hint_id):
		return false
	if _save:
		_save.mark_tutorial_seen(hint_id)
	if _bus:
		_bus.tutorial_hint_requested.emit(hint_id)
	return true

## Translation key for this hint on the current device: device is "touch" (gestures),
## "classic" (touch buttons) or "pc" (keyboard / controller).
func get_hint_key(hint_id: String, device: String) -> String:
	var data: Dictionary = HINTS.get(hint_id, {})
	return data.get(device, data.get("touch", ""))

## InputMap action that dismisses the hint early ("move" = either direction), or "".
func get_hint_action(hint_id: String) -> String:
	return HINTS.get(hint_id, {}).get("action", "")

## Display duration (seconds) for this hint. Defaults to 3.0 s if unspecified in HINTS.
func get_hint_display_time(hint_id: String, default_time: float = 3.0) -> float:
	var data: Dictionary = HINTS.get(hint_id, {})
	return float(data.get("time", default_time))

func is_seen(hint_id: String) -> bool:
	return _save != null and _save.is_tutorial_seen(hint_id)
