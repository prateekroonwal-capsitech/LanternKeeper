// Lantern glow — additive radial halo drawn on a quad behind the scene.
// The quad is scaled to the light radius, so the soft rim marks exactly
// where ghost platforms stop being solid. `flicker` is driven by Lantern.gd.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 glow_color : source_color = vec4(1.0, 0.6, 0.22, 1.0);
uniform float intensity = 0.55;
uniform float falloff = 1.8;
uniform float core_size : hint_range(0.0, 1.0) = 0.12;
uniform float core_intensity = 0.6;
uniform float rim_width : hint_range(0.0, 0.5) = 0.05;
uniform float rim_intensity = 0.25;
uniform float flicker = 1.0;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	if (d > 1.0) {
		discard;
	}
	float body = pow(1.0 - d, falloff) * intensity;
	float core = (1.0 - smoothstep(0.0, max(core_size, 0.001), d)) * core_intensity;
	float rim = smoothstep(1.0 - rim_width, 1.0 - rim_width * 0.5, d)
		* (1.0 - smoothstep(1.0 - rim_width * 0.5, 1.0, d)) * rim_intensity;
	ALBEDO = glow_color.rgb * (body + core + rim) * flicker;
	ALPHA = 1.0;
}
