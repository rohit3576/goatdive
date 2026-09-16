shader_type spatial;
// Phase 5 terrain look v2 (plan: docs/plans/phase-5-realistic-mountain.md D3).
// HARD RULE (Step 2): visual snow == grip snow. Zone identity comes ONLY
// from the vertex color stamp written by TerrainGenerator.surface_at() —
// the same classifier that sets friction. This shader *shades within*
// zones (scree tints, snow depth on flats, strata, wet ice); it never
// invents zone boundaries of its own.
//
// Vertex COLOR.rgb = classifier zone color. COLOR.a = zone id / 3.0
// (0 = rock, 1/3 = grass, 2/3 = snow, 1 = ice) — interpolated at edges,
// rounded here. gl_compatibility-safe features only.

render_mode diffuse_lambert;

uniform vec3 scree_col : source_color = vec3(0.50, 0.47, 0.42);
uniform float snow_line = 170.0;
uniform float snow_fade = 30.0;       // m of soft blend toward the line
uniform float snow_flat_deg = 28.0;   // flatter than this = deep snow look
uniform float strata_scale = 0.09;    // strata ripple, cycles per meter
uniform float strata_strength = 0.10; // peak darkening in rock zones
uniform float ice_wet_rough = 0.30;

varying vec3 v_world_pos;
varying vec3 v_normal_w;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_w = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = COLOR.rgb;
	float zone_id = round(COLOR.a * 3.0);
	float h = v_world_pos.y;
	float slope_deg = degrees(acos(clamp(v_normal_w.y, -1.0, 1.0)));

	vec3 albedo = base;
	float roughness = 1.0;

	// --- Rock: wavy horizontal strata (cheap 2-axis wiggle breaks the
	// perfect-contour look the cliff bands would otherwise give). ---
	if (zone_id < 0.5) {
		float strata = sin(h * strata_scale * 6.28318
			+ sin(v_world_pos.x * 0.05) * 2.0
			+ sin(v_world_pos.z * 0.07) * 2.0);
		albedo *= 1.0 - strata_strength * (0.5 + 0.5 * strata);
	}

	// --- Grass: scree tint creeps in as the slope steepens toward the
	// rock threshold (30°) — a transition, not a new zone. ---
	else if (zone_id < 1.5) {
		float scree = smoothstep(14.0, 30.0, slope_deg);
		albedo = mix(albedo, scree_col, scree * 0.7);
		roughness = 0.95;
	}

	// --- Snow: depth on flats, wind-scoured gray on steeps. Shedding to
	// ROCK IS FORBIDDEN (grip says snow above the line) — steep snow just
	// reads older and harder. ---
	else if (zone_id < 2.5) {
		float line_f = smoothstep(snow_line - snow_fade, snow_line + snow_fade, h);
		float flat_f = 1.0 - smoothstep(snow_flat_deg, 48.0, slope_deg);
		vec3 deep = vec3(0.97, 0.98, 1.00);
		vec3 scoured = vec3(0.78, 0.80, 0.86);
		albedo = mix(scoured, deep, flat_f * line_f);
		roughness = mix(0.75, 0.55, flat_f * line_f);
	}

	// --- Ice: keep the pale blue, read wet. ---
	else {
		roughness = ice_wet_rough;
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
