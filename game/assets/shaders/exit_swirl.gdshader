// Exit portal swirl — a glowing spiral inside the door's opening (additive, unshaded).
// `collapse` (0..1) is driven by ExitPortal while the child is pulled in: the spiral
// tightens, speeds up and brightens.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.9, 0.97, 1.0, 1.0);
uniform float arms = 3.0;
uniform float twist = 7.0;
uniform float speed = 0.35;
uniform float intensity = 1.2;
uniform float collapse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.x *= 2.2;                          // the quad is tall: keep the spiral round-ish
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = TIME * speed * (1.0 + collapse * 4.0);
	float spiral = 0.5 + 0.5 * sin(arms * a + (twist + collapse * 10.0) * r - t * 6.2831);
	float edge = 1.0 - smoothstep(0.55, 1.05, r);
	float core = pow(clamp(1.0 - r * (1.2 - collapse * 0.6), 0.0, 1.0), 3.0);
	float v = spiral * edge * 0.75 + core;
	vec3 rgb = mix(color.rgb, core_color.rgb, core) * v * intensity * (1.0 + collapse * 2.0);
	ALBEDO = rgb;
	ALPHA = clamp(v * edge, 0.0, 1.0);
}
