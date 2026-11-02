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

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(grey), darkness * max_desaturation);
	vec2 uv = SCREEN_UV - 0.5;
	uv.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float d = length(uv) * 2.0;
	float inner = mix(vignette_start, vignette_end, darkness);
	float v = smoothstep(inner, inner + vignette_softness, d);
	c = mix(c, vignette_color.rgb, v * clamp(darkness * 1.5, 0.0, 1.0));
	COLOR = vec4(c, 1.0);
}
