extends Node

# GameBus — global signal bus
# Nothing talks to each other directly — everything goes through signals here
#
# Features receive this bus through explicit dependency setup.
# Lantern Keeper: GameManager is the only emitter of the gameplay signals below;
# gameplay scripts report to GameManager and listen here.

# ── Player ────────────────────────────────────────────────────────────────
signal player_died(cause: String)
signal player_respawned
signal score_changed(new_score: int)
signal health_changed(new_health: int, max_health: int)

# ── Game State ────────────────────────────────────────────────────────────
signal game_started
signal game_paused
signal game_resumed
signal game_over(reason: String)
signal level_started(level_id: String)
signal level_completed(level_id: String)

signal game_state_changed(new_state: int)

# ── Lantern Keeper: light, oil, darkness ─────────────────────────────────
signal oil_changed(oil: float, max_oil: float)
signal dark_meter_changed(ratio: float)
signal dark_meter_emptied
signal dark_meter_recovered
signal lantern_place_requested
signal lantern_placed(at: Vector3)
signal lantern_picked_up
signal platform_lost
signal level_reset(checkpoint_serial: int)
signal checkpoint_activated(shrine: Node3D)
## Every resettable object stores its state on this, and restores it on level_reset.
signal checkpoint_saved(checkpoint_serial: int)
signal lantern_returned
signal enemies_wake_requested(group: StringName)
signal enemy_woke(enemy: Node3D)
signal lantern_hook_changed(hook_id: StringName, hung: bool)
signal lever_pulled(lever_id: StringName)
## A falling trap (rock on a rope, collapsing ceiling) hit the ground; creatures under it check is_in_kill_zone().
signal trap_sprung(trap: Node3D)
## A creature was beaten for good (e.g. the Shade crushed in level 10). Gates with open_on_defeat == kind open.
signal enemy_defeated(enemy_kind: String)
## Show this world point together with the child for `duration` seconds (the camera frames both).
signal camera_focus_requested(point: Vector3, duration: float)
signal control_layout_changed(layout: StringName)
signal tutorial_hint_requested(hint_id: String)

# ── Economy ───────────────────────────────────────────────────────────────
signal coins_changed(new_amount: int)
signal item_unlocked(item_id: String)
signal purchase_completed(product_id: String)

# ── UI ────────────────────────────────────────────────────────────────────
signal screen_opened(screen_name: String)
signal screen_closed(screen_name: String)

# ── Network & Persistence ─────────────────────────────────────────────────
signal auth_completed(uid: String)
signal auth_failed(reason: String)
signal save_loaded
signal save_saved
signal sync_started
signal sync_completed
signal sync_failed(reason: String)

func configure(data_signals: Node) -> void:
	if data_signals == null:
		return
	data_signals.sync_started.connect(func(): sync_started.emit())
	data_signals.sync_finished.connect(func(res):
		if res and res.success:
			sync_completed.emit()
		else:
			var err_msg = res.error_message if res else "Unknown sync error"
			sync_failed.emit(err_msg)
	)
	data_signals.save_finished.connect(func(res):
		if res and res.success:
			save_saved.emit()
	)
	data_signals.login_changed.connect(func(uid: String, is_auth: bool):
		if is_auth and not uid.is_empty():
			auth_completed.emit(uid)
	)

func _ready() -> void:
	pass
