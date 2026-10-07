// Letters: words on the screen with no texels behind them. A letter is some
// of twenty strokes between nine points of its cell: the sixteen of a
// sixteen-segment display, and four that cut its corners, without which a D
// is an O or a pair of posts. So it is sharp at any size, and a font is a
// table of forty words.
// What is said is in the tables (`say` in tables.inc), not here.
//
// The including file has included the shared header (for Tables and Say).

// A cell's nine points, three across and three down, numbered along the rows;
// and the strokes, each from one point to another.
static const uint LETTER_STROKES = 20;
static const uint letter_ends[LETTER_STROKES] =
{
    0x01, 0x12, 0x25, 0x58, 0x78, 0x67, 0x36, 0x03,     // round the edge: top, right, bottom, left, each in two halves
    0x34, 0x45,                                         // the bar across the middle, in two halves
    0x04, 0x14, 0x24, 0x46, 0x47, 0x48,                 // from the middle: up left, up, up right, down left, down, down right
    0x15, 0x57, 0x37, 0x13,                             // across the corners: top right, bottom right, bottom left, top left
};
// Which strokes: A to Z, 0 to 9, then space - + / . : ! '. Above the strokes:
// a dot on the line, a dot above it, a tick at the top.
static const uint LETTER_DOT = 1u << 24, LETTER_HIGH_DOT = 1u << 25, LETTER_TICK = 1u << 26;
static const uint letter_strokes[44] =
{
    0x03CF, 0x4A3F, 0x00F3, 0x300E1, 0x03F3, 0x01C3, 0x02FB, 0x03CC, 0x4833, 0x007C, 0x91C0, 0x00F0, 0x14CC,
    0x84CC, 0x00FF, 0x03C7, 0x80FF, 0x83C7, 0x03BB, 0x4803, 0x00FC, 0x30C0, 0xA0CC, 0xB400, 0x5400, 0x3033,
    0x30FF, 0x100C, 0x0377, 0x023F, 0x038C, 0x03BB, 0x03FB, 0x000F, 0x03FF, 0x03BF,
    0x0000, 0x0300, 0x4B00, 0x3000, 0x1000000, 0x3000000, 0x1000800, 0x4000000,
};

// A character as text has it, to its place in the table; what is not there is a space.
uint letter_of(uint character)
{
    if (character >= 97 && character <= 122) character -= 32;
    if (character >= 65 && character <= 90) return character - 65;
    if (character >= 48 && character <= 57) return character - 48 + 26;
    switch (character)
    {
    case 45: return 37;     // -
    case 43: return 38;     // +
    case 47: return 39;     // /
    case 46: return 40;     // .
    case 58: return 41;     // :
    case 33: return 42;     // !
    case 39: return 43;     // '
    default: return 36;
    }
}

float stroke_distance(float2 at, float2 from, float2 to)
{
    float2 along = to - from, back = at - from;
    return length(back - along * saturate(dot(back, along) / max(dot(along, along), 1e-6)));
}

// How much of a point a letter inks, 0..1. `at` is from the top left of the
// letter's cell, which is `size` across and down; a stroke is `thick` wide.
float letter_ink(uint letter, float2 at, float2 size, float thick)
{
    uint strokes = letter_strokes[min(letter, 43u)];
    float nearest = 1e9;
    for (uint stroke = 0; stroke < LETTER_STROKES; ++stroke)
    {
        if ((strokes & (1u << stroke)) == 0) continue;
        uint ends = letter_ends[stroke], from = ends >> 4, to = ends & 15;
        nearest = min(nearest, stroke_distance(at, float2(from % 3, from / 3) * 0.5 * size, float2(to % 3, to / 3) * 0.5 * size));
    }
    if ((strokes & LETTER_DOT) != 0) nearest = min(nearest, distance(at, float2(0.5, 1.0) * size) - thick * 0.25);
    if ((strokes & LETTER_HIGH_DOT) != 0) nearest = min(nearest, distance(at, float2(0.5, 0.4) * size) - thick * 0.25);
    if ((strokes & LETTER_TICK) != 0) nearest = min(nearest, stroke_distance(at, float2(0.5, 0.0) * size, float2(0.5, 0.2) * size));
    return saturate((thick * 0.5 - nearest) / max(thick * 0.35, 1e-3) + 0.5);
}

// A line of the tables' sayings, `high` units tall, its middle at `middle`:
// how much of the playfield point `at` it inks.
float say_ink(Tables tables, uint which, float2 at, float2 middle, float high)
{
    Say said = tables.says[which];
    float2 size = float2(high * 0.52, high);
    float step = high * 0.74, wide = float(said.count) * step - (step - size.x), thick = high * 0.09;
    float2 from = at - (middle - float2(wide, high) * 0.5);
    if (from.x < -thick || from.y < -thick || from.x > wide + thick || from.y > high + thick) return 0.0;
    uint place = uint(clamp(from.x / step, 0.0, float(max(said.count, 1u) - 1)));
    uint character = (said.letters[place >> 2] >> ((place & 3) * 8)) & 255;
    return letter_ink(letter_of(character), from - float2(float(place) * step, 0.0), size, thick);
}
