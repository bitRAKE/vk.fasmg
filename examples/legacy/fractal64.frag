#version 450
layout(push_constant) uniform View {
    layout(offset=0) dvec2 center;
    layout(offset=16) double scale;
    layout(offset=24) uint palette;
    layout(offset=28) uint iterations;
    layout(offset=32) vec2 origin;
    layout(offset=40) vec2 size;
} view;
layout(location=0) out vec4 color;
void main() {
    dvec2 pixel = dvec2(gl_FragCoord.xy) + dvec2(view.origin);
    precise dvec2 c = view.center + (pixel - dvec2(view.size) * 0.5lf) *
        (view.scale / double(view.size.y));
    precise dvec2 z = dvec2(0.0lf);
    uint n = 0;
    for (; n < view.iterations; ++n) {
        precise double xx = z.x * z.x;
        precise double yy = z.y * z.y;
        if (xx + yy > 4.0lf) break;
        precise double nextY = 2.0lf * z.x * z.y + c.y;
        z = dvec2(xx - yy + c.x, nextY);
    }
    uint k = n * 7 + view.palette * 41;
    uvec3 rgb = n == view.iterations ? uvec3(10, 15, 26) :
        uvec3((k * 3) & 255, (k * 5 + 64) & 255, (k * 7 + 128) & 255);
    color = vec4(vec3(rgb) / 255.0, 1.0);
}
