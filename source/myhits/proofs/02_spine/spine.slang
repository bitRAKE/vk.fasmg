// Proof 02, the spine: every way the plan has shaders touch memory, once each.
// What it settles and how to run it is in ..\README.md.
#include "myhits_shared.slang"

static const float PLAYER_SPEED = 600.0;    // playfield units a second
static const float NEAR = 160.0;            // motes this close to the player make a "sound"

struct Mote { float2 position; float2 velocity; uint color; uint pad; };
struct State { uint steps; uint pad; };
// The header the CPU writes once: SpineWorld in spine.asm.
struct World { Mote* motes; uint* texels; State* state; uint count; uint pad; };

[[vk::push_constant]] ConstantBuffer<Root> root;

uint hash(uint x)
{
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return x;
}
float unit(uint x) { return float(x >> 8) * (1.0 / 16777216.0); }

// Once, at start: the world is made on the device, not uploaded.
[shader("compute")]
[numthreads(64, 1, 1)]
void seed(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    uint i = id.x;
    if (i < world.count)
    {
        Mote mote;
        mote.position = float2(unit(hash(i * 2 + 1)) * PLAYFIELD_WIDTH, unit(hash(i * 2 + 2)) * PLAYFIELD_HEIGHT);
        float angle = unit(hash(i + 7919)) * 6.2831853;
        mote.velocity = float2(cos(angle), sin(angle)) * (40.0 + 120.0 * unit(hash(i + 104729)));
        mote.color = 0xff404040U | (hash(i + 31) & 0x00ffffffU);
        mote.pad = 0;
        if (i == 0)
        {
            mote.position = float2(480.0, 540.0);
            mote.velocity = float2(0.0, 0.0);
            mote.color = 0xffffffffU;
        }
        world.motes[i] = mote;
    }
    if (i < 1024)
    {
        // A shaded disc, 32 x 32. Its alpha is its mask.
        float2 p = float2(i % 32, i / 32) + 0.5 - 16.0;
        float distance = length(p);
        uint alpha = distance < 15.0 ? 255 : 0;
        uint shade = uint(clamp(255.0 - distance * 9.0, 60.0, 255.0));
        world.texels[i] = (alpha << 24) | (shade << 16) | (shade << 8) | shade;
    }
    if (i == 0) world.state.steps = 0;
}

// First each frame, alone: opens the frame's event slot and applies the
// controls, so what was read for this frame is on screen in this frame.
[shader("compute")]
[numthreads(1, 1, 1)]
void direct()
{
    World* world = root.world;
    Events* events = root.events;
    events.frame = root.frame;
    events.state = 0; events.score = 0; events.wave = 0; events.lives = 0; events.multiplier = 0;
    events.rank = 0.0; events.shield = 0.0; events.intensity = 0.0;
    events.rumble_low = 0.0; events.rumble_high = 0.0; events.flags = 0;
    for (uint kind = 0; kind < SOUND_KINDS; ++kind)
    {
        events.sound[kind].count = 0;
        events.sound[kind].pan = 0;
    }
    float2 position = world.motes[0].position + root.move * (PLAYER_SPEED * root.ticks * TICK_SECONDS);
    position = clamp(position, float2(16.0, 16.0), float2(PLAYFIELD_WIDTH - 16.0, PLAYFIELD_HEIGHT - 16.0));
    world.motes[0].position = position;
    events.debug[0] = 0;                    // every mote adds one below
    events.debug[1] = world.state.steps;    // what all earlier frames added, on the device
    events.debug[2] = asuint(position.x);
    events.debug[3] = asuint(position.y);
}

// Then every mote at once. Each writes its own slot; shared results are atomic.
[shader("compute")]
[numthreads(64, 1, 1)]
void advance(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    uint i = id.x;
    if (i >= world.count) return;
    if (i != 0)
    {
        Mote mote = world.motes[i];
        mote.position += mote.velocity * (root.ticks * TICK_SECONDS);
        if (mote.position.x < 16.0 || mote.position.x > PLAYFIELD_WIDTH - 16.0)
        {
            mote.velocity.x = -mote.velocity.x;
            mote.position.x = clamp(mote.position.x, 16.0, PLAYFIELD_WIDTH - 16.0);
        }
        if (mote.position.y < 16.0 || mote.position.y > PLAYFIELD_HEIGHT - 16.0)
        {
            mote.velocity.y = -mote.velocity.y;
            mote.position.y = clamp(mote.position.y, 16.0, PLAYFIELD_HEIGHT - 16.0);
        }
        world.motes[i] = mote;
        float2 offset = mote.position - world.motes[0].position;
        if (dot(offset, offset) < NEAR * NEAR)
        {
            // A sound trigger: a count and a sum of positions, not a queue entry.
            InterlockedAdd(root.events.sound[0].count, 1);
            InterlockedAdd(root.events.sound[0].pan, int(mote.position.x) - int(PLAYFIELD_WIDTH / 2));
        }
    }
    InterlockedAdd(world.state.steps, 1);       // device-local memory
    InterlockedAdd(root.events.debug[0], 1);    // host-visible memory
}

struct MoteVertex
{
    float4 position : SV_Position;
    float2 texel : TEXCOORD0;
    nointerpolation uint color : COLOR0;
};

// No vertex buffer and no instance buffer: the mote is pulled through the root.
// The indices are Vulkan's own: SV_VertexID and SV_InstanceID would subtract a
// base and need the shaderDrawParameters feature for it.
[shader("vertex")]
MoteVertex mote_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    Mote mote = root.world.motes[instance];
    uint corner = corners[vertex];
    float2 square = float2(corner & 1, corner >> 1);
    float size = instance == 0 ? 48.0 : 32.0;
    float2 playfield = mote.position + (square - 0.5) * size;
    MoteVertex result;
    result.position = float4(playfield / float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) * 2.0 - 1.0, 0.0, 1.0);
    result.texel = square * 32.0;
    result.color = mote.color;
    return result;
}

// No image and no sampler: the texel is pulled too, and the fragment counts itself.
[shader("fragment")]
float4 mote_fragment(MoteVertex input) : SV_Target0
{
    int2 t = clamp(int2(input.texel), int2(0, 0), int2(31, 31));
    uint texel = root.world.texels[t.y * 32 + t.x];
    if ((texel >> 24) < 128) discard;
    InterlockedAdd(root.events.score, 1);
    float3 shade = float3(texel & 255, (texel >> 8) & 255, (texel >> 16) & 255) / 255.0;
    float3 tint = float3(input.color & 255, (input.color >> 8) & 255, (input.color >> 16) & 255) / 255.0;
    return float4(shade * tint, 1.0);
}
