// Enemy silhouette shader — gives creature bodies a subtle rim light / outline
// so their silhouettes are readable against pitch-black backgrounds, while
// keeping red eyes as the brightest element.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 body_color : source_color = vec4(0.04, 0.04, 0.06, 1.0);
uniform vec4 rim_color : source_color = vec4(0.30, 0.36, 0.46, 1.0);
uniform float rim_width : hint_range(0.5, 4.0) = 1.5;
uniform float rim_intensity : hint_range(0.0, 1.0) = 0.7;

void fragment() {
	vec4 col = texture(albedo_texture, UV);
	if (col.a < 0.1) {
		discard;
	}
	vec2 size = vec2(textureSize(albedo_texture, 0));
	vec2 ps = (size.x > 0.0) ? (vec2(rim_width) / size) : vec2(0.002);

	// Check 4 cardinal neighbors to detect silhouette edge
	float a_up    = texture(albedo_texture, UV + vec2(0.0, -ps.y)).a;
	float a_down  = texture(albedo_texture, UV + vec2(0.0,  ps.y)).a;
	float a_left  = texture(albedo_texture, UV + vec2(-ps.x, 0.0)).a;
	float a_right = texture(albedo_texture, UV + vec2( ps.x, 0.0)).a;

	float min_a = min(min(a_up, a_down), min(a_left, a_right));
	float is_edge = (min_a < 0.5) ? 1.0 : 0.0;

	vec3 final_rgb = mix(body_color.rgb, rim_color.rgb, is_edge * rim_intensity);
	ALBEDO = final_rgb;
	ALPHA = col.a;
}
