// myhits, the game: everything the proofs proved, in one world. What its own
// scripted run holds it to is in proofs\README.md, under 07.
#include "pictures.slang"
#include "motion.slang"

static const uint BODIES = 1024;                // each twice
static const uint SHOTS = 256;                  // the first slots: what the player fires, a ring
static const uint PELLETS = 384;                // then what hostiles fire, a ring
static const uint HOSTILES = 384;               // then hostiles and the segments of their chains
static const uint HOSTILE_FIRST = SHOTS + PELLETS;
static const uint PARTICLES = 16384;
static const uint TRAILS = 32;
static const uint REQUESTS = 256;
static const uint STARS = 160;
static const uint HUD = 21;                     // eight digits, three lives, ten pips of rank
static const uint INSTANCES = STARS + BODIES + 4 + HUD;
static const uint STOP_TICKS = 4;               // a hurt stops the world this long: it is felt
static const uint SPRITE_INK = 16;              // a sprite's flags from here are which ink it is drawn in
static const float SHIP_SPEED = 600.0;
static const float SHIP_SCALE = 1.5;
static const float PACE = 240.0;                // the level's full speed
static const uint PACE_TICKS = 90;              // it eases from one pace to another in this long
static const uint LOOK_TICKS = 120;             // how often rank looks at the shooting
static const uint GRACE_TICKS = 240;            // after a hurt, nothing more can hurt
static const uint LIVES = 3;
static const uint SPARKS = 6;
static const uint DEBRIS = 48;
static const uint FLASH_TICKS = 10;
static const uint SPRITE_FLASH = 8;             // a sprite's flags above this are how white it is
static const uint STATE_PLAY = 0;
static const uint STATE_OVER = 1;

struct Game
{
    uint tick;              // ticks run
    uint opened;            // the frame whose events are open, plus one
    uint state;
    uint over_tick;
    float2 ship;
    float2 ship_before;
    float pace;             // the level's speed now, and the ease it is in:
    float pace_from;        // shares of its full pace
    float pace_to;
    uint pace_tick;
    float scroll;
    float scroll_before;
    uint cooldown;
    uint shot_cursor;
    uint pellet_cursor;
    uint hostile_cursor;
    uint trail_cursor;
    uint fired;             // by the player; and what became of each:
    uint escaped;
    uint struck;
    uint looked_escaped;    // as they stood when rank last looked
    uint looked_struck;
    float rank;             // 0..1
    uint kills;
    uint score;
    uint lives;
    uint ship_hits;         // as the last tick's passes counted
    uint hurts;
    uint hurt_tick;         // the tick of the last, plus one
    uint wave;              // squads begun
    uint wave_tick;         // when the last began
    uint members;           // of it, still to come
    uint member;            // and how many have
    uint member_tick;       // when the next is due
    uint pace_due;          // the tick a squad's pace takes hold, plus one
    float pace_wanted;
    uint requests;          // what this tick's bodies asked the director for
    uint requested;         // ever
    uint alive;             // hostiles, as the last resolve counted
    uint probe;             // the slot of the last chain's head, plus one
    uint shown;             // the score as the HUD shows it: it chases the real one
    uint score_seen;
    uint score_tick;        // when the score last grew, plus one: the digits jump
    uint stop;              // ticks of stillness still to come
    uint frozen;            // whether this tick is one of them
    uint stopped;           // ticks ever spent so
};
struct Request { uint kind; float2 at; float angle; uint seed; };
// The header the CPU writes once: GameWorld in myhits.asm.
struct World
{
    Pictures pictures; Tables tables; Body* bodies; Game* game; uint* damage; Particle* particles; ParticlePool* pool;
    float2* trails; Request* queue; float* bank; uint capacity; uint particle_capacity;
};

#include "hits.slang"
#include "particles.slang"
#include "chains.slang"
#include "sounds.slang"

Sprite ship_pose(float2 at)
{
    Sprite pose;
    pose.position = at;
    pose.axis = float2(SHIP_SCALE, 0.0);
    pose.frame = FRAME_SHIP;
    pose.flags = 0;
    return pose;
}

void new_game(Game* game)
{
    Game fresh;
    fresh.tick = game.tick; fresh.opened = game.opened;
    fresh.state = STATE_PLAY; fresh.over_tick = 0;
    fresh.ship = float2(300.0, 540.0); fresh.ship_before = fresh.ship;
    fresh.pace = PACE; fresh.pace_from = 1.0; fresh.pace_to = 1.0; fresh.pace_tick = 0;
    fresh.scroll = game.scroll; fresh.scroll_before = game.scroll_before;
    fresh.cooldown = 0; fresh.shot_cursor = 0; fresh.pellet_cursor = 0; fresh.hostile_cursor = 0; fresh.trail_cursor = 0;
    fresh.fired = 0; fresh.escaped = 0; fresh.struck = 0; fresh.looked_escaped = 0; fresh.looked_struck = 0;
    fresh.rank = 0.0; fresh.kills = 0; fresh.score = 0; fresh.lives = LIVES;
    fresh.ship_hits = 0; fresh.hurts = 0; fresh.hurt_tick = 0;
    fresh.wave = 0; fresh.wave_tick = game.tick; fresh.members = 0; fresh.member = 0; fresh.member_tick = 0;
    fresh.pace_due = 0; fresh.pace_wanted = 1.0;
    fresh.requests = 0; fresh.requested = 0; fresh.alive = 0; fresh.probe = 0;
    fresh.shown = 0; fresh.score_seen = 0; fresh.score_tick = 0; fresh.stop = 0; fresh.frozen = 0; fresh.stopped = game.stopped;
    *game = fresh;
}

// Once, at start, alone: nothing on the device is as the game needs it yet.
[shader("compute")]
[numthreads(1, 1, 1)]
void begin()
{
    World* world = root.world;
    world.game.tick = 0;
    world.game.opened = 0;
    world.game.scroll = 0.0;
    world.game.scroll_before = 0.0;
    world.game.stopped = 0;
    new_game(world.game);
    for (uint body = 0; body < 2 * BODIES; ++body) { world.bodies[body].kind = 0; world.bodies[body].born = 0; }
    for (uint slot = 0; slot < BODIES; ++slot) world.damage[slot] = 0;
    for (uint particle = 0; particle < PARTICLES; ++particle) world.particles[particle].life = 0;
    world.pool.asked = 0;
    open_particles(world);
}

// A new body goes into last tick's copy: this tick's update is its first.
void place(World* world, uint slot, Body body)
{
    world.bodies[((world.game.tick & 1) ^ 1) * BODIES + slot] = body;
}

// A hostile of a kind, and with it the segments of its chain if it heads one.
// A chain takes a run of slots with its head in the last, so the head is
// drawn over its body; and a ring of trail.
void spawn_hostile(World* world, uint kind, float2 at, float angle, uint seed)
{
    Game* game = world.game;
    Kind made = world.tables.kinds[kind];
    uint run = made.links + 1;
    uint base = game.hostile_cursor + run > HOSTILES ? 0 : game.hostile_cursor;
    game.hostile_cursor = base + run;
    uint head = HOSTILE_FIRST + base + made.links;
    Body body = new_body(world.tables, kind, at, angle, seed, game.tick);
    if (made.links != 0)
    {
        body.link = game.trail_cursor % TRAILS + 1;
        game.trail_cursor += 1;
        game.probe = head + 1;
        for (uint place_in = 1; place_in <= made.links; ++place_in)
        {
            Body segment = new_body(world.tables, place_in == made.links ? made.tail_kind : made.link_kind, at, angle, game.tick, game.tick);
            segment.link = head | (place_in << LINK_PLACE);
            place(world, head - place_in, segment);
        }
    }
    place(world, head, body);
}

// The director: alone, first in every tick. Everything that is awkward in
// parallel is here: the controls, the level's pace, rank, what comes next, and
// every new body.
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

    // A run that is over waits for Enter, and begins again.
    if (game.state == STATE_OVER)
    {
        if (first && (root.pressed & BUTTON_START) != 0 && tick - game.over_tick > 60)
        {
            new_game(game);
            for (uint body = 0; body < 2 * BODIES; ++body) world.bodies[body].kind = 0;
        }
    }
    bool playing = game.state == STATE_PLAY;

    // A hurt stops the world for a few ticks. Nothing moves, nothing comes,
    // nothing is fired; only the clock, the HUD and the veil go on.
    bool frozen = game.stop != 0;
    if (frozen)
    {
        game.stop -= 1;
        game.stopped += 1;
    }
    game.frozen = frozen ? 1 : 0;

    // The score the HUD shows chases the real one, so it rolls; and when the
    // real one grows the digits jump.
    if (game.score != game.score_seen)
    {
        game.score_seen = game.score;
        game.score_tick = tick + 1;
    }
    if (game.shown < game.score) game.shown += max((game.score - game.shown) / 8, 1u);

    float2 ship = game.ship;
    game.ship_before = ship;
    if (playing && !frozen) ship = clamp(ship + root.move * (SHIP_SPEED * TICK_SECONDS), float2(80.0, 60.0), float2(PLAYFIELD_WIDTH - 60.0, PLAYFIELD_HEIGHT - 60.0));
    game.ship = ship;

    // What last tick did to the ship. A hurt costs a life and some rank, and
    // buys a while in which nothing more can hurt.
    if (playing && game.ship_hits != 0 && (game.hurt_tick == 0 || tick + 1 - game.hurt_tick >= GRACE_TICKS))
    {
        game.hurts += 1;
        game.hurt_tick = tick + 1;
        game.lives -= 1;
        game.rank = max(game.rank - 0.15, 0.0);
        game.stop = STOP_TICKS;
        trigger(SOUND_HURT, ship.x);
        emit(world, STYLE_BURST, ship, float2(1.0, 0.0), float2(0.0, 0.0), DEBRIS / 2, tick, tick + 1);
        if (game.lives == 0)
        {
            game.state = STATE_OVER;
            game.over_tick = tick;
            playing = false;
            emit(world, STYLE_BURST, ship, float2(-1.0, 0.0), float2(0.0, 0.0), DEBRIS, tick + 7, tick + 1);
            trigger(SOUND_BURST, ship.x);
        }
    }
    game.ship_hits = 0;

    // Rank looks at the shooting once a second: of the shots that have come
    // to anything since it last looked, the share that struck moves it up or
    // down about a neutral two in five; and living through the second counts.
    if (playing && tick % LOOK_TICKS == LOOK_TICKS - 1)
    {
        uint struck = game.struck - game.looked_struck, escaped = game.escaped - game.looked_escaped;
        game.looked_struck = game.struck;
        game.looked_escaped = game.escaped;
        float rank = game.rank + 0.01;
        if (struck + escaped != 0) rank += 0.04 * (float(struck) / float(struck + escaped) - 0.4);
        game.rank = saturate(rank);
    }

    // The level's pace, eased from what it was to what the last squad asked.
    if (game.pace_due != 0 && tick + 1 >= game.pace_due)
    {
        game.pace_from = game.pace / PACE;
        game.pace_to = game.pace_wanted;
        game.pace_tick = tick;
        game.pace_due = 0;
    }
    game.pace = PACE * lerp(game.pace_from, game.pace_to, ease(EASE_INOUT_SINE, float(tick - game.pace_tick + 1) / float(PACE_TICKS)));
    game.scroll_before = game.scroll;
    if (!frozen) game.scroll += game.pace * TICK_SECONDS;

    // What comes next, by the table; and the table again when it runs out.
    // Rank adds to a squad: one more for every third of it. They come whether
    // or not anyone is playing: a run that is over is still a world.
    if (!frozen)
    {
        Wave next = world.tables.waves[game.wave % world.tables.wave_count];
        if (game.members == 0 && tick >= game.wave_tick + next.after)
        {
            game.members = next.count + (next.count > 1 ? uint(game.rank * 3.0) : 0);
            game.member = 0;
            game.member_tick = tick;
            game.wave_tick = tick;
            if (next.pace >= 0.0)
            {
                game.pace_wanted = next.pace;
                game.pace_due = tick + next.pace_after + 1;
            }
        }
        if (game.members != 0 && tick >= game.member_tick)
        {
            spawn_hostile(world, next.kind, float2(PLAYFIELD_WIDTH + 100.0, next.y + next.spread * float(game.member % max(next.count, 1u))), 3.14159265, game.member);
            game.member += 1;
            game.member_tick = tick + next.stagger;
            game.members -= 1;
            if (game.members == 0) game.wave += 1;
        }
    }

    // What last tick's bodies asked for: only the director makes a body.
    uint asked = min(game.requests, REQUESTS);
    for (uint each = 0; each < asked; ++each)
    {
        Request request = world.queue[each];
        place(world, SHOTS + game.pellet_cursor % PELLETS, new_body(world.tables, request.kind, request.at, request.angle, request.seed, game.tick));
        game.pellet_cursor += 1;
        trigger(SOUND_SHOT, request.at.x);
    }
    game.requested += asked;
    game.requests = 0;

    // The player's own.
    if (game.cooldown > 0) game.cooldown -= 1;
    playing = playing && !frozen;
    if (playing && (root.held & BUTTON_FIRE) != 0 && game.cooldown == 0)
    {
        place(world, game.shot_cursor % SHOTS, new_body(world.tables, KIND_SHOT, ship + float2(60.0, 0.0), 0.0, 0, game.tick));
        game.shot_cursor += 1;
        game.cooldown = SHOT_TICKS;
        game.fired += 1;
        trigger(SOUND_SHOT, ship.x);
    }
    if (playing && first && (root.pressed & BUTTON_SECOND) != 0)
    {
        for (uint side = 0; side < 2; ++side)
        {
            place(world, game.shot_cursor % SHOTS, new_body(world.tables, KIND_MISSILE, ship + float2(30.0, 0.0), 0.0, side, game.tick));
            game.shot_cursor += 1;
        }
        game.fired += 2;
        trigger(SOUND_LAUNCH, ship.x);
    }
    if (!frozen) game.alive = 0;
}

// Every body at once: last tick's copy in, this tick's out. A head lays its
// trail; a segment follows its head's; a body that fires hands its request on.
[shader("compute")]
[numthreads(64, 1, 1)]
void update(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    uint slot = id.x;
    if (slot >= BODIES) return;
    Game game = *world.game;
    uint now = (game.tick & 1) * BODIES, before = ((game.tick & 1) ^ 1) * BODIES;
    Body body = world.bodies[before + slot];
    if (body.kind != 0 && game.frozen == 0)
    {
        Kind kind = world.tables.kinds[body.kind];
        bool alive;
        if ((kind.flags & KIND_FOLLOWS) != 0)
        {
            Body head = world.bodies[before + link_head(body.link)];
            alive = follow(body, head, world.trails, world.tables.kinds[head.kind].link_spacing);
            if (!alive)
            {
                emit(world, STYLE_BURST, body.position, float2(1.0, 0.0), float2(0.0, 0.0), DEBRIS / 2, slot, game.tick);
                trigger(SOUND_BURST, body.position.x);
            }
        }
        else
        {
            Scene scene;
            scene.player = game.ship;
            scene.crosshair = root.aim;
            scene.drift = game.pace * TICK_SECONDS;
            float2 was = body.position;
            uint fires;
            alive = advance_body(body, world.tables, scene, fires);
            if (body.link != 0) lay_trail(body, was, world.trails);
            if (fires != 0 && game.state == STATE_PLAY)
            {
                uint place_in;
                InterlockedAdd(world.game.requests, 1, place_in);
                if (place_in < REQUESTS)
                {
                    Request request;
                    request.kind = fires;
                    request.at = body.position;
                    float2 toward = game.ship - body.position;
                    request.angle = atan2(toward.y, toward.x);
                    request.seed = slot;
                    world.queue[place_in] = request;
                }
            }
        }
        if (body.position.x < -260.0 || body.position.x > PLAYFIELD_WIDTH + 260.0 || body.position.y < -260.0 || body.position.y > PLAYFIELD_HEIGHT + 260.0)
        {
            // What follows a head leaves with it, not before.
            if ((kind.flags & KIND_FOLLOWS) == 0)
            {
                alive = false;
                if (slot < SHOTS) InterlockedAdd(world.game.escaped, 1);
            }
        }
        if (!alive) body.kind = 0;
    }
    world.bodies[now + slot] = body;
}

// Every shot at once. The player's against everything that can be hit; a
// hostile's against the ship. A shot writes its own death; the rest is atomics.
[shader("compute")]
[numthreads(64, 1, 1)]
void collide(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    uint slot = id.x;
    if (slot >= SHOTS + PELLETS) return;
    Game game = *world.game;
    if (game.frozen != 0) return;
    uint now = (game.tick & 1) * BODIES, before = ((game.tick & 1) ^ 1) * BODIES;
    Body shot = world.bodies[now + slot];
    if (shot.kind == 0) return;
    float2 to = shot.position, from = world.bodies[before + slot].position;
    Pictures pictures = world.pictures;
    if (slot >= SHOTS)
    {
        if (game.state != STATE_PLAY) return;
        Picture frame = pictures.frames[FRAME_SHIP];
        float along = sweep(pictures, frame, into_picture(ship_pose(game.ship_before), frame, from), into_picture(ship_pose(game.ship), frame, to));
        if (along < 0.0) return;
        InterlockedAdd(world.game.ship_hits, 1);
        emit(world, STYLE_SPARK, lerp(from, to, along), -heading(shot.angle), float2(0.0, 0.0), SPARKS, slot, game.tick);
        world.bodies[now + slot].kind = 0;
        return;
    }
    float nearest = 2.0;
    uint taker = 0;
    for (uint other = HOSTILE_FIRST; other < HOSTILE_FIRST + HOSTILES; ++other)
    {
        uint kind = world.bodies[now + other].kind;
        if (kind == 0 || world.tables.kinds[kind].health <= 0.0) continue;
        Body target = world.bodies[now + other];
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
    InterlockedAdd(world.damage[taker], shot.kind == KIND_MISSILE ? 4 : 1);
    InterlockedAdd(world.game.struck, 1);
    trigger(SOUND_HIT, where.x);
    emit(world, STYLE_SPARK, where, -heading(shot.angle), float2(0.0, 0.0), SPARKS, slot, game.tick);
    world.bodies[now + slot].kind = 0;
}

// Then every hostile at once: each takes what struck it, dies of it or not,
// and says whether it is touching the ship. A kill is worth more the higher
// rank is.
[shader("compute")]
[numthreads(32, 1, 1)]
void resolve(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    if (id.x >= HOSTILES) return;
    uint slot = HOSTILE_FIRST + id.x;
    Game game = *world.game;
    if (game.frozen != 0) return;
    uint at = (game.tick & 1) * BODIES + slot;
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
            InterlockedAdd(world.game.score, uint(float(kind.worth) * (1.0 + game.rank) + 0.5));
            InterlockedAdd(world.game.kills, 1);
            trigger(SOUND_BURST, body.position.x);
            body.kind = 0;
        }
        world.bodies[at] = body;
        if (body.kind == 0) return;
    }
    InterlockedAdd(world.game.alive, 1);
    if (game.state == STATE_PLAY && kind.health > 0.0 && touches(world.pictures, ship_pose(game.ship), pose_of(body))) InterlockedAdd(world.game.ship_hits, 1);
}

// And every particle, in place.
[shader("compute")]
[numthreads(64, 1, 1)]
void drift(uint3 id : SV_DispatchThreadID)
{
    World* world = root.world;
    if (id.x >= PARTICLES || world.game.frozen != 0) return;
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
    uint now = (game.tick & 1) * BODIES, before = ((game.tick & 1) ^ 1) * BODIES;
    uint flying = 0, pellets = 0;
    for (uint slot = 0; slot < SHOTS + PELLETS; ++slot)
        if (world.bodies[now + slot].kind != 0) { if (slot < SHOTS) ++flying; else ++pellets; }
    events.state = game.state;
    events.score = game.score;
    events.wave = game.wave;
    events.lives = game.lives;
    events.rank = game.rank;
    float hurt = game.hurt_tick == 0 ? 0.0 : saturate(1.0 - float(game.tick + 1 - game.hurt_tick) / 60.0);
    events.rumble_low = hurt;
    events.rumble_high = hurt * hurt;
    events.intensity = saturate(float(game.alive) / 24.0);
    events.reserved[0] = game.tick;
    events.reserved[1] = game.fired;
    events.reserved[2] = game.escaped;
    events.reserved[3] = game.struck;
    events.reserved[4] = flying;
    events.reserved[5] = game.kills;
    events.reserved[6] = game.hurts;
    events.reserved[7] = game.alive;
    events.reserved[8] = pellets;
    events.reserved[9] = asuint(game.pace);
    events.reserved[10] = asuint(game.scroll);
    events.reserved[11] = game.requested;
    // The last chain: its head as it stood a tick ago, and its first segment
    // now. The one should be a spacing along the path from the other.
    events.debug[0] = 0;
    if (game.probe != 0)
    {
        Body head = world.bodies[before + game.probe - 1], now_head = world.bodies[now + game.probe - 1];
        uint links = world.tables.kinds[now_head.kind].links;
        Body tail = world.bodies[now + game.probe - 1 - links], second = world.bodies[now + game.probe - 2];
        events.debug[0] = now_head.kind != 0 && tail.kind != 0 ? links : 0;
        events.reserved[12] = asuint(head.position.x);
        events.reserved[13] = asuint(head.position.y);
        events.reserved[14] = asuint(second.position.x);
        events.reserved[15] = asuint(second.position.y);
        // And the least and most that two neighbors of it are apart.
        float least = 1e9, most = 0.0;
        for (uint place_in = 0; place_in < links; ++place_in)
        {
            float apart = distance(world.bodies[now + game.probe - 1 - place_in].position, world.bodies[now + game.probe - 2 - place_in].position);
            // The head itself is a tick ahead of where its segments read it.
            if (place_in == 0) continue;
            least = min(least, apart);
            most = max(most, apart);
        }
        events.debug[1] = asuint(least);
        events.debug[2] = asuint(most);
    }
    events.debug[3] = world.pool.live;
    events.report[0] = game.shown;
    events.report[1] = game.stopped;
}

// How far a hurt throws the picture about: a little under half a second of
// it, less and less.
float2 shake_of(Game game)
{
    uint since = game.tick + 1 - game.hurt_tick;
    if (game.hurt_tick == 0 || since >= 48) return float2(0.0, 0.0);
    return float2(sin(float(since) * 1.9), cos(float(since) * 2.7)) * (18.0 * (1.0 - ease(EASE_OUT_QUAD, float(since) / 48.0)));
}

// The level's specks, the bodies between their last two ticks, and the ship
// with what the controls light on it.
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
    float2 shake = shake_of(game);
    uint index = instance;
    if (index < STARS)
    {
        float depth = 0.25 + 0.75 * unit(hash(index * 3 + 1));
        float span = PLAYFIELD_WIDTH + 80.0;
        float x = unit(hash(index * 3 + 2)) * span - lerp(game.scroll_before, game.scroll, root.blend) * depth;
        sprite.position = float2(x - span * floor(x / span) - 40.0, unit(hash(index * 3 + 3)) * PLAYFIELD_HEIGHT) + shake * depth;
        sprite.axis = float2(0.1 + 0.3 * depth, 0.0);
    }
    else if ((index -= STARS) < BODIES)
    {
        uint now = game.tick & 1;
        Body body = world.bodies[now * BODIES + index];
        Shown shown = show_body(world.bodies[(now ^ 1) * BODIES + index], body, root.blend);
        sprite.position = shown.position + shake;
        sprite.axis = shown.axis;
        sprite.frame = shown.picture;
        uint since = game.tick - body.struck;
        sprite.flags = body.struck != 0 && since < FLASH_TICKS ? (255 - since * 255 / FLASH_TICKS) << SPRITE_FLASH : 0;
    }
    else if ((index -= BODIES) < 4)
    {
        float2 ship = lerp(game.ship_before, game.ship, root.blend) + shake;
        bool there = game.state == STATE_PLAY;
        // In its grace the ship blinks.
        uint since = game.tick + 1 - game.hurt_tick;
        if (game.hurt_tick != 0 && since < GRACE_TICKS && (since / 8) % 2 == 0) there = false;
        if (index == 0)
        {
            sprite.position = ship - float2(78.0, 0.0);
            sprite.axis = float2(there && dot(root.move, root.move) > 0.0 ? -0.7 : 0.0, 0.0);
            sprite.frame = FRAME_FLARE;
        }
        else if (index == 1)
        {
            sprite.position = ship + float2(72.0, 0.0);
            sprite.axis = float2(there && (root.held & BUTTON_FIRE) != 0 ? 0.9 : 0.0, 0.0);
        }
        else if (index == 2)
        {
            sprite = ship_pose(ship);
            if (!there) sprite.axis = float2(0.0, 0.0);
        }
        else
        {
            sprite.position = root.aim;
            sprite.axis = float2(1.0, 0.0);
            sprite.frame = FRAME_CROSSHAIR;
        }
    }
    else if ((index -= 4) < 8)
    {
        // The score, eight digits, the greatest first. Those before its first
        // are dim; all of them jump when it grows.
        uint place_of = 1;
        for (uint power = index; power < 7; ++power) place_of *= 10;
        float jump = game.score_tick == 0 ? 0.0 : saturate(1.0 - float(game.tick + 1 - game.score_tick) / 30.0);
        sprite.position = float2(70.0 + 34.0 * index, 56.0 - 10.0 * jump * jump);
        sprite.axis = float2(1.0 + 0.3 * jump * jump, 0.0);
        sprite.frame = FRAME_DIGIT_0 + (game.shown / place_of) % 10;
        sprite.flags = (game.shown < place_of && index != 7 ? 5 : jump > 0.0 ? 2 : 1) << SPRITE_INK;
    }
    else if ((index -= 8) < 3)
    {
        // The lives, as ships. One just lost shrinks away, red.
        uint since = game.tick + 1 - game.hurt_tick;
        bool lost = index == game.lives && game.hurt_tick != 0 && since < 60;
        sprite.position = float2(PLAYFIELD_WIDTH - 80.0 - 78.0 * index, 56.0);
        sprite.axis = float2(index < game.lives ? 0.6 : lost ? 0.6 * (1.0 - float(since) / 60.0) : 0.0, 0.0);
        sprite.frame = FRAME_SHIP;
        sprite.flags = (lost ? 4 : 1) << SPRITE_INK;
    }
    else
    {
        // Rank, as ten pips: green, then gold, then red.
        index -= 3;
        bool lit = float(index) < game.rank * 10.0;
        sprite.position = float2(PLAYFIELD_WIDTH * 0.5 - 162.0 + 36.0 * index, 50.0);
        sprite.axis = float2(lit ? 0.55 : 0.18, 0.0);
        sprite.flags = (lit ? (index < 4 ? 3 : index < 7 ? 2 : 4) : 5) << SPRITE_INK;
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
    float flash = float((input.flags >> SPRITE_FLASH) & 255) * (1.0 / 255.0);
    color.rgb = lerp(color.rgb, float3(color.a, color.a, color.a), flash);
    // The HUD's pictures are white, and take an ink.
    static const float3 inks[6] = { float3(1.0, 1.0, 1.0), float3(1.0, 1.0, 1.0), float3(1.0, 0.78, 0.25), float3(0.35, 1.0, 0.45), float3(1.0, 0.25, 0.15), float3(0.2, 0.24, 0.32) };
    color.rgb *= inks[min((input.flags >> SPRITE_INK) & 15, 5u)];
    return color;
}

[shader("vertex")]
ParticleVertex particle_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    World* world = root.world;
    ParticleVertex result = particle_corner(world, instance, vertex, world.game.tick);
    result.position.xy += shake_of(*world.game) / float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) * 2.0;
    return result;
}

[shader("fragment")]
float4 particle_fragment(ParticleVertex input) : SV_Target0
{
    return particle_light(input);
}

struct VeilVertex
{
    float4 position : SV_Position;
    float2 at : TEXCOORD0;                  // -1..1 across the playfield
    nointerpolation float hurt : COLOR0;
    nointerpolation float over : COLOR1;
};

// The last thing drawn, over everything: being hurt reddens the edges of
// the picture for a moment, and a run that is over dims all of it.
[shader("vertex")]
VeilVertex veil_vertex(uint vertex : SV_VulkanVertexID)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    Game game = *root.world.game;
    uint since = game.tick + 1 - game.hurt_tick;
    VeilVertex result;
    result.at = float2(corners[vertex] & 1, corners[vertex] >> 1) * 2.0 - 1.0;
    result.hurt = game.hurt_tick == 0 ? 0.0 : saturate(1.0 - float(since) / 80.0);
    result.over = game.state == STATE_OVER ? saturate(float(game.tick - game.over_tick) / 120.0) : 0.0;
    // With nothing to show it covers nothing.
    result.position = float4(result.hurt + result.over > 0.0 ? result.at : float2(0.0, 0.0), 0.0, 1.0);
    return result;
}

[shader("fragment")]
float4 veil_fragment(VeilVertex input) : SV_Target0
{
    float edge = smoothstep(0.3, 1.25, length(input.at));
    float red = input.hurt * input.hurt * edge * 0.8;
    float dim = input.over * 0.45;
    return float4(red * 0.9, red * 0.05, red * 0.02, saturate(red * 0.5 + dim));
}
