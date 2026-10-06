// Adapted from NoGraphicsAPI/examples/cube; see LICENSE-NoGraphicsAPI.txt.
struct CubeVertex { float4 position; float2 uv; };
struct CubeRoot { CubeVertex* vertices; float4x4 transform; };
[[vk::push_constant]] ConstantBuffer<CubeRoot> root;
[vk::constant_id(0)] const uint material_flags = 0;
static const uint TEXTURE_DECODE = 1;
static const uint TARGET_ENCODE = 2;
struct VertexOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float3 fragment_position : TEXCOORD1;
};
[shader("vertex")]
VertexOutput vertexMain(uint vertex_id : SV_VertexID) {
    CubeVertex vertex = root.vertices[vertex_id];
    VertexOutput result;
    result.position = mul(root.transform, vertex.position);
    result.uv = vertex.uv;
    result.fragment_position = result.position.xyz;
    return result;
}
[shader("fragment")]
float4 fragmentMain(VertexOutput input) : SV_Target0 {
    Texture2D<float4> texture = ResourceDescriptorHeap[0];
    SamplerState sampler = SamplerDescriptorHeap[0];
    float3 normal = normalize(cross(ddx(input.fragment_position), ddy(input.fragment_position)));
    float light = max(0.0f, dot(float3(0.424f, 0.566f, 0.707f), normal));
    float4 texel = texture.Sample(sampler, input.uv);
    if ((material_flags & TEXTURE_DECODE) != 0) texel.rgb = select(texel.rgb <= 0.04045f, texel.rgb/12.92f, pow((texel.rgb+0.055f)/1.055f,2.4f));
    float3 lit = light * texel.rgb;
    if ((material_flags & TARGET_ENCODE) != 0) lit = select(lit <= 0.0031308f,lit*12.92f,1.055f*pow(lit,1.0f/2.4f)-0.055f);
    return float4(lit, texel.a);
}
