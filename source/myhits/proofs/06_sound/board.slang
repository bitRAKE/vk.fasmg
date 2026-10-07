// Proof 06, sound: the bank the device renders from the recipes of
// tables.inc, and triggers on their way to the voices. What it settles and how
// to run it is in ..\README.md. The library is ..\..\sounds.slang.
#include "common.slang"
#include "myhits_tables.slang"
#include "ease.slang"

struct State
{
    uint next;              // which of the last three sounds Enter plays next
    uint asked[8];          // the frame each sound was last asked for, plus one
    uint faults[4];         // what the examination of the bank found
};
// The header the CPU writes once: BoardWorld in board.asm.
struct World { Tables tables; float* bank; State* state; };

#include "sounds.slang"

// Once, at start, after the bank is rendered: what a sound must be, whatever
// its recipe. It begins at silence, ends near it, is never louder than its
// gain, and does get loud.
[shader("compute")]
[numthreads(1, 1, 1)]
void examine()
{
    World* world = root.world;
    State state;
    state.next = 0;
    for (uint each = 0; each < 8; ++each) state.asked[each] = 0;
    uint starts = 0, ends = 0, loud = 0, quiet = 0;
    for (uint sound = 0; sound < TABLE_SOUNDS; ++sound)
    {
        Recipe recipe = world.tables.sounds[sound];
        float peak = 0.0;
        for (uint index = 0; index < recipe.samples; ++index) peak = max(peak, abs(world.bank[recipe.first + index]));
        if (world.bank[recipe.first] != 0.0) ++starts;
        if (abs(world.bank[recipe.first + recipe.samples - 1]) > 0.01 * recipe.gain) ++ends;
        if (peak > recipe.gain * 1.0001) ++loud;
        if (peak < recipe.gain * 0.25) ++quiet;
    }
    state.faults[0] = starts; state.faults[1] = ends; state.faults[2] = loud; state.faults[3] = quiet;
    *world.state = state;
}

void ask(State* state, uint sound, float x)
{
    trigger(sound, x);
    state.asked[sound] = root.frame + 1;
}

// Alone, once a frame: the frame's events, and the sounds it asks for. A
// scripted run asks by the frame; otherwise the buttons ask, where the
// crosshair is.
[shader("compute")]
[numthreads(1, 1, 1)]
void direct()
{
    World* world = root.world;
    State* state = world.state;
    open_events(root.events);
    for (uint fault = 0; fault < 4; ++fault) root.events.debug[fault] = state.faults[fault];
    if ((root.flags & ROOT_SCRIPTED) != 0)
    {
        uint frame = root.frame;
        if (frame == 10) ask(state, SOUND_SHOT, 480.0);
        if (frame == 20) ask(state, SOUND_LAUNCH, 960.0);
        // Five in one frame: one voice, louder, at their mean.
        if (frame == 30) for (uint k = 0; k < 5; ++k) ask(state, SOUND_HIT, 200.0 + 200.0 * k);
        if (frame == 40) ask(state, SOUND_BURST, 1700.0);
        if (frame == 50) ask(state, SOUND_HURT, 960.0);
        // And more in a row than there are voices.
        if (frame >= 60 && frame < 80) ask(state, SOUND_SHOT, 960.0);
        return;
    }
    if ((root.pressed & BUTTON_FIRE) != 0) ask(state, SOUND_SHOT, root.aim.x);
    if ((root.pressed & BUTTON_SECOND) != 0) ask(state, SOUND_LAUNCH, root.aim.x);
    if ((root.pressed & BUTTON_START) != 0)
    {
        ask(state, SOUND_HIT + state.next % 3, root.aim.x);
        state.next += 1;
    }
}

struct WaveVertex
{
    float4 position : SV_Position;
    float2 at : TEXCOORD0;                  // along the sound and down its row, 0..1
    nointerpolation uint sound : COLOR0;
};

// A row a sound, as wide as the sound is long.
[shader("vertex")]
WaveVertex wave_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    World* world = root.world;
    uint longest = 1;
    for (uint sound = 0; sound < TABLE_SOUNDS; ++sound) longest = max(longest, world.tables.sounds[sound].samples);
    WaveVertex result;
    result.at = float2(corners[vertex] & 1, corners[vertex] >> 1);
    float2 size = float2(1800.0 * float(world.tables.sounds[instance].samples) / float(longest), 170.0);
    result.position = float4((float2(60.0, 50.0 + 200.0 * instance) + result.at * size) / float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) * 2.0 - 1.0, 0.0, 1.0);
    result.sound = instance;
    return result;
}

// The samples themselves: each column of the picture shows how far the sound
// swings over the samples it covers. A sound just asked for is lit.
[shader("fragment")]
float4 wave_fragment(WaveVertex input) : SV_Target0
{
    World* world = root.world;
    Recipe recipe = world.tables.sounds[input.sound];
    float along = input.at.x * float(recipe.samples);
    uint from = min(uint(along), recipe.samples - 1), covered = clamp(uint(fwidth(along)) + 1, 1u, 64u);
    float low = 1.0, high = -1.0;
    for (uint each = 0; each < covered && from + each < recipe.samples; ++each)
    {
        float swing = world.bank[recipe.first + from + each];
        low = min(low, swing);
        high = max(high, swing);
    }
    float value = 1.0 - 2.0 * input.at.y, pixel = fwidth(value);
    float inside = saturate(1.0 - max(low - value, value - high) / pixel);
    float rule = saturate(1.0 - abs(value) / pixel);
    uint asked = world.state.asked[input.sound];
    float lit = asked == 0 ? 0.0 : saturate(1.0 - float(root.frame + 1 - asked) / 30.0);
    float4 color = float4(0.004, 0.008, 0.02, 0.8) + float4(0.1, 0.07, 0.02, 0.0) * lit;
    color = lerp(color, float4(0.05, 0.08, 0.14, 1.0), rule);
    return lerp(color, float4(lerp(float3(0.3, 0.7, 1.0), float3(1.0, 0.95, 0.8), lit), 1.0), inside);
}
