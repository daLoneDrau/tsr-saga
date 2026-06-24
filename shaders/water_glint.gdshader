shader_type spatial;
render_mode unshaded;
// Water-facet glint for the sun's reflection on the diorama sea.
// Also reused for the sun's halo shimmer (base_color = halo pink,
// min_level = 0.8, period = 2.8).
//
// Apply to EACH reflection facet mesh; stagger them with `phase`
// (prototype delays 0.0 / 0.5 / 1.0 s, sun -> shore) so light ripples in.
//
// Prototype: brightness 0.45 -> 1.0, 2.4s, steps(2), alternate.

uniform vec3 base_color : source_color = vec3(0.776, 0.435, 0.659);
uniform float period = 2.4;
uniform float steps = 2.0;
uniform float min_level = 0.45;
uniform float phase = 0.0;   // per-facet delay in seconds

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	float c = mod(TIME + phase, period * 2.0) / (period * 2.0);
	float t = 1.0 - abs(c * 2.0 - 1.0);
	float q = floor(t * steps) / steps;        // 0 or 1 when steps = 2
	ALBEDO = base_color * mix(min_level, 1.0, q);
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
