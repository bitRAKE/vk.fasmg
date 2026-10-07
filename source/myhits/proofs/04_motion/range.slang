// Proof 04, motion: the easing curves on the wall, and a range where bodies
// run the programs of tables.inc at a fixed tick. What it settles and how to
// run it is in ..\README.md. The library is ..\..\ease.slang and motion.slang.
#include "../../pictures.slang"
#include "../../motion.slang"

static const uint CAPACITY = 256;                   // bodies, each twice
static const uint SHOTS = 128;                      // the first slots: what the player fires, a ring
static const uint HOSTILES = 96;                    // the next: what comes at the player, a ring
static const uint ANCHOR_SLOT = SHOTS + HOSTILES;   // and one thing that rides the level
static const uint STARS = 160;
static const uint TRACE = 128;                      // points of the traced missile's path
static const uint SAMPLES = 65;                     // of each curve, read back by the CPU
static const uint INSTANCES = STARS + CAPACITY + TRACE + 2 * EASE_CURVES + 4;
static const float SHIP_SPEED = 600.0;
static const float PACE = 240.0;                    // the level's full speed
static const uint CYCLE = 1200;                     // ticks: it slows, stops and resumes, over and over
static const float2 CELL = float2(176.0, 86.0);     // one curve's plot

struct Game
{
    uint tick;              // ticks run
    uint opened;            // the frame whose events are open, plus one
    float2 ship;
    float2 ship_before;
    float pace;             // the level's speed now
    float scroll;           // how far it has come
    float scroll_before;
    uint cooldown;          // ticks until the next shot
    uint shot_cursor;
    uint hostile_cursor;
    uint fired;             // by the player; and what became of them:
    uint escaped;           // left the playfield
    uint struck;            // hit something (nothing can be hit yet)
    uint traced;            // the slot of the missile being traced, plus one
    uint trace_count;
    uint faults[4];         // what the examination of the curves found
};
// The header the CPU writes once: RangeWorld in range.asm.
struct World { Pictures pictures; Tables tables; Body* bodies; Game* game; float2* trace; float* curves; uint capacity; uint pad; };

// Where a curve's plot is: LINEAR alone on the first row, then a row a family.
float2 cell_corner(uint curve)
{
    uint row = curve == 0 ? 0 : (curve - 1) / 3 + 1, column = curve == 0 ? 0 : (curve - 1) % 3;
    return float2(20.0 + column * 184.0, 14.0 + row * 96.0);
}
// A value's height in a plot, from its top: there is room above 1 and below 0.
float plot_height(float value) { return 1.0 - (value + 0.45) / 1.9; }

// Once, at start. Every curve is sampled into memory the CPU can read, which
// is how the proof's script holds them to a second implementation; and one
// invocation examines them here for what needs no reference.
[shader("compute")]
[numthreads(64, 1, 1)]
void examine(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    uint index = id.x;
    if (index < EASE_CURVES * SAMPLES) world.curves[index] = ease(index / SAMPLES, float(index % SAMPLES) / float(SAMPLES - 1));
    if (index < 2 * CAPACITY) { world.bodies[index].kind = 0; world.bodies[index].born = 0; }
    if (index < TRACE) world.trace[index] = float2(-4000.0, -4000.0);
    if (index != 0) return;
    Game game;
    game.tick = 0; game.opened = 0;
    game.ship = float2(760.0, 540.0); game.ship_before = game.ship;
    game.pace = 0.0; game.scroll = 0.0; game.scroll_before = 0.0;
    game.cooldown = 0; game.shot_cursor = 0; game.hostile_cursor = 0;
    game.fired = 0; game.escaped = 0; game.struck = 0; game.traced = 0; game.trace_count = 0;
    uint ends = 0, mirrors = 0, order = 0, reach = 0;
    for (uint curve = 0; curve < EASE_CURVES; ++curve)
    {
        uint family = curve == 0 ? 99 : (curve - 1) / 3, form = curve == 0 ? 0 : (curve - 1) % 3;
        bool wild = family == 7 || family == 8;     // back and elastic pass outside 0..1
        bool bounces = family == 9;
        // 0 and 1, exactly: a move ends where it says.
        if (ease(curve, 0.0) != 0.0 || ease(curve, 1.0) != 1.0) ++ends;
        float low = 0.0, high = 1.0, last = 0.0;
        bool falls = false;
        for (uint sample = 0; sample < SAMPLES; ++sample)
        {
            float t = float(sample) / float(SAMPLES - 1), value = ease(curve, t);
            low = min(low, value);
            high = max(high, value);
            if (value < last - 1e-6) falls = true;
            last = value;
            // An OUT is its IN turned about the middle.
            if (form == 1 && abs(value - (1.0 - ease(curve - 1, 1.0 - t))) > 1e-5) ++mirrors;
        }
        // An INOUT passes through the middle.
        if (form == 2 && abs(ease(curve, 0.5) - 0.5) > 1e-5) ++mirrors;
        // All but bounce never go back; all but the wild ones stay inside, and those do not.
        if (!wild && !bounces && falls) ++order;
        if (wild ? !(low < -0.05 || high > 1.05) : (low < -1e-6 || high > 1.0 + 1e-6)) ++reach;
    }
    game.faults[0] = ends; game.faults[1] = mirrors; game.faults[2] = order; game.faults[3] = reach;
    *world.game = game;
}

// A new body goes into last tick's copy: this tick's update is its first.
void spawn(World* world, uint slot, uint kind, float2 at, float angle, uint seed)
{
    uint tick = world.game.tick;
    world.bodies[((tick & 1) ^ 1) * CAPACITY + slot] = new_body(world.tables, kind, at, angle, seed, tick);
}

// The director: alone, first in every tick. It moves the ship from the
// controls, sets the level's pace, and makes every new body.
[shader("compute")]
[numthreads(1, 1, 1)]
void direct()
{
    World* world = root.world;
    Game* game = world.game;
    // A frame may run several ticks; its events open, and a press counts, once.
    bool first = game.opened != root.frame + 1;
    if (first)
    {
        game.opened = root.frame + 1;
        open_events(root.events);
    }
    uint tick = game.tick;
    game.tick = tick + 1;

    float2 ship = game.ship;
    game.ship_before = ship;
    ship = clamp(ship + root.move * (SHIP_SPEED * TICK_SECONDS), float2(640.0, 60.0), float2(PLAYFIELD_WIDTH - 60.0, PLAYFIELD_HEIGHT - 60.0));
    game.ship = ship;

    // The level's own motion is eased like anything else. Here it slows to a
    // stop for something anchored to it, waits, and moves on.
    uint phase = tick % CYCLE;
    float share = phase < 100 ? 1.0 : phase < 160 ? 1.0 - ease(EASE_INOUT_SINE, float(phase - 99) / 60.0)
        : phase < 240 ? 0.0 : phase < 300 ? ease(EASE_INOUT_SINE, float(phase - 239) / 60.0) : 1.0;
    game.pace = PACE * share;
    game.scroll_before = game.scroll;
    game.scroll += game.pace * TICK_SECONDS;
    if (phase == 0) spawn(world, ANCHOR_SLOT, KIND_ANCHOR, float2(1760.0, 250.0), 0.0, 0);

    // Something to watch: a hostile now and then, each kind in turn.
    if (tick % 150 == 75)
    {
        uint count = game.hostile_cursor;
        game.hostile_cursor = count + 1;
        uint kind = count % 3 == 0 ? KIND_SWOOPER : count % 3 == 1 ? KIND_WEAVER : KIND_DIVER;
        spawn(world, SHOTS + count % HOSTILES, kind, float2(PLAYFIELD_WIDTH + 80.0, 220.0 + 640.0 * unit(hash(count + 17))), 3.14159265, count);
    }

    // Fire held: a shot every SHOT_TICKS.
    if (game.cooldown > 0) game.cooldown -= 1;
    if ((root.held & BUTTON_FIRE) != 0 && game.cooldown == 0)
    {
        uint slot = game.shot_cursor % SHOTS;
        game.shot_cursor += 1;
        spawn(world, slot, KIND_SHOT, ship + float2(60.0, 0.0), 0.0, 0);
        game.cooldown = SHOT_TICKS;
        game.fired += 1;
    }
    // The second button, pressed: a pair of missiles, mirrored. The first is traced.
    if (first && (root.pressed & BUTTON_SECOND) != 0)
    {
        for (uint side = 0; side < 2; ++side)
        {
            uint slot = game.shot_cursor % SHOTS;
            game.shot_cursor += 1;
            spawn(world, slot, KIND_MISSILE, ship + float2(30.0, 0.0), 0.0, side);
            if (side == 0) game.traced = slot + 1;
        }
        game.fired += 2;
        game.trace_count = 0;
        for (uint point = 0; point < TRACE; ++point) world.trace[point] = float2(-4000.0, -4000.0);
    }
    if (game.traced != 0)
    {
        Body body = world.bodies[((tick & 1)) * CAPACITY + game.traced - 1];
        if (body.kind != KIND_MISSILE) game.traced = 0;
        else if ((tick & 1) == 0)
        {
            world.trace[game.trace_count % TRACE] = body.position;
            game.trace_count += 1;
        }
    }
}

// Then every body at once: last tick's copy in, this tick's out.
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
        scene.drift = game.pace * TICK_SECONDS;
        // Of a pair of missiles the second goes about its moves twice as
        // quick: a tempo is how rank will hurry what is hostile.
        scene.tempo = body.kind == KIND_MISSILE && (body.seed & 1) != 0 ? 2.0 : 1.0;
        bool alive = advance_body(body, world.tables, scene);
        if (body.position.x < -220.0 || body.position.x > PLAYFIELD_WIDTH + 220.0 || body.position.y < -220.0 || body.position.y > PLAYFIELD_HEIGHT + 220.0)
        {
            alive = false;
            // A shot that leaves the playfield has missed: accuracy is counted here.
            if (slot < SHOTS) InterlockedAdd(world.game.escaped, 1);
        }
        if (!alive) body.kind = 0;
    }
    world.bodies[now * CAPACITY + slot] = body;
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
    events.score = INSTANCES;
    for (uint fault = 0; fault < 4; ++fault) events.debug[fault] = game.faults[fault];
    events.reserved[0] = game.tick;
    events.reserved[1] = game.fired;
    events.reserved[2] = game.escaped;
    events.reserved[3] = flying;
    events.reserved[4] = asuint(game.pace);
    events.reserved[5] = asuint(game.scroll);
    Body anchor = world.bodies[now + ANCHOR_SLOT];
    events.reserved[6] = asuint(anchor.position.x);
    events.reserved[7] = anchor.kind;
    events.reserved[8] = asuint(game.ship.x);
    events.reserved[9] = asuint(game.ship.y);
    if (game.traced != 0)
    {
        Body missile = world.bodies[now + game.traced - 1];
        events.reserved[10] = missile.kind;
        events.reserved[11] = asuint(missile.position.x);
        events.reserved[12] = asuint(missile.position.y);
        events.reserved[13] = asuint(missile.angle);
        events.reserved[14] = asuint(missile.speed);
        events.reserved[15] = missile.move - world.tables.kinds[KIND_MISSILE].first;
        // And its twin, in the next slot, which is the hurried one.
        Body twin = world.bodies[now + game.traced % SHOTS];
        events.report[0] = twin.kind == KIND_MISSILE ? twin.move - world.tables.kinds[KIND_MISSILE].first : 99;
        events.report[1] = asuint(twin.position.x);
        events.report[2] = asuint(twin.position.y);
    }
}

// Everything that is a sprite, in one draw: the level's specks, the bodies
// between their last two ticks, the missile's trace, a rider on every curve,
// and the ship with what the controls light on it.
[shader("vertex")]
SpriteVertex scene_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    World* world = root.world;
    Game game = *world.game;
    Sprite sprite;
    sprite.position = float2(0.0, 0.0);
    sprite.axis = float2(0.0, 0.0);
    sprite.frame = FRAME_SPARK;
    sprite.flags = 0;
    uint index = instance;
    if (index < STARS)
    {
        // The nearer a speck, the faster it passes: the level's pace, seen.
        float depth = 0.25 + 0.75 * unit(hash(index * 3 + 1));
        float span = PLAYFIELD_WIDTH + 80.0;
        float x = unit(hash(index * 3 + 2)) * span - lerp(game.scroll_before, game.scroll, root.blend) * depth;
        sprite.position = float2(x - span * floor(x / span) - 40.0, unit(hash(index * 3 + 3)) * PLAYFIELD_HEIGHT);
        sprite.axis = float2(0.1 + 0.3 * depth, 0.0);
    }
    else if ((index -= STARS) < CAPACITY)
    {
        uint now = game.tick & 1;
        Shown shown = show_body(world.bodies[(now ^ 1) * CAPACITY + index], world.bodies[now * CAPACITY + index], root.blend);
        sprite.position = shown.position;
        sprite.axis = shown.axis;
        sprite.frame = shown.picture;
    }
    else if ((index -= CAPACITY) < TRACE)
    {
        sprite.position = world.trace[index];
        sprite.axis = float2(0.2, 0.0);
    }
    else if ((index -= TRACE) < 2 * EASE_CURVES)
    {
        // Two riders a curve: one on the plot, and one under it that only
        // slides, which is what the curve feels like.
        uint curve = index / 2;
        float2 corner = cell_corner(curve);
        float phase = saturate(frac(root.time / 2.4) * 1.25);
        float value = ease(curve, phase);
        sprite.position = (index & 1) == 0 ? corner + float2(phase, plot_height(value)) * CELL : corner + float2(value * CELL.x, CELL.y + 4.0);
        sprite.axis = float2((index & 1) == 0 ? 0.3 : 0.22, 0.0);
    }
    else
    {
        index -= 2 * EASE_CURVES;
        float2 ship = lerp(game.ship_before, game.ship, root.blend);
        sprite.position = ship;
        sprite.axis = float2(1.5, 0.0);
        sprite.frame = FRAME_SHIP;
        // The controls show themselves, straight from the root: no tick between.
        if (index == 0)
        {
            sprite.position = ship - float2(78.0, 0.0);
            sprite.axis = float2(dot(root.move, root.move) > 0.0 ? -0.7 : 0.0, 0.0);
            sprite.frame = FRAME_FLARE;
        }
        if (index == 1)
        {
            sprite.position = ship + float2(72.0, 0.0);
            sprite.axis = float2((root.held & BUTTON_FIRE) != 0 ? 0.9 : 0.0, 0.0);
            sprite.frame = FRAME_SPARK;
        }
        if (index == 3)
        {
            sprite.position = root.aim;
            sprite.axis = float2(1.0, 0.0);
            sprite.frame = FRAME_CROSSHAIR;
        }
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
    return color;
}

struct PlotVertex
{
    float4 position : SV_Position;
    float2 at : TEXCOORD0;                  // across and down the plot, 0..1
    nointerpolation uint curve : COLOR0;
};

[shader("vertex")]
PlotVertex plot_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    uint corner = corners[vertex];
    PlotVertex result;
    result.at = float2(corner & 1, corner >> 1);
    result.position = float4((cell_corner(instance) + result.at * CELL) / float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) * 2.0 - 1.0, 0.0, 1.0);
    result.curve = instance;
    return result;
}

// A curve is drawn by evaluating it: each fragment asks how far it is from
// the curve at its own x. IN is amber, OUT blue, INOUT green.
[shader("fragment")]
float4 plot_fragment(PlotVertex input) : SV_Target0
{
    float off = plot_height(ease(input.curve, input.at.x)) - input.at.y;
    float stroke = saturate(1.6 - abs(off) / max(length(float2(ddx(off), ddy(off))), 1e-5));
    float pixel = max(fwidth(input.at.y), 1e-5);
    float rule = max(saturate(1.0 - abs(input.at.y - plot_height(0.0)) / pixel), saturate(1.0 - abs(input.at.y - plot_height(1.0)) / pixel));
    uint form = input.curve == 0 ? 3 : (input.curve - 1) % 3;
    float3 ink = form == 0 ? float3(1.0, 0.6, 0.15) : form == 1 ? float3(0.3, 0.7, 1.0) : form == 2 ? float3(0.4, 1.0, 0.5) : float3(1.0, 1.0, 1.0);
    float4 color = float4(0.004, 0.008, 0.02, 0.8);
    color = lerp(color, float4(0.05, 0.08, 0.14, 1.0), rule);
    return lerp(color, float4(ink, 1.0), stroke);
}
