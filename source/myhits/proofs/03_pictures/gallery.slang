// Proof 03, pictures: every frame art.txt lists, made on the device and drawn
// from it, with nothing bound. What it settles and how to run it is in
// ..\README.md. The pictures themselves are ..\..\pictures.slang.
#include "pictures.slang"

static const float SHIP_SPEED = 600.0;      // playfield units a second
static const uint CHAIN = 14;               // head, bodies, tail
static const float CHAIN_SCALE = 1.5;
static const float CHAIN_SPACING = 112.0;   // closer than a body is long: the couplings overlap
static const uint SHOWN = 8;                // the light, pulsing in a row
static const uint COLUMNS = 16;
static const uint SPRITE_CHAIN = 2;         // counted by which side its light falls on
static const uint SPRITE_GALLERY = 4;       // counted against its mask

struct State { float2 ship; };
// The header the CPU writes once: GalleryWorld in gallery.asm.
struct World { Pictures pictures; Sprite* sprites; State* state; uint count; uint pad; };

void place(World* world, inout uint next, float2 position, float2 axis, uint frame, uint flags)
{
    Sprite sprite;
    sprite.position = position;
    sprite.axis = axis;
    sprite.frame = frame;
    sprite.flags = flags;
    if (next < world.count) world.sprites[next] = sprite;
    ++next;
}
float2 turned(float angle, float scale) { return float2(cos(angle), sin(angle)) * scale; }

// The chain's road: a loop with a sway in it, so its tangent goes all the way round.
float2 road(float s) { return float2(1230.0, 760.0) + float2(540.0 * cos(s), 230.0 * sin(s) + 40.0 * sin(3.0 * s)); }
float2 road_tangent(float s) { return float2(-540.0 * sin(s), 230.0 * cos(s) + 120.0 * cos(3.0 * s)); }

// Alone, once a frame: opens the frame's events, applies the controls, and
// sets every sprite down. Nothing of this is known to the CPU.
[shader("compute")]
[numthreads(1, 1, 1)]
void direct()
{
    World* world = root.world;
    Events* events = root.events;
    events.frame = root.frame;
    events.state = 0; events.score = 0; events.wave = 0; events.lives = 0; events.multiplier = 0;
    events.rank = 0.0; events.shield = 0.0; events.intensity = 0.0;
    events.rumble_low = 0.0; events.rumble_high = 0.0; events.flags = 0;
    for (uint kind = 0; kind < SOUND_KINDS; ++kind)
    {
        events.sound[kind].count = 0;
        events.sound[kind].pan = 0;
    }
    for (uint slot = 0; slot < 4; ++slot) events.debug[slot] = 0;
    for (uint spare = 0; spare < 16; ++spare) events.reserved[spare] = 0;

    // What the device found when it made the pictures, every frame: it costs nothing.
    Census census = *world.pictures.census;
    events.reserved[0] = census.baked;
    events.reserved[1] = census.baked_wrong;
    events.reserved[2] = census.baked_solid;
    events.reserved[3] = census.made;
    events.reserved[4] = census.made_wrong;
    events.reserved[5] = census.made_solid;
    events.reserved[6] = census.lopsided;

    float2 ship = root.frame == 0 ? float2(300.0, 640.0) : world.state.ship;
    ship = clamp(ship + root.move * (SHIP_SPEED * root.ticks * TICK_SECONDS), float2(60.0, 60.0), float2(PLAYFIELD_WIDTH - 60.0, PLAYFIELD_HEIGHT - 60.0));
    world.state.ship = ship;
    events.reserved[8] = asuint(ship.x);
    events.reserved[9] = asuint(ship.y);

    uint next = 0;
    // The gallery: every frame as it is, and under it the mask the device made of it.
    for (uint frame = 0; frame < ART_FRAMES; ++frame)
    {
        float2 at = float2(90.0 + (frame % COLUMNS) * 116.0, 62.0 + (frame / COLUMNS) * 200.0);
        place(world, next, at, float2(1.0, 0.0), frame, SPRITE_GALLERY);
        place(world, next, at + float2(0.0, 98.0), float2(1.0, 0.0), frame, SPRITE_MASK);
    }
    // The light, alive: each turns slowly and swells in its own time.
    static const uint shown[SHOWN] = { FRAME_BOLT, FRAME_PLASMA, FRAME_FLARE, FRAME_FLASH, FRAME_BURST, FRAME_NOVA, FRAME_SPARK, FRAME_WAVE };
    for (uint k = 0; k < SHOWN; ++k)
        place(world, next, float2(80.0 + k * 78.0, 500.0), turned(k < 2 ? 0.0 : root.time * 0.6 + k, 1.0 + 0.25 * sin(root.time * 5.0 + k * 1.3)), shown[k], 0);
    // The chain, tail first so the head lies over the rest. Each piece sits a
    // step back along the road from the one before and points the way it goes;
    // the art faces left, so its own x points back down the road.
    float along[CHAIN];
    along[0] = root.time * 1.6;
    for (uint k = 1; k < CHAIN; ++k) along[k] = along[k - 1] - CHAIN_SPACING / length(road_tangent(along[k - 1]));
    for (uint k = CHAIN; k > 0; --k)
    {
        uint piece = k - 1;
        uint frame = piece == 0 ? FRAME_WORM_HEAD : piece == CHAIN - 1 ? FRAME_WORM_TAIL : FRAME_WORM_BODY;
        place(world, next, road(along[piece]), -normalize(road_tangent(along[piece])) * CHAIN_SCALE, frame, SPRITE_CHAIN);
    }
    // The ship under the controls, its shield turning round it, and the crosshair.
    place(world, next, ship, float2(1.5, 0.0), FRAME_SHIP, 0);
    place(world, next, ship, turned(root.time * 1.5, 1.45), FRAME_SHIELD, 0);
    place(world, next, root.aim, float2(1.0, 0.0), FRAME_CROSSHAIR, 0);
    events.reserved[10] = next;
    for (; next < world.count; ++next) world.sprites[next].axis = float2(0.0, 0.0);
}

// No vertex buffer and no instance buffer: sprite and frame are pulled.
[shader("vertex")]
SpriteVertex sprite_vertex(uint vertex : SV_VulkanVertexID, uint instance : SV_VulkanInstanceID)
{
    World* world = root.world;
    Sprite sprite = world.sprites[instance];
    return sprite_corner(sprite, world.pictures.frames[sprite.frame], vertex);
}

// No image and no sampler: the texels are pulled too, and the fragment counts
// itself toward whichever claim its sprite stands for.
[shader("fragment")]
float4 sprite_fragment(SpriteVertex input) : SV_Target0
{
    Pictures pictures = root.world.pictures;
    Picture frame = pictures.frames[input.frame];
    if ((input.flags & SPRITE_MASK) != 0)
    {
        if (!sprite_mask(pictures, frame, input)) discard;
        InterlockedAdd(root.events.reserved[11], 1);
        return float4(0.08, 0.55, 0.3, 1.0);
    }
    float alpha, toward;
    float4 color = sprite_color(pictures, frame, input, alpha, toward);
    if (alpha <= 0.0) discard;
    InterlockedAdd(root.events.score, 1);
    if ((input.flags & SPRITE_GALLERY) != 0 && alpha >= 0.5) InterlockedAdd(root.events.reserved[12], 1);
    if ((input.flags & SPRITE_CHAIN) != 0 && (frame.flags & FRAME_LIGHT) != 0 && alpha >= 0.5)
    {
        // A fragment brightened by the light should lie on the side of its
        // sprite the light is on, whichever way the sprite has turned.
        uint side = dot(input.offset, LIGHT.xy) > 0.0 ? 0 : 1;
        if (toward > LIGHT.z + 0.1) InterlockedAdd(root.events.debug[side], 1);
        // And had the light turned with the picture, it would not.
        if (facing(pull_normal(pictures, frame, tap_at(input.texel)), float2(1.0, 0.0)) > LIGHT.z + 0.1) InterlockedAdd(root.events.debug[2 + side], 1);
    }
    return color;
}
