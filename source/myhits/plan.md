# myhits: plan

A fast horizontal shooter whose world lives on the GPU. This is the plan we
iterate on. What has been proved is marked so and lives, runnable, in
[proofs](proofs/README.md); everything else is intent.

## Settled

Decisions taken, in the order they were asked:

1. **Horizontal.** The playfield scrolls sideways, so there is room to see
   what is coming and time to be impressed by it.
2. **One ship, then a companion.** The game starts with a single ship. The
   companion arrives as a surprise and grows in three steps: it trails where
   you were; then it acts for itself, shielding one way and firing another;
   then you can steer it.
3. **Every kind of art.** Authored and animated, baked from Blender, vector,
   generated: all of it goes through one picture format.
4. **Slang**, compiled by the SDK's `slangc`.
5. **XAudio2**, playing a sound bank the GPU renders at start.
6. **Modern only.** The target is a GTX 1080 Ti and later. No alternates.
7. **A fixed playfield of 1920×1080**, scaled to the window inside bars.

Proved on the device (GTX 1080 Ti, with and without validation):

- The whole CPU–GPU boundary below: pointers from one root block, atomics
  through them, pulled vertices and texels, events read back. Proof 02.
- The assembly and the shader compiler agree on every boundary offset, from
  one definition. Proof 01.
- A frame costs the CPU 72 bytes down and 512 up.

## Shape

The CPU is a platform layer: window, input, audio device, Vulkan plumbing. The
game is shader code over GPU memory. The CPU never reads or writes an entity.

```text
          every frame                           once at start
CPU ──── Root, 72 bytes ────────────▶ GPU      CPU ── tables, baked art ──▶ GPU
CPU ◀─── Events, 512 bytes ───────── GPU       CPU ◀── sound bank, PCM ──── GPU
          (read one frame late)
```

| Traffic | Bytes | How |
| --- | ---: | --- |
| CPU to GPU, per frame | 72 | Push constants; no buffer write, no staging copy |
| GPU to CPU, per frame | 512 | A host-visible slot the shaders write; read when its frame has finished |
| CPU to GPU, at start | tables, then art | Tables straight into host-visible memory; baked pictures copied in once |
| GPU to CPU, at start | a few MB | Sound effects synthesized by a compute pass, copied out once |

Everything else is device-local memory only shaders touch. The checks count
the CPU's bytes and commands every frame and fail if they grow.

**No descriptors.** Every resource is a pointer in the root block. Sprite
instances are pulled in the vertex shader and their texels in the fragment
shader; backgrounds and HUD are procedural. One pipeline layout holds one push
constant range. This stands until a picture needs what only an image has,
mipmaps or compressed formats; see Pictures.

**Contract.** Modern only, stated with the blocks of `vulkan_routes.inc`:
dynamic rendering, synchronization2, timeline semaphores, inline shader code,
`bufferDeviceAddress` and `scalarBlockLayout` are required and nothing they
replace is assembled. The floor is Vulkan 1.4, or 1.3 with maintenance5.

## Interfaces

Three blocks cross the CPU boundary. They are defined once, in
[shared.inc](shared.inc). Assembling it writes the Slang header the shaders
include, each member with its offset, and the checks hold the compiler to
those offsets. Everything else is private to the shaders.

### Root: CPU to GPU, every frame

```c
struct Root {             // 72 bytes; at most 128, the size every device has
    World*  world;        //  0  everything else is reached from here
    Events* events;       //  8  this frame's slot
    float   time, dt;     // 16  seconds; dt clamped, fixed in scripted runs
    uint    frame, seed;  // 24
    float2  view;         // 32  the playfield's size on screen, in pixels
    float2  move, aim;    // 40  -1..1, and the crosshair in playfield units
    uint    held, pressed;// 56  buttons down, and those that went down this frame
    float   beat;         // 64  music phase 0..1, so the picture can pulse with it
    uint    flags;        // 68  paused, scripted run, ...
};
```

### Events: GPU to CPU, every frame

```c
struct Events {                  // 512 bytes; a ring of four slots
    uint  frame, state;          // echo of Root.frame; title, playing, over
    uint  score, wave, lives, multiplier;
    float rank, shield, intensity;       // intensity drives the music mix
    float rumble_low, rumble_high;       // gamepad motors
    uint  flags, debug[4];
    struct { uint count; int pan; } sound[48];   // triggers
};
```

Sound triggers are a histogram, not a queue. A shader that wants a sound adds
one to `sound[k].count` and its screen x to `pan`, atomically. The CPU plays
kind `k` once per frame at a gain that grows with the count and a pan of
`pan / count`. Fifty explosions at once cost the same 8 bytes and one voice as
one, and nothing can overflow.

### Tables: CPU to GPU, once

Static data authored in fasmg with small macros and written into one
host-visible buffer: kinds, their motion programs, waves, bonuses, particle
styles, sound recipes, the frame table of the pictures, HUD layout, glyphs,
palettes. The same macros give the shader header its `KIND_*`, `SOUND_*` and
`BONUS_*` numbers. This is where variety is cheap: a new enemy is a few lines.

### World: GPU only

| Pool | Capacity | Notes |
| --- | ---: | --- |
| Sprites | 8192 × 64 B, twice | Read last frame's copy, write this frame's: no races, no tearing |
| Spawn queue | 2048 requests | Appended atomically by parallel passes, drained by the director |
| Trails | 64 × 256 points | One ring per snake head, and one for the player |
| Links | 256 | A pair of sprite slots and a style |
| Particles | 65536 × 32 B | A ring; the oldest are overwritten |
| Pictures | as the art needs | Texels of every frame, packed; see below |
| Masks | one bit a texel | Derived on the GPU from the pictures' alpha, so they match what is drawn |
| Game | one block | Clock, rank, player, bonuses, HUD timers, cursors, damage accumulators |

Sprite slots are partitioned by group in fixed ranges: 16 player parts, 240
pickups, 1792 enemies, 4096 enemy shots, 2048 player shots. A group is a
contiguous instance range, so layers draw in order without sorting and
collision loops know their bounds.

## The frame

| # | Step | Runs as | Writes |
| --- | --- | --- | --- |
| 0 | await | CPU | Waits for the device to finish the last frame, plays its events' sounds, then reads the controls |
| 1 | direct | one invocation | Clock, rank, game state, bonuses; moves the player from input; creates every new sprite: waves, the player's shots, and whatever the spawn queue asked for |
| 2 | update | per sprite | Its own slot in this frame's copy: its motion program, trail samples; requests for shots into the spawn queue |
| 3 | collide | per shot and per hostile | Damage accumulators and pickup counters by atomics; its own death; sparks; sound counts |
| 4 | resolve | per sprite | Its own health, death and hit flash; score; explosions; drops into the spawn queue; HUD timers |
| 5 | particles | per particle | Its own slot, in place |
| 6 | draw | background, sprites by group, links, particles, HUD | The swapchain image |

Rules that keep it honest:

- **A frame begins when the device has finished the one before.** Proof 02
  found why: presentation lets a program queue frames ahead, and a queued
  frame's commands wait for a swapchain image, simulation and all. Events
  came back three frames late and the controls were as stale. Waiting first
  makes events exactly one frame late, and reads the controls at the last
  moment, so what you press is in the next picture.
- **Controls show themselves.** Thruster flare from `move`, muzzle flash from
  `held`, the crosshair from `aim` are drawn straight from the root bits, so
  they appear even while a cooldown delays the consequence.
- **Only the director creates sprites.** Parallel passes append requests; the
  director, alone and first, turns them into sprites. No two writers share a
  slot. The player's shots are made by the director from input in the same
  frame.
- **A parallel pass writes its own slot and atomics, nothing else.**
- **Only compute passes write events.** The draw does not.
- **Sound follows events.** One frame plus XAudio2's 10 ms quantum: about
  27 ms at 60 Hz, 16 ms at 165 Hz, before the device's own delay.

## Subsystems

**Pictures.** A frame is a rectangle of texels of any size with a pivot; a
picture is a strip of frames, for animation or for rotation steps. Three
sources fill the same texel buffer, so there is one way to draw and one way
to collide:

- *Baked*: PNG frames, from Blender or by hand, packed at build time into a
  blob with its frame table and copied to the device once.
- *Generated*: a compute pass at start, from a seed. Mirrored pixel ships and
  the like: variety with no asset.
- *Vector*: shape recipes rasterized by the same pass at whatever size is
  asked.

A frame may carry a second plane, the *light*: a shading overlay that stays
upright while the color plane turns under it. That is the fake depth for
rotating chain segments, a sphere's highlight that does not spin with its
markings. A normal map lit by nearby explosions can use the same plane later.
Texels are pulled with four fetches and blended, which is bilinear filtering
without a sampler. If minified art shimmers, or the buffer outgrows what is
sensible, pictures become images and the root gains a descriptor index; the
frame table and everything above it stay as they are.

**Sprites.** A sprite is position, velocity, angle, scale, kind, frame,
state, health, a link word, a seed and a tint. Three composite forms:

- *Chains* for snakes and dragons. The head writes its path into a trail ring;
  segment `i` reads the trail `i` spacings back. Following is exact, parallel
  and has no lag down the body. Each segment turns on its own under its light
  plane. Segments can be hit, and a table flag decides whether a broken chain
  dies or splits.
- *Pairs*. A link names two sprites and a style; the link shader draws the
  effect between them by pulling both ends, and the collide pass samples
  points along it against masks.
- *Assemblies*. Anything too large for one frame is several linked parts,
  each separately destructible.

**Motion.** A kind's behavior is a short program of moves, authored in the
tables. A move is a duration, an easing curve and a target: hold, an offset
from where it is, the player, the crosshair, along its heading, around its
parent. One easing library, the usual in, out and in-out families of power,
sine, exponential, circular, back, elastic and bounce, serves motion, the
HUD's pops, particle sizes and the camera's shake. The missile is the model:

```text
kind MISSILE
    move 0.35, OUT_CUBIC, OFFSET, 40, -60      ; drift out to a strike position
    move 0.15, INOUT_SINE, FACE, CROSSHAIR     ; settle its aim
    move 0,    IN_EXPO,   THRUST, 2400         ; and go
```

Variety comes from recombining moves, not from new shader code.

**The player and the companion.** One ship, moved by `move`, with a crosshair
at `aim` for what is aimed. The companion uses machinery that already exists:
as a trailer it reads the player's own trail ring some samples back, which is
"where you were" exactly; as an agent the update pass gives it two headings,
a shield toward the densest incoming fire and a gun toward the best target;
steered, it takes `aim`. A link between ship and companion is where pair
effects come in.

**Mask collision.** Circles reject first; survivors test masks. A shot maps
its center, and a point or two back along its motion, into the target's mask
space through the inverse of the target's rotation and scale, and tests one
bit: exact against any shape at any angle, with no pre-rotated masks. Body
against body samples a coarse lattice of the smaller sprite's solid texels
the same way. Group ranges are scanned whole at first; a grid can replace the
scan without touching the interface.

**Particles.** Position, velocity, age, life, style, seed. The style table
gives color ramp, size curve, drag, gravity and an optional pull toward the
player. Drawn additively in linear light.

**Director, rank and bonuses.** One serial invocation holds everything that
is awkward in parallel: the state machine, the wave script, and rank. Rank
rises with survival and firepower and falls on a hit; enemy counts, speeds
and shot density read it. Bonuses read it too, in rate and in strength, so a
harder game pays more.

**HUD.** Drawn by the GPU from the game block; the CPU never formats a
number. The displayed score chases the real one, so it rolls. Each bonus slot
records when it was collected and animates from that with its own curve.
Damage sets one timestamp that the HUD, the shake, the vignette and the
rumble all read, with a few frames of hit-stop from the director.

**Backgrounds.** Several procedural layers in one fullscreen pass, each a
pattern function, palette and scroll factor from the wave table, scrolling
sideways at their own rates and crossfading between stages.

**Sound.** XAudio2. Effects are rendered by a compute pass at start from
recipes in the tables, read back once, and submitted to a pool of voices on
triggers, with a little random pitch on the CPU. Music follows as looped
stems whose gains track `intensity`; the loop position returns as `beat`.

**Input.** Keyboard and mouse, and an XInput pad when present, merged into
the same four fields. Rumble goes back out from the events.

## Files

| File | Owns | State |
| --- | --- | --- |
| `shared.inc`, `shared.asm` | The boundary blocks; the generated shader header | Built |
| `machine.inc` | Window, contract, pipelines, the frame, events | Built; proved by the spine |
| `proofs\` | Each proof, its checks, and what to look at | Three so far |
| `tables.inc` | The table macros and the game's data | |
| `pictures.inc`, a packer under `tools\` | The frame table; baked art into a blob | |
| `input.inc`, `audio.inc` | Pad and rumble; XAudio2 voices and the bank | |
| `myhits.asm`, `*.slang` | The game | |

One addition went into `examples\common`: device-local buffers in the pools,
for the world. One is still to come: a present-mode choice in
`vulkan_wsi.inc` for a `--low-latency` switch.

Build order: assemble `shared.asm` to write the header, compile and validate
the shaders against it, assemble the program with the SPIR-V embedded.
`SLANGC=` on the `build.cmd` line substitutes another Slang compiler. The
clang under `C:\git\llvm-project` compiles plain HLSL to SPIR-V but rejects
pointers, so it cannot stand in today.

## Proofs

Every idea is proved small before the game leans on it, and the proof stays
in the tree with its documentation: what it claims, how it is checked, what
to look at. A proof fails by number. Findings go under the proof and, when
they change a rule, into this plan.

| # | Proof | Milestone | State |
| --- | --- | --- | --- |
| 00 | survey: what the machine offers | | Passes here |
| 01 | style: the toolchain takes the pointer style; offsets agree | 0 | Passes |
| 02 | spine: the boundary end to end | 0 | Passes; two findings, both adopted |
| 03 | pictures: baked, generated and vector frames in one buffer; masks beside them; a turning chain under its light plane | 1 | |
| 04 | motion: every easing curve drawn and checked against reference values; the missile's program traced | 2 | |
| 05 | hits: mask collision counted against a reference computed outside the GPU | 3 | |
| 06 | sound: the bank rendered and compared; a trigger's delay measured | 4 | |

## Milestones

0. **Spine.** Done.
1. **Pictures and sprites.** The frame table, the three sources, masks,
   filtered pulling, the light plane; the ship under keyboard and pad.
2. **Motion.** The easing library and move programs; shots and the missile.
3. **Hits.** Mask collision, particles, events.
4. **Sound.** The bank and triggers.
5. **Opposition.** Kinds, waves, rank, chains, the director.
6. **Reward.** Bonuses, the animated HUD, damage you feel, the companion's
   three stages.
7. **Atmosphere.** Backgrounds, music and beat, tuning.

## Open

- **How baked art is authored.** A frame size and count convention for
  Blender output, and whether the light plane is a painted overlay or baked
  normals, are best settled against a first real asset.
- **Pad layout.** Which stick aims, and what the second button does before
  the companion exists.
- **How long the scripted runs may take.** Proofs so far finish in seconds;
  the game's checks will want a budget.

## Risks

- The director is one GPU thread. If draining 2048 spawn requests a frame is
  slow, the queue is partitioned by group and drained in parallel.
- Waiting for the device each frame trades throughput for latency. If a
  heavy frame makes that visible, the simulation moves to its own queue.
- Debugging game logic in shaders has no debugger. The `debug` words in
  Events and RenderDoc are the tools; scripted runs make failures repeat.
- Pool sizes and pass costs are estimates until their milestone measures
  them.
