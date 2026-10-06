// Hits: whether two things touch, by their masks. A picture is hit where it
// is drawn: a point is taken into the picture's own texels by the inverse of
// the turn and scale that set the picture down, and one bit of its mask is
// read. No mask is ever turned or scaled.
//
// The including file has included pictures.slang and motion.slang.

// A body as a picture set down, at a tick rather than between two.
Sprite pose_of(Body body)
{
    Sprite pose;
    pose.position = body.position;
    float2 ahead = heading(body.angle);
    pose.axis = ((body.flags & KIND_FACES_LEFT) != 0 ? -ahead : ahead) * body.scale;
    pose.frame = body.picture;
    pose.flags = 0;
    return pose;
}

// A playfield point in a set-down picture's own texels, from its top left:
// the inverse of set_down.
float2 into_picture(Sprite pose, Picture frame, float2 point)
{
    float2 offset = point - pose.position;
    return float2(dot(offset, pose.axis), dot(offset, float2(-pose.axis.y, pose.axis.x))) / dot(pose.axis, pose.axis) + float2(frame.width, frame.height) * 0.5;
}

bool solid_at(Pictures pictures, Picture frame, float2 texel)
{
    int2 at = int2(floor(texel));
    if (at.x < 0 || at.y < 0 || at.x >= int(frame.width) || at.y >= int(frame.height)) return false;
    return mask_bit(pictures, frame, at.x, at.y);
}

// How far a picture reaches from where it is set down, at most.
float reach_of(Sprite pose, Picture frame)
{
    return 0.5 * length(float2(frame.width, frame.height)) * length(pose.axis);
}

// Something small went from one point to another, each already in a
// picture's texels. Did it pass through anything solid? It is walked a texel
// at a time, so a shot too fast to ever land inside a thin wall still strikes
// it. How far along it struck, 0..1, or less than none.
float sweep(Pictures pictures, Picture frame, float2 from, float2 to)
{
    float2 low = min(from, to), high = max(from, to);
    if (high.x < 0.0 || high.y < 0.0 || low.x >= float(frame.width) || low.y >= float(frame.height)) return -1.0;
    float2 span = to - from;
    uint steps = uint(clamp(ceil(max(abs(span.x), abs(span.y))), 1.0, 96.0));
    for (uint step = 0; step <= steps; ++step)
    {
        float along = float(step) / float(steps);
        if (solid_at(pictures, frame, from + span * along)) return along;
    }
    return -1.0;
}

// A moving point against a moving body, over one tick: where the point was
// against where the body was, to where each is now. Both have moved, and the
// walk is of the one seen from the other.
float sweep_body(Pictures pictures, Body was, Body now, float2 from, float2 to)
{
    Picture frame = pictures.frames[now.picture];
    return sweep(pictures, frame, into_picture(pose_of(was), frame, from), into_picture(pose_of(now), frame, to));
}

// Two pictures: do they overlap? Every sixth solid texel of the first, each
// way, is set down on the playfield and looked up in the second. The first
// should be the smaller.
bool touches(Pictures pictures, Sprite small, Sprite large)
{
    Picture a = pictures.frames[small.frame], b = pictures.frames[large.frame];
    float2 apart = small.position - large.position;
    float reach = reach_of(small, a) + reach_of(large, b);
    if (dot(apart, apart) > reach * reach) return false;
    for (uint y = 3; y < a.height; y += 6)
        for (uint x = 3; x < a.width; x += 6)
            if (mask_bit(pictures, a, x, y) && solid_at(pictures, b, into_picture(large, b, set_down(small, a, float2(x + 0.5, y + 0.5))))) return true;
    return false;
}
