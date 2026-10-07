// Chains: a head, and segments that go exactly where it went. The head lays
// its path into a ring of points a fixed distance apart, however fast it
// goes; a segment takes the point its own distance back along that ring.
//
// A segment reads its head as the head stood last tick. The two copies of
// every body keep that still while this tick is written, so nothing is read
// while it changes, and every segment is the same one tick behind: there is
// no lag down the body.
//
// The including file has included motion.slang.

// A head's `link` is its ring, plus one. A segment's is its head's slot, and
// above that its place in the chain, from 1.
static const uint LINK_PLACE = 16;
uint link_head(uint link) { return link & ((1u << LINK_PLACE) - 1); }
uint link_place(uint link) { return link >> LINK_PLACE; }

// A head has moved from `before` to where it is: lay the points it passed.
void lay_trail(inout Body head, float2 before, float2* trails)
{
    float2 step = head.position - before;
    float moved = length(step);
    if (moved <= 0.0) return;
    float carried = head.carried + moved;
    uint ring = (head.link - 1) * TRAIL_POINTS;
    for (uint guard = 0; guard < 16 && carried >= float(TRAIL_STEP); ++guard)
    {
        carried -= float(TRAIL_STEP);
        trails[ring + head.laid % TRAIL_POINTS] = head.position - step * (carried / moved);
        head.laid += 1;
    }
    head.carried = min(carried, float(TRAIL_STEP));
}

// Where the path is, `back` units behind a head, and which way it runs
// there. Nearer than the newest point, it is between that and the head; past
// the oldest, it is the oldest: a chain not yet out of its lair waits there.
void trail_at(Body head, float2* trails, float back, out float2 at, out float2 toward)
{
    uint have = min(head.laid, uint(TRAIL_POINTS)), ring = (max(head.link, 1u) - 1) * TRAIL_POINTS;
    if (have == 0)
    {
        at = head.position;
        toward = heading(head.angle);
        return;
    }
    float2 newest = trails[ring + (head.laid - 1) % TRAIL_POINTS];
    if (back <= head.carried)
    {
        at = lerp(head.position, newest, head.carried > 0.0 ? back / head.carried : 0.0);
        toward = head.position - newest;
        return;
    }
    float steps = (back - head.carried) / float(TRAIL_STEP);
    uint whole = min(uint(steps), have - 1), next = min(whole + 1, have - 1);
    float2 near = trails[ring + (head.laid - 1 - whole) % TRAIL_POINTS], far = trails[ring + (head.laid - 1 - next) % TRAIL_POINTS];
    at = lerp(near, far, whole == next ? 0.0 : steps - float(whole));
    toward = whole == 0 ? head.position - near : trails[ring + (head.laid - whole) % TRAIL_POINTS] - near;
    if (whole == next) toward = near - far;
}

// One tick of a segment. `head` is its head's body as of last tick, and
// `spacing` its kind's. False when it has died of its head's death: a chain
// goes one segment after another, three ticks apart, from the head back.
bool follow(inout Body body, Body head, float2* trails, float spacing)
{
    if (head.kind == 0 || head.born != body.seed)
    {
        body.elapsed += 1;
        return body.elapsed < 3 * link_place(body.link);
    }
    float2 at, toward;
    trail_at(head, trails, float(link_place(body.link)) * spacing, at, toward);
    body.position = at;
    body.origin = at;
    if (dot(toward, toward) > 1e-6) body.angle = atan2(toward.y, toward.x);
    return true;
}
