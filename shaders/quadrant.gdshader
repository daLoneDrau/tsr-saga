// quadrant.gdshader
// Divides the plane into four quadrants using standard mathematical convention
// with the origin at the centre of the plane:
//
//   Q2 (X-, Z-)  red    | Q1 (X+, Z-)  green
//   -------------+-------------
//   Q3 (X-, Z+)  blue   | Q4 (X+, Z+)  black
//
// Uses world-space XZ position so the split is always at the world origin
// regardless of UV mapping or mesh scaling.

shader_type spatial;
render_mode unshaded;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	bool pos_x = world_pos.x >= 0.0;
	bool neg_z = world_pos.z <= 0.0;

	vec3 color;
	if (pos_x && neg_z) {
		color = vec3(0.0, 1.0, 0.0);  // Q1 — green
	} else if (!pos_x && neg_z) {
		color = vec3(1.0, 0.0, 0.0);  // Q2 — red
	} else if (!pos_x && !neg_z) {
		color = vec3(0.0, 0.0, 1.0);  // Q3 — blue
	} else {
		color = vec3(0.0, 0.0, 0.0);  // Q4 — black
	}

	ALBEDO = color;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
