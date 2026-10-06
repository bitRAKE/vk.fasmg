#version 450
#if POINTER_VERTICES
#extension GL_EXT_buffer_reference : require
// Scalar members preserve the original 24-byte vertex stride without scalarBlockLayout.
struct Vertex { float x, y, z, w, u, v; };
layout(buffer_reference, std430, buffer_reference_align=8) readonly buffer Vertices { Vertex data[]; };
layout(push_constant, std430) uniform Root { Vertices vertices; float transform[16]; } root;
#else
layout(location=0) in vec4 position;
layout(location=1) in vec2 texcoord;
layout(push_constant, std430) uniform Root { uvec2 vertices; float transform[16]; } root;
#endif
layout(location=0) out vec2 uv;
layout(location=1) out vec3 fragment_position;
void main() {
#if POINTER_VERTICES
    Vertex vertex = root.vertices.data[gl_VertexIndex];
    vec4 position = vec4(vertex.x, vertex.y, vertex.z, vertex.w);
    vec2 texcoord = vec2(vertex.u, vertex.v);
#endif
    // A scalar array keeps the original matrix at byte 8 without scalarBlockLayout.
    mat4 transform = transpose(mat4(
        vec4(root.transform[0], root.transform[1], root.transform[2], root.transform[3]),
        vec4(root.transform[4], root.transform[5], root.transform[6], root.transform[7]),
        vec4(root.transform[8], root.transform[9], root.transform[10], root.transform[11]),
        vec4(root.transform[12], root.transform[13], root.transform[14], root.transform[15])));
    gl_Position = transform * position;
    uv = texcoord;
    fragment_position = gl_Position.xyz;
}
