// What every pass shares: the root, a hash, and how a frame's events are
// opened and added to.
#include "myhits_shared.slang"

[[vk::push_constant]] ConstantBuffer<Root> root;

uint hash(uint x)
{
    x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16;
    return x;
}
float unit(uint x) { return float(x >> 8) * (1.0 / 16777216.0); }

// A number made of how many lines each table has and what the sounds come
// to (tables_counted in reload.inc): a program that has taken tables again
// can ask the device what it makes of its own.
uint tables_counted(Tables tables)
{
    uint fold = tables.sound_samples;
    fold = fold * 31 + tables.move_count;
    fold = fold * 31 + tables.kind_count;
    fold = fold * 31 + tables.style_count;
    fold = fold * 31 + tables.sound_count;
    fold = fold * 31 + tables.wave_count;
    fold = fold * 31 + tables.stem_count;
    fold = fold * 31 + tables.say_count;
    return fold;
}

// A frame's events, emptied: by the frame's first pass, whichever that is.
void open_events(Events* events)
{
    events.frame = root.frame;
    events.state = 0; events.score = 0; events.wave = 0; events.lives = 0; events.multiplier = 0;
    events.rank = 0.0; events.shield = 0.0; events.intensity = 0.0;
    events.rumble_low = 0.0; events.rumble_high = 0.0; events.flags = 0;
    for (uint kind = 0; kind < SOUND_KINDS; ++kind)
    {
        events.sound[kind].count = 0;
        events.sound[kind].pan = 0;
    }
    for (uint slot = 0; slot < 4; ++slot) events.debug[slot] = 0;
    for (uint spare = 0; spare < 16; ++spare) events.reserved[spare] = 0;
    for (uint word = 0; word < 32; ++word) events.report[word] = 0;
}

// Ask for a sound: any pass may. A trigger is a count and a sum of where, so
// a hundred in a frame cost what one does, and the CPU pans by the mean.
void trigger(uint sound, float x)
{
    InterlockedAdd(root.events.sound[sound].count, 1);
    InterlockedAdd(root.events.sound[sound].pan, int(x) - int(PLAYFIELD_WIDTH / 2));
}
