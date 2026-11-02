class_name AudioManager
extends Node

## AudioManager — Centralized Music and Pooled SFX Playback
##
## Features:
## - Object pooling for SFX (8 players) with PROCESS_MODE_DISABLED when idle (zero CPU waste).
## - Independent Music and SFX enabled/disabled states.
## - PROCESS_MODE_ALWAYS so music and UI sounds continue when game is paused.
## - Avoids music restart stutter if the same track is requested again.
## - Pitch variation option for punchy sound effects.
## - Bus fallback (checks for "Music" and "SFX" buses, falls back to "Master").
##
## Lantern Keeper additions:
## - AudioLibrary (game/resources/audio_library.tres): every stream, set in the Inspector.
## - play_event(name): plays a library sound by name (called by GameManager / UIManager).
## - crossfade_music(): two music players, crossfade between menu / world tracks.
## - set_heartbeat(intensity): looping heartbeat while the dark meter is low.
## - set_bus_volume(): Master / Music / SFX bus volumes (settings).
## Receives: calls from GameManager and UIManager only. Sends: nothing.

var _music_player: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _heartbeat_player: AudioStreamPlayer
var _music_tween: Tween
var library: AudioLibrary
var _sfx_pool: Array[AudioStreamPlayer] = []

const _POOL_SIZE := 8
var _logger: Node

var _music_enabled: bool = true
var _sfx_enabled: bool = true
var _music_volume: float = 1.0
var _sfx_volume: float = 1.0

func configure(logger: Node, library_path: String = "") -> void:
	_logger = logger
	if not library_path.is_empty():
		library = load(library_path) as AudioLibrary
		if library == null and _logger:
			_logger.error("AudioManager: audio library missing", { "path": library_path })

func _ready() -> void:
	# UI sounds and background music should continue playing during pause menu:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_music_player()
	_setup_sfx_pool()

# ==============================================================================
# 🎵 MUSIC SYSTEM
# ==============================================================================

## Plays a background music stream. If already playing the same stream, avoids restart stutter.
func play_music(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
		
	if _music_player.stream == stream and _music_player.playing:
		return

	_music_player.stream = stream
	_music_player.volume_db = volume_db
	
	if _music_enabled:
		_music_player.play()

## Stops background music.
func stop_music() -> void:
	_music_player.stop()

## Temporarily pauses background music without resetting playback position.
func pause_music() -> void:
	_music_player.stream_paused = true

## Resumes paused background music.
func resume_music() -> void:
	if _music_enabled:
		_music_player.stream_paused = false

## Toggles music on or off. Stops or resumes active music playback accordingly.
func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if not enabled:
		_music_player.stop()
	else:
		if _music_player.stream and not _music_player.playing:
			_music_player.play()

func is_music_enabled() -> bool:
	return _music_enabled

## Sets music volume using a linear 0.0 to 1.0 scale.
func set_music_volume(linear: float) -> void:
	_music_volume = clampf(linear, 0.0, 1.0)
	_music_player.volume_db = linear_to_db(_music_volume)

# ==============================================================================
# 🔊 SFX SYSTEM (Pooled)
# ==============================================================================

## Plays a sound effect using an idle player from the pool.
## Optional pitch_scale adds variety to repetitive sounds (e.g. jumps, clicks).
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not _sfx_enabled or stream == null:
		return
		
	var player := _get_free_sfx_player()
	if player == null:
		return
		
	# UI SFX pause ke waqt bhi baj sakein isliye INHERIT / ALWAYS:
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()

## Toggles sound effects on or off.
func set_sfx_enabled(enabled: bool) -> void:
	_sfx_enabled = enabled
	if not enabled:
		for p in _sfx_pool:
			if p.playing:
				p.stop()
				p.process_mode = Node.PROCESS_MODE_DISABLED

func is_sfx_enabled() -> bool:
	return _sfx_enabled

## Sets volume for all SFX players using a linear 0.0 to 1.0 scale.
func set_sfx_volume(linear: float) -> void:
	_sfx_volume = clampf(linear, 0.0, 1.0)
	var db := linear_to_db(_sfx_volume)
	for p in _sfx_pool:
		p.volume_db = db

# ==============================================================================
# 🏮 LANTERN KEEPER: EVENTS, CROSSFADE, HEARTBEAT, BUS VOLUMES
# ==============================================================================

## Plays a library sound by name, e.g. play_event(&"jump").
func play_event(event_name: StringName, vary_pitch: bool = false) -> void:
	if library == null:
		return
	var pitch := 1.0
	if vary_pitch:
		pitch = randf_range(1.0 - library.pitch_variation, 1.0 + library.pitch_variation)
	play_sfx(library.get_event(event_name), 0.0, pitch)

func play_menu_music() -> void:
	if library:
		crossfade_music(library.menu_music)

## world is 1-based.
func play_world_music(world: int) -> void:
	if library and world >= 1 and world <= library.world_music.size():
		crossfade_music(library.world_music[world - 1])

## Fades the current track out while `stream` fades in. Same track = no restart.
func crossfade_music(stream: AudioStream, duration: float = -1.0) -> void:
	if stream == null or (_music_player.stream == stream and _music_player.playing):
		return
	if duration < 0.0:
		duration = library.music_crossfade_time if library else 1.0
	var target_db := library.music_volume_db if library else 0.0
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var old := _music_player
	_music_player = _music_player_b
	_music_player_b = old
	_music_player.stream = stream
	_music_player.volume_db = -40.0
	if _music_enabled:
		_music_player.play()
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(_music_player, "volume_db", target_db, duration)
	if old.playing:
		_music_tween.tween_property(old, "volume_db", -40.0, duration)
		_music_tween.chain().tween_callback(old.stop)

## 0 = off. 0..1 raises volume and tempo as the dark meter empties.
func set_heartbeat(intensity: float) -> void:
	if library == null or library.heartbeat == null:
		return
	if intensity <= 0.0 or not _sfx_enabled:
		if _heartbeat_player.playing:
			_heartbeat_player.stop()
		return
	if _heartbeat_player.stream != library.heartbeat:
		if library.heartbeat is AudioStreamOggVorbis:
			(library.heartbeat as AudioStreamOggVorbis).loop = true
		_heartbeat_player.stream = library.heartbeat
	_heartbeat_player.volume_db = lerpf(-24.0, library.heartbeat_volume_db, intensity)
	_heartbeat_player.pitch_scale = lerpf(library.heartbeat_pitch_range.x, library.heartbeat_pitch_range.y, intensity)
	if not _heartbeat_player.playing:
		_heartbeat_player.play()

## Linear 0..1 volume of a bus ("Master", "Music", "SFX").
func set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		var v := clampf(linear, 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)

func get_bus_volume(bus_name: StringName) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0 or AudioServer.is_bus_mute(idx):
		return 0.0 if idx >= 0 else 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))

# ==============================================================================
# 🔇 GLOBAL MUTE
# ==============================================================================

func mute(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)

func is_muted() -> bool:
	return AudioServer.is_bus_mute(AudioServer.get_bus_index("Master"))

# ==============================================================================
# ⚙️ INTERNAL SETUP & POOLING
# ==============================================================================

func _setup_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	var bus := "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master"
	_music_player.bus = bus
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	# Second player for crossfades, and a looping heartbeat player (SFX bus).
	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.name = "MusicPlayerB"
	_music_player_b.bus = bus
	_music_player_b.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player_b)
	_heartbeat_player = AudioStreamPlayer.new()
	_heartbeat_player.name = "HeartbeatPlayer"
	_heartbeat_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(_heartbeat_player)

func _setup_sfx_pool() -> void:
	var bus := "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	for i in _POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		p.bus = bus
		# All idle players start disabled for 0 CPU ticking
		p.process_mode = Node.PROCESS_MODE_DISABLED
		p.finished.connect(_on_sfx_finished.bind(p))
		add_child(p)
		_sfx_pool.append(p)

func _get_free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	if _logger:
		_logger.warn("AudioManager: SFX pool exhausted")
	return null

func _on_sfx_finished(player: AudioStreamPlayer) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED





#How to use
# Sound Effect (Click, Popup open etc.):
#_audio.play_sfx(my_sound)

# Pitch variation (e.g. bounce/click ko dynamic banane ke liye):
#_audio.play_sfx(my_sound, 0.0, randf_range(0.9, 1.1))

# Music play or toggle:
#_audio.play_music(bgm_stream)
#_audio.set_music_enabled(false)
#_audio.set_sfx_enabled(true)
