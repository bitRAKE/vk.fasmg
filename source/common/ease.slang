// The easing curves: EASE_ in the shared header. One library for motion, the
// HUD, particles and the level's own pace. Each takes 0..1 to 0..1, exactly
// at both ends; the back and elastic families pass outside on the way.
//
// These are the curves of easings.net, written as families: an `in`, its
// mirror the `out`, and the two joined at the middle. Proof 04 holds every
// one to a second implementation written the long way.

float bounce_out(float t)
{
    const float n = 7.5625, d = 2.75;
    if (t < 1.0 / d) return n * t * t;
    if (t < 2.0 / d) { t -= 1.5 / d; return n * t * t + 0.75; }
    if (t < 2.5 / d) { t -= 2.25 / d; return n * t * t + 0.9375; }
    t -= 2.625 / d;
    return n * t * t + 0.984375;
}

float ease_in(uint family, float t)
{
    switch (family)
    {
    case 0: return t * t;
    case 1: return t * t * t;
    case 2: return t * t * t * t;
    case 3: return t * t * t * t * t;
    case 4: return 1.0 - cos(t * 1.5707963);
    case 5: return exp2(10.0 * t - 10.0);
    case 6: return 1.0 - sqrt(max(1.0 - t * t, 0.0));
    case 7: return t * t * (2.70158 * t - 1.70158);
    case 8: return -exp2(10.0 * t - 10.0) * sin((t * 10.0 - 10.75) * 2.0943951);
    default: return 1.0 - bounce_out(1.0 - t);
    }
}

float ease(uint curve, float t)
{
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    if (curve == EASE_LINEAR) return t;
    uint family = (curve - 1) / 3, form = (curve - 1) % 3;
    if (form == 0) return ease_in(family, t);
    if (form == 1) return 1.0 - ease_in(family, 1.0 - t);
    // Two families join their halves with a constant of their own.
    if (curve == EASE_INOUT_BACK)
    {
        const float c = 1.70158 * 1.525;
        float u = t < 0.5 ? 2.0 * t : 2.0 * t - 2.0;
        return t < 0.5 ? u * u * ((c + 1.0) * u - c) * 0.5 : (u * u * ((c + 1.0) * u + c) + 2.0) * 0.5;
    }
    if (curve == EASE_INOUT_ELASTIC)
    {
        float wave = sin((20.0 * t - 11.125) * 1.3962634);
        return t < 0.5 ? -exp2(20.0 * t - 10.0) * wave * 0.5 : exp2(-20.0 * t + 10.0) * wave * 0.5 + 1.0;
    }
    return t < 0.5 ? ease_in(family, 2.0 * t) * 0.5 : 1.0 - ease_in(family, 2.0 - 2.0 * t) * 0.5;
}
