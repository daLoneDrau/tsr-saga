shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(1.0, 0.498, 0.667, 1.0);
uniform float period = 2.8;
uniform float min_opacity = 0.8;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	float t = mod(TIME, period * 2.0) / (period * 2.0);
	if (t > 0.5) {
		t = 1.0 - t;
	}
	t = t * 2.0;
	float stepped = floor(t * 2.0) / 2.0;
	float opacity = min_opacity + stepped * (1.0 - min_opacity);
	ALBEDO = base_color.rgb;
	ALPHA = base_color.a * opacity;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
