// toon_character.gdshader
// Two-pass toon shader for all character models (heroes, monsters, jarls).
// Pass 1 — flat cel shading with a single hard shadow band.
// Pass 2 — inverted hull outline in a soft dark brown.
//
// Light direction is baked in as a fixed world-space vector matching the
// 2:1 isometric camera setup (upper-left at 45 deg yaw, 26.565 deg pitch).
// All materials using this shader pass their colour as the albedo uniform.

shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------

// The surface colour for this material instance.
uniform vec4 albedo : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Shadow darkening factor — how much darker the shadow band is.
// 0.0 = black shadow, 1.0 = no shadow. 0.45 gives a clear but not harsh band.
uniform float shadow_strength : hint_range(0.0, 1.0, 0.01) = 0.45;

// Shadow coolness — shifts the shadow tone slightly toward blue-grey.
// Keeps shadows from looking muddy on warm colours.
uniform float shadow_cool : hint_range(0.0, 0.3, 0.01) = 0.08;

// Hard threshold between lit and shadow bands.
// 0.0 = centre, positive = more lit, negative = more shadow.
uniform float shadow_threshold : hint_range(-0.5, 0.5, 0.01) = 0.05;

// ---------------------------------------------------------------------------
// Baked light direction (world space, normalized)
// Upper-left relative to the isometric camera.
// ---------------------------------------------------------------------------

const vec3 LIGHT_DIR = vec3(-0.502519, 0.703526, -0.502519);

// ---------------------------------------------------------------------------
// Fragment — Pass 1: cel shading
// ---------------------------------------------------------------------------

void fragment() {
	// Transform the surface normal to world space.
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Diffuse intensity — dot product of normal and light direction.
	float n_dot_l = dot(world_normal, LIGHT_DIR);

	// Hard step at threshold — lit (1.0) or shadow (0.0).
	float band = step(shadow_threshold, n_dot_l);

	// Compute shadow colour: darken and cool the albedo.
	vec3 shadow_color = albedo.rgb * shadow_strength;
	shadow_color.b = min(shadow_color.b + shadow_cool, 1.0);

	// Mix lit and shadow bands.
	vec3 final_color = mix(shadow_color, albedo.rgb, band);

	ALBEDO = final_color;
	ALPHA  = albedo.a;
}
