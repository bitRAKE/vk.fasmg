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
static const uint REQUEST_CELLS = 6;            // a hostile's own places to ask the director from: four its program's, two its death's
static const uint REQUESTS = HOSTILES * REQUEST_CELLS;
static const uint NO_SLOT = 0xffffffffu;        // what the director says when there is no room
static const uint STARS = 160;
static const uint BONUSES = 5;                  // in the order of their kinds and their pictures:
static const uint BONUS_RAPID = 0;              // shots twice as often
static const uint BONUS_SPREAD = 1;             // three at a time
static const uint BONUS_SHIELD = 2;             // the next hurt is not one
static const uint BONUS_NOVA = 3;               // everything on the playfield is struck, now
static const uint BONUS_DOUBLE = 4;             // kills are worth twice
static const uint BONUS_TICKS = 960;            // how long one lasts, before rank adds to it
static const uint CHARGE_PIPS = 8;
static const uint HUD = 21 + CHARGE_PIPS + BONUSES * 9; // eight digits, three lives, ten pips of rank, eight of charge; an icon and eight pips a bonus
static const uint MARKS = PELLETS + HOSTILES;   // what a hostile or its shot means to strike, shown
static const uint TETHER = 8;                   // points of light between the ship and its companion
static const uint SHIP_PARTS = 8 + TETHER;      // flare, muzzle, ship, shield, crosshair; the companion, its gun, its guard; the tether
static const float MATE_BACK = 150.0;           // how far behind the ship, along the ship's own path, the companion keeps
static const float MATE_REACH = 64.0;           // how near its guard stops a shot
static const uint MATE_TICKS = 10;              // between its shots when it fires for itself
static const uint MATE_SHOT = 2;                // the seed of a shot that is its and not the player's
static const uint INSTANCES = STARS + BODIES + SHIP_PARTS + MARKS + HUD;
static const float MISSILE_COST = 0.25;         // of charge, for a pair
static const float DASH_COST = 0.2;
static const float KILL_CHARGE = 0.06;          // what a kill pays,
static const float GRAZE_CHARGE = 0.03;         // a hostile shot that passes close,
static const float BONUS_CHARGE = 0.12;         // and a bonus
static const uint DASH_TICKS = 16;
static const float DASH_SPEED = 2400.0;         // so a dash is 320 units
static const uint SLIP_TICKS = 6;               // after a dash, shots still pass through for this long
static const float GRAZE_REACH = 95.0;          // how close to the ship's middle is close
static const uint BODY_SLIPPED = 1u << 31;      // a shot's own flag: it has passed through the ship in a dash
static const uint SPRITE_DIM = 20;              // a sprite's flags from here are how much of it is taken away, of 255
static const float LOCK_RING = 84.0;            // the ring of the lock picture, in its texels
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
    uint requested;         // what bodies have asked the director for, ever
    uint alive;             // hostiles, as the last resolve counted
    uint probe;             // the slot of the last chain's head, plus one
    uint shown;             // the score as the HUD shows it: it chases the real one
    uint score_seen;
    uint score_tick;        // when the score last grew, plus one: the digits jump
    uint stop;              // ticks of stillness still to come
    uint frozen;            // whether this tick is one of them
    uint stopped;           // ticks ever spent so
    uint began;             // the tick this run began in
    uint runs;              // runs before this one
    uint life_tick;         // when a life was last lost, plus one
    uint until[5];          // the tick each timed bonus lasts to
    uint got[5];            // when each was last taken, plus one: its slot in the HUD jumps
    uint collected[5];      // taken since the director last looked, by atomics
    uint taken[5];          // taken this run
    uint shield;            // hurts it will still take
    uint blocked;           // hurts it has taken
    uint nova_tick;         // when the last nova went off, plus one
    uint companion;         // 0: none. 1: it is where you were. 2: it acts for itself. 3: it takes your aim
    uint promoted;          // heads killed since the director last looked: each makes it more
    float2 promoted_at;     // where the last died: it comes from there
    float2 mate;            // where it is,
    float2 mate_before;
    float mate_gun;         // which way it fires,
    float mate_guard;       // and which way it shields
    uint mate_cooldown;
    uint mate_fired;
    uint mate_struck;       // its shots that struck
    uint guarded;           // shots its guard stopped
    uint ship_laid;         // the ship's own trail, as a head's
    float ship_carried;
    uint stage;             // times the table of squads has been gone through: the backdrop's inks
    uint stage_tick;        // when it last was
    uint music_faults;      // stems of the music that are louder than their gain, or silent
    float charge;           // 0..1: what missiles and the dash are paid from
    uint earned;            // kills since the director last looked: each pays charge
    uint grazes;            // hostile shots that passed close and did not strike
    uint grazes_seen;       // as the director last saw it
    uint dash_tick;         // the tick the last dash began in, plus one
    uint slip_until;        // until this tick hostile shots pass through the ship
    float2 dash_way;
    uint dashes;
    uint slipped;           // shots that passed through the ship in a dash
    uint empties;           // launches and dashes refused for want of charge
    uint blasts;            // things that ended in a burst
    uint blast_hits;        // and caught the ship in it
    float2 blast_at;        // where the last was
    uint raider;            // the slot of the last body a script set down, plus one
    uint heavy;             // the slot of the last heavy shot, plus one
    uint refused_shots;     // what there was no room for, by pool: nothing alive is written over to make room
    uint refused_pellets;
    uint refused_hostiles;
    uint near_hostile;      // the companion's nearest of each, as near_key, from the last tick's passes
    uint near_pellet;
};
struct Request { uint kind; float2 at; float angle; uint seed; float2 mark; uint marking; };
// The header the CPU writes once: GameWorld in myhits.asm.
struct World
{
    Pictures pictures; Tables tables; Body* bodies; Game* game; uint* damage; Particle* particles; ParticlePool* pool;
    float2* trails; Request* queue; float* bank; float2* ship_trail; uint capacity; uint particle_capacity;
    uint* staged; uint* home; uint words; uint spare;
    uint* asking;           // a bit for each hostile that has asked the director for something
};

// A lone thread on the device is slow: a quarter of a microsecond for every
// step of a loop that reads memory. So the director walks no pool. What a
// pool has to say to it, each of the pool's own threads says for itself: a
// bit raised (`asking`), or the least of something kept by an atomic minimum.
// A key for that: how far, and who, so that the nearest wins and of two as
// near the lower slot does, whichever thread came first.
static const uint NOBODY = 0xffffffffu;
uint near_key(float2 from, float2 to, uint who) { return (uint(min(distance(from, to), 4000.0) * 256.0) << 10) | who; }

#include "hits.slang"
#include "particles.slang"
#include "chains.slang"
#include "sounds.slang"
#include "backdrop.slang"

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
    fresh.requested = 0; fresh.alive = 0; fresh.probe = 0;
    fresh.shown = 0; fresh.score_seen = 0; fresh.score_tick = 0; fresh.stop = 0; fresh.frozen = 0; fresh.stopped = game.stopped;
    fresh.began = game.tick; fresh.runs = game.runs; fresh.life_tick = 0;
    for (uint bonus = 0; bonus < BONUSES; ++bonus) { fresh.until[bonus] = 0; fresh.got[bonus] = 0; fresh.collected[bonus] = 0; fresh.taken[bonus] = 0; }
    fresh.shield = 0; fresh.blocked = 0; fresh.nova_tick = 0;
    fresh.companion = 0; fresh.promoted = 0; fresh.promoted_at = fresh.ship; fresh.mate = fresh.ship; fresh.mate_before = fresh.ship;
    fresh.mate_gun = 0.0; fresh.mate_guard = 3.14159265; fresh.mate_cooldown = 0; fresh.mate_fired = 0; fresh.mate_struck = 0; fresh.guarded = 0;
    fresh.ship_laid = 0; fresh.ship_carried = 0.0;
    fresh.stage = 0; fresh.stage_tick = game.tick; fresh.music_faults = game.music_faults;
    fresh.charge = 1.0; fresh.earned = 0; fresh.grazes = 0; fresh.grazes_seen = 0;
    fresh.dash_tick = 0; fresh.slip_until = 0; fresh.dash_way = float2(1.0, 0.0); fresh.dashes = 0; fresh.slipped = 0; fresh.empties = 0;
    fresh.blasts = 0; fresh.blast_hits = 0; fresh.blast_at = float2(0.0, 0.0); fresh.raider = 0; fresh.heavy = 0;
    fresh.refused_shots = 0; fresh.refused_pellets = 0; fresh.refused_hostiles = 0;
    fresh.near_hostile = NOBODY; fresh.near_pellet = NOBODY;
    *game = fresh;
}

// First of all, once: the header and the tables, word for word, from the
// memory the CPU wrote them into to memory only the device touches. Every
// pass reads them, the director a hundred times a tick, and memory the CPU
// can see is slow for the device to read. Root.world is the CPU's copy for
// this pass alone.
[shader("compute")]
[numthreads(64, 1, 1)]
void settle(uint3 id : SV_DispatchThreadID)
{
    World* written = root.world;
    if (id.x < written.words) written.home[id.x] = written.staged[id.x];
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
    world.game.runs = 0;
    // The music has been rendered by now: every stem should reach its gain,
    // or near it, and never pass it.
    uint faults = 0;
    for (uint which = 0; which < world.tables.stem_count; ++which)
    {
        float peak = 0.0, gain = world.tables.stems[which].gain;
        for (uint index = 0; index < MUSIC_SAMPLES; index += 3) peak = max(peak, abs(world.bank[BANK_SAMPLES + which * MUSIC_SAMPLES + index]));
        if (peak > gain * 1.0001 || peak < gain * 0.5) ++faults;
    }
    world.game.music_faults = faults;
    new_game(world.game);
    for (uint body = 0; body < 2 * BODIES; ++body) { world.bodies[body].kind = 0; world.bodies[body].born = 0; }
    for (uint slot = 0; slot < BODIES; ++slot) world.damage[slot] = 0;
    for (uint cell = 0; cell < REQUESTS; ++cell) world.queue[cell].kind = 0;
    for (uint word = 0; word < HOSTILES / 32; ++word) world.asking[word] = 0;
    for (uint particle = 0; particle < PARTICLES; ++particle) world.particles[particle].life = 0;
    world.pool.asked = 0;
    open_particles(world);
}

// A new body goes into last tick's copy: this tick's update is its first.
void place(World* world, uint slot, Body body)
{
    world.bodies[((world.game.tick & 1) ^ 1) * BODIES + slot] = body;
}

// The director looks for room; it does not take the next slot whatever is in
// it. A slot is free when the copy a new body goes into holds nothing there.
// From `cursor` on, round a pool of `count` slots that begins at `first`: the
// slot, or NO_SLOT when the pool is full.
uint free_slot(World* world, uint first, uint count, inout uint cursor)
{
    uint latest = ((world.game.tick & 1) ^ 1) * BODIES;
    for (uint tried = 0; tried < count; ++tried)
    {
        uint slot = (cursor + tried) % count;
        if (world.bodies[latest + first + slot].kind != 0) continue;
        cursor = (slot + 1) % count;
        return first + slot;
    }
    return NO_SLOT;
}

// One of the player's shots, where there is room. What there is none for is
// refused, and counted: nothing alive is written over.
bool put_shot(World* world, Body body)
{
    uint slot = free_slot(world, 0, SHOTS, world.game.shot_cursor);
    if (slot == NO_SLOT)
    {
        world.game.refused_shots += 1;
        return false;
    }
    place(world, slot, body);
    return true;
}

// A hostile shot likewise: its slot, or NO_SLOT.
uint put_pellet(World* world, Body body)
{
    uint slot = free_slot(world, SHOTS, PELLETS, world.game.pellet_cursor);
    if (slot == NO_SLOT) world.game.refused_pellets += 1;
    else place(world, slot, body);
    return slot;
}

// A hostile of a kind, and with it the segments of its chain if it heads one.
// A chain takes a run of slots with its head in the last, so the head is
// drawn over its body; and a ring of trail. It needs the whole run free, and
// takes none of it otherwise: its head's slot, or NO_SLOT.
uint spawn_hostile(World* world, uint kind, float2 at, float angle, uint seed)
{
    Game* game = world.game;
    Kind made = world.tables.kinds[kind];
    uint run = made.links + 1, latest = ((game.tick & 1) ^ 1) * BODIES;
    uint starts = HOSTILES - run + 1, base = NO_SLOT;
    for (uint tried = 0; tried < starts && base == NO_SLOT; ++tried)
    {
        uint from = (game.hostile_cursor + tried) % starts;
        bool room = true;
        for (uint each = 0; each < run && room; ++each) room = world.bodies[latest + HOSTILE_FIRST + from + each].kind == 0;
        if (room) base = from;
    }
    if (base == NO_SLOT) return NO_SLOT;
    game.hostile_cursor = (base + run) % starts;
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
    return head;
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
            game.runs += 1;
            new_game(game);
            for (uint body = 0; body < 2 * BODIES; ++body) world.bodies[body].kind = 0;
            for (uint cell = 0; cell < REQUESTS; ++cell) world.queue[cell].kind = 0;
            for (uint word = 0; word < HOSTILES / 32; ++word) world.asking[word] = 0;
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
    if (playing && !frozen)
    {
        // The dash, on the third button: a burst the way the ship is going,
        // or ahead if it is going nowhere, paid for in charge. Hostile shots
        // pass through the ship while it lasts and a moment after; bodies
        // and bursts do not.
        if (first && (root.pressed & BUTTON_THIRD) != 0)
        {
            if (game.charge >= DASH_COST && tick >= game.slip_until)
            {
                game.charge -= DASH_COST;
                game.dash_tick = tick + 1;
                game.slip_until = tick + DASH_TICKS + SLIP_TICKS;
                game.dash_way = dot(root.move, root.move) > 0.0 ? normalize(root.move) : float2(1.0, 0.0);
                game.dashes += 1;
                trigger(SOUND_DASH, ship.x);
            }
            else
            {
                game.empties += 1;
                trigger(SOUND_EMPTY, ship.x);
            }
        }
        bool dashing = game.dash_tick != 0 && tick + 1 - game.dash_tick < DASH_TICKS;
        float2 step = dashing ? game.dash_way * (DASH_SPEED * TICK_SECONDS) : root.move * (SHIP_SPEED * TICK_SECONDS);
        ship = clamp(ship + step, float2(80.0, 60.0), float2(PLAYFIELD_WIDTH - 60.0, PLAYFIELD_HEIGHT - 60.0));
        if (dashing) emit(world, STYLE_SPARK, ship, -game.dash_way, float2(0.0, 0.0), 3, tick * 5 + 1, tick + 1);
    }
    game.ship = ship;

    // Charge is earned: by kills and by hostile shots that pass close.
    uint grazed = game.grazes - game.grazes_seen;
    game.grazes_seen = game.grazes;
    game.charge = min(game.charge + KILL_CHARGE * float(game.earned) + GRAZE_CHARGE * float(grazed), 1.0);
    game.earned = 0;

    // The ship lays a trail as a chain's head does: at first the companion
    // is simply where the ship was.
    Body lead = new_body(world.tables, 0, ship, 0.0, 0, tick);
    lead.link = 1;
    lead.laid = game.ship_laid;
    lead.carried = game.ship_carried;
    lay_trail(lead, game.ship_before, world.ship_trail);
    game.ship_laid = lead.laid;
    game.ship_carried = lead.carried;

    // What last tick did to the ship. A hurt costs a life and some rank, and
    // buys a while in which nothing more can hurt.
    bool hit = playing && game.ship_hits != 0 && (game.hurt_tick == 0 || tick + 1 - game.hurt_tick >= GRACE_TICKS);
    if (hit && game.shield != 0)
    {
        // The shield takes it: no life, no rank, no stop. The grace is the same.
        hit = false;
        game.shield -= 1;
        game.blocked += 1;
        game.hurt_tick = tick + 1;
        trigger(SOUND_BLOCK, ship.x);
        emit(world, STYLE_SPARK, ship, float2(1.0, 0.0), float2(0.0, 0.0), 64, tick, tick + 1);
    }
    if (hit)
    {
        game.hurts += 1;
        game.hurt_tick = tick + 1;
        game.life_tick = tick + 1;
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

    // The bonuses taken since last tick. A harder game pays more: rank adds
    // up to half again to how long one lasts.
    for (uint bonus = 0; bonus < BONUSES; ++bonus)
    {
        uint count = game.collected[bonus];
        if (count == 0) continue;
        game.collected[bonus] = 0;
        game.taken[bonus] += count;
        game.got[bonus] = tick + 1;
        game.charge = min(game.charge + BONUS_CHARGE * float(count), 1.0);
        if (bonus == BONUS_SHIELD) game.shield = min(game.shield + count, 3u);
        else if (bonus == BONUS_NOVA)
        {
            // Everything that can be hurt is, at once. The director is alone
            // here, so it may write what the shots otherwise add to.
            for (uint slot = HOSTILE_FIRST; slot < HOSTILE_FIRST + HOSTILES; ++slot)
            {
                uint kind = world.bodies[(tick & 1) * BODIES + slot].kind;
                if (kind != 0 && world.tables.kinds[kind].health > 0.0) world.damage[slot] += 3;
            }
            game.nova_tick = tick + 1;
            emit(world, STYLE_BURST, ship, float2(1.0, 0.0), float2(0.0, 0.0), 128, tick + 3, tick + 1);
            trigger(SOUND_BURST, ship.x);
        }
        else game.until[bonus] = max(game.until[bonus], tick) + uint(float(BONUS_TICKS) * (1.0 + 0.5 * game.rank));
    }

    // A scripted run's second game is given one of each, in front of the
    // ship, and then something to see them work on: a drone for the nova, and
    // a rammer for the shield.
    if ((root.flags & ROOT_SCRIPTED) != 0 && game.runs == 1 && !frozen)
    {
        static const uint gifts[BONUSES] = { BONUS_SHIELD, BONUS_RAPID, BONUS_SPREAD, BONUS_DOUBLE, BONUS_NOVA };
        static const uint due[BONUSES] = { 48, 148, 248, 348, 480 };
        uint since = tick - game.began;
        for (uint gift = 0; gift < BONUSES; ++gift)
            if (since == due[gift]) spawn_hostile(world, KIND_BONUS_RAPID + gifts[gift], ship + float2(150.0, 0.0), 3.14159265, 0);
        if (since == 440) spawn_hostile(world, KIND_DRONE, float2(1500.0, 760.0), 3.14159265, 0);
        if (since == 700) spawn_hostile(world, KIND_RAMMER, float2(PLAYFIELD_WIDTH + 120.0, ship.y), 3.14159265, 0);
        // And the dragon, when it has held the level long enough, is struck
        // dead by the script: what is checked is that the level then moves on.
        if (since == 4400 && game.probe != 0) world.damage[game.probe - 1] += 1000;
        // And, once the worm's head has brought the companion, its two
        // promotions, with a drone for its gun and a pellet for its guard.
        if (since == 1440 || since == 1700) game.promoted += 1;
        if (since == 1440) spawn_hostile(world, KIND_DRONE, float2(1300.0, 200.0), 3.14159265, 0);
        if (since == 1460)
        {
            put_pellet(world, new_body(world.tables, KIND_PELLET, float2(-100.0, 420.0), 0.0, 0, game.tick));
        }
    }

    // A scripted run's third game has no squads: a bare stage, on which the
    // script sets down what it wants seen. A shot to dash through; a shot to
    // pass close; and three divers, each hurt to half as soon as it is there,
    // the third struck dead while it is still fixing on the ship, which does
    // not save the ship from it.
    bool staged = (root.flags & ROOT_SCRIPTED) != 0 && game.runs >= 2;
    if (staged && !frozen)
    {
        uint since = tick - game.began;
        if (since == 80 || since == 160)
        {
            bool through = since == 80;
            put_pellet(world, new_body(world.tables, KIND_PELLET,
                ship + (through ? float2(0.0, -150.0) : float2(400.0, -85.0)), through ? 1.5707963 : 3.14159265, 0, game.tick));
        }
        if (since == 320 || since == 760 || since == 1200) game.raider = spawn_hostile(world, KIND_DIVER, float2(1500.0, 620.0), 3.14159265, 0) + 1;
        if ((since == 336 || since == 776 || since == 1216) && game.raider != 0) world.damage[game.raider - 1] += 3;
        if (since == 1316 && game.raider != 0) world.damage[game.raider - 1] += 100;
        // A worm; its head struck dead; and in the very next tick something
        // else set down in the head's own slot. The segments are to die of
        // their head's death, and not take the newcomer for it.
        if (since == 1740) spawn_hostile(world, KIND_WORM, float2(1500.0, 860.0), 3.14159265, 0);
        if (since == 1760 && game.probe != 0) world.damage[game.probe - 1] += 1000;
        if (since == 1761 && game.probe != 0) place(world, game.probe - 1, new_body(world.tables, KIND_TARGET, float2(1700.0, 200.0), 0.0, 0, game.tick));
        // A flood: four hundred hostile shots, where there is room for 384;
        // then four hundred drones, where there is room for fewer. Then five
        // places side by side are emptied and a worm asked for: it needs
        // ten, and is refused whole. Then the five are asked back, with five
        // more than there is room for. What there is room for is made, the
        // rest is refused and counted, and nothing that was there is
        // written over.
        if (since == 1850)
            for (uint each = 0; each < 400; ++each)
                put_pellet(world, new_body(world.tables, KIND_PELLET, float2(900.0 + 8.0 * float(each % 40), 100.0 + 30.0 * float(each / 40)), 0.0, 0, game.tick));
        if (since == 1860)
        {
            for (uint each = 0; each < 400; ++each)
                if (spawn_hostile(world, KIND_DRONE, float2(1000.0 + 20.0 * float(each % 40), 150.0 + 60.0 * float(each / 40)), 3.14159265, each + 1) == NO_SLOT) game.refused_hostiles += 1;
            uint latest = ((game.tick & 1) ^ 1) * BODIES + HOSTILE_FIRST + 100, kept[5];
            for (uint each = 0; each < 5; ++each)
            {
                kept[each] = world.bodies[latest + each].seed;
                world.bodies[latest + each].kind = 0;
            }
            if (spawn_hostile(world, KIND_WORM, float2(1500.0, 300.0), 3.14159265, 0) == NO_SLOT) game.refused_hostiles += 1;
            for (uint each = 0; each < 10; ++each)
                if (spawn_hostile(world, KIND_DRONE, float2(1000.0 + 20.0 * float(each), 760.0), 3.14159265, kept[each % 5]) == NO_SLOT) game.refused_hostiles += 1;
        }
    }

    // The companion. It arrives when a chain's head is killed, from where
    // that happened, and each head after makes it more: first it is where
    // you were; then it acts for itself, firing at what is nearest and
    // turning its guard to what is coming; then its gun takes your aim.
    if (game.promoted != 0)
    {
        if (game.companion == 0)
        {
            game.mate = game.promoted_at;
            game.mate_before = game.mate;
        }
        game.companion = min(game.companion + game.promoted, 3u);
        game.promoted = 0;
        trigger(SOUND_BONUS, game.mate.x);
        emit(world, STYLE_SPARK, game.mate, float2(1.0, 0.0), float2(0.0, 0.0), 48, tick + 11, tick + 1);
    }
    bool mate_fires = false;
    if (game.companion != 0 && playing && !frozen)
    {
        float2 place_at, toward;
        trail_at(lead, world.ship_trail, MATE_BACK, place_at, toward);
        game.mate_before = game.mate;
        game.mate += (place_at - game.mate) * 0.2;
        uint latest = (tick & 1) * BODIES;
        float gun = 0.0;
        if (game.companion == 2 && game.near_hostile != NOBODY)
        {
            // What was nearest, of what can be hit and is on the playfield:
            // every hostile said how near it was, and the least was kept.
            float2 apart = world.bodies[latest + HOSTILE_FIRST + (game.near_hostile & 1023)].position - game.mate;
            gun = atan2(apart.y, apart.x);
            mate_fires = true;
        }
        if (game.companion == 3)
        {
            float2 apart = root.aim - game.mate;
            gun = atan2(apart.y, apart.x);
            mate_fires = (root.held & BUTTON_FIRE) != 0;
        }
        game.mate_gun = turn_to(game.mate_gun + turn_to(gun - game.mate_gun) * 0.25);
        // Its guard faces the nearest hostile shot within 600, or behind its gun.
        float guard = game.mate_gun + 3.14159265;
        if ((game.near_pellet >> 10) < 600 * 256)
        {
            float2 apart = world.bodies[latest + SHOTS + (game.near_pellet & 1023)].position - game.mate;
            guard = atan2(apart.y, apart.x);
        }
        game.mate_guard = turn_to(game.mate_guard + turn_to(guard - game.mate_guard) * 0.3);
        if (game.mate_cooldown > 0) game.mate_cooldown -= 1;
        if (mate_fires && game.mate_cooldown == 0)
        {
            put_shot(world, new_body(world.tables, KIND_SHOT, game.mate + heading(game.mate_gun) * 30.0, game.mate_gun, MATE_SHOT, game.tick));
            game.mate_cooldown = MATE_TICKS;
            game.mate_fired += 1;
        }
    }

    // What this tick's passes find nearest the companion is for the next.
    game.near_hostile = NOBODY;
    game.near_pellet = NOBODY;

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
    if (!frozen && !staged)
    {
        Wave next = world.tables.waves[game.wave % world.tables.wave_count];
        // After a squad that holds the level, nothing comes while anything is
        // alive; and what comes next counts its time from when the last died.
        if (game.members == 0 && game.wave != 0 && world.tables.waves[(game.wave - 1) % world.tables.wave_count].holds != 0 && game.alive != 0) game.wave_tick = tick;
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
        // One of a squad that there is no room for waits until there is.
        if (game.members != 0 && tick >= game.member_tick
            && spawn_hostile(world, next.kind, float2(PLAYFIELD_WIDTH + 100.0, next.y + next.spread * float(game.member % max(next.count, 1u))), 3.14159265, game.member) != NO_SLOT)
        {
            game.member += 1;
            game.member_tick = tick + next.stagger;
            game.members -= 1;
            if (game.members == 0)
            {
                game.wave += 1;
                // The table gone through, the place changes: the backdrop takes its next inks.
                if (game.wave % world.tables.wave_count == 0)
                {
                    game.stage += 1;
                    game.stage_tick = tick;
                }
            }
        }
    }

    // What last tick's bodies asked for: only the director makes a body. A
    // hostile asks in cells that are its own, so nothing is contended for and
    // nothing is lost, and raises its bit; the director reads the cells of
    // those whose bit is up, in order, so what is made and where does not
    // depend on which thread came first.
    for (uint word = 0; word < HOSTILES / 32; ++word)
    {
        uint asking = world.asking[word];
        if (asking == 0) continue;
        world.asking[word] = 0;
        for (uint cell = word * 32 * REQUEST_CELLS; asking != 0; ++cell)
        {
            // The cells of the lowest bit still up; then that bit comes down.
            uint first = (word * 32 + firstbitlow(asking)) * REQUEST_CELLS;
            if (cell < first) cell = first;
            if (cell == first + REQUEST_CELLS - 1) asking &= asking - 1;
            if (world.queue[cell].kind == 0) continue;
            Request request = world.queue[cell];
            world.queue[cell].kind = 0;
            game.requested += 1;
        // A bonus someone dropped goes among the hostiles, where the ship can touch it.
        if ((world.tables.kinds[request.kind].flags & KIND_PICKUP) != 0)
        {
            if (spawn_hostile(world, request.kind, request.at, 3.14159265, request.seed) == NO_SLOT) game.refused_hostiles += 1;
            continue;
        }
        // What was fired at a mark takes the mark with it.
        Body fired = new_body(world.tables, request.kind, request.at, request.angle, request.seed, game.tick);
        fired.mark = request.mark;
        fired.marking = request.marking;
        uint into = put_pellet(world, fired);
        if (into == NO_SLOT) continue;
        if (request.kind == KIND_HEAVY) game.heavy = into + 1;
        trigger(request.kind == KIND_HEAVY ? SOUND_HEAVY : SOUND_SHOT, request.at.x);
        }
    }

    // The player's own.
    if (game.cooldown > 0) game.cooldown -= 1;
    playing = playing && !frozen;
    if (playing && (root.held & BUTTON_FIRE) != 0 && game.cooldown == 0)
    {
        // RAPID halves the wait; SPREAD makes each shot three.
        uint volley = game.until[BONUS_SPREAD] > tick ? 3 : 1, away = 0;
        for (uint each = 0; each < volley; ++each)
            if (put_shot(world, new_body(world.tables, KIND_SHOT, ship + float2(60.0, 0.0), (float(each) - float(volley / 2)) * 0.16, 0, game.tick))) ++away;
        game.cooldown = game.until[BONUS_RAPID] > tick ? SHOT_TICKS / 2 : SHOT_TICKS;
        game.fired += away;
        trigger(SOUND_SHOT, ship.x);
        // At first the companion fires when you do, and the way you do.
        if (game.companion == 1)
        {
            if (put_shot(world, new_body(world.tables, KIND_SHOT, game.mate + float2(30.0, 0.0), 0.0, MATE_SHOT, game.tick))) game.mate_fired += 1;
        }
    }
    if (playing && first && (root.pressed & BUTTON_SECOND) != 0)
    {
        // A pair of missiles is paid for; with too little charge there is a click and nothing.
        if (game.charge >= MISSILE_COST)
        {
            game.charge -= MISSILE_COST;
            for (uint side = 0; side < 2; ++side)
                if (put_shot(world, new_body(world.tables, KIND_MISSILE, ship + float2(30.0, 0.0), 0.0, side, game.tick))) game.fired += 1;
            trigger(SOUND_LAUNCH, ship.x);
        }
        else
        {
            game.empties += 1;
            trigger(SOUND_EMPTY, ship.x);
        }
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
            // The higher rank is, the quicker everything hostile goes about its moves.
            scene.tempo = kind.health > 0.0 ? 1.0 + 0.5 * game.rank : 1.0;
            float2 was = body.position;
            uint fires, fixing = body.marking;
            float fan;
            alive = advance_body(body, world.tables, scene, fires, fan);
            if (body.link != 0) lay_trail(body, was, world.trails);
            // A fix that has just locked is heard to.
            if (fixing == MARK_FOCUS && body.marking == MARK_LOCKED && game.state == STATE_PLAY) trigger(SOUND_LOCK, body.mark.x);
            if (fires != 0)
            {
                // As many as it asked for, at the player, each a little to one
                // side or the other; or, its mark locked, at the mark, which
                // what it fires then carries and it no longer shows.
                bool marked = body.marking == MARK_LOCKED;
                if (game.state == STATE_PLAY && slot >= HOSTILE_FIRST)
                {
                    // Its own cells: the first four are for what its program fires.
                    uint count = min(fires >> FIRE_COUNT, REQUEST_CELLS - 2), place_in = (slot - HOSTILE_FIRST) * REQUEST_CELLS;
                    float2 toward = (marked ? body.mark : game.ship) - body.position;
                    for (uint each = 0; each < count; ++each)
                    {
                        Request request;
                        request.kind = fires & ((1u << FIRE_COUNT) - 1);
                        request.at = body.position;
                        request.angle = atan2(toward.y, toward.x) + (unit(hash(slot * 31 + game.tick * 7 + each)) - 0.5) * fan;
                        request.seed = slot;
                        request.mark = body.mark;
                        request.marking = marked ? MARK_LOCKED : 0;
                        world.queue[place_in + each] = request;
                    }
                    if (count != 0) InterlockedOr(world.asking[(slot - HOSTILE_FIRST) >> 5], 1u << ((slot - HOSTILE_FIRST) & 31));
                }
                body.marking = 0;
            }
            // A program that ends in a burst: what is within its reach of
            // where it ended is hurt. A dash does not slip a burst.
            if (!alive && fan > 0.0)
            {
                emit(world, STYLE_BLAST, body.position, float2(1.0, 0.0), float2(0.0, 0.0), 160, slot, game.tick);
                trigger(SOUND_BLAST, body.position.x);
                InterlockedAdd(world.game.blasts, 1);
                world.game.blast_at = body.position;
                float2 apart = game.ship - body.position;
                if (game.state == STATE_PLAY && dot(apart, apart) < fan * fan)
                {
                    InterlockedAdd(world.game.ship_hits, 1);
                    InterlockedAdd(world.game.blast_hits, 1);
                }
            }
            // Something in the second part of its program is on its last legs, and looks it.
            if (alive && kind.wounded_first != 0 && body.move >= kind.wounded_first && ((game.tick + slot) & 7) == 0)
                emit(world, STYLE_EMBER, body.position, -heading(body.angle), float2(0.0, 0.0), 1, slot, game.tick);
        }
        if (body.position.x < -260.0 || body.position.x > PLAYFIELD_WIDTH + 260.0 || body.position.y < -260.0 || body.position.y > PLAYFIELD_HEIGHT + 260.0)
        {
            // What follows a head leaves with it, not before.
            if ((kind.flags & KIND_FOLLOWS) == 0)
            {
                alive = false;
                // The companion's misses are its own: the player's accuracy is the player's.
                if (slot < SHOTS && body.seed != MATE_SHOT) InterlockedAdd(world.game.escaped, 1);
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
        if (game.companion != 0) InterlockedMin(world.game.near_pellet, near_key(to, game.mate, slot - SHOTS));
        // The companion's guard stops what passes close on the side it faces.
        if (game.companion >= 2)
        {
            float2 step = to - from, back = game.mate - from;
            float along = dot(step, step) > 0.0 ? saturate(dot(back, step) / dot(step, step)) : 0.0;
            float2 off = from + step * along - game.mate;
            if (dot(off, off) < MATE_REACH * MATE_REACH && dot(off, heading(game.mate_guard)) > 0.5 * length(off))
            {
                InterlockedAdd(world.game.guarded, 1);
                trigger(SOUND_BLOCK, game.mate.x);
                emit(world, STYLE_SPARK, from + step * along, -heading(shot.angle), float2(0.0, 0.0), SPARKS * 2, slot, game.tick);
                world.bodies[now + slot].kind = 0;
                return;
            }
        }
        // What is thrown over the field touches nothing on its way: its harm is where it lands.
        if ((shot.flags & KIND_LOBBED) != 0) return;
        Picture frame = pictures.frames[FRAME_SHIP];
        float along = sweep(pictures, frame, into_picture(ship_pose(game.ship_before), frame, from), into_picture(ship_pose(game.ship), frame, to));
        if (along < 0.0)
        {
            // A near miss: it passed close to the ship's middle and did not
            // strike. It pays once for a shot, and the shot flashes for it. (A
            // shot the ship is dashing through is not near: it is through.)
            float2 step = to - from, back = game.ship - from;
            float closest = dot(step, step) > 0.0 ? saturate(dot(back, step) / dot(step, step)) : 0.0;
            float2 off = from + step * closest - game.ship;
            if (shot.struck == 0 && (shot.flags & BODY_SLIPPED) == 0 && game.tick >= game.slip_until && dot(off, off) < GRAZE_REACH * GRAZE_REACH)
            {
                world.bodies[now + slot].struck = game.tick;
                InterlockedAdd(world.game.grazes, 1);
                trigger(SOUND_GRAZE, game.ship.x);
                emit(world, STYLE_SPARK, from + step * closest, -heading(shot.angle), float2(0.0, 0.0), 2, slot, game.tick);
            }
            return;
        }
        // In a dash, and a moment after, it passes through. Counted once.
        if (game.tick < game.slip_until)
        {
            if ((shot.flags & BODY_SLIPPED) == 0)
            {
                world.bodies[now + slot].flags = shot.flags | BODY_SLIPPED;
                InterlockedAdd(world.game.slipped, 1);
            }
            return;
        }
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
    if (shot.seed == MATE_SHOT && shot.kind == KIND_SHOT) InterlockedAdd(world.game.mate_struck, 1);
    else InterlockedAdd(world.game.struck, 1);
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
    if ((kind.flags & KIND_PICKUP) != 0)
    {
        // A bonus is taken by coming near it: nobody should miss one by a texel.
        float2 apart = body.position - game.ship;
        if (game.state == STATE_PLAY && dot(apart, apart) < 72.0 * 72.0)
        {
            InterlockedAdd(world.game.collected[body.kind - KIND_BONUS_RAPID], 1);
            trigger(SOUND_BONUS, body.position.x);
            emit(world, STYLE_SPARK, body.position, float2(1.0, 0.0), float2(0.0, 0.0), 24, slot, game.tick);
            world.bodies[at].kind = 0;
        }
        return;
    }
    if (taken != 0)
    {
        body.health -= float(taken);
        body.struck = game.tick;
        // Hurt enough and still alive, a kind that has a second part to its
        // program leaves whatever it was doing for that, from where it is.
        if (body.health > 0.0 && kind.wounded_first != 0 && body.health <= kind.wounded && body.move < kind.wounded_first)
        {
            body.move = kind.wounded_first;
            body.elapsed = 0;
            body.origin = body.position;
            body.from = body.angle;
            body.from_speed = body.speed;
            trigger(SOUND_FOCUS, body.position.x);
            emit(world, STYLE_EMBER, body.position, float2(1.0, 0.0), float2(0.0, 0.0), 12, slot, game.tick);
        }
        if (body.health <= 0.0)
        {
            emit(world, STYLE_BURST, body.position, float2(1.0, 0.0), heading(body.angle) * (body.speed * 0.3), DEBRIS, slot, game.tick);
            uint worth = uint(float(kind.worth) * (1.0 + game.rank) + 0.5);
            InterlockedAdd(world.game.score, game.until[BONUS_DOUBLE] > game.tick ? 2 * worth : worth);
            InterlockedAdd(world.game.kills, 1);
            InterlockedAdd(world.game.earned, 1);
            trigger(SOUND_BURST, body.position.x);
            // Killing is not an answer to what a thing was about to do. A
            // kind with a second part to its program that dies before it has
            // fired what that part fires, fires it as it dies: at its mark
            // if it has one, and at where the ship is if it had not got that
            // far. The kill chooses when the lock falls, not whether.
            if (kind.wounded_first != 0 && game.state == STATE_PLAY)
            {
                uint from = max(body.move, kind.wounded_first);
                for (uint ahead = from; ahead < from + 8 && ahead < world.tables.move_count; ++ahead)
                {
                    Move still = world.tables.moves[ahead];
                    if (still.action == MOVE_HOLD && still.ticks == 0) break;
                    if (still.action != MOVE_FIRE) continue;
                    // Its fifth cell is for what it fires as it dies.
                    uint place_in = (slot - HOSTILE_FIRST) * REQUEST_CELLS + REQUEST_CELLS - 2;
                    {
                        float2 mark = body.marking != 0 ? body.mark : game.ship;
                        float2 toward = mark - body.position;
                        Request request;
                        request.kind = still.target;
                        request.at = body.position;
                        request.angle = atan2(toward.y, toward.x);
                        request.seed = slot;
                        request.mark = mark;
                        request.marking = MARK_LOCKED;
                        world.queue[place_in] = request;
                        InterlockedOr(world.asking[(slot - HOSTILE_FIRST) >> 5], 1u << ((slot - HOSTILE_FIRST) & 31));
                        trigger(SOUND_LOCK, mark.x);
                    }
                    break;
                }
            }
            // The head of a chain, killed, is what brings the companion.
            if (kind.links != 0)
            {
                world.game.promoted_at = body.position;
                InterlockedAdd(world.game.promoted, 1);
            }
            // Bonuses galore, and more the harder it is: a kill leaves one
            // more often the higher rank is. The director makes it.
            uint roll = hash(slot * 977 + game.tick);
            if (kind.worth != 0 && unit(roll) < 0.22 + 0.4 * game.rank)
            {
                // Its sixth cell is for what it leaves behind.
                uint place_in = (slot - HOSTILE_FIRST) * REQUEST_CELLS + REQUEST_CELLS - 1;
                {
                    Request request;
                    request.kind = KIND_BONUS_RAPID + (roll >> 8) % BONUSES;
                    request.at = body.position;
                    request.angle = 3.14159265;
                    request.seed = slot;
                    request.mark = body.position;
                    request.marking = 0;
                    world.queue[place_in] = request;
                    InterlockedOr(world.asking[(slot - HOSTILE_FIRST) >> 5], 1u << ((slot - HOSTILE_FIRST) & 31));
                }
            }
            body.kind = 0;
        }
        world.bodies[at] = body;
        if (body.kind == 0) return;
    }
    InterlockedAdd(world.game.alive, 1);
    if (game.companion == 2 && kind.health > 0.0 && body.position.x >= 0.0 && body.position.x <= PLAYFIELD_WIDTH && body.position.y >= 0.0 && body.position.y <= PLAYFIELD_HEIGHT)
        InterlockedMin(world.game.near_hostile, near_key(body.position, game.mate, id.x));
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
    // What follows walks pools, on one thread: it is what a scripted run is
    // held to, and only a scripted run pays for it.
    bool scripted = (root.flags & ROOT_SCRIPTED) != 0;
    uint flying = 0, pellets = 0;
    for (uint slot = 0; scripted && slot < SHOTS + PELLETS; ++slot)
    {
        Body shot = world.bodies[now + slot];
        if (shot.kind == 0) continue;
        if (slot >= SHOTS) ++pellets;
        else if (!(shot.seed == MATE_SHOT && shot.kind == KIND_SHOT)) ++flying;
    }
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
    // A sum over everything that is simulated: two runs of one script are to
    // agree on it, whatever order their threads ran in.
    uint sum = hash(game.score ^ hash(game.tick ^ hash(asuint(game.rank) ^ hash(asuint(game.ship.x) ^ hash(asuint(game.ship.y) ^ hash(asuint(game.mate.x) ^ asuint(game.mate.y)))))));
    for (uint slot = 0; scripted && slot < BODIES; ++slot)
    {
        Body body = world.bodies[now + slot];
        if (body.kind == 0) continue;
        sum += hash(slot ^ hash(body.kind ^ hash(asuint(body.position.x) ^ hash(asuint(body.position.y) ^ hash(asuint(body.health) ^ hash(body.move * 65536 + body.elapsed))))));
    }
    events.debug[3] = sum;
    // On the stage, where no chain is being watched: how full the hostiles'
    // pool is and with what, and what has been refused.
    if ((root.flags & ROOT_SCRIPTED) != 0 && game.runs >= 2)
    {
        uint occupied = 0, drones = 0, seeds = 0, worms = 0;
        for (uint slot = HOSTILE_FIRST; slot < HOSTILE_FIRST + HOSTILES; ++slot)
        {
            Body body = world.bodies[now + slot];
            if (body.kind == 0) continue;
            ++occupied;
            if (body.kind == KIND_DRONE) { ++drones; seeds += body.seed; }
            if (body.kind == KIND_WORM || body.kind == KIND_WORM_BODY || body.kind == KIND_WORM_TAIL) ++worms;
        }
        events.reserved[12] = occupied;
        events.reserved[13] = min(game.refused_shots, 255u) | (min(game.refused_pellets, 255u) << 8) | (min(game.refused_hostiles, 65535u) << 16);
        events.reserved[14] = seeds;
        events.reserved[15] = worms | (drones << 16);
    }
    events.report[0] = game.shown;
    events.report[1] = game.stopped;
    for (uint bonus = 0; bonus < BONUSES; ++bonus) events.report[2 + bonus] = game.taken[bonus];
    events.report[7] = game.shield;
    events.report[8] = game.blocked;
    events.report[9] = game.companion;
    events.report[10] = asuint(game.mate.x);
    events.report[11] = asuint(game.mate.y);
    events.report[12] = asuint(game.mate_gun);
    events.report[13] = asuint(game.mate_guard);
    events.report[14] = game.mate_fired;
    events.report[15] = game.mate_struck;
    events.report[16] = game.guarded;
    events.report[17] = game.stage;
    events.report[18] = game.music_faults;
    events.report[19] = asuint(game.charge);
    events.report[20] = (game.dashes & 255) | ((game.slipped & 255) << 8) | ((game.grazes & 255) << 16) | ((game.blasts & 255) << 24);
    events.report[21] = (game.blast_hits & 255) | ((game.empties & 255) << 8);
    events.report[22] = asuint(game.ship.x);
    events.report[23] = asuint(game.ship.y);
    // The body the script last set down, and the last heavy shot: whether
    // each is there, what is marked, and where everything is.
    uint seen = 0;
    float2 mark = float2(0.0, 0.0), raider_at = float2(0.0, 0.0), heavy_at = game.blast_at;
    float fade = 0.0;
    if (game.raider != 0)
    {
        Body raider = world.bodies[now + game.raider - 1];
        if (raider.kind == KIND_DIVER)
        {
            seen |= raider.marking | 256 | (raider.move >= world.tables.kinds[KIND_DIVER].wounded_first ? 512 : 0);
            raider_at = raider.position;
            if (raider.marking != 0) mark = raider.mark;
        }
    }
    if (game.heavy != 0)
    {
        Body heavy = world.bodies[now + game.heavy - 1];
        if (heavy.kind == KIND_HEAVY)
        {
            seen |= 1024;
            heavy_at = heavy.position;
            mark = heavy.mark;
            fade = mark_fade(heavy);
        }
    }
    events.report[24] = seen;
    events.report[25] = asuint(mark.x);
    events.report[26] = asuint(mark.y);
    events.report[27] = asuint(raider_at.x);
    events.report[28] = asuint(raider_at.y);
    events.report[29] = asuint(heavy_at.x);
    events.report[30] = asuint(heavy_at.y);
    events.report[31] = asuint(fade);
    events.multiplier = game.until[BONUS_DOUBLE] > game.tick ? 2 : 1;
    events.shield = float(game.shield);
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
        sprite.flags = shown.flags | (body.struck != 0 && since < FLASH_TICKS ? (255 - since * 255 / FLASH_TICKS) << SPRITE_FLASH : 0);
    }
    else if ((index -= BODIES) < SHIP_PARTS)
    {
        float2 ship = lerp(game.ship_before, game.ship, root.blend) + shake;
        bool there = game.state == STATE_PLAY;
        // In its grace the ship blinks.
        uint since = game.tick + 1 - game.hurt_tick;
        if (game.hurt_tick != 0 && since < GRACE_TICKS && (since / 8) % 2 == 0) there = false;
        // In a dash, and while shots still pass through it, the ship is half there.
        bool dashing = game.dash_tick != 0 && game.tick + 1 - game.dash_tick < DASH_TICKS, slipping = game.tick < game.slip_until;
        if (index == 0)
        {
            sprite.position = ship - float2(78.0, 0.0);
            sprite.axis = float2(!there ? 0.0 : dashing ? -1.8 : dot(root.move, root.move) > 0.0 ? -0.7 : 0.0, 0.0);
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
            if (slipping) sprite.flags |= 120 << SPRITE_DIM;
        }
        else if (index == 3)
        {
            // The shield, turning round the ship while there is any of it.
            sprite.position = ship;
            sprite.axis = heading(float(game.tick) * 0.02) * (there && game.shield != 0 ? 1.3 + 0.1 * float(game.shield) : 0.0);
            sprite.frame = FRAME_SHIELD;
        }
        else if (index == 4)
        {
            sprite.position = root.aim;
            sprite.axis = float2(1.0, 0.0);
            sprite.frame = FRAME_CROSSHAIR;
        }
        else
        {
            // The companion: a ball that keeps its light as anything does, its
            // gun, its guard, and between it and the ship a thread of light
            // that is the two of them being one.
            float2 mate = lerp(game.mate_before, game.mate, root.blend) + shake;
            bool here = there && game.companion != 0;
            if (index == 5)
            {
                sprite.position = mate;
                sprite.axis = float2(here ? 1.1 : 0.0, 0.0);
                sprite.frame = FRAME_ORB;
            }
            else if (index == 6)
            {
                sprite.position = mate + heading(game.mate_gun) * 36.0;
                sprite.axis = heading(game.mate_gun) * (here ? 0.9 : 0.0);
                sprite.frame = FRAME_BOLT;
            }
            else if (index == 7)
            {
                sprite.position = mate;
                sprite.axis = heading(game.mate_guard) * (here && game.companion >= 2 ? 1.0 : 0.0);
                sprite.frame = FRAME_GUARD;
            }
            else
            {
                float along = (float(index - 8) + 0.5) / float(TETHER);
                float2 across = mate - ship;
                float wave = sin(along * 3.14159265) * sin(root.time * 9.0 + along * 11.0);
                sprite.position = ship + across * along + normalize(float2(-across.y, across.x) + float2(1e-4, 0.0)) * (wave * 14.0);
                sprite.axis = float2(here ? 0.14 + 0.08 * abs(wave) : 0.0, 0.0);
            }
        }
    }
    else if ((index -= SHIP_PARTS) < MARKS)
    {
        // What a hostile, or the shot it loosed, means to strike. While it is
        // being fixed it is brackets that shake and close in on where the
        // target is; locked, it is crosshairs as wide as the strike will
        // reach, which fade as the shot comes: all there at its launch, gone
        // as it lands.
        uint now = game.tick & 1, slot = SHOTS + index;
        Body body = world.bodies[now * BODIES + slot], before = world.bodies[(now ^ 1) * BODIES + slot];
        if (body.kind != 0 && body.marking != 0 && game.state == STATE_PLAY)
        {
            if (before.kind != body.kind || before.born != body.born || before.marking == 0) before = body;
            float2 at = lerp(before.mark, body.mark, root.blend) + shake;
            if (body.marking == MARK_FOCUS)
            {
                float loose = 1.0 - float(body.elapsed) / float(max(body.span, 1u));
                uint shaken = hash(game.tick * 31 + slot);
                sprite.position = at + (float2(unit(shaken), unit(hash(shaken))) - 0.5) * (40.0 * loose + 6.0);
                sprite.axis = heading((unit(hash(shaken + 7)) - 0.5) * 0.6 * loose) * (1.0 + 0.9 * loose);
                sprite.frame = FRAME_FOCUS;
                sprite.flags = 7 << SPRITE_INK;
            }
            else
            {
                sprite.position = at;
                sprite.axis = float2(HEAVY_REACH / LOCK_RING, 0.0);
                sprite.frame = FRAME_LOCK;
                sprite.flags = (4 << SPRITE_INK) | (uint(255.0 * (1.0 - mark_fade(body))) << SPRITE_DIM);
            }
        }
    }
    else if ((index -= MARKS) < 8)
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
        uint since = game.tick + 1 - game.life_tick;
        bool lost = index == game.lives && game.life_tick != 0 && since < 60;
        sprite.position = float2(PLAYFIELD_WIDTH - 80.0 - 78.0 * index, 56.0);
        sprite.axis = float2(index < game.lives ? 0.6 : lost ? 0.6 * (1.0 - float(since) / 60.0) : 0.0, 0.0);
        sprite.frame = FRAME_SHIP;
        sprite.flags = (lost ? 4 : 1) << SPRITE_INK;
    }
    else if ((index -= 3) < 10)
    {
        // Rank, as ten pips: green, then gold, then red.
        bool lit = float(index) < game.rank * 10.0;
        sprite.position = float2(PLAYFIELD_WIDTH * 0.5 - 162.0 + 36.0 * index, 50.0);
        sprite.axis = float2(lit ? 0.55 : 0.18, 0.0);
        sprite.flags = (lit ? (index < 4 ? 3 : index < 7 ? 2 : 4) : 5) << SPRITE_INK;
    }
    else if ((index -= 10) < CHARGE_PIPS)
    {
        // Charge, as eight pips under rank's: what the missiles and the dash are paid from.
        bool lit = float(index) + 0.5 < game.charge * float(CHARGE_PIPS);
        sprite.position = float2(PLAYFIELD_WIDTH * 0.5 - 126.0 + 36.0 * index, 84.0);
        sprite.axis = float2(lit ? 0.45 : 0.16, 0.0);
        sprite.flags = (lit ? 6 : 5) << SPRITE_INK;
    }
    else
    {
        // The bonuses: a slot each along the bottom. One just taken jumps, each
        // in its own way; one in force is bright, with a pip for every eighth
        // of its time still to run, and blinks when that is nearly gone.
        index -= CHARGE_PIPS;
        uint bonus = index / 9, part = index % 9;
        static const uint jumps[BONUSES] = { EASE_OUT_BACK, EASE_OUT_ELASTIC, EASE_OUT_BOUNCE, EASE_OUT_EXPO, EASE_INOUT_BACK };
        uint since = game.tick + 1 - game.got[bonus];
        bool fresh = game.got[bonus] != 0 && since < 48;
        uint left = game.until[bonus] > game.tick ? game.until[bonus] - game.tick : 0;
        bool held = bonus == BONUS_SHIELD ? game.shield != 0 : bonus == BONUS_NOVA ? fresh : left != 0;
        float2 at = float2(80.0 + 104.0 * bonus, PLAYFIELD_HEIGHT - 64.0);
        if (part == 0)
        {
            float jump = fresh ? 1.0 - ease(jumps[bonus], float(since) / 48.0) : 0.0;
            bool blink = left != 0 && left < 240 && (game.tick / 10) % 2 == 0;
            sprite.position = at;
            sprite.axis = float2((held ? 1.0 : 0.55) * (1.0 + 1.2 * jump), 0.0);
            sprite.frame = FRAME_BONUS_RAPID + bonus;
            sprite.flags = (held && !blink ? 1 : 5) << SPRITE_INK;
        }
        else
        {
            uint lit = bonus == BONUS_SHIELD ? game.shield : min((left * 8 + BONUS_TICKS - 1) / BONUS_TICKS, 8u);
            sprite.position = at + float2(-31.5 + 9.0 * float(part - 1), -44.0);
            sprite.axis = float2(part - 1 < lit ? 0.24 : 0.0, 0.0);
            sprite.flags = 2 << SPRITE_INK;
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
    float flash = float((input.flags >> SPRITE_FLASH) & 255) * (1.0 / 255.0);
    color.rgb = lerp(color.rgb, float3(color.a, color.a, color.a), flash);
    // The HUD's pictures are white, and take an ink.
    static const float3 inks[8] = { float3(1.0, 1.0, 1.0), float3(1.0, 1.0, 1.0), float3(1.0, 0.78, 0.25), float3(0.35, 1.0, 0.45), float3(1.0, 0.25, 0.15), float3(0.2, 0.24, 0.32),
        float3(0.2, 0.55, 2.2), float3(1.0, 0.55, 0.12) };
    color.rgb *= inks[min((input.flags >> SPRITE_INK) & 15, 7u)];
    return color * (1.0 - float((input.flags >> SPRITE_DIM) & 255) * (1.0 / 255.0));
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
    nointerpolation float nova : COLOR2;
    nointerpolation float paused : COLOR3;
};

// The last thing drawn, over everything: being hurt reddens the edges of
// the picture for a moment, a run that is over dims all of it, and a pause
// dims it and puts its two bars in the middle.
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
    result.nova = game.nova_tick == 0 ? 0.0 : saturate(1.0 - float(game.tick + 1 - game.nova_tick) / 24.0);
    result.paused = (root.flags & ROOT_PAUSED) != 0 ? 1.0 : 0.0;
    // With nothing to show it covers nothing.
    result.position = float4(result.hurt + result.over + result.nova + result.paused > 0.0 ? result.at : float2(0.0, 0.0), 0.0, 1.0);
    return result;
}

[shader("fragment")]
float4 veil_fragment(VeilVertex input) : SV_Target0
{
    float edge = smoothstep(0.3, 1.25, length(input.at));
    float red = input.hurt * input.hurt * edge * 0.8;
    float dim = input.over * 0.45;
    // A nova is a flash of white light over everything: it adds.
    float white = input.nova * input.nova * 0.6;
    float4 veil = float4(red * 0.9 + white, red * 0.05 + white, red * 0.02 + white, saturate(red * 0.5 + dim));
    if (input.paused == 0.0) return veil;
    // Paused: darker than a run that is over, and the bars, with soft edges.
    float2 place = float2(abs(input.at.x) * float(PLAYFIELD_WIDTH) / float(PLAYFIELD_HEIGHT), abs(input.at.y));
    float bar = saturate((0.028 - abs(place.x - 0.062)) * 220.0) * saturate((0.15 - place.y) * 220.0);
    float shade = 0.55 * (1.0 - bar);
    return float4(veil.rgb * (1.0 - shade) + float3(0.82, 0.90, 1.0) * bar, saturate(veil.a + shade * (1.0 - veil.a) + bar));
}

struct BackdropVertex
{
    float4 position : SV_Position;
    float2 at : TEXCOORD0;                  // on the playfield
    nointerpolation float scroll : COLOR0;
    nointerpolation float fade : COLOR1;
    nointerpolation uint stage : COLOR2;
};

// The first thing drawn, under everything: the backdrop, where the level has
// come to between its last two ticks, and shaken with the rest when the
// ship is hurt.
[shader("vertex")]
BackdropVertex backdrop_vertex(uint vertex : SV_VulkanVertexID)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    Game game = *root.world.game;
    float2 corner = float2(corners[vertex] & 1, corners[vertex] >> 1);
    BackdropVertex result;
    result.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
    result.at = corner * float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) - shake_of(game) * 0.5;
    result.scroll = lerp(game.scroll_before, game.scroll, root.blend);
    result.fade = saturate(float(game.tick - game.stage_tick) / 480.0);
    result.stage = game.stage;
    return result;
}

[shader("fragment")]
float4 backdrop_fragment(BackdropVertex input) : SV_Target0
{
    return float4(backdrop(input.at, input.scroll, input.stage == 0 ? 0 : input.stage - 1, input.stage, input.fade), 1.0);
}
