// Darkness overlay — as the dark meter runs out, a vignette creeps in from the screen
// edges and colours drain to grey. `darkness` (0..1) is driven by HUD.gd.
// Full-screen ColorRect in the HUD; hidden entirely while darkness is 0.
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float darkness : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.015, 1.0);
// Radius (screen-height units) where the vignette starts, at darkness 0 and at darkness 1.
uniform float vignette_start = 1.2;
uniform float vignette_end = 0.3;
uniform float vignette_softness = 0.5;
uniform float max_desaturation : hint_range(0.0, 1.0) = 0.85;

// Screen positions (UV) and radii (screen-height units) of active light sources.
// The vignette and desaturation never tint or dim the light circles.
uniform vec2 light1_pos = vec2(-1.0, -1.0);
uniform float light1_radius = 0.0;
uniform vec2 light2_pos = vec2(-1.0, -1.0);
uniform float light2_radius = 0.0;
uniform vec2 light3_pos = vec2(-1.0, -1.0);
uniform float light3_radius = 0.0;
uniform vec2 light4_pos = vec2(-1.0, -1.0);
uniform float light4_radius = 0.0;

float calc_light_influence(vec2 uv, vec2 l_pos, float l_radius, vec2 screen_pixel_size) {
	if (l_radius <= 0.0) {
		return 0.0;
	}
	vec2 delta = uv - l_pos;
	delta.x *= screen_pixel_size.y / screen_pixel_size.x;
	float dist = length(delta);
	// Full light protection inside 0.85 * radius, smoothly tapering to 0 by 1.15 * radius
	return 1.0 - smoothstep(l_radius * 0.85, l_radius * 1.15, dist);
}

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;

	// Determine light mask (1.0 inside any active light circle, 0.0 outside)
	float light_mask = 0.0;
	light_mask = max(light_mask, calc_light_influence(SCREEN_UV, light1_pos, light1_radius, SCREEN_PIXEL_SIZE));
	light_mask = max(light_mask, calc_light_influence(SCREEN_UV, light2_pos, light2_radius, SCREEN_PIXEL_SIZE));
	light_mask = max(light_mask, calc_light_influence(SCREEN_UV, light3_pos, light3_radius, SCREEN_PIXEL_SIZE));
	light_mask = max(light_mask, calc_light_influence(SCREEN_UV, light4_pos, light4_radius, SCREEN_PIXEL_SIZE));
	light_mask = clamp(light_mask, 0.0, 1.0);

	// Effective darkness for areas outside light circles
	float effective_darkness = darkness * (1.0 - light_mask);

	// Desaturate only outside the light circles
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey), effective_darkness * max_desaturation);

	// Vignette from screen edges, only darkening outside the light circles
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float d = length(uv) * 2.0;
	float inner = mix(vignette_start, vignette_end, darkness);
	float v = smoothstep(inner, inner + vignette_softness, d);
	c = mix(c, vignette_color.rgb, v * clamp(effective_darkness * 1.5, 0.0, 1.0));

	COLOR = vec4(c, 1.0);
}
