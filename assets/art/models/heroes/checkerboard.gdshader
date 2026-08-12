shader_type spatial;

uniform int cells : hint_range(1, 64) = 8;
uniform vec3 color_a : source_color = vec3(1.0);
uniform vec3 color_b : source_color = vec3(0.0);

void fragment() {
    vec2 c = floor(UV * float(cells));
    float checker = mod(c.x + c.y, 2.0);
    ALBEDO = mix(color_a, color_b, checker);
}