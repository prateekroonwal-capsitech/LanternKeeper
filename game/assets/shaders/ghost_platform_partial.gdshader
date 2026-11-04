// Ghost platform (partial light) — solid shimmering surface inside light circles,
// faint dashed outline in darkness. Smooth circular transition at light boundaries.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

// Lighting uniforms (supports at least 4 lights)
uniform int light_count = 0;
uniform vec3 light_centers[4];
uniform float light_radii[4];
uniform float soft_edge_width = 0.15;

// Fallback / editor preview solidity
uniform float solidity : hint_range(0.0, 1.0) = 0.0;
uniform float editor_solidity : hint_range(0.0, 1.0) = 0.0;

group_uniforms solid;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 solid_color : source_color = vec4(1.0, 0.8, 0.55, 1.0);
uniform float texture_tiles_per_unit = 0.5;
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.2;
uniform float shimmer_speed = 1.6;
uniform float shimmer_scale = 2.5;
uniform float lit_edge_glow : hint_range(0.0, 2.0) = 0.5;

group_uniforms ghost_outline;
uniform vec4 outline_color : source_color = vec4(0.62, 0.74, 1.0, 1.0);
uniform float outline_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float outline_width = 0.06;
uniform float dash_length = 0.3;
uniform float dash_speed = 0.25;
group_uniforms;

varying vec2 v_size;
varying vec3 v_world_pos;

void vertex() {
	v_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = UV * v_size;
	float edge = min(min(p.x, v_size.x - p.x), min(p.y, v_size.y - p.y));
	float outline = 1.0 - step(outline_width, edge);
	float dash = step(0.5, fract((p.x + p.y) / max(dash_length, 0.001) - TIME * dash_speed));

	// Calculate per-fragment solidity from active light circles in X/Y plane
	float sol = max(solidity, editor_solidity);
	for (int i = 0; i < 4; i++) {
		if (i >= light_count) {
			break;
		}
		float d = distance(v_world_pos.xy, light_centers[i].xy);
		float r = light_radii[i];
		// Soft edge about 0.15 m wide that follows the circle smoothly
		float s = smoothstep(r, r - soft_edge_width, d);
		sol = max(sol, s);
	}

	vec4 tex = texture(albedo_texture, p * texture_tiles_per_unit);
	float shimmer = 1.0 + shimmer_strength * sin(TIME * shimmer_speed + (p.x + p.y * 0.5) * shimmer_scale);
	vec3 solid_rgb = tex.rgb * solid_color.rgb * shimmer + solid_color.rgb * outline * lit_edge_glow;

	ALBEDO = mix(outline_color.rgb, solid_rgb, sol);
	ALPHA = mix(outline * dash * outline_alpha, tex.a * solid_color.a, sol);
}

