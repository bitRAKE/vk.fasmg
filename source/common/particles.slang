// Particles: light with a short life. A ring on the device; any pass may ask
// for some, and each style admits only so many a tick, so one explosion
// cannot crowd out the sparks of the next hit. The styles are data, authored
// in tables.inc.
//
// The including file defines World with `tables`, `particles`, `pool` and
// `particle_capacity` (a power of two), and has included motion.slang.

struct Particle
{
    float2 position;
    float2 velocity;
    uint born;          // the tick it was made in
    uint life;          // ticks; none: nothing here
    uint style;
    uint seed;
};

struct ParticlePool
{
    uint asked;             // particles ever admitted; the ring's next slot is this, wrapped
    uint live;              // as the last update counted
    uint admitted[16];      // this tick, by style
};

// A new tick: the caps start again. The director's.
void open_particles(World* world)
{
    world.pool.live = 0;
    for (uint style = 0; style < 16; ++style) world.pool.admitted[style] = 0;
}

// Ask for `count` of a style at a point, thrown about `toward` (a unit
// vector) and carried with `carried`. Returns how many the cap let in.
uint emit(World* world, uint style, float2 at, float2 toward, float2 carried, uint count, uint seed, uint tick)
{
    Style look = world.tables.styles[style];
    uint before;
    InterlockedAdd(world.pool.admitted[style], count, before);
    if (before >= look.cap) return 0;
    count = min(count, look.cap - before);
    uint first;
    InterlockedAdd(world.pool.asked, count, first);
    float aim = atan2(toward.y, toward.x);
    for (uint each = 0; each < count; ++each)
    {
        uint salt = hash(seed * 0x9e3779b9U + first + each);
        Particle particle;
        particle.position = at;
        particle.velocity = heading(aim + (unit(salt) * 2.0 - 1.0) * look.spread) * (look.speed + unit(hash(salt + 1)) * look.speed_spread) + carried;
        particle.born = tick;
        particle.life = look.life + hash(salt + 2) % (look.life_spread + 1);
        particle.style = style;
        particle.seed = salt;
        world.particles[(first + each) & (world.particle_capacity - 1)] = particle;
    }
    return count;
}

// One tick of one particle, in place. `tick` is the tick being run.
void advance_particle(World* world, uint slot, uint tick, float2 player)
{
    Particle particle = world.particles[slot];
    if (particle.life == 0) return;
    if (tick - particle.born >= particle.life)
    {
        world.particles[slot].life = 0;
        return;
    }
    Style look = world.tables.styles[particle.style];
    particle.velocity *= 1.0 - look.drag * TICK_SECONDS;
    particle.velocity.y += look.gravity * TICK_SECONDS;
    if (look.pull != 0.0)
    {
        float2 toward = player - particle.position;
        particle.velocity += toward * (look.pull * TICK_SECONDS / max(length(toward), 1.0));
    }
    particle.position += particle.velocity * TICK_SECONDS;
    world.particles[slot] = particle;
    InterlockedAdd(world.pool.live, 1);
}

struct ParticleVertex
{
    float4 position : SV_Position;
    float2 at : TEXCOORD0;                      // -1..1 across it
    nointerpolation float3 color : COLOR0;      // linear, and already as bright as it is
};

// A particle between its last two ticks: its size and color from its style
// and its age. `tick` is how many ticks have run.
ParticleVertex particle_corner(World* world, uint slot, uint vertex, uint tick)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    Particle particle = world.particles[slot];
    ParticleVertex result;
    result.at = float2(corners[vertex] & 1, corners[vertex] >> 1) * 2.0 - 1.0;
    result.color = float3(0.0, 0.0, 0.0);
    result.position = float4(0.0, 0.0, 0.0, 1.0);
    if (particle.life == 0) return result;
    Style look = world.tables.styles[particle.style];
    float age = saturate((float(tick - particle.born) - 1.0 + root.blend) / float(particle.life));
    float size = lerp(look.size_from, look.size_to, ease(look.size_curve, age));
    float4 from = unpack(look.color_from), to = unpack(look.color_to);
    float4 color = lerp(float4(linear_fast(from.rgb), from.a), float4(linear_fast(to.rgb), to.a), age);
    result.color = color.rgb * color.a;
    float2 shown = particle.position - particle.velocity * (TICK_SECONDS * (1.0 - root.blend));
    result.position = float4((shown + result.at * (size * 0.5)) / float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) * 2.0 - 1.0, 0.0, 1.0);
    return result;
}

// Light only: it adds, and covers nothing. No texel is pulled; a particle is
// its own falloff.
float4 particle_light(ParticleVertex input)
{
    float glow = saturate(1.0 - length(input.at));
    // Brighter than its color at the heart, so a thick of them burns white.
    return float4(input.color * (glow * glow * (3.0 - 2.0 * glow) * 1.8), 0.0);
}
