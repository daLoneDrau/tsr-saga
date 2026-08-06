shader_type canvas_item;

// Apple II hi-res 6-color palette (NTSC composite artifact colors).
const int PALETTE_SIZE = 6;
const vec3 PALETTE[6] = vec3[](
    vec3(0.000, 0.000, 0.000), // 0  Black
    vec3(0.714, 0.239, 1.000), // 1  Violet
    vec3(0.918, 0.365, 0.082), // 2  Orange
    vec3(0.063, 0.643, 0.890), // 3  Blue
    vec3(0.263, 0.765, 0.000), // 4  Green
    vec3(1.000, 1.000, 1.000)  // 5  White
);

const int bayer4x4[16] = int[](
    0,  8,  2,  10,
    12, 4,  14, 6,
    3,  11, 1,  9,
    15, 7,  13, 5
);

// Perceptual-ish weighting so distance comparisons favor luminance
// a bit more than raw RGB distance would.
float colorDist(vec3 a, vec3 b) {
    vec3 d = a - b;
    vec3 w = vec3(0.30, 0.59, 0.11);
    return dot(d * d, w);
}

void fragment() {
    vec3 src = texture(TEXTURE, UV).rgb;

    // Find closest and second-closest palette colors.
    int bestIdx = 0;
    int secondIdx = 0;
    float bestDist = 1e9;
    float secondDist = 1e9;

    for (int i = 0; i < PALETTE_SIZE; i++) {
        float d = colorDist(src, PALETTE[i]);
        if (d < bestDist) {
            secondDist = bestDist;
            secondIdx = bestIdx;
            bestDist = d;
            bestIdx = i;
        } else if (d < secondDist) {
            secondDist = d;
            secondIdx = i;
        }
    }

    vec3 c0 = PALETTE[bestIdx];
    vec3 c1 = PALETTE[secondIdx];

    // Where does src sit between c0 and c1? Project onto the c0->c1 line.
    vec3 c0c1 = c1 - c0;
    float denom = dot(c0c1, c0c1);
    float t = denom > 0.0001 ? clamp(dot(src - c0, c0c1) / denom, 0.0, 1.0) : 0.0;

    // Bayer threshold for this pixel, based on rendered (low-res) pixel coords.
    ivec2 pixel = ivec2(mod(FRAGCOORD.xy, 4.0));
    float threshold = float(bayer4x4[pixel.y * 4 + pixel.x]) / 16.0;

    vec3 result = t > threshold ? c1 : c0;
    COLOR = vec4(result, 1.0);
}
