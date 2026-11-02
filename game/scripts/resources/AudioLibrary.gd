class_name AudioLibrary
extends Resource

## AudioLibrary — every music track and sound effect, assigned in the Inspector
## (game/resources/audio_library.tres). AudioManager reads it; GameManager asks
## AudioManager to play events by name (e.g. &"jump" → `jump` below).

@export_group("Music")
@export var menu_music: AudioStream
## One track per world, in world order (World 1 first).
@export var world_music: Array[AudioStream] = []
@export var music_crossfade_time: float = 1.6
@export var music_volume_db: float = -4.0

@export_group("Gameplay SFX")
@export var jump: AudioStream
@export var land: AudioStream
@export var lantern_place: AudioStream
@export var lantern_pickup: AudioStream
@export var oil_pickup: AudioStream
@export var shrine: AudioStream
@export var death: AudioStream
@export var level_complete: AudioStream

@export var lantern_return: AudioStream
@export var enemy_wake: AudioStream
@export var enemy_hiss: AudioStream

@export_group("UI SFX")
@export var ui_button: AudioStream

@export_group("Heartbeat")
@export var heartbeat: AudioStream
## Dark-meter ratio below which the heartbeat starts (0..1).
@export_range(0.0, 1.0) var heartbeat_threshold: float = 0.45
@export var heartbeat_volume_db: float = -2.0
@export var heartbeat_pitch_range: Vector2 = Vector2(0.9, 1.4)

## Small random pitch variation on repetitive sounds.
@export var pitch_variation: float = 0.06

func get_event(event_name: StringName) -> AudioStream:
	var value: Variant = get(event_name)
	return value as AudioStream
