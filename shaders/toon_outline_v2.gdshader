// toon_outline.gdshader
// Inverted hull outline pass for character/marker models.
// Applied as the next_pass on toon materials so it renders automatically
// alongside the cel shading pass.
//
// The hull is expanded along a SMOOTHED per-position normal (baked in
// Blender via bake_outline_normals.py and stored in the mesh's vertex
// color channel), then rendered with back faces only (cull_front) so it
// appears as a thin border around the model's silhouette.
//
// Using the smoothed normal instead of the real shading NORMAL avoids
// uneven/gapped outlines at hard edges and UV seams on low-poly meshes,
// where the shading normal is split into multiple face-aligned copies
// per position.
//
// Outline width is specified in target screen pixels and converted to
// world units via world_units_per_pixel, which must be pushed from
// script whenever an orthogonal camera's zoom (Camera3D.size) or the
// viewport resolution changes. This keeps the outline a consistent
// on-screen thickness regardless of how small or distant the mesh is
// rendered -- a fixed world-space width alone becomes sub-pixel (and
// therefore inconsistent) on small on-screen meshes.
//
// Outline colour is a soft dark desaturated brown rather than pure black,
// which reads warmer and suits the period aesthetic.

shader_type spatial;
render_mode cull_front, unshaded, depth_draw_always;

// ---------------------------------------------------------------------------
// Uniforms
// ---------------------------------------------------------------------------

// Target outline width in screen pixels. 1.5-2.5 reads as a clean, even
// line after anti-aliasing; below ~1.0 the line becomes sub-pixel and
// will flicker in and out along the silhouette.
uniform float outline_width_px : hint_range(0.0, 10.0, 0.1) = 2.0;

// World-space units represented by one screen pixel at the current
// orthogonal camera zoom. Must be updated from script:
//   world_units_per_pixel = camera.size / viewport_height
// (assumes Camera3D.keep_aspect == KEEP_HEIGHT; swap to viewport_width
// if using KEEP_WIDTH). Recompute whenever camera.size or the viewport
// resolution changes -- not a per-frame cost, just an on-change one.
uniform float world_units_per_pixel = 0.01;

// Outline colour -- soft dark desaturated brown.
uniform vec4 outline_color : source_color = vec4(0.18, 0.13, 0.10, 1.0);

// ---------------------------------------------------------------------------
// Vertex -- expand hull outward along the baked smoothed normal
// ---------------------------------------------------------------------------

void vertex() {
	// Read the pre-baked, position-averaged normal from the vertex color
	// channel instead of the real (possibly hard-split) shading NORMAL.
	// Packed as [-1,1] -> [0,1] by bake_outline_normals.py.
	vec3 baked = COLOR.rgb * 2.0 - 1.0;

	// The bake is done in Blender's Z-up space and vertex colors are NOT
	// axis-converted by the glTF exporter the way real normals are, so
	// swizzle Z-up -> Y-up here to match Godot's convention. Verify this
	// against a known-facing surface on your mesh before trusting it --
	// see bake_outline_normals.py's docstring for how to check.
	vec3 smooth_normal = normalize(vec3(baked.x, baked.z, -baked.y));

	// Convert to view space for the hull expansion.
	vec3 view_normal = normalize(mat3(MODELVIEW_MATRIX) * smooth_normal);

	// Convert the target pixel width to world units at the current zoom,
	// then expand the hull by that amount along the view-space normal.
	float width = outline_width_px * world_units_per_pixel;

	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)
		+ vec4(view_normal * width, 0.0));
}

// ---------------------------------------------------------------------------
// Fragment -- flat outline colour
// ---------------------------------------------------------------------------

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA  = outline_color.a;
}
