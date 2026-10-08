// Proof 08, text: strings the system shaped, drawn from their outlines on the
// device. What it settles and how to run it is in ..\README.md. The drawing
// itself, and the building of what it is drawn from, is ..\..\..\common\text.slang.
#include "common.slang"
#include "text.slang"

// The header the CPU writes: PageWorld in page.asm.
struct World { Text text; };

// Alone, once a frame: opens the frame's events and says what the device
// found when it built the bands and examined the glyphs. Nothing here knows
// what the page says.
[shader("compute")]
[numthreads(1, 1, 1)]
void direct()
{
    Text text = root.world.text;
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
}

// No vertex buffer and no instance buffer: the glyph and its place are pulled.
[shader("vertex")]
TextVertex text_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    Text text = root.world.text;
    return text_corner(text, text.placed[instance & (TEXT_PLACED - 1)], vertex);
}

// No image and no sampler: its curves are pulled too.
[shader("fragment")]
float4 text_fragment(TextVertex input) : SV_Target0
{
    float alpha = text_ink(root.world.text, input) * input.color.a;
    return float4(input.color.rgb * alpha, alpha);
}
