# myhits: plan

A fast horizontal shooter whose world lives on the GPU. This is the plan we
iterate on. What has been proved is marked so and lives, runnable, in
[proofs](proofs/README.md); everything else is intent.

## Settled

Decisions taken, in the order they were asked:

1. **Horizontal.** The playfield scrolls sideways, so there is room to see
   what is coming and time to be impressed by it. Sideways does not mean
   relentless: the level's pace is a thing the game eases. It slows for a hard
   enemy and stops for an anchored one or a boss, and moves on afterwards.
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
- Every picture is made, masked and drawn on the device from one list, and a
  picture that turns stays lit from one side. Proof 03.
- The simulation steps 120 times a second whatever the display does; bodies
  run programs of eased moves that end exactly where they say; the level's
  pace is eased by the same curves. Proof 04.
- What is drawn is what is hit, by its mask, at any angle, size and speed; a
  hit throws off exactly the particles and sounds it should. Proof 05.
- The sounds are recipes the device renders into a bank, sample for sample
  what a second implementation makes; a sound asked for in one frame is on an
  XAudio2 voice as the next begins. Proof 06.
- The game: waves by a table, chains that follow their head exactly, hostile
  fire through the director, rank from the shooting, lives, and a level that
  stops and moves on, in one world of 753 KB. Proof 07, the game's own run.

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
    float   time, blend;  // 16  seconds the picture shows; where it stands between the last two ticks
    uint    frame, ticks; // 24  and how many ticks this frame runs
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

The pictures are the first of these to exist, and show the pattern. The
packer writes the frame table from [art.txt](art/art.txt) with its `FRAME_*`
numbers for both sides; `Picture`, `Stroke` and `Pictures` in shared.inc are
its layout; the table and the cut texels go up once, the device makes its own
copy, and the uploaded one is let go. The `Census` block is what the device
found when it did, and a proof reads it back through Events.

### World: GPU only

| Pool | Capacity | Notes |
| --- | ---: | --- |
| Sprites | 8192 × 64 B, twice | Read last frame's copy, write this frame's: no races, no tearing |
| Spawn queue | 2048 requests | Appended atomically by parallel passes, drained by the director |
| Trails | 64 × 256 points | One ring per snake head, and one for the player |
| Links | 256 | A pair of sprite slots and a style |
| Particles | 65536 × 32 B | A ring; the oldest are overwritten |
| Pictures | as the art needs | Texels of every frame, packed, with normals for those that ask; see below. 539 KB for the first 22 frames |
| Masks | one bit a texel | Derived on the GPU from the pictures' alpha, so they match what is drawn |
| Game | one block | Clock, rank, player, bonuses, HUD timers, cursors, damage accumulators |

Sprite slots are partitioned by group in fixed ranges: 16 player parts, 240
pickups, 1792 enemies, 4096 enemy shots, 2048 player shots. A group is a
contiguous instance range, so layers draw in order without sorting and
collision loops know their bounds.

## The frame

| # | Step | Runs as | Writes |
| --- | --- | --- | --- |
| 0 | await | CPU | Waits for the device to finish the last frame, plays its events' sounds, then reads the controls and says how many ticks real time has earned |
| 1 | direct | one invocation | Clock, rank, game state, bonuses; moves the player from input; creates every new sprite: waves, the player's shots, and whatever the spawn queue asked for |
| 2 | update | per sprite | Its own slot in this frame's copy: its motion program, trail samples; requests for shots into the spawn queue |
| 3 | collide | per shot and per hostile | Damage accumulators and pickup counters by atomics; its own death; sparks; sound counts |
| 4 | resolve | per sprite | Its own health, death and hit flash; score; explosions; drops into the spawn queue; HUD timers |
| 5 | particles | per particle | Its own slot, in place |
| 6 | draw | background, sprites by group, links, particles, HUD | The swapchain image |

Steps 1 to 5 are one tick, and a frame runs as many as real time has earned:
none or one on a 165 Hz display, two on a 60 Hz one. A last small pass
reports the frame to its events whether a tick ran or not.

Rules that keep it honest:

- **The simulation runs in ticks, 120 a second.** What happens does not depend
  on the display: a hit, a spawn, a scripted run are the same at 60 Hz and at
  165. There are two copies of every body, the last tick's and this one's; a
  pass reads the one and writes the other, and the picture stands between
  them by `Root.blend`. Real time is paid out in whole ticks, at most eight a
  frame: after a stall the rest is forgiven, not chased. The time is kept on
  the device, so Root carries no clock a shader could step by. Proof 04.
- **A press is taken from its message.** A key or button that goes down and
  up between two frames is still pressed, and held, for one. Only the frame's
  first tick sees a press.

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
- **Sound follows events.** A sound is on its voice one frame after the
  controls that caused it were read: 17 ms at 60 Hz, 6 ms at 165 Hz. After
  that comes the engine's and the device's own latency, which proof 06 read
  as 40 ms on this machine: the larger part, and not the program's to shorten.

## Subsystems

**Pictures.** A frame is a rectangle of texels of any size; a picture is a
strip of frames, for animation or for rotation steps. [art.txt](art/art.txt)
lists every frame, and three sources fill the same run of texels, so there is
one way to draw and one way to collide:

- *Cut*: PNG frames, lifted from a sheet by `tools\cut-art.ps1`, rendered in
  Blender or painted by hand, packed at build time into a block with the
  frame table and copied to the device once.
- *Made*: computed by a generator in a compute pass at start. Mirrored pixel
  ships and the like: variety with no asset.
- *Drawn*: strokes written in art.txt, rasterized by the same pass at
  whatever size is asked.

A texel is premultiplied in linear light and stored sRGB-encoded. One blend,
`ONE, ONE_MINUS_SRC_ALPHA`, then covers where alpha is 1 and adds where it is
0: matter and light share a pipeline and a draw. A frame marked `glow` is
drawn with its alpha squared as coverage, so its halo adds and only its core
covers.

A frame marked `light` carries a second plane, of normals. The packer
inflates them from the frame's own alpha, as if the picture were the top of
something round; Blender or a painter can supply better ones in the same
plane. When a sprite turns its normals turn with it and the light does not:
that is the fake depth for rotating chain segments, a sphere's highlight that
does not spin with its markings. Nearby explosions can light the same plane
later.

Texels are pulled with four fetches and blended. Magnified, a texel keeps its
square and only its edge is blended, so pixel art stays crisp at any angle;
at one to one and below it is plain bilinear filtering, without a sampler. If
minified art shimmers, or the run outgrows what is sensible, pictures become
images and the root gains a descriptor index; the frame table and everything
above it stay as they are. Proof 03 holds all of this.
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

**Motion.** A kind's behavior is a short program of moves, authored in
[tables.inc](tables.inc). A body always coasts along its heading at its
speed; a move changes something on top of that, over its seconds and along
its curve: slide by an offset, slide to a target, turn to face one, turn by
an angle, come to a speed, go back and repeat. A move is computed from where
the body stood when it began, so nothing accumulates and it ends exactly
where it says. A move of no seconds happens at once and the next follows in
the same tick; a program that runs out coasts. One easing library, the in,
out and in-out of power, sine, exponential, circular, back, elastic and
bounce, serves motion, the HUD's pops, particle sizes, the camera's shake and
the level's pace. The missile is the model:

```text
mover MISSILE,FRAME_PLASMA,1.2
	move 0.35,OUT_CUBIC,OFFSET,40,-60       ; drift out to a strike position
	move 0.15,INOUT_SINE,FACE,0,0,CROSSHAIR ; settle its aim
	move 0.50,IN_EXPO,THRUST,2400           ; and go
end mover
```

Variety comes from recombining moves, not from new shader code: the three
hostiles of proof 04 are fifteen lines of table. Still to come as moves:
circling a parent, and firing.

**The level's pace.** The level moves at a speed the director eases with the
same curves, and can bring to nothing. Kinds marked as riding the level are
carried at its pace and stand still when it does; everything else flies
through it. That is how an anchored enemy or a boss holds the screen, and how
a hard enemy can be given room: the director slows the level for it and lets
it go again afterwards. Backgrounds scroll by the same number.
**The player and the companion.** One ship, moved by `move`, with a crosshair
at `aim` for what is aimed. The companion uses machinery that already exists:
as a trailer it reads the player's own trail ring some samples back, which is
"where you were" exactly; as an agent the update pass gives it two headings,
a shield toward the densest incoming fire and a gun toward the best target;
steered, it takes `aim`. A link between ship and companion is where pair
effects come in.

**Mask collision.** A point is tested against a picture by taking it into the
picture's own texels, through the inverse of the turn and scale that set the
picture down, and reading one bit of its mask: exact against any shape at any
angle, with no pre-rotated masks. Circles reject first. A shot is tested as
the step it took this tick, seen from its target, which has moved too, and
the step is walked a texel at a time: nothing is too fast to hit. The nearest
thing along the step takes it. Body against body sets every sixth solid texel
of the smaller down on the playfield and looks each up in the larger. Group
ranges are scanned whole for now; a grid can replace the scan without
touching the interface. What a hit does goes by atomics: damage into the
target's slot, which the target takes up in the next pass.

**Particles.** Position, velocity, birth, life, style, seed, in a ring. Any
pass may ask for some, and each style admits only so many a tick, so one
explosion cannot crowd out the sparks of the next hit. The style table gives
the colors and sizes from birth to death and the curve between, life, speed
and spread, drag, gravity and a pull toward the player. Drawn additively in
linear light with no texel pulled: a particle is its own falloff.
**Director, rank and bonuses.** One serial invocation holds everything that
is awkward in parallel: the state machine, the wave script, the level's pace
and rank. Rank rises with survival and firepower and falls on a hit; enemy
counts, speeds and shot density read it. Bonuses read it too, in rate and in
strength, so a harder game pays more.

Rank also reads how the player shoots. Three counts are kept where they
happen, on the device: shots fired, shots that left the playfield, and shots
that struck. A player who hits what they aim at is ready for more; one who
fills the screen and misses is not, however long they survive. Fired and
escaped are counted already (proof 04); struck arrives with the hits. How the
three become rank, over what window, is for milestone 5.

**HUD.** Drawn by the GPU from the game block; the CPU never formats a
number. The displayed score chases the real one, so it rolls. Each bonus slot
records when it was collected and animates from that with its own curve.
Damage sets one timestamp that the HUD, the shake, the vignette and the
rumble all read, with a few frames of hit-stop from the director.

**Backgrounds.** Several procedural layers in one fullscreen pass, each a
pattern function, palette and scroll factor from the wave table, scrolling
sideways at their own rates and crossfading between stages.

**Sound.** XAudio2, called from the assembly through its interfaces' tables.
A sound is a recipe in tables.inc: a wave whose pitch sweeps along an easing
curve, risen quickly and fallen away along another, with a share of noise. A
compute pass renders every recipe once into memory the CPU can read; the
voices play from there, uncopied. A frame's events carry a count and a sum of
positions for each sound; the CPU plays each sound asked for once, on the
next of sixteen voices, louder for being many, between the speakers at their
mean, and a little off pitch. Music follows as looped stems whose gains track
`intensity`; the loop position returns as `beat`.
**Input.** Keyboard and mouse, and an XInput pad when present, merged into
the same four fields. What is held is read when the frame begins; what was
pressed comes from the window's messages, and from the edges of the pad's
buttons. Rumble goes back out from the events.

## Files

| File | Owns | State |
| --- | --- | --- |
| `shared.inc`, `shared.asm` | The boundary blocks; the generated shader header | Built |
| `machine.inc` | Window, contract, pipelines, the frame, events | Built; proved by the spine |
| `snapshot.inc` | Pictures of chosen frames of a scripted run, as files | Built; used by proofs 04 to 07 |
| `proofs\` | Each proof, its checks, and what to look at | Eight so far, the last the game itself |
| `art\art.txt`, `art\*.png` | Every frame, whatever its source; the cut ones | 22 frames |
| `tools\art.cs`, `cut-art.ps1`, `pack-art.ps1` | Cutting sprites out of sheets (authoring); packing the art (build) | Built |
| `pictures.inc`, `pictures.slang` | Making the pictures on the device; pulling, filtering and lighting them | Built; proved by 03 |
| `input.inc` | The pad into Root; rumble to come | Built, without rumble |
| `tables.inc`, `tables.asm` | The table macros and the game's data; their numbers for the shaders | Kinds, moves, chains, particle styles, sounds, squads |
| `chains.slang` | A head's trail, and the segments that follow it | Built; proved by 07 |
| `common.slang` | The root, a hash, opening a frame's events, asking for a sound | Built |
| `ease.slang`, `motion.slang` | The easing curves; a body and one tick of its program | Built; proved by 04 |
| `hits.slang`, `particles.slang` | Mask collision; the particle ring, its styles and its light | Built; proved by 05 |
| `audio.inc`, `sounds.slang` | XAudio2's engine and voices; the bank rendered on the device | Built; proved by 06 |
| `myhits.asm`, `myhits.slang` | The game | Playable: squads, chains, hostile fire, rank, lives. No HUD yet |

One addition went into `examples\common`: device-local buffers in the pools,
for the world. One is still to come: a present-mode choice in
`vulkan_wsi.inc` for a `--low-latency` switch. The programs link `xinput.lib`.

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
| 03 | pictures: cut, made and drawn frames in one run of texels; masks beside them; a turning chain under a light that does not turn; the pad | 1 | Passes; three findings |
| 04 | motion: every easing curve drawn and held to a second implementation; a fixed tick; the missile's program traced; the level's pace eased to a stop and back | 2 | Passes; three findings |
| 05 | hits: every texel hit where it is drawn, counted against the packer's PNGs; swept shots; damage and death; particles by the count; sounds as events; the ship hurt by a touch | 3 | Passes; two findings |
| 06 | sound: the bank rendered and held to a second implementation; triggers to voices in one frame; many as one, panned; the engine's latency read | 4 | Passes; three findings |
| 07 | game: the game's own scripted run of two games: squads by the table, a chain behind its head and dead with it, hostile fire through the director, rank, lives, the level's pace | 5 | Passes; two findings |

## Milestones

0. **Spine.** Done.
1. **Pictures and sprites.** Done: the frame table, the three sources, masks,
   filtered pulling, the plane of normals; the ship under keyboard and pad.
   Left for when they are first needed: strips of frames for animation, and a
   pivot other than a frame's center.
2. **Motion.** Done: the fixed tick, the easing library, move programs, shots
   and the missile, the level's pace, presses from messages. Left for when
   they are first needed: circling a parent and firing as moves, and the
   sprite pool at its full size with its groups.
3. **Hits.** Done: mask collision at any angle, size and speed, damage and
   death, the particle ring with its styles and caps, sound triggers as
   counts, the ship hurt by a touch. Left for when they are first needed:
   enemy shots against the ship, pickups, and a grid in place of the scan.
4. **Sound.** Done: recipes, the bank rendered on the device, sixteen voices,
   triggers as counts and positions. Left for milestone 7: music and the beat.
5. **Opposition.** Done: the game as one program; squads by a table; chains;
   hostile fire through the director; rank from the shooting; lives. Rank so
   far adds to a squad's numbers and to what a kill is worth; how often
   hostiles fire and how fast they come are still to read it. More kinds and
   squads, and a boss, are table work for milestone 7.
6. **Reward.** Bonuses, the animated HUD, damage you feel, the companion's
   three stages.
7. **Atmosphere.** Backgrounds, music and beat, tuning.

## Milestone 5 in detail

The proofs so far are separate programs, each with its own small world.
Milestone 5 is where they become one: `myhits.asm` and `myhits.slang`, the
game, whose own scripted run is its proof (07). What it adds, and how:

- **One world.** Pictures, tables, bodies in groups (the player's shots,
  hostile shots, hostiles and their segments), damage, particles, trails, a
  spawn queue and the game block, behind one header.
- **Chains.** A head lays its path into a ring of points a fixed distance
  apart, however fast it goes. A segment is a body whose kind follows: it
  reads its head as it stood last tick, which the two copies of every body
  keep still for it, and takes the point its own distance back along the
  ring. Every segment lags by the same one tick, so there is no lag down the
  body, and nothing is read while it is written. A head that dies takes its
  segments with it, one after another; a segment that dies leaves a gap.
- **Hostile fire.** A FIRE move cannot make a body: only the director does.
  It appends a request to the spawn queue by an atomic count, and the
  director makes the shot at the start of the next tick. Hostile shots are
  swept against the ship's mask as the player's are against hostiles'.
- **Waves.** A table of what comes when: a kind, how many, where, how far
  apart in time, and the pace the level should ease to for it. The director
  reads it; rank adds to its numbers.
- **Rank.** Every second the director looks at the shots resolved since the
  last look: the share that struck moves rank up or down about a neutral
  40%, surviving adds a little, and being hurt takes a lot. Rank raises how
  many come, how often they fire and what a kill is worth.
- **Lives.** A hurt costs one and buys two seconds of grace; none left ends
  the run, and Enter starts another.

Built as written, with one change the run itself forced: the squads keep
coming when a run is over. A world that stopped with the player left the
level standing still for turrets that would never be relieved.

## Open

- **Art.** The creature atlas is the reference for quality and scale: about
  80 texels to a head, two sheet pixels to a pixel of the art. The ship is a
  stand-in from another sheet and does not match it yet. A frame size and
  count convention for Blender output is still to be settled against a first
  rendered asset; its normals would replace the packer's inflated ones.
- **How far the level has come** is a float that grows without end. Before a
  session can last hours it wants to wrap, or to be kept as a tick count.
- **Tables in host-visible memory.** Bodies read their moves there every
  tick, as the plan first said. They are about a kilobyte and the proofs do not feel
  it; if a full pool does, a pass copies the tables to the device as the
  pictures are copied.
- **The sweep takes one sample a texel along its longer side.** A wall one
  texel thick lying diagonally across a shot's way can fall between two
  samples. Nothing in the art is that thin; if something becomes so, the walk
  visits both texels at each crossing.
- **The collide pass scans every hostile for every shot.** 128 by 96 pairs a
  tick, nearly all rejected by the circles. At the full pool that is 2048 by
  1792; the grid is for then.
- **Pad layout.** Provisional: left stick and d-pad move, right stick carries
  the crosshair, A or the right trigger fires, B or X is the second button.
  What the second button does before the companion exists is open.
- **How long the scripted runs may take.** Proofs so far finish in seconds;
  the game's checks will want a budget.

## The other branch

`myhits-codex` is another take on the same game, read on 2026-10-06. Ideas
from it that this plan takes, each at the milestone it belongs to:

- **A fixed simulation tick** with a bounded catch-up, rather than one step
  of clamped real time a frame: hits and scripted runs repeat exactly at any
  refresh rate. Taken in milestone 2: `Root.dt` became `Root.ticks`.
- **Control edges gathered from window messages** between frames, so a tap
  shorter than a frame is not lost. Taken in milestone 2.
- **A swept test for shots against masks**: a fast shot walks the texels it
  crossed this tick rather than testing only where it landed. Taken in
  milestone 3, and seen from the target, so its motion counts too.
- **Trails sampled by distance travelled**, not by frame, so a chain keeps
  its spacing at any speed. Milestone 5; the proof-03 chain steps along its
  road the same way.
- **Admission caps on particles** by kind, so one explosion cannot starve the
  rest. Taken in milestone 3: a cap a tick in each style.
- **Priority events and loop state beside the sound histogram.** Counts and a
  pan sum lose which sound mattered most; a few slots of `Events.reserved`
  can carry it. Milestone 4.

Where this plan differs on purpose: the boundary blocks are defined once and
projected into the shaders, with every member's offset checked in every
module; the contract is stated with route blocks; a frame waits for the one
before, and event latency is measured rather than assumed; draws use Vulkan's
raw indices and need no extra feature; the programs are assembly throughout,
with no C++ bridge; and each proof fails by a numbered claim.

Both branches change `examples\common\vulkan_pools.inc` and
`vulkan_context.inc`, differently: this one adds `create_device_buffer`, the
other `create_buffer_domain` and two context switches. Merging both to main
will conflict there and wants one design for the pair.

## Risks

- The director is one GPU thread. If draining 2048 spawn requests a frame is
  slow, the queue is partitioned by group and drained in parallel.
- Waiting for the device each frame trades throughput for latency. If a
  heavy frame makes that visible, the simulation moves to its own queue.
- Debugging game logic in shaders has no debugger. The `debug` words in
  Events and RenderDoc are the tools; scripted runs make failures repeat.
- Pool sizes and pass costs are estimates until their milestone measures
  them.
