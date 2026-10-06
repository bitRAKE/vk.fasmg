// Motion: a body, and one tick of the program its kind gives it. The moves
// are data, authored in tables.inc; this is all the code there is for them.
//
// The including file has included the shared header (pictures.slang does).
#include "myhits_tables.slang"
#include "ease.slang"

// A body, as the simulation knows it. There are two copies of every body, the
// last tick's and this one's: a pass reads the one and writes the other, and
// the picture stands between them.
struct Body
{
    float2 position;
    float2 origin;      // where it would be but for the move in hand; this is what coasts
    float angle;        // its heading, in radians; 0 is to the right
    float from;         // its heading when the move began
    float speed;        // along its heading, playfield units a second
    float from_speed;
    uint move;          // in the moves table
    uint elapsed;       // ticks into it
    uint kind;          // 0: nothing here
    uint picture;
    float scale;
    uint seed;          // odd: its moves are mirrored
    uint flags;
    uint born;          // the tick it was made in
    float health;       // hits it can still take
    uint struck;        // the tick it was last hit in, for the flash
};

// What a moving body may look at.
struct Scene
{
    float2 player;
    float2 crosshair;
    float drift;        // how far the level carried its riders this tick
};

float2 heading(float angle) { return float2(cos(angle), sin(angle)); }
float2 right_of(float2 ahead) { return float2(-ahead.y, ahead.x); }
// An angle as the shortest turn, -pi..pi.
float turn_to(float angle) { return angle - 6.2831853 * floor(angle / 6.2831853 + 0.5); }

Body new_body(Tables tables, uint kind, float2 at, float angle, uint seed, uint tick)
{
    Kind made = tables.kinds[kind];
    Body body;
    body.position = at;
    body.origin = at;
    body.angle = angle;
    body.from = angle;
    body.speed = 0.0;
    body.from_speed = 0.0;
    body.move = made.first;
    body.elapsed = 0;
    body.kind = kind;
    body.picture = made.picture;
    body.scale = made.scale;
    body.seed = seed;
    body.flags = made.flags;
    body.born = tick;
    body.health = made.health;
    body.struck = 0;
    return body;
}

// One tick of one body's program. False when the program ended it.
//
// A move runs for its ticks along its curve, from where the body stood when
// it began: nothing accumulates, so a move ends exactly where it says. Moves
// of no ticks happen at once, a few to a tick. Then the body coasts along its
// heading at its speed, and the level carries what rides it.
bool advance_body(inout Body body, Tables tables, Scene scene)
{
    float side = (body.seed & 1) != 0 ? -1.0 : 1.0;
    float2 slid = float2(0.0, 0.0);
    for (uint chained = 0; chained < 4; ++chained)
    {
        Move move = tables.moves[body.move];
        bool at_once = move.ticks == 0;
        if (move.action == MOVE_DIE) return false;
        if (move.action == MOVE_HOLD && at_once) break;
        if (move.action == MOVE_AGAIN)
        {
            body.move -= move.target;
            body.elapsed = 0;
            body.from = body.angle;
            body.from_speed = body.speed;
            continue;
        }
        if (!at_once) ++body.elapsed;
        float eased = at_once ? 1.0 : ease(move.curve, float(body.elapsed) / float(move.ticks));
        float2 ahead = heading(body.from);
        float2 target = move.target == TARGET_PLAYER ? scene.player : move.target == TARGET_CROSSHAIR ? scene.crosshair : body.origin + ahead * 1000.0;
        float2 reach = float2(move.a, move.b * side);
        switch (move.action)
        {
        case MOVE_OFFSET: slid = reach * eased; break;
        case MOVE_ALONG: slid = (ahead * reach.x + right_of(ahead) * reach.y) * eased; break;
        case MOVE_TO: slid = (target + reach - body.origin) * eased; break;
        case MOVE_FACE:
        {
            float2 toward = target - body.origin;
            body.angle = body.from + turn_to(atan2(toward.y, toward.x) - body.from) * eased;
            break;
        }
        case MOVE_TURN: body.angle = body.from + radians(move.a) * side * eased; break;
        case MOVE_THRUST: body.speed = lerp(body.from_speed, move.a, eased); break;
        default: break;
        }
        if (!at_once && body.elapsed < move.ticks) break;
        // The move is over: what it slid becomes where the body is.
        body.origin += slid;
        slid = float2(0.0, 0.0);
        body.move += 1;
        body.elapsed = 0;
        body.from = body.angle;
        body.from_speed = body.speed;
        if (!at_once) break;
    }
    body.origin += heading(body.angle) * (body.speed * TICK_SECONDS);
    if ((body.flags & KIND_RIDES) != 0) body.origin.x -= scene.drift;
    body.position = body.origin + slid;
    return true;
}

// A body as the picture shows it: between its last two ticks. One that has
// just died, or is not there, has no size.
struct Shown { float2 position; float2 axis; uint picture; };
Shown show_body(Body before, Body now, float blend)
{
    Shown shown;
    bool there = now.kind != 0;
    // One made this tick was nowhere before.
    if (before.kind != now.kind || before.born != now.born) before = now;
    shown.position = lerp(before.position, now.position, blend);
    float2 ahead = heading(before.angle + turn_to(now.angle - before.angle) * blend);
    // A picture that looks left points its own x behind it.
    shown.axis = ((now.flags & KIND_FACES_LEFT) != 0 ? -ahead : ahead) * (there ? now.scale : 0.0);
    shown.picture = now.picture;
    return shown;
}
