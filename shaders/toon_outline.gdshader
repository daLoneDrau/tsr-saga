// toon_outline.gdshader
// Inverted hull outline pass for character models.
// Applied as the next_pass on every toon character material so it renders
// automatically alongside the cel shading pass.
//
// The hull is expanded along vertex normals in view space, then rendered
// with back faces only (cull_front) so it appears as a thin dark border
// around the silhouette of the model.
//
// Outline colour is a soft dark desaturated brown rather than pure black,
// which reads warmer and suits the period aesthetic.

shader_type spatial;
render_mode cull_front, unshaded, depth_draw_always;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------

// Outline width in view-space units. 0.015 gives a thin, clean line
// at the scale character models are viewed from.
uniform float outline_width : hint_range(0.001, 0.1, 0.001) = 0.015;

// Outline colour — soft dark desaturated brown.
uniform vec4 outline_color : source_color = vec4(0.18, 0.13, 0.10, 1.0);

// ---------------------------------------------------------------------------
// Vertex — expand hull outward along normals
// ---------------------------------------------------------------------------

void vertex() {
	// Push each vertex outward along its normal in view space.
	// Multiplying by MODELVIEW_MATRIX normal brings the offset into
	// the correct space so the outline scales consistently regardless
	// of model transform.
	vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)
		+ vec4(view_normal * outline_width, 0.0));
}

// ---------------------------------------------------------------------------
// Fragment — flat outline colour
// ---------------------------------------------------------------------------

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA  = outline_color.a;
}
