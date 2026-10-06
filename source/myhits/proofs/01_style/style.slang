// Proof 01, the style: the three things the plan asks of the shader toolchain,
// written the way the game will write them. This proof only compiles and
// validates; nothing here runs. See ..\README.md.
//
//   collide          mask collision with atomics on memory reached by pointer
//   sprite_vertex    a sprite instance pulled through a pointer
//   sprite_fragment  a texel pulled from a buffer: no image, no sampler
#include "myhits_shared.slang"

struct Sprite
{
    float2 position; float2 velocity;
    float angle; float scale;
    uint kind; uint frame; uint state; uint health; uint parent; uint seed;
};
struct Game { uint score; uint particle_cursor; uint damage[4096]; };
struct World { Sprite* sprites; uint* masks; uint* texels; Game* game; };

[[vk::push_constant]] ConstantBuffer<Root> root;

// A mask is 32 rows of 32 bits for each frame.
bool solid(uint frame, int2 texel)
{
    if (texel.x < 0 || texel.y < 0 || texel.x >= 32 || texel.y >= 32) return false;
    return ((root.world.masks[frame * 32 + texel.y] >> texel.x) & 1) != 0;
}

// A shot against every enemy: its center goes into the target's mask space
// through the inverse of the target's rotation and scale, and one bit decides.
[shader("compute")]
[numthreads(64, 1, 1)]
void collide(uint3 id : SV_DispatchThreadID)
{
    Sprite* sprites = root.world.sprites;
    Sprite shot = sprites[id.x];
    if (shot.state == 0) return;
    for (uint e = 1024; e < 2048; ++e)
    {
        Sprite enemy = sprites[e];
        if (enemy.state == 0) continue;
        float2 offset = shot.position - enemy.position;
        float c = cos(-enemy.angle), s = sin(-enemy.angle);
        float2 local = float2(c * offset.x - s * offset.y, s * offset.x + c * offset.y) / enemy.scale + 16.0;
        if (!solid(enemy.frame, int2(floor(local)))) continue;
        InterlockedAdd(root.world.game.damage[e], 1);               // many shots, one enemy: no lost update
        uint slot;
        InterlockedAdd(root.world.game.particle_cursor, 8, slot);   // a run of the particle ring
        InterlockedAdd(root.events.sound[3].count, 1);              // a sound trigger
        InterlockedAdd(root.events.sound[3].pan, int(enemy.position.x) - int(PLAYFIELD_WIDTH / 2));
        sprites[id.x].state = 0;                                    // its own slot only
        sprites[id.x].seed = slot;
        return;
    }
}

struct SpriteVertex
{
    float4 position : SV_Position;
    float2 texel : TEXCOORD0;
    nointerpolation uint frame : FRAME;
};

[shader("vertex")]
SpriteVertex sprite_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    Sprite sprite = root.world.sprites[instance];
    uint corner = corners[vertex];
    float2 square = float2(corner & 1, corner >> 1);
    float2 offset = (square - 0.5) * 32.0 * sprite.scale;
    float c = cos(sprite.angle), s = sin(sprite.angle);
    float2 playfield = sprite.position + float2(c * offset.x - s * offset.y, s * offset.x + c * offset.y);
    SpriteVertex result;
    // A dead sprite's corners collapse: nothing is drawn, nothing is sorted out.
    result.position = float4(playfield / float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) * 2.0 - 1.0, 0.0, sprite.state == 0 ? 0.0 : 1.0);
    result.texel = square * 32.0;
    result.frame = sprite.frame;
    return result;
}

[shader("fragment")]
float4 sprite_fragment(SpriteVertex input) : SV_Target0
{
    int2 t = clamp(int2(input.texel), int2(0, 0), int2(31, 31));
    uint texel = root.world.texels[input.frame * 1024 + t.y * 32 + t.x];
    if ((texel >> 24) < 128) discard;
    return float4(float3(texel & 255, (texel >> 8) & 255, (texel >> 16) & 255) / 255.0, 1.0);
}
