// The pictures: every frame the game draws, as one run of texels on the device
// with a mask beside each, and the two ways shaders use them: making them once,
// and pulling them filtered and lit when a sprite is drawn.
//
// A texel is R G B A, premultiplied in linear light and encoded again as sRGB,
// so one blend (ONE, ONE_MINUS_SRC_ALPHA) covers and adds alike.
//
// The including file defines World, beginning with `Pictures pictures`.
#include "common.slang"
#include "myhits_art.slang"

float4 unpack(uint texel) { return float4(texel & 255, (texel >> 8) & 255, (texel >> 16) & 255, texel >> 24) * (1.0 / 255.0); }
uint pack(float4 color)
{
    uint4 bytes = uint4(saturate(color) * 255.0 + 0.5);
    return bytes.x | (bytes.y << 8) | (bytes.z << 16) | (bytes.w << 24);
}
// Exact where pictures are made, once; a cubic where they are drawn, always.
float3 linear_exact(float3 c) { return lerp(c / 12.92, pow((c + 0.055) / 1.055, 2.4), step(0.04045, c)); }
float3 encoded_exact(float3 l) { return lerp(l * 12.92, 1.055 * pow(max(l, 0.0), 1.0 / 2.4) - 0.055, step(0.0031308, l)); }
float3 linear_fast(float3 c) { return c * (c * (c * 0.305306011 + 0.682171111) + 0.012522878); }

// ---- Making them -----------------------------------------------------------

// Frames lie in the order of their texels and of their masks: the last one
// that starts at or before an index holds it.
uint frame_of_texel(Pictures pictures, uint index)
{
    uint low = 0, high = pictures.count - 1;
    while (low < high)
    {
        uint middle = (low + high + 1) >> 1;
        if (pictures.packed_frames[middle].texels <= index) low = middle; else high = middle - 1;
    }
    return low;
}
uint frame_of_mask(Pictures pictures, uint index)
{
    uint low = 0, high = pictures.count - 1;
    while (low < high)
    {
        uint middle = (low + high + 1) >> 1;
        if (pictures.packed_frames[middle].mask <= index) low = middle; else high = middle - 1;
    }
    return low;
}

// A generated frame: premultiplied linear color at a point of it. `at` runs
// over texel centers, `size` is the frame's.
float4 made(uint generator, float2 at, float2 size)
{
    float distance = length(at - size * 0.5) / (size.x * 0.5);
    if (generator == MADE_SPARK)
    {
        // A point of light: white at the heart, warm and thin at the rim. Its
        // color outruns its alpha, which is what adding light means.
        float heat = saturate(1.0 - distance), glow = heat * heat;
        return float4(float3(1.0, 0.6, 0.25) * glow + pow(heat, 6.0), glow);
    }
    if (generator == MADE_WAVE)
    {
        // A shock ring.
        float ring = saturate(1.0 - abs(distance - 0.78) / 0.16);
        ring *= ring;
        return float4(lerp(float3(0.3, 0.6, 1.0), float3(1.0, 1.0, 1.0), ring) * ring, ring);
    }
    return float4(0.0, 0.0, 0.0, 0.0);
}

// A drawn frame: its strokes over one another, in order. The packer's
// Coverage in tools\art.cs follows the same rule for the alpha.
float4 drawn(Pictures pictures, uint argument, float2 at)
{
    float4 result = float4(0.0, 0.0, 0.0, 0.0);
    uint first = argument & 0xffff, count = argument >> 16;
    for (uint k = 0; k < count; ++k)
    {
        Stroke stroke = pictures.strokes[first + k];
        float2 along = stroke.finish - stroke.start;
        float span = dot(along, along);
        float t = span > 0.0 ? saturate(dot(at - stroke.start, along) / span) : 0.0;
        float distance = length(at - stroke.start - along * t) - stroke.radius;
        if (stroke.outline > 0.0) distance = abs(distance) - stroke.outline;
        float4 color = unpack(stroke.color);
        float cover = saturate(0.5 - distance) * color.a;
        result = float4(linear_exact(color.rgb) * cover, cover) + result * (1.0 - cover);
    }
    return result;
}

// Once, over every texel: the packer's are copied, the rest are computed.
[shader("compute")]
[numthreads(64, 1, 1)]
void develop(uint3 id : SV_DispatchThreadID)
{
    Pictures pictures = root.world.pictures;
    uint index = id.x;
    if (index == 0)
    {
        Census empty = { 0, 0, 0, 0, 0, 0, 0, 0 };
        *pictures.census = empty;
    }
    if (index >= pictures.texel_count) return;
    if (index < pictures.baked_texels)
    {
        pictures.texels[index] = pictures.packed_texels[index];
        return;
    }
    Picture frame = pictures.packed_frames[frame_of_texel(pictures, index)];
    uint local = index - frame.texels;
    float2 at = float2(local % frame.width, local / frame.width) + 0.5;
    float4 color = frame.recipe == RECIPE_MADE ? made(frame.argument, at, float2(frame.width, frame.height)) : drawn(pictures, frame.argument, at);
    pictures.texels[index] = pack(float4(encoded_exact(color.rgb), color.a));
}

// Then over every mask word: a bit for each texel at least half there. The
// masks come from the texels on the device, so they are what is drawn.
[shader("compute")]
[numthreads(64, 1, 1)]
void chart(uint3 id : SV_DispatchThreadID)
{
    Pictures pictures = root.world.pictures;
    uint index = id.x;
    if (index >= pictures.mask_words) return;
    Picture frame = pictures.packed_frames[frame_of_mask(pictures, index)];
    uint row_words = (frame.width + 31) / 32, local = index - frame.mask;
    uint first = frame.texels + (local / row_words) * frame.width + (local % row_words) * 32;
    uint count = min(32u, frame.width - (local % row_words) * 32), bits = 0;
    for (uint bit = 0; bit < count; ++bit)
        if ((pictures.texels[first + bit] >> 24) >= 128) bits |= 1u << bit;
    pictures.masks[index] = bits;
}

bool mask_bit(Pictures pictures, Picture frame, uint x, uint y)
{
    return ((pictures.masks[frame.mask + y * ((frame.width + 31) / 32) + (x >> 5)] >> (x & 31)) & 1) != 0;
}

// Last, one invocation a frame: count it, hold it to what the packer said, and
// write the device's own table.
[shader("compute")]
[numthreads(1, 1, 1)]
void census(uint3 id : SV_DispatchThreadID)
{
    Pictures pictures = root.world.pictures;
    if (id.x >= pictures.count) return;
    Picture frame = pictures.packed_frames[id.x];
    uint row_words = (frame.width + 31) / 32, solid = 0, checksum = 0, lopsided = 0;
    for (uint word = 0; word < row_words * frame.height; ++word) solid += countbits(pictures.masks[frame.mask + word]);
    for (uint texel = 0; texel < frame.width * frame.height; ++texel)
        checksum += pictures.texels[frame.texels + texel] ^ ((frame.texels + texel) * 2654435761u);
    if ((frame.flags & FRAME_SYMMETRIC) != 0)
        for (uint y = 0; y < frame.height; ++y)
            for (uint x = 0; x < frame.width / 2; ++x)
                if (mask_bit(pictures, frame, x, y) != mask_bit(pictures, frame, frame.width - 1 - x, y)) ++lopsided;
    if (frame.recipe == RECIPE_BAKED)
    {
        InterlockedAdd(pictures.census.baked, 1);
        InterlockedAdd(pictures.census.baked_solid, solid);
        if (solid != frame.solid || checksum != frame.checksum) InterlockedAdd(pictures.census.baked_wrong, 1);
    }
    else
    {
        InterlockedAdd(pictures.census.made, 1);
        InterlockedAdd(pictures.census.made_solid, solid);
        // The packer's arithmetic is not the device's: a drawn frame may differ by its edge's rounding.
        uint apart = solid > frame.solid ? solid - frame.solid : frame.solid - solid;
        if (solid == 0 || (frame.recipe == RECIPE_DRAWN && apart > max(4u, frame.solid / 64))) InterlockedAdd(pictures.census.made_wrong, 1);
    }
    InterlockedAdd(pictures.census.lopsided, lopsided);
    frame.solid = solid;
    frame.checksum = checksum;
    pictures.frames[id.x] = frame;
}

// ---- Drawing them ----------------------------------------------------------

// A sprite: a frame set down on the playfield. `axis` is where the picture's
// own x points, and its length is the scale; y is a quarter turn on from it.
struct Sprite
{
    float2 position;
    float2 axis;
    uint frame;
    uint flags;
};
static const uint SPRITE_MASK = 1;      // show the frame's mask, not its picture
static const uint SPRITE_FLIP = 2;      // set its picture down mirrored, top for bottom

struct SpriteVertex
{
    float4 position : SV_Position;
    float2 texel : TEXCOORD0;                   // in the frame, from its top left
    float2 offset : TEXCOORD1;                  // from the sprite's position, on the playfield
    nointerpolation float2 turn : TEXCOORD2;    // the axis, unit length
    nointerpolation uint frame : COLOR0;
    nointerpolation uint flags : COLOR1;
};

// A point of a frame, in texels from its top left, as its sprite sets it down:
// how far from the sprite's position, and where on the playfield. A picture
// is drawn by this and hit by its inverse (into_picture in hits.slang).
float2 laid(Sprite sprite, Picture frame, float2 texel)
{
    float2 local = texel - float2(frame.width, frame.height) * 0.5;
    if ((sprite.flags & SPRITE_FLIP) != 0) local.y = -local.y;
    return local.x * sprite.axis + local.y * float2(-sprite.axis.y, sprite.axis.x);
}
float2 set_down(Sprite sprite, Picture frame, float2 texel) { return sprite.position + laid(sprite, frame, texel); }

// One corner of a sprite's quad. The quad is a texel wider than the frame all
// round, so a filtered edge has somewhere to fade.
SpriteVertex sprite_corner(Sprite sprite, Picture frame, uint vertex)
{
    static const uint corners[6] = { 0, 1, 2, 2, 1, 3 };
    uint corner = corners[vertex];
    float2 size = float2(frame.width, frame.height);
    SpriteVertex result;
    result.texel = float2(corner & 1, corner >> 1) * (size + 2.0) - 1.0;
    result.offset = laid(sprite, frame, result.texel);
    result.position = float4((sprite.position + result.offset) / float2(PLAYFIELD_WIDTH, PLAYFIELD_HEIGHT) * 2.0 - 1.0, 0.0, 1.0);
    float scale = length(sprite.axis);
    result.turn = scale > 0.0 ? sprite.axis / scale : float2(1.0, 0.0);
    result.frame = sprite.frame;
    result.flags = sprite.flags;
    return result;
}

// The four texels around a point and their weights. Magnified, a texel keeps
// its square and only its edge is blended: pixel art stays crisp at any angle.
struct Tap { int2 base; float2 weight; };
Tap tap_at(float2 texel)
{
    float2 t = texel - 0.5, base = floor(t);
    float2 weight = t - base;
    weight = saturate((weight - 0.5) / clamp(fwidth(texel), 1e-4, 1.0) + 0.5);
    Tap tap;
    tap.base = int2(base);
    tap.weight = weight;
    return tap;
}
uint texel_at(Pictures pictures, Picture frame, uint plane, int2 at, uint outside)
{
    if (at.x < 0 || at.y < 0 || at.x >= int(frame.width) || at.y >= int(frame.height)) return outside;
    return pictures.texels[frame.texels + plane * frame.width * frame.height + at.y * frame.width + at.x];
}
// The picture at a point: premultiplied, linear.
float4 pull(Pictures pictures, Picture frame, Tap tap)
{
    float4 texels[4];
    for (int corner = 0; corner < 4; ++corner)
    {
        float4 texel = unpack(texel_at(pictures, frame, 0, tap.base + int2(corner & 1, corner >> 1), 0));
        texels[corner] = float4(linear_fast(texel.rgb), texel.a);
    }
    return lerp(lerp(texels[0], texels[1], tap.weight.x), lerp(texels[2], texels[3], tap.weight.x), tap.weight.y);
}
// Its normal there, in the picture's own directions.
float3 pull_normal(Pictures pictures, Picture frame, Tap tap)
{
    float3 normals[4];
    for (int corner = 0; corner < 4; ++corner)
    {
        float4 texel = unpack(texel_at(pictures, frame, 1, tap.base + int2(corner & 1, corner >> 1), 0xffff8080u));
        normals[corner] = float3(texel.xy * (255.0 / 127.0) - 128.0 / 127.0, texel.z);
    }
    return normalize(lerp(lerp(normals[0], normals[1], tap.weight.x), lerp(normals[2], normals[3], tap.weight.x), tap.weight.y));
}

// The light is over the player's left shoulder and stays there: a picture's
// normals turn with it, the light does not.
static const float3 LIGHT = float3(-0.5494, -0.6193, 0.5609);
float facing(float3 normal, float2 turn)
{
    return dot(float3(normal.x * turn + normal.y * float2(-turn.y, turn.x), normal.z), LIGHT);
}
float3 lit(float3 color, float alpha, float toward)
{
    float shade = max(1.0 + 0.9 * (toward - LIGHT.z), 0.3);
    return color * shade + pow(saturate(toward), 24.0) * 0.3 * alpha;
}

// What a sprite shows at a fragment. `alpha` is the picture's own, before a
// glow thins it; `toward` is how far its surface faces the light, or the
// light's own height where the frame has no normals.
float4 sprite_color(Pictures pictures, Picture frame, SpriteVertex input, out float alpha, out float toward)
{
    Tap tap = tap_at(input.texel);
    float4 color = pull(pictures, frame, tap);
    alpha = color.a;
    toward = LIGHT.z;
    if ((frame.flags & FRAME_LIGHT) != 0)
    {
        float3 normal = pull_normal(pictures, frame, tap);
        if ((input.flags & SPRITE_FLIP) != 0) normal.y = -normal.y;
        toward = facing(normal, input.turn);
        color.rgb = lit(color.rgb, color.a, toward);
    }
    if ((frame.flags & FRAME_GLOW) != 0) color.a *= color.a;
    return color;
}
// Its mask there instead: one texel, unfiltered.
bool sprite_mask(Pictures pictures, Picture frame, SpriteVertex input)
{
    int2 at = int2(floor(input.texel));
    if (at.x < 0 || at.y < 0 || at.x >= int(frame.width) || at.y >= int(frame.height)) return false;
    return mask_bit(pictures, frame, at.x, at.y);
}
