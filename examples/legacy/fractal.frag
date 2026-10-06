#version 450
layout(push_constant) uniform View {
    vec2 center;
    float scale;
    uint palette;
    vec2 origin;
    vec2 size;
} view;
layout(location=0) out vec4 color;
void main() {
    vec2 pixel = gl_FragCoord.xy + view.origin;
    vec2 c = view.center + (pixel - view.size * 0.5) * (view.scale / view.size.y);
    precise vec2 z = vec2(0.0);
    uint n = 0;
    for (; n < 192; ++n) {
        precise float xx = z.x * z.x;
        precise float yy = z.y * z.y;
        if (xx + yy > 4.0) break;
        precise float nextY = 2.0 * z.x * z.y + c.y;
        z = vec2(xx - yy + c.x, nextY);
    }
    uint k = n * 7 + view.palette * 41;
    uvec3 rgb = n == 192 ? uvec3(10, 15, 26) :
        uvec3((k * 3) & 255, (k * 5 + 64) & 255, (k * 7 + 128) & 255);
    color = vec4(vec3(rgb) / 255.0, 1.0);
}
