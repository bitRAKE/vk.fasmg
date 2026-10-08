// Proof 08, text: strings the system shaped, drawn from their outlines on the
// device. What it settles and how to run it is in ..\README.md. The drawing
// itself, and the building of what it is drawn from, is ..\..\..\common\text.slang.
#include "common.slang"
#include "text.slang"

// The header the CPU writes: PageWorld in page.asm.
struct World { Text* text; };

// Alone, once a frame: opens the frame's events and says what the device
// found when it built the bands and examined the glyphs. Nothing here knows
// what the page says.
[shader("compute")]
[numthreads(1, 1, 1)]
void direct()
{
    Text text = *root.world.text;
    Events* events = root.events;
    open_events(events);
    TextCensus census = *text.census;
    events.reserved[0] = census.listed;
    events.reserved[1] = census.crowded;
    events.reserved[2] = census.longest;
    events.reserved[3] = census.unplaced;
    events.reserved[4] = census.examined;
    events.reserved[5] = census.band_faults;
    events.reserved[6] = census.area_faults;
    events.reserved[7] = census.worst_area;
    events.reserved[8] = census.samples;
    events.reserved[9] = text.glyph_count;
    events.reserved[10] = text.band_count;
    events.reserved[11] = text.placed_count;
    events.reserved[12] = text.band_from;
    events.reserved[13] = census.cover_faults;
    events.reserved[14] = census.overlapped;
    events.reserved[15] = text.taken;
}

// The last page: lines that are kept, said by the device; and numbers, which
// it sets down from the ten digits. Nothing of this is set down by the CPU:
// which glyph an instance is, where and how, is decided here, from its
// number alone. (pictures.ps1 knows where these are, to hold the picture to.)
static const uint KEPT_HELLO = 0, KEPT_COLOUR = 1, KEPT_DIGITS = 2, KEPT_FIGURES = 3;
static const uint KEPT_SLOTS = 6, KEPT_GLYPHS = 64;     // KEPT_INSTANCES in page.asm is these, and the cells below
static const uint GOLD = 0xff40c8ffu;

TextVertex kept_corner(Text text, uint index, uint vertex)
{
    Placed placed = {};
    float4 clip = TEXT_UNCLIPPED;
    bool there = false;
    Line digits = text_line(text, KEPT_DIGITS);
    if (index < KEPT_SLOTS * KEPT_GLYPHS)
    {
        // One line, said six ways.
        float rise = text_line(text, KEPT_HELLO).rise;
        Said said;
        said.line = KEPT_HELLO;
        said.across = float2(40.0, 0.0);
        said.align = 0.0;
        said.color = 0xffffffffu;
        switch (index / KEPT_GLYPHS)
        {
        case 0:     // as it was set down by the CPU, 960 to the left of this
            said.at = float2(1020.0, 80.0 + rise * 40.0);
            break;
        case 1:     // at twice the size
            said.at = float2(60.0, 180.0 + rise * 80.0);
            said.across = float2(80.0, 0.0);
            break;
        case 2:     // about its middle, in a color
            said.at = float2(960.0, 470.0);
            said.align = 0.5;
            said.color = GOLD;
            break;
        case 3:     // turned
            said.at = float2(1200.0, 380.0);
            said.across = 40.0 * float2(cos(-0.25), sin(-0.25));
            break;
        case 4:     // a line with glyphs of their font's colors in it: they keep them
            said.line = KEPT_COLOUR;
            said.at = float2(60.0, 560.0);
            said.across = float2(64.0, 0.0);
            said.color = GOLD;
            break;
        default:    // and the same, half there
            said.line = KEPT_COLOUR;
            said.at = float2(760.0, 560.0);
            said.across = float2(64.0, 0.0);
            said.color = 0x80ffffffu;
            break;
        }
        there = text_said(text, said, index % KEPT_GLYPHS, placed);
    }
    else if ((index -= KEPT_SLOTS * KEPT_GLYPHS) < 8)
    {
        // A number: eight cells, the greatest first. The CPU sets the same
        // digits down as a string 960 to the right, in a font whose digits
        // are all one width, so that the two should be one picture.
        Line figures = text_line(text, KEPT_FIGURES);
        uint place_of = 1;
        for (uint power = index; power < 7; ++power) place_of *= 10;
        float2 at = float2(60.0 + figures.step * 64.0 * float(index), 640.0 + figures.rise * 64.0);
        there = text_one(text, KEPT_FIGURES, (90817263u / place_of) % 10, at, float2(64.0, 0.0), 0xffffffffu, placed);
    }
    else if ((index -= 8) < 16)
    {
        // A number that is turning over, as a counter of wheels does: a cell
        // is two digits, the one going out at the top and the one coming in
        // from below, and neither is drawn outside the cell. It counts in
        // tenths, one a frame; a wheel turns with the last one only while
        // every wheel after it stands at nine. Its font's digits are not all
        // one width: each stands in the middle of a cell as wide as the widest.
        uint cell = index / 2;
        uint tenths = 12345990u + (root.frame >= 60 ? root.frame - 60 : 0);
        uint whole = tenths / 10, place_of = 1;
        for (uint power = cell; power < 7; ++power) place_of *= 10;
        float roll = float(tenths % 10) * 0.1;
        if (place_of > 1 && whole % place_of != place_of - 1) roll = 0.0;
        uint digit = (whole / place_of) % 10;
        float2 at = float2(60.0 + digits.step * 64.0 * float(cell), 780.0 + digits.rise * 64.0);
        clip = float4(at.x, at.y + digits.low.y * 64.0 - 4.0, at.x + digits.step * 64.0, at.y + digits.high.y * 64.0 + 4.0);
        float travel = clip.w - clip.y;
        if ((index & 1) == 0) at.y -= roll * travel;
        else
        {
            digit = (digit + 1) % 10;
            at.y += (1.0 - roll) * travel;
        }
        there = ((index & 1) == 0 || roll > 0.0) && text_one(text, KEPT_DIGITS, digit, at, float2(64.0, 0.0), 0xffffffffu, placed);
    }
    if (!there) placed.across = float2(0.0, 0.0);
    return text_corner(text, placed, vertex, clip);
}

// No vertex buffer and no instance buffer: the glyph and its place are pulled.
// What the CPU set down comes first; what the device says for itself, after.
[shader("vertex")]
TextVertex text_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    Text text = *root.world.text;
    if (instance < text.placed_count) return text_corner(text, text.placed[instance & (TEXT_PLACED - 1)], vertex);
    return kept_corner(text, instance - text.placed_count, vertex);
}

// No image and no sampler: its curves are pulled too.
[shader("fragment")]
float4 text_fragment(TextVertex input) : SV_Target0
{
    float alpha = text_ink(*root.world.text, input) * input.color.a;
    return float4(input.color.rgb * alpha, alpha);
}
