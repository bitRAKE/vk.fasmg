// Text, drawn from its outlines by the Slug algorithm.
//
// The algorithm is Eric Lengyel's: "GPU-Centered Font Rendering Directly from
// Glyph Outlines", Journal of Computer Graphics Techniques 6(2), 2017, and "A
// Decade of Slug", terathon.com/blog/decade-slug.html, 2026, which dedicates
// its patent to the public domain. What follows is written for this layer,
// with the algorithm's reference shaders (github.com/EricLengyel/Slug,
// copyright 2017 Eric Lengyel, MIT License) beside it: the root code, the
// solving of a curve against a ray, and the way two rays' coverage is
// combined are theirs, and are used under that license.
//
// What is this layer's own is where everything lives. A curve, a band and a
// list are memory reached through pointers, not texels; a glyph on the page
// is pulled by the vertex shader, as a sprite is; and the bands are built on
// the device, by the passes at the end, from curves that are all that ever
// comes up from the CPU. What comes up is taken, once, into memory that is
// the device's own, and drawn from there.
//
// A pixel's coverage by a glyph is found from two rays, one along x and one
// along y, each through the pixel's middle. A ray counts the curves it
// crosses, by which way each goes, and for a crossing within half a pixel
// counts only the part of the pixel on its far side: that is the winding
// number, with antialiasing in it. Which crossings count is decided from the
// signs of a curve's three points alone, which is why it never cracks. Only
// the curves in the pixel's band are looked at, and those in order of how far
// they reach, so that a ray stops looking when nothing further can reach it.
//
// Every number read here that says where to read next is masked to the room
// there is, and every loop has an end that no number sets: whatever is in
// memory, nothing reads outside it and nothing goes on for ever.
//
// The including file has included common.slang, and defines World with
// `text`, a pointer to the Text that text.inc made.

static const float TEXT_BAND_OVERLAP = 1.0 / 1024.0;   // of an em: how far a band reaches into its neighbors
static const uint TEXT_BAND_CURVES = 256;               // the most curves a band is walked for
static const uint TEXT_GLYPH_CURVES = 2048;             // the most curves a glyph is looked through for

Glyph text_glyph(Text text, uint glyph) { return text.glyphs[glyph & (TEXT_GLYPHS - 1)]; }
Curve text_curve(Text text, uint curve) { return text.curves[curve & (TEXT_CURVES - 1)]; }
Band text_band(Text text, uint band) { return text.bands[band & (TEXT_BANDS - 1)]; }
uint text_listed(Text text, uint entry) { return text.lists[entry & (TEXT_LISTS - 1)]; }

// Which of a curve's two crossings of the line y = 0 count, from the signs of
// its three points' y: bit 0 the first, bit 8 the second.
uint text_root_code(float y1, float y2, float y3)
{
    uint i1 = asuint(y1) >> 31;
    uint i2 = asuint(y2) >> 30;
    uint i3 = asuint(y3) >> 29;
    uint shift = (i2 & 2) | (i1 & ~2u);
    shift = (i3 & 4) | (shift & ~4u);
    return (0x2E74u >> shift) & 0x0101u;
}

// Where a curve, given about the pixel's middle, crosses y = 0: the x of each
// of its two crossings. a t^2 - 2 b t + c, with the roots taken as one where
// there are none, and the line's root where it is next to straight.
float2 text_crossings(float2 p1, float2 p2, float2 p3)
{
    float2 a = p1 - p2 * 2.0 + p3;
    float2 b = p1 - p2;
    float ra = 1.0 / a.y;
    float rb = 0.5 / b.y;
    float d = sqrt(max(b.y * b.y - a.y * p1.y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;
    if (abs(a.y) < 1.0 / 65536.0) { t1 = p1.y * rb; t2 = t1; }
    return float2((a.x * t1 - b.x * 2.0) * t1 + p1.x, (a.x * t2 - b.x * 2.0) * t2 + p1.x);
}

// One curve against the ray along x: what it adds to the coverage, and how
// near a crossing came to the pixel's middle. `scale` is pixels to an em.
void text_ray(float2 p1, float2 p2, float2 p3, float scale, inout float coverage, inout float weight)
{
    uint code = text_root_code(p1.y, p2.y, p3.y);
    if (code == 0) return;
    float2 r = text_crossings(p1, p2, p3) * scale;
    if ((code & 1) != 0)
    {
        coverage += saturate(r.x + 0.5);
        weight = max(weight, saturate(1.0 - abs(r.x) * 2.0));
    }
    if (code > 1)
    {
        coverage -= saturate(r.y + 0.5);
        weight = max(weight, saturate(1.0 - abs(r.y) * 2.0));
    }
}

// The two rays' winding as one: each weighed by how near its crossings came,
// and never less than what both agree on. Either way round a font winds.
float text_wound(float across, float down, float across_weight, float down_weight)
{
    return max(abs(across * across_weight + down * down_weight) / max(across_weight + down_weight, 1.0 / 65536.0), min(abs(across), abs(down)));
}

// And what is drawn of it: a place is covered once, however often it is
// enclosed. Contours that lie over one another, which fonts are full of, are
// drawn as the one shape they make.
float text_combined(float across, float down, float across_weight, float down_weight)
{
    return saturate(text_wound(across, down, across_weight, down_weight));
}

// How much of the pixel whose middle is `em`, in the glyph's ems, the glyph
// covers; `pixels` is pixels to an em, each way.
float text_coverage(Text text, Glyph glyph, float2 em, float2 pixels)
{
    if (glyph.curve_count == 0 || glyph.rows == 0 || glyph.columns == 0) return 0.0;
    float2 size = max(glyph.high - glyph.low, float2(1e-6, 1e-6));
    float2 along = (em - glyph.low) / size;
    uint row = uint(clamp(along.y * float(glyph.rows), 0.0, float(glyph.rows - 1)));
    uint column = uint(clamp(along.x * float(glyph.columns), 0.0, float(glyph.columns - 1)));

    // The ray along x, through the row the pixel is in: its curves reach
    // less and less far to the right, and the first that does not reach the
    // pixel ends it.
    Band band = text_band(text, glyph.bands + row);
    float across = 0.0, across_weight = 0.0;
    uint count = min(band.count, TEXT_BAND_CURVES);
    for (uint each = 0; each < count; ++each)
    {
        Curve curve = text_curve(text, text_listed(text, band.first + each));
        float2 p1 = curve.p1 - em, p2 = curve.p2 - em, p3 = curve.p3 - em;
        if (max(max(p1.x, p2.x), p3.x) * pixels.x < -0.5) break;
        text_ray(p1, p2, p3, pixels.x, across, across_weight);
    }
    // And the ray along y, through its column: the same, on its side.
    band = text_band(text, glyph.bands + glyph.rows + column);
    float down = 0.0, down_weight = 0.0;
    count = min(band.count, TEXT_BAND_CURVES);
    for (uint each = 0; each < count; ++each)
    {
        Curve curve = text_curve(text, text_listed(text, band.first + each));
        float2 p1 = curve.p1 - em, p2 = curve.p2 - em, p3 = curve.p3 - em;
        if (max(max(p1.y, p2.y), p3.y) * pixels.y < -0.5) break;
        text_ray(p1.yx, p2.yx, p3.yx, pixels.y, down, down_weight);
    }
    return text_combined(across, -down, across_weight, down_weight);
}

// The same from every curve the glyph has, bands or no bands: what the bands
// are held to. And `wound`: how often the place is enclosed.
float text_coverage_plain(Text text, Glyph glyph, float2 em, float2 pixels, out float wound)
{
    float across = 0.0, across_weight = 0.0, down = 0.0, down_weight = 0.0;
    uint count = min(glyph.curve_count, TEXT_GLYPH_CURVES);
    for (uint each = 0; each < count; ++each)
    {
        Curve curve = text_curve(text, glyph.curves + each);
        float2 p1 = curve.p1 - em, p2 = curve.p2 - em, p3 = curve.p3 - em;
        text_ray(p1, p2, p3, pixels.x, across, across_weight);
        text_ray(p1.yx, p2.yx, p3.yx, pixels.y, down, down_weight);
    }
    wound = text_wound(across, -down, across_weight, down_weight);
    return text_combined(across, -down, across_weight, down_weight);
}

// A glyph on the page, as a draw sees it.
struct TextVertex
{
    float4 position : SV_Position;
    float2 em : TEXCOORD0;                      // where in the glyph, in its ems
    float2 place : TEXCOORD1;                   // and where on the playfield
    nointerpolation uint glyph : COLOR0;
    nointerpolation float4 color : COLOR1;      // in linear light, not yet multiplied by its alpha
    nointerpolation float4 clip : COLOR2;       // the box of the playfield it may be drawn in: its low corner, and its high
};
static const float4 TEXT_UNCLIPPED = float4(-1e9, -1e9, 1e9, 1e9);

// A color as a texel has it, in linear light: exactly, so that a font's own
// colors come out on the screen as the font has them.
float3 text_linear(float3 color)
{
    return lerp(color / 12.92, pow((color + 0.055) / 1.055, float3(2.4, 2.4, 2.4)), step(float3(0.04045, 0.04045, 0.04045), color));
}

// One corner of a glyph's box, pushed out by a little more than half a pixel
// so that a pixel the outline only grazes is still drawn. No vertex buffer:
// the glyph and its place are pulled. A glyph the device has not yet taken is
// not looked at, and not drawn.
TextVertex text_corner(Text text, Placed placed, uint vertex, float4 clip = TEXT_UNCLIPPED)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    bool taken = placed.glyph < min(text.glyph_from, TEXT_GLYPHS);
    Glyph glyph = {};
    if (taken) glyph = text_glyph(text, placed.glyph);
    float size = length(placed.across);
    float pixels = size * root.view.x / float(PLAYFIELD_WIDTH);
    float margin = 0.75 / max(pixels, 1e-3);
    float2 corner = float2(corners[vertex] & 1, corners[vertex] >> 1);
    float2 em = lerp(glyph.low - margin, glyph.high + margin, corner);
    float2 down = float2(-placed.across.y, placed.across.x);
    float2 at = placed.at + placed.across * em.x + down * em.y;
    TextVertex result;
    result.em = em;
    result.place = at;
    result.clip = clip;
    result.glyph = placed.glyph;
    float4 color = float4(placed.color & 255, (placed.color >> 8) & 255, (placed.color >> 16) & 255, placed.color >> 24) * (1.0 / 255.0);
    result.color = float4(text_linear(color.rgb), color.a);
    // A glyph of nothing, or of no size, covers nothing.
    bool drawn = taken && glyph.curve_count != 0 && size > 0.0;
    result.position = float4(drawn ? at / float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) * 2.0 - 1.0 : float2(0.0, 0.0), 0.0, 1.0);
    return result;
}

// How much of this pixel the glyph covers. How large a pixel is in ems comes
// from how fast the ems change across the screen, each way.
float text_ink(Text text, TextVertex input)
{
    float2 pixels = 1.0 / max(fwidth(input.em), float2(1e-6, 1e-6));
    // What lies outside its box is not drawn; the box's edge is a pixel soft.
    float2 inside = saturate(input.place - input.clip.xy + 0.5) * saturate(input.clip.zw - input.place + 0.5);
    float kept = inside.x * inside.y;
    if (kept <= 0.0) return 0.0;
    return text_coverage(text, text_glyph(text, input.glyph), input.em, pixels) * kept;
}

// Lines that are kept. The system laid each out once; from then on a glyph of
// one is found from the line, where it is said and which glyph of it is
// wanted, by whoever draws: nothing is set down for it and nothing is asked
// of the CPU. What says a line is a program's to decide, a pixel at a time if
// it likes: it fills in a Said, asks for a glyph of it, and may move, turn,
// color or clip that glyph before it is drawn.
struct Said
{
    float2 at;          // a point of its baseline: its left end, its middle or its right end
    float2 across;      // one em along it there: its size, and its turn
    float align;        // 0 from its left end, 0.5 about its middle, 1 to its right end
    uint line;
    uint color;         // R G B A: what its glyphs take that have no color of their own
};

// A line, or one of nothing if there is none such, or none has been taken yet.
Line text_line(Text text, uint line)
{
    Line none = {};
    if (text.taken == 0 || line >= TEXT_LINES) return none;
    return text.lines[line];
}

// A glyph's own color, as faint as what it is said in; or that, if it has none.
uint text_tint(uint own, uint said)
{
    if ((own >> 24) == 0) return said;
    return (own & 0x00ffffffu) | ((((own >> 24) * (said >> 24) + 127) / 255) << 24);
}

// The glyph numbered `index` of a line that is said, as a glyph set down;
// false, and nothing, when the line has no such glyph.
bool text_said(Text text, Said said, uint index, out Placed placed)
{
    Placed none = {};
    placed = none;
    Line line = text_line(text, said.line);
    uint which = line.first + index;
    if (index >= line.count || which >= min(text.laid_from, TEXT_LAID)) return false;
    Laid laid = text.laid[which];
    float2 from = laid.at - float2(line.wide * said.align, 0.0);
    placed.at = said.at + said.across * from.x + float2(-said.across.y, said.across.x) * from.y;
    placed.across = said.across;
    placed.glyph = laid.glyph;
    placed.color = text_tint(laid.color, said.color);
    return true;
}

// One glyph of a line, by itself, in the middle of a cell that begins at
// `at` and is the line's step wide: a digit, of a line that is the ten of
// them in order. A number is then the device's to set down: which digit
// stands in which cell is arithmetic, and so is where a cell is, how large,
// what color, and what it is doing.
bool text_one(Text text, uint from, uint index, float2 at, float2 across, uint color, out Placed placed)
{
    Placed none = {};
    placed = none;
    Line line = text_line(text, from);
    uint which = line.first + index;
    if (index >= line.count || which >= min(text.laid_from, TEXT_LAID)) return false;
    Laid laid = text.laid[which];
    // How far it advances by itself: to the next of its line, or to the line's end.
    float next = line.wide;
    if (index + 1 < line.count) next = text.laid[(which + 1) & (TEXT_LAID - 1)].at.x;
    placed.at = at + across * ((line.step - (next - laid.at.x)) * 0.5);
    placed.across = across;
    placed.glyph = laid.glyph;
    placed.color = text_tint(laid.color, color);
    return true;
}

// The bands. Each glyph's box is cut into rows and into columns; a row lists
// the curves that reach into it, the one that reaches furthest right first,
// and a column those that reach into it, the one that reaches furthest down
// first. A straight line along a row crosses no ray along it, and is left
// out of the rows; one along a column, out of the columns.
//
// Before any of that, what is new is taken: each curve, glyph and kept glyph
// the CPU has staged since the last time, and every line, a thread to one of
// each, into memory that is the device's own.
//
// Then three passes, over the bands from Text.band_from on. The first, a
// thread to a band, counts its curves. The second, alone, gives each band its
// place in the lists, which depends on every band before it. The third, a
// thread to a band again, writes the curves' numbers there in order.
[shader("compute")]
[numthreads(64, 1, 1)]
void text_take(uint3 id : SV_DispatchThreadID)
{
    Text text = *root.world.text;
    uint curve = text.curve_from + id.x, glyph = text.glyph_from + id.x, laid = text.laid_from + id.x;
    if (curve < min(text.curve_count, TEXT_CURVES)) text.curves[curve] = text.staged_curves[curve];
    if (glyph < min(text.glyph_count, TEXT_GLYPHS)) text.glyphs[glyph] = text.staged_glyphs[glyph];
    if (laid < min(text.laid_count, TEXT_LAID)) text.laid[laid] = text.staged_laid[laid];
    if (id.x < TEXT_LINES) text.lines[id.x] = text.staged_lines[id.x];
}

// Whose band this is: the last glyph whose bands begin at or before it.
uint text_owner(Text text, uint band)
{
    uint low = 0, high = clamp(text.glyph_count, 1u, TEXT_GLYPHS) - 1;
    for (uint step = 0; step < 16 && low < high; ++step)
    {
        uint middle = (low + high + 1) >> 1;
        if (text_glyph(text, middle).bands <= band) low = middle; else high = middle - 1;
    }
    return low;
}

// Whether a curve reaches into a glyph's band, and how far it reaches the
// way that band's ray goes.
bool text_reaches(Glyph glyph, uint which, Curve curve, out float reach)
{
    bool row = which < glyph.rows;
    // (A column is a row with x and y changed about.)
    float2 p1 = row ? curve.p1 : curve.p1.yx, p2 = row ? curve.p2 : curve.p2.yx, p3 = row ? curve.p3 : curve.p3.yx;
    float2 low = row ? glyph.low : glyph.low.yx, high = row ? glyph.high : glyph.high.yx;
    uint many = max(row ? glyph.rows : glyph.columns, 1u);
    float thick = (high.y - low.y) / float(many);
    float from = low.y + thick * float(row ? which : which - glyph.rows);
    reach = max(max(p1.x, p2.x), p3.x);
    if (p1.y == p2.y && p2.y == p3.y) return false;
    return max(max(p1.y, p2.y), p3.y) >= from - TEXT_BAND_OVERLAP && min(min(p1.y, p2.y), p3.y) <= from + thick + TEXT_BAND_OVERLAP;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void text_count(uint3 id : SV_DispatchThreadID)
{
    Text text = *root.world.text;
    uint band = id.x + text.band_from;
    if (band >= min(text.band_count, TEXT_BANDS)) return;
    Glyph glyph = text_glyph(text, text_owner(text, band));
    uint which = band - glyph.bands, count = 0;
    if (which < glyph.rows + glyph.columns)
    {
        uint curves = min(glyph.curve_count, TEXT_GLYPH_CURVES);
        for (uint each = 0; each < curves; ++each)
        {
            float reach;
            if (text_reaches(glyph, which, text_curve(text, glyph.curves + each), reach)) ++count;
        }
    }
    text.bands[band & (TEXT_BANDS - 1)].count = count;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void text_place()
{
    Text text = *root.world.text;
    TextCensus* census = text.census;
    uint listed = census.listed, longest = census.longest, crowded = census.crowded, unplaced = census.unplaced;
    uint end = min(text.band_count, TEXT_BANDS);
    for (uint band = min(text.band_from, end); band < end; ++band)
    {
        uint count = text.bands[band].count;
        // A band there is no room for is left with nothing in it, and counted.
        if (listed + count > TEXT_LISTS) { count = 0; text.bands[band].count = 0; ++unplaced; }
        text.bands[band].first = listed;
        listed += count;
        longest = max(longest, count);
        if (count > TEXT_BAND_CURVES) ++crowded;
    }
    census.listed = listed;
    census.longest = longest;
    census.crowded = crowded;
    census.unplaced = unplaced;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void text_fill(uint3 id : SV_DispatchThreadID)
{
    Text text = *root.world.text;
    uint band = id.x + text.band_from;
    if (band >= min(text.band_count, TEXT_BANDS)) return;
    Band placed = text_band(text, band);
    Glyph glyph = text_glyph(text, text_owner(text, band));
    uint which = band - glyph.bands;
    if (which >= glyph.rows + glyph.columns || placed.count == 0) return;
    // Its curves, in the order they come; then each put where it belongs
    // among those before it, the furthest-reaching first. (One of more
    // curves than a band is walked for is listed unsorted: it is counted as
    // crowded, and nothing reads past the end of it.)
    uint wanted = min(placed.count, TEXT_BAND_CURVES), found = 0;
    uint numbers[TEXT_BAND_CURVES] = {};
    float reaches[TEXT_BAND_CURVES] = {};
    uint curves = min(glyph.curve_count, TEXT_GLYPH_CURVES);
    for (uint each = 0; each < curves && found < wanted; ++each)
    {
        float reach;
        if (!text_reaches(glyph, which, text_curve(text, glyph.curves + each), reach)) continue;
        uint at = found;
        while (at > 0 && reaches[at - 1] < reach)
        {
            numbers[at] = numbers[at - 1];
            reaches[at] = reaches[at - 1];
            --at;
        }
        numbers[at] = glyph.curves + each;
        reaches[at] = reach;
        ++found;
    }
    for (uint each = 0; each < found; ++each) text.lists[(placed.first + each) & (TEXT_LISTS - 1)] = numbers[each];
}

// The glyphs examined, for a program that proves this. Over a glyph's box and
// a little round it, at pixels of two sizes, the bands' coverage is held to
// all the curves' coverage. And at the finer size two things are summed: how
// often each place is enclosed, which should come to the area the curves
// enclose, as the CPU found it from the curves alone; and what is drawn of
// each place, which should come to the same where nothing is enclosed twice,
// and to less where something is.
//
// A thread to a row of places, not to a glyph: one thread is slow, and a
// glyph of many curves examined by one alone would keep the device longer
// than a device may be kept. Each row adds what it found to its glyph's sum,
// and a second pass, a thread to a glyph, judges the sums.
static const float TEXT_EXAMINED_FINE = 64.0;   // pixels to an em, at the finer size
static const float TEXT_EXAMINED_PARTS = 4096.0; // what a pixel's coverage is counted in

[shader("compute")]
[numthreads(64, 1, 1)]
void text_examine(uint3 id : SV_DispatchThreadID)
{
    Text text = *root.world.text;
    uint which = id.x / TEXT_EXAMINED_MOST, row = id.x % TEXT_EXAMINED_MOST;
    if (which >= min(text.glyph_count, TEXT_GLYPHS)) return;
    Glyph glyph = text_glyph(text, which);
    if (glyph.curve_count == 0) return;
    uint faults = 0, places = 0, twice = 0;
    float covered = 0.0, wound = 0.0;
    static const float sizes[2] = { 11.0, TEXT_EXAMINED_FINE };
    for (uint pass = 0; pass < 2; ++pass)
    {
        float pixels = sizes[pass];
        float2 from = glyph.low - 1.5 / pixels;
        uint2 many = min(uint2(ceil((glyph.high - glyph.low) * pixels)) + 3, uint2(TEXT_EXAMINED_MOST, TEXT_EXAMINED_MOST));
        if (row >= many.y) continue;
        for (uint x = 0; x < many.x; ++x)
        {
            float2 em = from + (float2(x, row) + 0.5) / pixels;
            float banded = text_coverage(text, glyph, em, float2(pixels, pixels));
            float enclosed;
            float plain = text_coverage_plain(text, glyph, em, float2(pixels, pixels), enclosed);
            if (abs(banded - plain) > 1.0 / 256.0) ++faults;
            if (pass == 1)
            {
                covered += banded;
                wound += enclosed;
                if (enclosed > 1.25) ++twice;
            }
            ++places;
        }
    }
    TextCensus* census = text.census;
    if (places != 0) InterlockedAdd(census.samples, places);
    if (faults != 0) InterlockedAdd(census.band_faults, faults);
    which &= TEXT_GLYPHS - 1;
    if (covered > 0.0) InterlockedAdd(text.examined[which].covered, uint(covered * TEXT_EXAMINED_PARTS + 0.5));
    if (wound > 0.0) InterlockedAdd(text.examined[which].wound, uint(wound * TEXT_EXAMINED_PARTS + 0.5));
    if (twice != 0) InterlockedAdd(text.examined[which].twice, twice);
}

[shader("compute")]
[numthreads(64, 1, 1)]
void text_judge(uint3 id : SV_DispatchThreadID)
{
    Text text = *root.world.text;
    if (id.x >= min(text.glyph_count, TEXT_GLYPHS)) return;
    Glyph glyph = text_glyph(text, id.x);
    if (glyph.curve_count == 0) return;
    TextCensus* census = text.census;
    InterlockedAdd(census.examined, 1);
    Examined sums = text.examined[id.x & (TEXT_GLYPHS - 1)];
    float square = TEXT_EXAMINED_PARTS * TEXT_EXAMINED_FINE * TEXT_EXAMINED_FINE;
    float covered = float(sums.covered) / square, wound = float(sums.wound) / square, area = abs(glyph.area);
    float slack = 0.02 * area + 0.0005;
    // How often its places are enclosed, in square ems, against what its
    // curves enclose: the rays against the curves themselves.
    uint apart = uint(min(abs(wound - area) / max(area, 1e-4) * 1000.0, 100000.0));
    InterlockedMax(census.worst_area, apart);
    if (abs(wound - area) > slack) InterlockedAdd(census.area_faults, 1);
    // And what is drawn of it: the same, where nothing is enclosed twice.
    // Where something is, each such place was drawn once, which is a quarter
    // of a pixel less than it is enclosed at the very least.
    if (sums.twice == 0)
    {
        if (abs(covered - area) > slack) InterlockedAdd(census.cover_faults, 1);
    }
    else
    {
        InterlockedAdd(census.overlapped, 1);
        if (covered > wound - 0.2 * float(sums.twice) / (TEXT_EXAMINED_FINE * TEXT_EXAMINED_FINE)) InterlockedAdd(census.cover_faults, 1);
    }
}
