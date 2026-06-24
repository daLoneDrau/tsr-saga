shader_type canvas_item;
// Static CRT overlay for the title CanvasLayer (UI/Scanlines ColorRect).
// Parity with the HTML prototype: a 1px dark row every 3px (~22% strength) plus
// a soft corner vignette. No animation — pure static phosphor look.
//
// Assign to a full-rect ColorRect ABOVE the UI labels. The shader writes the
// overlay directly, so the ColorRect's own `color` is ignored (keep it white).

uniform float line_strength : hint_range(0.0, 1.0) = 0.22; // darkness of each scanline
uniform float line_period   : hint_range(2.0, 8.0) = 3.0;  // px per scanline (native 640x480)
uniform float vignette      : hint_range(0.0, 2.0) = 0.5;  // corner darkening amount

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	// Scanline: dark on the last row of each period.
	float row  = mod(FRAGCOORD.y, line_period);
	float line = step(line_period - 1.0, row) * line_strength;

	// Vignette: distance from screen center (UV is 0..1 across the rect).
	vec2  d   = UV - vec2(0.5);
	float vig = clamp(1.0 - dot(d, d) * vignette * 2.4, 0.0, 1.0);

	// Black overlay; alpha = scanline + corner falloff (approximates multiply).
	float a = clamp(line + (1.0 - vig), 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}

//void light() {
//	// Called for every pixel for every light affecting the CanvasItem.
//	// Uncomment to replace the default light processing function with this one.
//}
