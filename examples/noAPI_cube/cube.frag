#version 450
layout(set=0, binding=0) uniform texture2D cube_texture;
layout(set=0, binding=1) uniform sampler cube_sampler;
layout(location=0) in vec2 uv;
layout(location=1) in vec3 fragment_position;
layout(location=0) out vec4 color;
// Format recovery is fixed at pipeline creation, outside the per-draw root ABI.
layout(constant_id=0) const uint material_flags = 0;
const uint TEXTURE_DECODE = 1u;
const uint TARGET_ENCODE = 2u;
vec3 decode_srgb(vec3 c) { return mix(c/12.92, pow((c+0.055)/1.055, vec3(2.4)), greaterThan(c,vec3(0.04045))); }
vec3 encode_srgb(vec3 c) { return mix(c*12.92, 1.055*pow(c,vec3(1.0/2.4))-0.055, greaterThan(c,vec3(0.0031308))); }
void main() {
    vec3 normal = normalize(cross(dFdx(fragment_position), dFdy(fragment_position)));
    float light = max(0.0, dot(vec3(0.424, 0.566, 0.707), normal));
    vec4 texel = texture(sampler2D(cube_texture, cube_sampler), uv);
    if ((material_flags & TEXTURE_DECODE) != 0) texel.rgb = decode_srgb(texel.rgb);
    vec3 lit = light * texel.rgb;
    if ((material_flags & TARGET_ENCODE) != 0) lit = encode_srgb(lit);
    color = vec4(lit, texel.a);
}
