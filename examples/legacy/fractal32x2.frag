#version 450
// Deep zoom without shaderFloat64. A value is the unevaluated sum of two
// floats, high + low, about 48 significant bits. The error-free steps below
// need float32 add, subtract and multiply correctly rounded to nearest and
// performed as written; `precise` (SPIR-V NoContraction) forbids the rest.
layout(push_constant) uniform View {
    layout(offset=0) vec2 centerHigh;
    layout(offset=8) vec2 centerLow;
    layout(offset=16) vec2 step;            // one pixel: high, low
    layout(offset=24) uint palette;
    layout(offset=28) uint iterations;
    layout(offset=32) vec2 origin;
    layout(offset=40) vec2 size;
} view;
layout(location=0) out vec4 color;

// a + b as its rounded sum and the rounding error.
vec2 twoSum(float a, float b) {
    precise float s = a + b;
    precise float v = s - a;
    precise float e = (a - (s - v)) + (b - v);
    return vec2(s, e);
}
// The same, given |a| >= |b|.
vec2 fastTwoSum(float a, float b) {
    precise float s = a + b;
    precise float e = b - (s - a);
    return vec2(s, e);
}
// a as two halves of twelve bits each (Veltkamp).
vec2 split(float a) {
    precise float t = a * 4097.0;
    precise float high = t - (t - a);
    precise float low = a - high;
    return vec2(high, low);
}
// a * b as its rounded product and the rounding error (Dekker).
vec2 twoProduct(float a, float b) {
    precise float p = a * b;
    vec2 x = split(a);
    vec2 y = split(b);
    precise float e = ((x.x * y.x - p) + x.x * y.y + x.y * y.x) + x.y * y.y;
    return vec2(p, e);
}
vec2 add(vec2 a, vec2 b) {
    vec2 s = twoSum(a.x, b.x);
    vec2 t = twoSum(a.y, b.y);
    precise float c = s.y + t.x;
    vec2 v = fastTwoSum(s.x, c);
    precise float w = t.y + v.y;
    return fastTwoSum(v.x, w);
}
vec2 multiply(vec2 a, vec2 b) {
    vec2 p = twoProduct(a.x, b.x);
    precise float e = p.y + (a.x * b.y + a.y * b.x);
    return fastTwoSum(p.x, e);
}

void main() {
    // Half-integers well inside 24 bits: exact.
    precise vec2 pixel = gl_FragCoord.xy + view.origin - view.size * 0.5;
    vec2 cx = add(vec2(view.centerHigh.x, view.centerLow.x), multiply(vec2(pixel.x, 0.0), view.step));
    vec2 cy = add(vec2(view.centerHigh.y, view.centerLow.y), multiply(vec2(pixel.y, 0.0), view.step));
    vec2 zx = vec2(0.0);
    vec2 zy = vec2(0.0);
    uint n = 0;
    for (; n < view.iterations; ++n) {
        vec2 xx = multiply(zx, zx);
        vec2 yy = multiply(zy, zy);
        precise float radius = xx.x + yy.x;
        if (radius > 4.0) break;
        vec2 xy = multiply(zx, zy);
        precise vec2 twice = xy * 2.0;      // exact
        zy = add(twice, cy);
        zx = add(add(xx, -yy), cx);
    }
    uint k = n * 7 + view.palette * 41;
    uvec3 rgb = n == view.iterations ? uvec3(10, 15, 26) :
        uvec3((k * 3) & 255, (k * 5 + 64) & 255, (k * 7 + 128) & 255);
    color = vec4(vec3(rgb) / 255.0, 1.0);
}
