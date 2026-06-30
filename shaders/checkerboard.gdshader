// checkerboard.gdshader
// Renders a 10x10 checkerboard pattern in ocean blue and land green.
// Assign to a StandardMaterial3D's Next Pass, or use directly as a
// ShaderMaterial on the plane's MeshInstance3D.
//
// Tile size is 2 world units — on a 20x20 plane this produces a 10x10 grid.
// Colours and tile size are exposed as uniforms for Inspector adjustment.

shader_type spatial;
render_mode unshaded;

uniform vec4 color_a : source_color = vec4(0.10, 0.28, 0.55, 1.0); // ocean blue
uniform vec4 color_b : source_color = vec4(0.22, 0.48, 0.22, 1.0); // land green
uniform float tile_size : hint_range(0.1, 20.0, 0.1) = 2.0;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Called for every pixel the material is visible on.
	// VERTEX is in world space when using world-space UV.
	// Use the built-in world-space position from the varying.
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Determine checker cell from world XZ position.
	ivec2 cell = ivec2(floor(world_pos.xz / tile_size));

	// Even + even or odd + odd → color_a; mixed → color_b.
	int parity = int(mod(float(cell.x + cell.y), 2.0));

	ALBEDO = (parity == 0 ? color_a : color_b).rgb;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
