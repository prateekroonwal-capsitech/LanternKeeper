class_name EnemyVisual
extends AnimatedSprite3D

## EnemyVisual — the creature's animated silhouette (visual only, no behaviour).
## Picks the animation from the owning Enemy's get_visual_state() through `anim_map`,
## feeds the current frame to the rim-light material (enemy_silhouette.gdshader samples
## `albedo_texture`; a sprite doesn't pass its texture to a material_override by itself),
## and keeps the eye glow sprites on the head, frame by frame.
## Frames and eye positions come from tools/generate_enemy_art.py (eyes.json).
##
## Sends: nothing.
## Receives: polls the owning Enemy's get_visual_state() each frame.

## Visual state ("idle", "move", "emerge", "windup", "lunge", "flinch", plus "hang", "drop",
## "ground" for the Dropper) → animation name. Unmapped states use the state name itself.
@export var anim_map: Dictionary = {}
## Eye glow sprites, in the order of the positions in `eye_track`.
@export var eye_nodes: Array[NodePath] = []
## Metres per pixel of the art as drawn (eye_track units). The imported textures may be
## smaller (import size limit), so `pixel_size` = art_pixel_size × (art size / texture size).
@export var art_pixel_size: float = 0.01
## Art pixel that sits on the node origin (same for every frame).
@export var canvas_origin: Vector2 = Vector2.ZERO
## animation → per frame → eye positions in art pixels.
@export var eye_track: Dictionary = {}
## Seconds a new looping animation (e.g. idle ↔ walk) must be wanted before it switches,
## so slow drifting doesn't flicker. One-shot animations (windup, lunge…) switch at once.
@export var settle_time: float = 0.2

var _enemy: Enemy
var _eyes: Array[Node3D] = []
var _want: StringName = &""
var _want_t: float = 0.0

func _ready() -> void:
	_enemy = owner as Enemy
	for path in eye_nodes:
		_eyes.append(get_node(path) as Node3D)
	if material_override:
		# One material per creature, so each can show its own frame.
		material_override = material_override.duplicate()
	frame_changed.connect(_sync_frame)
	animation_changed.connect(_sync_frame)
	_sync_frame()

func _process(delta: float) -> void:
	if _enemy == null:
		return
	var state: StringName = _enemy.get_visual_state()
	var anim: StringName = anim_map.get(state, state)
	if not sprite_frames.has_animation(anim):
		anim = anim_map.get(&"idle", &"idle")
	if anim == animation:
		_want = &""
		if not is_playing() and sprite_frames.get_animation_loop(anim):
			play(anim)
		return
	if sprite_frames.get_animation_loop(anim) and sprite_frames.get_animation_loop(animation):
		if anim != _want:
			_want = anim
			_want_t = 0.0
		_want_t += delta
		if _want_t < settle_time:
			return
	_want = &""
	play(anim)

func _sync_frame() -> void:
	if sprite_frames == null:
		return
	var tex := sprite_frames.get_frame_texture(animation, frame)
	var mat := material_override as ShaderMaterial
	if mat and tex:
		mat.set_shader_parameter(&"albedo_texture", tex)
	var frames: Array = eye_track.get(String(animation), [])
	if frame >= frames.size():
		return
	var points: Array = frames[frame]
	for i in mini(points.size(), _eyes.size()):
		var e: Vector2 = points[i]
		var eye := _eyes[i]
		eye.position = Vector3((e.x - canvas_origin.x) * art_pixel_size, (canvas_origin.y - e.y) * art_pixel_size, eye.position.z)
