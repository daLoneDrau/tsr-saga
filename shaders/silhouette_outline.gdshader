shader_type canvas_item;

// Recolors a flat-alpha silhouette texture (frame.png, wolf_left/right.png)
// into a primary fill color, optionally with a secondary "outline/shadow"
// color detected by sampling alpha at neighboring texels.
//
// outline_px = 0.0 collapses this to a plain flat recolor (equivalent to
// the old `modulate` tint approach) — used for Prototype A. A non-zero
// outline_px reveals the secondary color as a ring around the silhouette's
// edge — used for Prototype B, where the source art has no real tonal
// structure to separate (verified: these PNGs are flat white, 2-3 near-
// identical shades from anti-aliasing only), so the "outline/shadow" has
// to be synthesized rather than sampled from the source.
//
// cutout_uv_left/right/top/bottom: an optional rectangular region (in this
// node's own UV space, 0.0-1.0 on both axes) where nothing is drawn at
// all, regardless of source alpha. Used on PresentationFrame only — not
// the shared ornament material — so the frame's border visually stops
// where it reaches TitleGroup instead of drawing underneath it.
//
// IMPORTANT: this must be bounded on BOTH axes, not just X. An X-only
// cutout blanks the full height of that column — which also erases the
// bottom border directly below TitleGroup, not just the top border behind
// it. Bounding by Y (matching TitleGroup's own vertical extent) keeps the
// cutout confined to just the top border zone.
//
// left >= right or top >= bottom disables that axis's check (the default),
// since a per-node UV cutout is only meaningful for a node whose position
// corresponds to real screen coordinates, like the frame.

uniform vec4 primary_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_px : hint_range(0.0, 6.0) = 0.0;
uniform float cutout_uv_left : hint_range(0.0, 1.0) = 0.0;
uniform float cutout_uv_right : hint_range(0.0, 1.0) = 0.0;
uniform float cutout_uv_top : hint_range(0.0, 1.0) = 0.0;
uniform float cutout_uv_bottom : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	bool in_cutout_x = cutout_uv_right > cutout_uv_left && UV.x >= cutout_uv_left && UV.x <= cutout_uv_right;
	bool in_cutout_y = cutout_uv_bottom > cutout_uv_top && UV.y >= cutout_uv_top && UV.y <= cutout_uv_bottom;
	if (in_cutout_x && in_cutout_y) {
		COLOR = vec4(0.0);
	} else {
		vec4 tex = texture(TEXTURE, UV);

		if (tex.a > 0.5) {
			COLOR = vec4(primary_color.rgb, primary_color.a * tex.a);
		} else {
			if (outline_px <= 0.0) {
				COLOR = vec4(0.0);
			} else {
				vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
				float edge_alpha = 0.0;
				edge_alpha = max(edge_alpha, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
				edge_alpha = max(edge_alpha, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
				edge_alpha = max(edge_alpha, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
				edge_alpha = max(edge_alpha, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
				edge_alpha = max(edge_alpha, texture(TEXTURE, UV + vec2(px.x, px.y)).a);
				edge_alpha = max(edge_alpha, texture(TEXTURE, UV - vec2(px.x, px.y)).a);
				edge_alpha = max(edge_alpha, texture(TEXTURE, UV + vec2(px.x, -px.y)).a);
				edge_alpha = max(edge_alpha, texture(TEXTURE, UV + vec2(-px.x, px.y)).a);

				COLOR = vec4(secondary_color.rgb, secondary_color.a * edge_alpha);
			}
		}
	}
}
