#version 440
// local: a reveal in growing dots. After the halftone in Rune's rune-fx (fill.wgsl; github.com/anomalyco/rune, MIT, © Anomaly):
// the four nearest dots, so big ones merge across cell lines. Its tone is a wave here and the grid stays square, like the wall.
// Rebuild: /usr/lib/qt6/bin/qsb --qt6 -o halftone.frag.qsb halftone.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // the item, px
    vec2 origin;    // where the wave starts, px
    float pitch;    // px between dots
    float progress; // 0 nothing, 1 all of it
    float band;     // px, how wide the wave is
    vec4 ink;       // the dots on the wave's front
};
layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 base = floor(p / pitch - 0.5);
    float far = length(max(abs(origin), abs(size - origin))); // to the farthest corner
    float front = progress * (far + band);
    float aa = fwidth(p.x);
    float mask = 0.0, cover = 1.0;
    for (int y = 0; y <= 1; y++) {
        for (int x = 0; x <= 1; x++) {
            vec2 c = (base + vec2(x, y) + 0.5) * pitch;
            float cov = clamp((front - distance(c, origin)) / band, 0.0, 1.0);
            if (cov <= 0.0) continue;
            // 0.75 of a pitch at full cover: past a cell's corner (0.707), so nothing is left between the dots
            float a = 1.0 - smoothstep(-aa, aa, distance(p, c) - sqrt(cov) * 0.75 * pitch);
            if (a > mask) {
                mask = a;
                cover = cov;
            }
        }
    }
    vec4 t = texture(source, qt_TexCoord0) * mask;
    float lit = pow(1.0 - cover, 3.0) * mask; // bright while small, gone by the time they merge
    fragColor = (t + ink * lit * (1.0 - t.a)) * qt_Opacity;
}
