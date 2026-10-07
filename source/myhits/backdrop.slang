// The backdrop: what is behind everything, as layers of pattern that pass at
// their own rates. Nothing of it is stored: each layer is a function of where
// on the playfield and how far the level has come, so it moves when the level
// moves and stands when the level stands, and the nearer a layer the faster
// it passes.
//
// The including file has included common.slang (for the hash).

// How far the level has come, kept so that it is exact however far that is:
// whole units, which only count up, and the part of a unit over. (The part
// may be a little under nothing: a picture stands between two ticks, and is
// that much short of the second.) A float that only grew would lose a unit's
// worth of its low end every time the distance doubled; after an hour the
// far layers would move in steps.
struct Travel
{
    uint units;
    float part;
};

// A layer shows a share of the travel, as a ratio of two small whole
// numbers, and takes its share in whole numbers too. Here, wrapped to a
// pattern's period: 0 up to `period`.
float travel_within(Travel travel, uint num, uint den, uint period)
{
    float along = (float((travel.units % (period * den)) * num) + travel.part * float(num)) / float(den);
    return along - float(period) * floor(along / float(period));
}

// And here as cells of a lattice `size` across, for a pattern that never
// repeats: how many whole cells have gone by, which may wrap as any count
// may, and how far into the next the layer is.
void travel_cells(Travel travel, uint num, uint den, uint size, out int cells, out float into)
{
    uint span = den * size;
    float over = (float((travel.units % span) * num) + travel.part * float(num)) / float(span);
    float whole = floor(over);
    cells = int((travel.units / span) * num) + int(whole);
    into = over - whole;
}

static const uint BACKDROP_LAYERS = 4;
static const uint BACKDROP_STAGES = 3;
// A stage is three inks: the sky's, the lattice's and the ridge's light.
static const float3 backdrop_inks[BACKDROP_STAGES * 3] =
{
    float3(0.010, 0.022, 0.060), float3(0.05, 0.22, 0.34), float3(0.10, 0.34, 0.50),
    float3(0.045, 0.010, 0.050), float3(0.34, 0.10, 0.26), float3(0.55, 0.24, 0.10),
    float3(0.008, 0.035, 0.030), float3(0.10, 0.30, 0.12), float3(0.42, 0.40, 0.12),
};

// Smooth noise on a lattice. `at` is in cells; `gone` is whole cells more
// along x, added where the cells are numbered and not where they are measured.
float lattice_noise(float2 at, int gone)
{
    float2 cell = floor(at), part = at - cell;
    part = part * part * (3.0 - 2.0 * part);
    uint2 corner = uint2(int2(cell) + int2(gone, 0) + 32768);
    float a = unit(hash(corner.x * 73856093U ^ corner.y * 19349663U));
    float b = unit(hash((corner.x + 1) * 73856093U ^ corner.y * 19349663U));
    float c = unit(hash(corner.x * 73856093U ^ (corner.y + 1) * 19349663U));
    float d = unit(hash((corner.x + 1) * 73856093U ^ (corner.y + 1) * 19349663U));
    return lerp(lerp(a, b, part.x), lerp(c, d, part.x), part.y);
}

// One octave of a layer's noise at a playfield point: the layer's share of
// the travel is `num` in `den`, and the octave's cells are `size` across.
float travelled_noise(Travel travel, uint num, uint den, uint size, float x, float y)
{
    int cells;
    float into;
    travel_cells(travel, num, den, size, cells, into);
    return lattice_noise(float2(x / float(size) + into, y), cells);
}

// The far layer's cloud, and the ridge's two edges: each the sum of its
// octaves. They are apart from the layers so that what is drawn is also what
// can be asked about.
float backdrop_cloud(float2 point, Travel travel)
{
    return travelled_noise(travel, 1, 25, 420, point.x, point.y / 420.0) * 0.6
        + travelled_noise(travel, 1, 25, 150, point.x, point.y / 150.0) * 0.3
        + travelled_noise(travel, 1, 25, 60, point.x, point.y / 60.0) * 0.1;
}
float backdrop_ridge(float x, Travel travel)
{
    return PLAYFIELD_HEIGHT - 90.0 - 170.0 * travelled_noise(travel, 3, 10, 260, x, 3.0) - 40.0 * travelled_noise(travel, 3, 10, 70, x, 9.0);
}

// One layer at a playfield point, the level having come `travel`: what it
// adds, and how much of what is behind it it hides. Far, lattice, ridge,
// rail: a twenty-fifth of the travel, three twenty-fifths, three tenths,
// three quarters.
float4 backdrop_layer(uint layer, float2 point, Travel travel, float3 sky, float3 trace, float3 rim)
{
    if (layer == 0)
    {
        // Far: clouds of the sky's own ink, thicker toward the middle.
        float cloud = backdrop_cloud(point, travel);
        float band = 1.0 - abs(point.y / PLAYFIELD_HEIGHT * 2.0 - 1.0);
        return float4(sky * (0.6 + 2.2 * cloud * cloud * band), 1.0);
    }
    if (layer == 1)
    {
        // A lattice of diamonds: the pattern that says this is a made place.
        float2 at = point + float2(travel_within(travel, 3, 25, 150), 0.0);
        float2 cell = float2(at.x + at.y, at.x - at.y) / 150.0;
        float2 part = abs(cell - floor(cell) - 0.5);
        float edge = saturate(1.0 - min(part.x, part.y) * 150.0 / 2.5);
        float node = saturate(1.0 - length(part) * 150.0 / 9.0);
        // Its nodes beat with the music, where there is any.
        return float4(trace * (edge * 0.28 + node * (0.9 + 2.0 * root.beat)), 0.0);
    }
    if (layer == 2)
    {
        // A ridge along the bottom and its echo along the top, dark, lit at the rim.
        float low = backdrop_ridge(point.x, travel);
        float high = 50.0 + 110.0 * travelled_noise(travel, 3, 10, 310, point.x, 17.0);
        float inside = max(point.y - low, high - point.y);
        float cover = saturate(inside * 0.5 + 0.5);
        float glow = saturate(1.0 - abs(inside) / 14.0);
        return float4(rim * (glow * glow * 0.55) * cover + sky * 0.25 * cover, cover);
    }
    // Rails at the very edges, with a rivet every so often: nearest and fastest.
    float depth = max(point.y - (PLAYFIELD_HEIGHT - 26.0), 22.0 - point.y);
    float cover = saturate(depth * 0.5 + 0.5);
    float along = (point.x + travel_within(travel, 3, 4, 96)) / 96.0;
    float rivet = saturate(1.0 - length(float2((along - floor(along) - 0.5) * 96.0, depth - 12.0)) / 5.0);
    return float4((trace * 0.5 * rivet + rim * 0.12 * saturate(1.0 - abs(depth) / 3.0)) * cover + sky * 0.1 * cover, cover);
}

// The whole of it at a playfield point. It is between two stages' inks by `fade`.
float3 backdrop(float2 point, Travel travel, uint from_stage, uint to_stage, float fade)
{
    uint a = (from_stage % BACKDROP_STAGES) * 3, b = (to_stage % BACKDROP_STAGES) * 3;
    float3 sky = lerp(backdrop_inks[a], backdrop_inks[b], fade);
    float3 trace = lerp(backdrop_inks[a + 1], backdrop_inks[b + 1], fade);
    float3 rim = lerp(backdrop_inks[a + 2], backdrop_inks[b + 2], fade);
    float3 color = float3(0.0, 0.0, 0.0);
    for (uint layer = 0; layer < BACKDROP_LAYERS; ++layer)
    {
        float4 over = backdrop_layer(layer, point, travel, sky, trace, rim);
        color = over.rgb + color * (1.0 - over.a);
    }
    return color;
}

// The specks in front of it all: each at its own depth, in sixty-fourths,
// and round a span of 2000. How far one of them has gone, 0 up to the span.
static const uint SPECK_SPAN = 2000;
float speck_gone(Travel travel, uint depth)
{
    float gone = float(((travel.units % (SPECK_SPAN * 64)) * depth) % (SPECK_SPAN * 64)) / 64.0 + travel.part * float(depth) / 64.0;
    return gone - float(SPECK_SPAN) * floor(gone / float(SPECK_SPAN));
}

// Is the level's distance exact? Asked once, at start, of the same functions
// the picture is drawn by, with the level as it would stand after about three
// thousand million units: five months at full pace. What repeats must be
// exactly what it is at the start, since that many units is a whole number
// of every period there is. What does not repeat must still move as the
// level does: twenty-five units more of travel is the far layer one unit to
// the left, and ten is the ridge three, there as at the start. A bit for
// each thing wrong.
uint backdrop_faults()
{
    static const uint FAR = 2999040000u;        // 1,920,000 times 1,562: a multiple of 3,750, of 384 and of 128,000
    Travel near, far;
    near.units = 12345;
    near.part = 0.37;
    far.units = near.units + FAR;
    far.part = near.part;
    Travel clouded = far, ridged = far;
    clouded.units += 25;
    ridged.units += 10;
    float3 one = float3(1.0, 1.0, 1.0);
    uint faults = 0;
    for (uint sample = 0; sample < 64; ++sample)
    {
        float x = 300.0 + float(sample);
        if (any(backdrop_layer(1, float2(x, 500.0), near, one, one, one) != backdrop_layer(1, float2(x, 500.0), far, one, one, one))) faults |= 1;
        if (any(backdrop_layer(3, float2(x, 12.0), near, one, one, one) != backdrop_layer(3, float2(x, 12.0), far, one, one, one))) faults |= 2;
        if (abs(backdrop_cloud(float2(x, 540.0), clouded) - backdrop_cloud(float2(x + 1.0, 540.0), far)) > 0.0003) faults |= 4;
        if (abs(backdrop_ridge(x, ridged) - backdrop_ridge(x + 3.0, far)) > 0.02) faults |= 8;
    }
    for (uint depth = 16; depth <= 64; ++depth)
        if (speck_gone(near, depth) != speck_gone(far, depth)) faults |= 16;
    return faults;
}
