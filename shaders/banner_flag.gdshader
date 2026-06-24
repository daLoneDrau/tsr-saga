shader_type spatial;
render_mode unshaded, cull_disabled;
// === BANNER SWAY — OPTION B (vertex-wave shader). LOCKED. ===
// Mead-hall pennant, now a 3D cloth mesh in the diorama. The hoist edge
// (UV.x = 0, pinned at the mast) holds still; the fly edge (UV.x = 1)
// sways, with a shallow ripple rolling toward/away from camera (Z).
// Quantized time keeps it chunky/retro rather than a smooth flag wave.
//
// Prototype reference (2D transform): skewX 2deg -> -9deg + scaleX
// 1 -> 0.92, 3.2s, steps(3), alternate.
//
// MESH REQUIREMENT: the pennant must be a PlaneMesh / QuadMesh with
// several subdivisions along its width (subdivide_width >= 6). A flat
// 2-triangle quad has no interior verts to bend and only skews.
//
// sway / ripple are in mesh-local world units — set sway so the fly
// edge travels ~10-12% of the pennant length (matches the 9deg skew).

uniform vec3 cloth_color : source_color = vec3(0.824, 0.29, 0.227);
uniform float period = 3.2;
uniform float steps = 3.0;
uniform float sway = 0.06;     // horizontal travel of the fly edge
uniform float ripple = 0.03;   // depth ripple (0 = pure skew)

void vertex() {
	// Called for every vertex the material is visible on.
	float c = mod(TIME, period * 2.0) / (period * 2.0);
	float tri = 1.0 - abs(c * 2.0 - 1.0);
	float s = (floor(tri * steps) / steps) * 2.0 - 1.0;   // -1..1
	float reach = UV.x;                       // 0 at mast, 1 at fly
	VERTEX.x += reach * sway * s;
	VERTEX.z += sin(reach * 3.14159) * ripple * s;
}

void fragment() {
	// Called for every pixel the material is visible on.
	ALBEDO = cloth_color;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
