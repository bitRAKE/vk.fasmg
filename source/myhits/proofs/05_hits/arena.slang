// Proof 05, hits: shots against masks, bodies against the ship, and the
// particles and events a hit throws off. What it settles and how to run it is
// in ..\README.md. The library is ..\..\hits.slang and particles.slang.
#include "pictures.slang"
#include "motion.slang"

static const uint CAPACITY = 256;           // bodies, each twice
static const uint SHOTS = 128;              // the first slots: what the player fires, a ring
static const uint HOSTILES = 96;            // the next: what can be hit
static const uint PARTICLES = 16384;
static const uint HIT_LOG = 64;
static const uint CYCLE = 720;              // ticks: the script of what appears repeats
static const float SHIP_SPEED = 600.0;
static const float SHIP_SCALE = 1.5;
static const uint SPARKS = 6;               // thrown off by a hit
static const uint DEBRIS = 48;              // by a death
static const uint FLASH_TICKS = 10;
static const uint SPRITE_FLASH = 8;         // the bits above this are how white it is

struct Game
{
    uint tick;              // ticks run
    uint opened;            // the frame whose events are open, plus one
    float2 ship;
    float2 ship_before;
    uint cooldown;
    uint shot_cursor;
    uint fired;             // by the player; and what became of each:
    uint escaped;           // left the playfield
    uint struck;            // hit something
    uint kills;
    uint score;
    uint ship_hits;         // hostiles touching the ship, as the last tick's resolve counted
    uint hurts;             // times that hurt it
    uint hurt_tick;         // the tick it last did, plus one
    uint hit_count;         // hits ever; the log is a ring of the last of them
    uint fireworks;         // how many were let in, the last time they were asked for
    uint survey[4];         // solid texels found through each of four poses
    uint survey_wrong;      // texels hit where the mask says there is nothing, or the other way
    uint survey_crossed;    // crossings of the wire that struck it
};
static const uint WIRE_CROSSINGS = 400;
// The header the CPU writes once: ArenaWorld in arena.asm.
struct World
{
    Pictures pictures; Tables tables; Body* bodies; Game* game; uint* damage;
    Particle* particles; ParticlePool* pool; float2* hit_log; uint capacity; uint particle_capacity;
};

#include "hits.slang"
#include "particles.slang"

Sprite ship_pose(float2 at)
{
    Sprite pose;
    pose.position = at;
    pose.axis = float2(SHIP_SCALE, 0.0);
    pose.frame = FRAME_SHIP;
    pose.flags = 0;
    return pose;
}

// Once, at start, alone: nothing on the device is as the game needs it yet.
[shader("compute")]
[numthreads(1, 1, 1)]
void begin()
{
    World* world = root.world;
    Game game;
    game.tick = 0; game.opened = 0;
    game.ship = float2(760.0, 540.0); game.ship_before = game.ship;
    game.cooldown = 0; game.shot_cursor = 0;
    game.fired = 0; game.escaped = 0; game.struck = 0; game.kills = 0; game.score = 0;
    game.ship_hits = 0; game.hurts = 0; game.hurt_tick = 0; game.hit_count = 0; game.fireworks = 0;
    for (uint pose = 0; pose < 4; ++pose) game.survey[pose] = 0;
    game.survey_wrong = 0;
    game.survey_crossed = 0;
    *world.game = game;
    for (uint body = 0; body < 2 * CAPACITY; ++body) { world.bodies[body].kind = 0; world.bodies[body].born = 0; }
    for (uint slot = 0; slot < CAPACITY; ++slot) world.damage[slot] = 0;
    for (uint particle = 0; particle < PARTICLES; ++particle) world.particles[particle].life = 0;
    for (uint entry = 0; entry < HIT_LOG; ++entry) world.hit_log[entry] = float2(0.0, 0.0);
    world.pool.asked = 0;
    open_particles(world);
}

// Then once a frame of the art. What is drawn is what is hit: every texel of
// the frame is set down on the playfield through a pose, as the draw sets it
// down, and brought back the way a hit is; it must come back solid exactly
// where its mask is. Four poses: plain, turned and grown, turned past a right
// angle and shrunk, and on its side at twice the size.
[shader("compute")]
[numthreads(1, 1, 1)]
void survey(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    Pictures pictures = world.pictures;
    if (id.x >= pictures.count) return;
    static const float turned[4] = { 0.0, 0.6457718, 2.4958208, 4.712389 };
    static const float grown[4] = { 1.0, 1.5, 0.75, 2.0 };
    Picture frame = pictures.frames[id.x];
    for (uint pose = 0; pose < 4; ++pose)
    {
        Sprite sprite;
        sprite.position = float2(700.5 + 13.0 * pose, 400.25 - 7.0 * pose);
        sprite.axis = heading(turned[pose]) * grown[pose];
        sprite.frame = id.x;
        // And the third of them mirrored, as a kind that keeps the right way up is.
        sprite.flags = pose == 2 ? SPRITE_FLIP : 0;
        uint found = 0, wrong = 0;
        for (uint y = 0; y < frame.height; ++y)
            for (uint x = 0; x < frame.width; ++x)
            {
                bool hit = solid_at(pictures, frame, into_picture(sprite, frame, set_down(sprite, frame, float2(x + 0.5, y + 0.5))));
                if (hit) ++found;
                if (hit != mask_bit(pictures, frame, x, y)) ++wrong;
            }
        // The cut frames have a count from outside the device: the packer's.
        if (frame.recipe == RECIPE_BAKED) InterlockedAdd(world.game.survey[pose], found);
        InterlockedAdd(world.game.survey_wrong, wrong);
    }
    // And the wire: a wall one texel thick lying across the diagonal, whose
    // texels touch only at their corners. Four hundred crossings, square to
    // it, each a little farther along it than the last, so that some pass
    // through the middle of a texel and some exactly between two. Every one
    // must strike.
    if (id.x == FRAME_WIRE)
    {
        uint struck = 0;
        float2 along = float2(0.70710678, 0.70710678), across = float2(0.70710678, -0.70710678);
        for (uint each = 0; each < WIRE_CROSSINGS; ++each)
        {
            float2 at = float2(20.5, 20.5) + along * (float(each) * 0.037);
            if (sweep(pictures, frame, at - across * 3.0, at + across * 3.0) >= 0.0) ++struck;
        }
        world.game.survey_crossed = struck;
    }
}

// A new body goes into last tick's copy: this tick's update is its first.
void spawn(World* world, uint slot, uint kind, float2 at, float angle, uint seed)
{
    uint tick = world.game.tick;
    world.bodies[((tick & 1) ^ 1) * CAPACITY + slot] = new_body(world.tables, kind, at, angle, seed, tick);
}

// The director: alone, first in every tick.
[shader("compute")]
[numthreads(1, 1, 1)]
void direct()
{
    World* world = root.world;
    Game* game = world.game;
    bool first = game.opened != root.frame + 1;
    if (first)
    {
        game.opened = root.frame + 1;
        open_events(root.events);
    }
    uint tick = game.tick;
    game.tick = tick + 1;
    open_particles(world);

    float2 ship = game.ship;
    game.ship_before = ship;
    ship = clamp(ship + root.move * (SHIP_SPEED * TICK_SECONDS), float2(80.0, 60.0), float2(PLAYFIELD_WIDTH - 60.0, PLAYFIELD_HEIGHT - 60.0));
    game.ship = ship;

    // What last tick's bodies did to the ship. Once hurt, it cannot be again
    // for a while: something passing through it hurts once.
    if (game.ship_hits != 0 && (game.hurt_tick == 0 || tick + 1 - game.hurt_tick >= 90))
    {
        game.hurts += 1;
        game.hurt_tick = tick + 1;
        trigger(SOUND_HURT, ship.x);
    }
    game.ship_hits = 0;

    // What there is to shoot at and be hit by, over and over.
    uint phase = tick % CYCLE;
    if (tick == 0) spawn(world, SHOTS, KIND_TARGET, float2(1400.0, 540.0), 0.0, 0);
    if (phase == 0) spawn(world, SHOTS + 1, KIND_DRONE, float2(1400.0, 250.0), 3.14159265, 0);
    if (phase == 300) spawn(world, SHOTS + 2, KIND_RAMMER, float2(PLAYFIELD_WIDTH + 120.0, ship.y - 110.0), 3.14159265, 0);
    if (phase == 330) spawn(world, SHOTS + 3, KIND_RAMMER, float2(PLAYFIELD_WIDTH + 120.0, ship.y), 3.14159265, 0);

    if (game.cooldown > 0) game.cooldown -= 1;
    if ((root.held & BUTTON_FIRE) != 0 && game.cooldown == 0)
    {
        uint slot = game.shot_cursor % SHOTS;
        game.shot_cursor += 1;
        spawn(world, slot, KIND_SHOT, ship + float2(60.0, 0.0), 0.0, 0);
        game.cooldown = SHOT_TICKS;
        game.fired += 1;
        trigger(SOUND_SHOT, ship.x);
    }
    if (first && (root.pressed & BUTTON_SECOND) != 0)
    {
        uint slot = game.shot_cursor % SHOTS;
        game.shot_cursor += 1;
        spawn(world, slot, KIND_LANCE, ship + float2(60.0, 0.0), 0.0, 0);
        game.fired += 1;
        trigger(SOUND_LAUNCH, ship.x);
    }
    // More than the style admits in a tick, to see that it admits no more.
    if (first && (root.pressed & BUTTON_START) != 0)
        game.fireworks = emit(world, STYLE_BURST, ship, float2(1.0, 0.0), float2(0.0, 0.0), 500, tick, tick + 1);
}

// Every body at once: last tick's copy in, this tick's out.
[shader("compute")]
[numthreads(64, 1, 1)]
void update(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    uint slot = id.x;
    if (slot >= CAPACITY) return;
    Game game = *world.game;
    uint now = game.tick & 1;
    Body body = world.bodies[(now ^ 1) * CAPACITY + slot];
    if (body.kind != 0)
    {
        Scene scene;
        scene.player = game.ship;
        scene.crosshair = root.aim;
        scene.drift = 0.0;
        scene.tempo = 1.0;
        bool alive = advance_body(body, world.tables, scene);
        if (body.position.x < -220.0 || body.position.x > PLAYFIELD_WIDTH + 220.0 || body.position.y < -220.0 || body.position.y > PLAYFIELD_HEIGHT + 220.0)
        {
            alive = false;
            if (slot < SHOTS) InterlockedAdd(world.game.escaped, 1);
        }
        if (!alive) body.kind = 0;
    }
    world.bodies[now * CAPACITY + slot] = body;
}

// Every shot at once, against everything that can be hit: the nearest thing
// along its way this tick takes it. A shot writes its own death and nothing
// else of its own; what it does to others goes by atomics.
[shader("compute")]
[numthreads(64, 1, 1)]
void collide(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    uint slot = id.x;
    if (slot >= SHOTS) return;
    Game game = *world.game;
    uint now = (game.tick & 1) * CAPACITY, before = ((game.tick & 1) ^ 1) * CAPACITY;
    Body shot = world.bodies[now + slot];
    if (shot.kind == 0) return;
    float2 to = shot.position, from = world.bodies[before + slot].position;
    Pictures pictures = world.pictures;
    float nearest = 2.0;
    uint taker = 0;
    for (uint other = SHOTS; other < SHOTS + HOSTILES; ++other)
    {
        uint kind = world.bodies[now + other].kind;
        if (kind == 0 || world.tables.kinds[kind].health <= 0.0) continue;
        Body target = world.bodies[now + other];
        // First by circles: the shot's whole step against all the target could cover.
        float2 apart = (from + to) * 0.5 - target.position;
        float reach = reach_of(pose_of(target), pictures.frames[target.picture]) + 0.5 * length(to - from) + 8.0;
        if (dot(apart, apart) > reach * reach) continue;
        Body was = world.bodies[before + other];
        if (was.kind != target.kind || was.born != target.born) was = target;
        float along = sweep_body(pictures, was, target, from, to);
        if (along >= 0.0 && along < nearest)
        {
            nearest = along;
            taker = other;
        }
    }
    if (nearest > 1.0) return;
    float2 where = lerp(from, to, nearest);
    InterlockedAdd(world.damage[taker], 1);
    InterlockedAdd(world.game.struck, 1);
    uint count;
    InterlockedAdd(world.game.hit_count, 1, count);
    world.hit_log[count % HIT_LOG] = where;
    trigger(SOUND_HIT, where.x);
    emit(world, STYLE_SPARK, where, -heading(shot.angle), float2(0.0, 0.0), SPARKS, count, game.tick);
    world.bodies[now + slot].kind = 0;
}

// Then everything that can be hit, at once: each takes what struck it, dies
// of it or not, and says whether it is touching the ship.
[shader("compute")]
[numthreads(32, 1, 1)]
void resolve(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    if (id.x >= HOSTILES) return;
    uint slot = SHOTS + id.x;
    Game game = *world.game;
    uint at = (game.tick & 1) * CAPACITY + slot;
    uint taken = world.damage[slot];
    if (taken != 0) world.damage[slot] = 0;
    Body body = world.bodies[at];
    if (body.kind == 0) return;
    Kind kind = world.tables.kinds[body.kind];
    if (taken != 0)
    {
        body.health -= float(taken);
        body.struck = game.tick;
        if (body.health <= 0.0)
        {
            emit(world, STYLE_BURST, body.position, float2(1.0, 0.0), heading(body.angle) * (body.speed * 0.3), DEBRIS, slot, game.tick);
            InterlockedAdd(world.game.score, kind.worth);
            InterlockedAdd(world.game.kills, 1);
            trigger(SOUND_BURST, body.position.x);
            body.kind = 0;
        }
        world.bodies[at] = body;
        if (body.kind == 0) return;
    }
    if (kind.health > 0.0 && touches(world.pictures, ship_pose(game.ship), pose_of(body))) InterlockedAdd(world.game.ship_hits, 1);
}

// And every particle, in place.
[shader("compute")]
[numthreads(64, 1, 1)]
void drift(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    if (id.x >= PARTICLES) return;
    advance_particle(world, id.x, world.game.tick, world.game.ship);
}

// Last in every frame, whether it ran a tick or not: the frame's report.
[shader("compute")]
[numthreads(1, 1, 1)]
void report()
{
    World* world = root.world;
    Game* game = world.game;
    Events* events = root.events;
    if (game.opened != root.frame + 1)
    {
        game.opened = root.frame + 1;
        open_events(events);
    }
    uint now = (game.tick & 1) * CAPACITY;
    uint flying = 0;
    for (uint slot = 0; slot < SHOTS; ++slot)
        if (world.bodies[now + slot].kind != 0) ++flying;
    events.score = game.score;
    events.wave = game.survey_wrong;
    events.multiplier = game.survey_crossed;
    // Being hurt is felt: for half a second, and less as it passes.
    float hurt = game.hurt_tick == 0 ? 0.0 : saturate(1.0 - float(game.tick + 1 - game.hurt_tick) / 60.0);
    events.rumble_low = hurt;
    events.rumble_high = hurt * hurt;
    for (uint pose = 0; pose < 4; ++pose) events.debug[pose] = game.survey[pose];
    events.reserved[0] = game.tick;
    events.reserved[1] = game.fired;
    events.reserved[2] = game.escaped;
    events.reserved[3] = game.struck;
    events.reserved[4] = flying;
    events.reserved[5] = game.kills;
    events.reserved[6] = game.hurts;
    events.reserved[7] = world.pool.asked;
    events.reserved[8] = world.pool.live;
    events.reserved[9] = game.fireworks;
    events.reserved[10] = game.hit_count;
    float2 last = world.hit_log[(game.hit_count + HIT_LOG - 1) % HIT_LOG];
    events.reserved[11] = asuint(last.x);
    events.reserved[12] = asuint(last.y);
    events.reserved[13] = asuint(game.ship.x);
    events.reserved[14] = asuint(game.ship.y);
    events.reserved[15] = asuint(world.bodies[now + SHOTS + 1].health);
}

// The bodies between their last two ticks, white for a moment when struck;
// then the ship, and the crosshair.
[shader("vertex")]
SpriteVertex scene_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    World* world = root.world;
    Game game = *world.game;
    Sprite sprite;
    if (instance < CAPACITY)
    {
        uint now = game.tick & 1;
        Body body = world.bodies[now * CAPACITY + instance];
        Shown shown = show_body(world.bodies[(now ^ 1) * CAPACITY + instance], body, root.blend);
        sprite.position = shown.position;
        sprite.axis = shown.axis;
        sprite.frame = shown.picture;
        uint since = game.tick - body.struck;
        sprite.flags = body.struck != 0 && since < FLASH_TICKS ? (255 - since * 255 / FLASH_TICKS) << SPRITE_FLASH : 0;
    }
    else if (instance == CAPACITY)
    {
        sprite = ship_pose(lerp(game.ship_before, game.ship, root.blend));
        uint since = game.tick + 1 - game.hurt_tick;
        sprite.flags = game.hurt_tick != 0 && since < 3 * FLASH_TICKS ? (255 - since * 255 / (3 * FLASH_TICKS)) << SPRITE_FLASH : 0;
    }
    else
    {
        sprite.position = root.aim;
        sprite.axis = float2(1.0, 0.0);
        sprite.frame = FRAME_CROSSHAIR;
        sprite.flags = 0;
    }
    return sprite_corner(sprite, world.pictures.frames[sprite.frame], vertex);
}

[shader("fragment")]
float4 scene_fragment(SpriteVertex input) : SV_Target0
{
    Pictures pictures = root.world.pictures;
    float alpha, toward;
    float4 color = sprite_color(pictures, pictures.frames[input.frame], input, alpha, toward);
    if (alpha <= 0.0) discard;
    float flash = float(input.flags >> SPRITE_FLASH) * (1.0 / 255.0);
    color.rgb = lerp(color.rgb, float3(color.a, color.a, color.a), flash);
    return color;
}

[shader("vertex")]
ParticleVertex particle_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    World* world = root.world;
    return particle_corner(world, instance, vertex, world.game.tick);
}

[shader("fragment")]
float4 particle_fragment(ParticleVertex input) : SV_Target0
{
    return particle_light(input);
}
