shader_type spatial;
// Phase 5 valley water (plan D5): one big transparent plane at the valley
// level. Scrolling sine ripples + a fresnel-ish rim — no textures, no
// gameplay (goat wades visually; swim is a later-phase question).
// Writing ALPHA is what makes it transparent (no render_mode needed).

uniform vec3 shallow_col : source_color = vec3(0.24, 0.42, 0.50);
uniform vec3 deep_col : source_color = vec3(0.10, 0.22, 0.36);
uniform float ripple_scale = 40.0;
uniform float scroll_speed = 0.5;

void fragment() {
	float w = sin(UV.x * ripple_scale + TIME * scroll_speed) * 0.5
		+ sin(UV.y * ripple_scale * 0.85 - TIME * scroll_speed * 0.8) * 0.5;
	vec3 col = mix(deep_col, shallow_col, 0.5 + 0.2 * w);
	ALBEDO = col;
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	ALPHA = 0.82;
}
