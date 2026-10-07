// Sound, as the device makes it: every recipe of tables.inc rendered once
// into one run of samples the CPU can read, which is the bank XAudio2 plays
// from. The pitch of a sound sweeps along any of the easing curves, and its
// level falls away along another: the same library as everything else.
//
// The including file defines World with `tables` and `bank`, and has included
// common.slang, the tables' header and ease.slang.

float wave_at(uint shape, float cycles)
{
    float part = frac(cycles);
    if (shape == WAVE_SQUARE) return part < 0.5 ? 1.0 : -1.0;
    if (shape == WAVE_SAW) return 2.0 * part - 1.0;
    if (shape == WAVE_TRIANGLE) return 1.0 - 4.0 * abs(part - 0.5);
    return sin(part * 6.2831853);
}

// The area under a curve from 0 to `along`, by Simpson's rule: how far a
// sweep that follows the curve has come.
float eased_area(uint curve, float along)
{
    float step = along / 32.0, sum = ease(curve, 0.0) + ease(curve, along);
    for (uint k = 1; k < 32; ++k) sum += ease(curve, step * k) * ((k & 1) != 0 ? 4.0 : 2.0);
    return sum * step / 3.0;
}

// One sample of one sound. Its noise is a hash of where it is, so it is the
// same every time and anywhere.
float sound_sample(Recipe recipe, uint sound, uint index)
{
    float seconds = float(recipe.samples) / float(SOUND_RATE);
    float along = float(index) / float(recipe.samples);
    float cycles = seconds * (recipe.pitch_from * along + (recipe.pitch_to - recipe.pitch_from) * eased_area(recipe.pitch_curve, along));
    float level = min(along * seconds / max(recipe.attack, 1e-6), 1.0) * (1.0 - ease(recipe.fall_curve, along));
    float hiss = unit(hash(index ^ (sound * 0x9e3779b9U + 0x85ebca6bU))) * 2.0 - 1.0;
    return recipe.gain * level * lerp(wave_at(recipe.wave, cycles), hiss, recipe.noise);
}

// One sample of one stem of the music. Every step strikes its note afresh,
// so the loop's end is a step's end like any other.
float stem_sample(Stem stem, uint which, uint index)
{
    uint step = index / MUSIC_STEP_SAMPLES, within = index % MUSIC_STEP_SAMPLES;
    uint note = stem.notes[step % MUSIC_STEPS];
    if (note == 0) return 0.0;
    float seconds = float(within) / float(SOUND_RATE), along = float(within) / float(MUSIC_STEP_SAMPLES);
    float level = min(seconds / 0.004, 1.0) * (1.0 - ease(stem.fall_curve, along));
    if (stem.wave == WAVE_DRUM)
    {
        // A thump is a low tone falling lower; a crack is noise; a tick is a little of it.
        if (note == 1) return stem.gain * level * sin(6.2831853 * (48.0 * seconds + 2.2 * (1.0 - exp2(-seconds * 60.0))));
        float hiss = unit(hash(index * 2654435761U + which * 977U)) * 2.0 - 1.0;
        return stem.gain * level * hiss * (note == 2 ? 0.9 : 0.4 * saturate(1.0 - along * 5.0));
    }
    return stem.gain * level * wave_at(stem.wave, 440.0 * exp2((float(note) - 69.0) / 12.0) * seconds);
}

// Once, over every sample of the bank: the sounds, and after them the stems
// of the music where a program has any.
[shader("compute")]
[numthreads(64, 1, 1)]
void render(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    uint index = id.x;
    if (index >= BANK_SAMPLES)
    {
        uint which = (index - BANK_SAMPLES) / MUSIC_SAMPLES;
        if (which < world.tables.stem_count) world.bank[index] = stem_sample(world.tables.stems[which], which, (index - BANK_SAMPLES) % MUSIC_SAMPLES);
        return;
    }
    Tables tables = world.tables;
    uint low = 0, high = tables.sound_count - 1;
    while (low < high)
    {
        uint middle = (low + high + 1) >> 1;
        if (tables.sounds[middle].first <= index) low = middle; else high = middle - 1;
    }
    Recipe recipe = tables.sounds[low];
    world.bank[index] = sound_sample(recipe, low, index - recipe.first);
}
