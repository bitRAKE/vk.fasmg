// The backdrop: what is behind everything, as layers of pattern that pass at
// their own rates. Nothing of it is stored: each layer is a function of where
// on the playfield and how far the level has come, so it moves when the level
// moves and stands when the level stands, and the nearer a layer the faster
// it passes.
//
// The including file has included common.slang (for the hash).

static const uint BACKDROP_LAYERS = 4;
// How much of the level's travel each layer shows: far, lattice, ridge, rail.
static const float backdrop_rates[BACKDROP_LAYERS] = { 0.04, 0.12, 0.3, 0.75 };
static const uint BACKDROP_STAGES = 3;
// A stage is three inks: the sky's, the lattice's and the ridge's light.
static const float3 backdrop_inks[BACKDROP_STAGES * 3] =
{
    float3(0.010, 0.022, 0.060), float3(0.05, 0.22, 0.34), float3(0.10, 0.34, 0.50),
    float3(0.045, 0.010, 0.050), float3(0.34, 0.10, 0.26), float3(0.55, 0.24, 0.10),
    float3(0.008, 0.035, 0.030), float3(0.10, 0.30, 0.12), float3(0.42, 0.40, 0.12),
};

float lattice_noise(float2 at)
{
    float2 cell = floor(at), part = at - cell;
    part = part * part * (3.0 - 2.0 * part);
    uint2 corner = uint2(int2(cell) + 32768);
    float a = unit(hash(corner.x * 73856093U ^ corner.y * 19349663U));
    float b = unit(hash((corner.x + 1) * 73856093U ^ corner.y * 19349663U));
    float c = unit(hash(corner.x * 73856093U ^ (corner.y + 1) * 19349663U));
    float d = unit(hash((corner.x + 1) * 73856093U ^ (corner.y + 1) * 19349663U));
    return lerp(lerp(a, b, part.x), lerp(c, d, part.x), part.y);
}

// One layer at a point of the level: what it adds, and how much of what is
// behind it it hides. `at` is the playfield point moved by the layer's share
// of the level's travel.
float4 backdrop_layer(uint layer, float2 at, float3 sky, float3 trace, float3 rim)
{
    if (layer == 0)
    {
        // Far: clouds of the sky's own ink, thicker toward the middle.
        float cloud = lattice_noise(at / 420.0) * 0.6 + lattice_noise(at / 150.0) * 0.3 + lattice_noise(at / 60.0) * 0.1;
        float band = 1.0 - abs(at.y / PLAYFIELD_HEIGHT * 2.0 - 1.0);
        return float4(sky * (0.6 + 2.2 * cloud * cloud * band), 1.0);
    }
    if (layer == 1)
    {
        // A lattice of diamonds: the pattern that says this is a made place.
        float2 cell = float2(at.x + at.y, at.x - at.y) / 150.0;
        float2 part = abs(cell - floor(cell) - 0.5);
        float edge = saturate(1.0 - min(part.x, part.y) * 150.0 / 2.5);
        float node = saturate(1.0 - length(part) * 150.0 / 9.0);
        return float4(trace * (edge * 0.28 + node * 0.9), 0.0);
    }
    if (layer == 2)
    {
        // A ridge along the bottom and its echo along the top, dark, lit at the rim.
        float low = PLAYFIELD_HEIGHT - 90.0 - 170.0 * lattice_noise(float2(at.x / 260.0, 3.0)) - 40.0 * lattice_noise(float2(at.x / 70.0, 9.0));
        float high = 50.0 + 110.0 * lattice_noise(float2(at.x / 310.0, 17.0));
        float inside = max(at.y - low, high - at.y);
        float cover = saturate(inside * 0.5 + 0.5);
        float glow = saturate(1.0 - abs(inside) / 14.0);
        return float4(rim * (glow * glow * 0.55) * cover + sky * 0.25 * cover, cover);
    }
    // Rails at the very edges, with a rivet every so often: nearest and fastest.
    float depth = max(at.y - (PLAYFIELD_HEIGHT - 26.0), 22.0 - at.y);
    float cover = saturate(depth * 0.5 + 0.5);
    float along = at.x / 96.0;
    float rivet = saturate(1.0 - length(float2((along - floor(along) - 0.5) * 96.0, depth - 12.0)) / 5.0);
    return float4((trace * 0.5 * rivet + rim * 0.12 * saturate(1.0 - abs(depth) / 3.0)) * cover + sky * 0.1 * cover, cover);
}

// The whole of it at a playfield point, the level having come `scroll`. It
// is between two stages' inks by `fade`.
float3 backdrop(float2 point, float scroll, uint from_stage, uint to_stage, float fade)
{
    uint a = (from_stage % BACKDROP_STAGES) * 3, b = (to_stage % BACKDROP_STAGES) * 3;
    float3 sky = lerp(backdrop_inks[a], backdrop_inks[b], fade);
    float3 trace = lerp(backdrop_inks[a + 1], backdrop_inks[b + 1], fade);
    float3 rim = lerp(backdrop_inks[a + 2], backdrop_inks[b + 2], fade);
    float3 color = float3(0.0, 0.0, 0.0);
    for (uint layer = 0; layer < BACKDROP_LAYERS; ++layer)
    {
        float4 over = backdrop_layer(layer, point + float2(scroll * backdrop_rates[layer], 0.0), sky, trace, rim);
        color = over.rgb + color * (1.0 - over.a);
    }
    return color;
}
