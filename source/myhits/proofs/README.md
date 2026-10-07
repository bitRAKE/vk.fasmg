# myhits proofs

Each idea the [plan](../plan.md) rests on is proved here before the game is
built on it, and the proof stays: a small program or script, the claims it
checks, and what to look at when you run it yourself. When a proof surprised
us, the surprise is written down under it.

Most of what 02 to 06 prove is no longer the game's alone: it lives in
[source\common](../../common/README.md), the layer the game is built on, and
these are that layer's proofs as much as the game's. The layer stands on the
projection alone, and every run holds it to that: each program's map names
one object, its own, and no source under `source\` includes one of the
examples'.

```bat
rem Build every proof and run its checks:
build.cmd myhits-proofs
rem The same, repeated under core and synchronization validation:
build.cmd check-myhits
rem What this machine offers; builds nothing:
build.cmd myhits-survey
```

`check-myhits` is part of `build.cmd check`. Reports and debugger logs land in
`build\myhits_checks\<mode>\<proof>\`.

So do pictures. A scripted run draws to a window nobody sees, so proofs 04
to 07 each leave `frame_NNN.png` there: the whole playfield at 1920×1080, at
the frames of the script worth looking at. The game's twenty-five are its swoopers,
its weavers, the worm coming and then turned back on itself, the turrets
firing with the level stopped, the run over; and of the second game three
volleys with RAPID and SPREAD in force, the nova going off, the shield about
to take a rammer, the worm's head under fire, and the companion: where the
ship was, acting for itself, and taking the player's aim; the dragon, in the
second place's inks; one frame drawn as a paused one is, dimmed under its
two bars; and of the third game, on its bare stage, the dash through a shot,
a diver's fix shaking round the ship, its lock, its heavy shot on the way
with the crosshairs fading, the burst, the second's shot coming for where
the ship no longer is, and the third's, loosed as the diver died, coming for
a ship that killed it and stayed; and of the fourth, TABLES TAKEN along the
top of an empty field, and the five that then came where three had been.

| # | Proof | Claim | State |
| --- | --- | --- | --- |
| 00 | [survey](00_survey/survey.ps1) | The target GPU, the system libraries and the shader compiler offer what the plan uses | Passes here |
| 01 | [style](01_style/style.slang) | The shader toolchain accepts the pointer-only style, and lays the boundary blocks out as the assembly does | Passes |
| 02 | [spine](02_spine/spine.asm) | The whole CPU–GPU boundary works on the device within the plan's traffic budget | Passes, with two findings |
| 03 | [pictures](03_pictures/gallery.asm) | Every frame, cut, made or drawn, is made and masked on the device and drawn from it with nothing bound; a picture that turns is still lit from one side | Passes, with three findings |
| 04 | [motion](04_motion/range.asm) | The easing curves are the textbook's; the simulation runs at a fixed tick; bodies run the tables' programs and end each move exactly where it says; the level's own pace is eased, to a stop and back | Passes, with three findings |
| 05 | [hits](05_hits/arena.asm) | What is drawn is what is hit, by its mask, at any angle, size and speed; what is hit takes it and dies of it; a hit throws off exactly the particles and sounds it should; a touch hurts the ship and a near miss does not | Passes, with two findings |
| 06 | [sound](06_sound/board.asm) | The bank the device renders is the recipes'; a sound asked for in one frame's events is on a voice as the next begins; many in a frame are one voice at their mean | Passes, with three findings |
| 07 | [game](../myhits.asm) | The game itself: what comes is what the table says; a chain follows its head exactly and dies with it; only the director makes a body; rank reads the shooting; a hurt costs a life, once; the level stops for what is anchored to it and moves on | Passes, with two findings |

## 00 survey

Reads the system; proves nothing about our code. For each GPU it lists the
features of the contract and the ones the shaders lean on, then checks that
`xaudio2_9.dll` and `xinput1_4.dll` export what sound and gamepads will call.

On this machine: the GTX 1080 Ti is Vulkan 1.4 with every contract feature;
descriptor heaps are absent, which the plan does not need. With `-Clang` it
repeats one more test:

```bat
powershell -File source\myhits\proofs\00_survey\survey.ps1 -Clang C:\git\llvm-project\build-native\bin\clang.exe
```

**Finding.** That clang (23, with the SPIR-V target) compiles plain HLSL to
valid Vulkan SPIR-V but rejects the pointer style: `pointers are unsupported
in HLSL`. The build therefore uses the SDK's `slangc`. `SLANGC=` on the
`build.cmd` line substitutes another Slang compiler.

## 01 style

Three shaders written the way the game will write them, compiled and
validated; none of them runs.

- `collide`: a shot against every enemy by mask. The shot's center goes into
  the target's mask space through the inverse of its rotation and scale and
  one bit decides. Damage, the particle ring and the sound trigger are atomics
  on memory reached through pointers.
- `sprite_vertex`: an instance pulled through a pointer; a dead sprite's
  corners collapse.
- `sprite_fragment`: a texel pulled from a buffer.

The checks, over these and the spine's modules:

1. Every module is valid SPIR-V for Vulkan 1.3 with scalar layout (the build
   runs `spirv-val` on each).
2. Every module reaches memory through pointers and declares no image,
   sampler or descriptor set.
3. No module declares `DrawParameters`.
4. Every member of `Root`, `Events` and `Trigger` sits at the offset the
   generated header prints beside it: 240 member offsets across 8 modules.
   The header is written by assembling `shared.inc`, so this is the assembly's
   layout and the compiler's agreeing.

What it does not show: that mask collision gives the right answers. That needs
a device and a reference, and is the proof that comes with collision.

## 02 spine

The first thing that runs on the GPU: 1024 motes drift about a 1920×1080
playfield and the controls move one of them. It exists to carry every kind of
traffic the plan allows, once, and nothing else.

```bat
build\myhits_spine.exe
build\myhits_spine.exe --self-test
```

**To look at.** Run it without arguments. Arrows or WASD move the white mote;
it should feel immediate. The title shows the frame count, how many frames
late events are read (it should say 1), how many motes are near the player
(the stand-in for a sound trigger) and how many pixels the draw shaded. Drag
the window wide or tall: the playfield keeps its shape inside bars. Click
another window: it stops drawing, and takes no CPU, until it is in front
again or resized.

**How it is made.** The CPU sends 72 bytes a frame as push constants and
reads 512 back; that is all. The world is device-local memory the CPU never
maps; a compute pass fills it at start. Each frame is two compute passes and
one draw:

- `direct`, one invocation: clears the frame's event slot and moves the
  player from the controls.
- `advance`, one invocation a mote: moves it, and reports by atomics.
- the draw: six vertices an instance with no vertex or instance buffer; the
  vertex shader pulls the mote and the fragment shader pulls its texels.

**The checks**, on 120 scripted frames with a fixed step. The program holds
every frame's events to them and reports the first failure by number.

| # | Claim | How it is held |
| --- | --- | --- |
| 1 | Events arrive once each, in frame order | `Events.frame` counts up from 0 |
| 2 | Atomics through pointers into host-visible memory lose nothing | Every mote adds one; each frame reads exactly 1024 |
| 3 | The same into device-local memory, across frames | The running total at frame N is N × 1024 |
| 4 | Controls read for frame N move the player in frame N | The script goes right for 30 frames, then down for 30; the player's position in each frame's events is where that makes it |
| 5 | The draw really pulled its texels | Between 50% and 85% of the motes' squares are shaded: a disc's share. A draw that ignored the texels would shade all or none |
| 6 | Events are in hand when the very next frame begins | Read exactly one frame late, every time |
| 7 | A sound trigger's pan stays a sum of on-screen offsets | Its magnitude is at most count × 960 |
| 8 | Every frame's events were read | 120 of 120 |
| 9, 10 | The traffic is Root down and Events up, and nothing more | Byte counters equal 120 × 72 and 120 × 512 |
| 11 | A frame is two dispatches and one draw | Command counters |
| 12 | A window of another shape keeps the playfield's | One more frame at 1200×500: the playfield is 888×500 inside bars, and fewer pixels are shaded than at 960×540 |

The script then checks the executable imports neither Vulkan nor GDI and that
the run was clean under validation.

Last result here, GTX 1080 Ti, default and validation alike: all twelve hold;
183,509 pixels shaded at 960×540 and 157,148 at 888×500.

**Finding: `SV_VertexID` costs a feature.** Slang's `SV_VertexID` and
`SV_InstanceID` subtract a base, which declares the SPIR-V `DrawParameters`
capability and so needs `shaderDrawParameters` enabled. Validation caught it
on the first run. The shaders use `SV_VulkanVertexID` and
`SV_VulkanInstanceID`, which are the raw indices, and check 3 of proof 01
keeps it that way.

**Finding: presentation makes events late unless the frame waits.** The
first version read events three frames late, on screen and scripted alike.
With FIFO presentation a program can queue frames ahead, and a queued frame's
commands, its compute passes included, wait for a swapchain image. So the
simulation ran when the picture could, not when it was submitted, and the
controls it used were as stale as the events were late. Now a frame begins
only when the device has finished the one before (`machine_await`): events
are one frame late, always, and the controls are read as late as they can be.
This is in the plan as a rule of the frame.

## 03 pictures

Every picture the game will draw, from all three sources, in one run of
texels on the device with a mask beside each: a gallery of the frames over
their masks, a chain that turns under a light that does not, and the ship
under the keys and the pad.

```bat
build\myhits_pictures.exe
build\myhits_pictures.exe --self-test
```

**To look at.** Run it without arguments. The top rows are every frame in
[art.txt](../art/art.txt), each over the mask the device made of it in green:
the mask should be the picture's silhouette, holes and all. Below them the
light sprites turn and swell; their halos should brighten what they cross,
not darken it. Watch the chain: every piece turns as it follows its road,
and the bright side of every piece stays toward the upper left. Arrows, WASD
or a pad's left stick or d-pad move the ship; the mouse or the right stick
carries the crosshair. The title gives the share of lit fragments that lie on
the lit side of their sprite, and what the share would have been had the
light turned with the pictures.

**Where the pictures come from.** [art.txt](../art/art.txt) lists every
frame, whatever its source:

- **cut** from a sheet of ideas by `tools\cut-art.ps1`, which removes the
  panel behind the sprite, cleans its edge for blending, and writes a PNG
  beside art.txt. This is authoring: it needs the sheets, which are not in the
  repository, and its PNGs are committed. Run it with `-Sheet out.png` to see
  every result over a dark and a light ground.
- **made** on the device by a generator in
  [pictures.slang](../../common/pictures.slang): a spark, a shock ring.
- **drawn** on the device from strokes written in art.txt itself: capsules,
  discs and rings. The crosshair and the shield are drawn.

The build runs `tools\pack-art.ps1`, which packs the PNGs into
`build\myhits_art.bin` (with a plane of normals for frames marked `light`)
and writes the table of every frame for the assembly and for the shaders.

**How it is made.** The program embeds the packer's block. At start it goes
into host-visible memory, once, and three compute passes make the pictures in
memory only shaders touch: `develop` writes every texel (copying the cut
ones, computing the rest), `chart` derives every mask word from the texels'
alpha, and `census` counts each frame and compares it with what the packer
said. Then the packer's block is let go. A frame of the proof is one compute
pass, which sets down all 107 sprites, and one draw, which pulls sprite, frame,
texels and normals through the root pointer.

**The checks**, on 120 scripted frames:

| # | Claim | How it is held |
| --- | --- | --- |
| 1 | Events arrive in order, one frame late | As in the spine |
| 2 | Every cut frame is on the device exactly as packed | For each, the device's count of solid texels (from its own mask) and its sum over the texels equal the packer's; the total is the packer's total |
| 3 | The other frames were made there | None is empty, and each drawn frame covers what the packer's own reading of its strokes covers, to within its edge's rounding |
| 4 | A frame said to be symmetric is | Its mask equals its mirror, bit for bit |
| 5 | The masks are what is drawn | At half size the gallery's masks cover a quarter of all solid texels in pixels, and its pictures, by their own filtered alpha, cover the same, each within a sixteenth |
| 6 | Controls read for frame N move the ship in frame N | As in the spine |
| 7 | One pass set down every sprite the draw pulls | It reports 107 |
| 8 | The light stays put while the pictures turn | Summed over the run, at least 85% of the chain's brightened fragments lie on the lit side of their sprite, and at most 70% would have with the light turned with the picture |
| 9 | The traffic is Root down and Events up | Byte counters, as in the spine |
| 10 | Three passes make the pictures; a frame is one pass and one draw | Command counters |
| 11 | The pad maps as designed | Six made-up pad states through `pad_apply`: nothing inside the dead zone, 1 at the rim, a half halfway, up is up, the d-pad and buttons |

Last result here, GTX 1080 Ti, default and validation alike: all eleven hold.
41 frames (18 cut, 2 made, 21 drawn), 243,025 texels and 7,491 mask words;
430 KB goes up once and the pictures take 980 KB on the device. The device
counts 52,469 solid texels in the cut frames, as the packer did. The gallery's
masks cover 16,878 pixels and its pictures 16,874, against a quarter of the
solid texels at 16,973. Of the chain's brightened fragments 90% lie on the lit
side; with the light turned with the pictures it would be 43%.

**Check 2 bites.** Flipping one bit of one texel in the embedded block, in a
copy of the program, fails check 2 at frame 0.

**Finding: `Frame` is not a name the assembly can use.** proc64 has a
`frame` keyword, matched without regard to case, so a boundary block called
`Frame` assembles as its prologue. The block is `Picture`; a frame is still
what it describes.

**Finding: light needs a different cut than matter.** A sprite of matter is
cut by connectivity: the panel reached from the cell's edge goes, the largest
piece left is the sprite, and only its rim is part transparent. A bolt or an
explosion has no rim. Its alpha is how far each pixel stands out from the
panel, and the threshold has to sit above the haze the sheet paints around
its light, or the haze comes along as a box. Such frames are marked `glow`,
and drawn with their alpha squared as coverage, so a halo adds light and only
a core covers.

**Finding: one blend does both.** Texels are premultiplied in linear light
and stored sRGB-encoded, which keeps 8 bits where the eye needs them. With
that, `ONE, ONE_MINUS_SRC_ALPHA` covers where alpha is 1 and adds where it is
0, so matter and light share a pipeline and a draw, in whatever order the
sprites lie.

## 04 motion

The easing curves, and what is built on them: a simulation that steps 120
times a second whatever the display does, bodies that run programs of eased
moves from [tables.inc](../tables.inc), and a level whose own pace is eased.

```bat
build\myhits_motion.exe
build\myhits_motion.exe --self-test
```

**To look at.** On the left wall are the 31 curves, each drawn by evaluating
it: LINEAR alone at the top, then a row a family (quad, cubic, quart, quint,
sine, expo, circ, back, elastic, bounce) with IN in amber, OUT in blue and
INOUT in green. A dot rides each curve, and under each plot a second dot only
slides from left to right by the curve's value: that one is what the curve
feels like as motion.

On the right is the range. Space or the left mouse button fires; shots leave
at once and at speed. Shift or the right button launches a pair of missiles:
each drifts out to its side, turns to face the crosshair, and goes; the upper
one leaves a trace. Arrows or WASD move the ship, and a flare and a muzzle
flash show the controls the instant they are read. Three hostiles come by in
turn: one loops the loop, one weaves, one rears back to look at you and
dives. None of them is code: each is a few lines of table.

Watch the specks and the purple core. The specks are the level, passing at
its pace. The core belongs to the level: it rides in with it. Then the level
slows to a stop, the core holds the screen with it, and both move on. The
hostiles and your shots fly on regardless. The title shows the ticks run this
frame (none or one on a fast display, two at 60 Hz), the level's pace, and
shots fired and missed.

**How it is made.** A frame runs as many ticks as real time has earned. A
tick is two passes: `direct`, alone, moves the ship from the controls, sets
the pace and makes every new body; `update` advances every body one tick of
its program, reading last tick's copy and writing this one's. A last pass,
`report`, writes the frame's events. The draw shows each body between its
last two ticks. The curves on the wall are a second draw of 31 quads whose
fragments evaluate the curve; they reach no memory at all.

**The checks**, on 200 scripted frames of two ticks each. The script moves
the ship for ten frames, launches at frame 20 with the crosshair fixed, and
holds fire from frame 60 to 99.

| # | Claim | How it is held |
| --- | --- | --- |
| 1 | Events arrive in order, one frame late | As in the spine |
| 2 | The curves are well formed | The device examines its own: each is 0 at 0 and 1 at 1 exactly; an OUT is its IN turned about the middle; an INOUT passes through it; none but bounce ever goes back; only back and elastic pass outside 0..1, and they do |
| 3 | A scripted frame is two ticks | The device's tick count is 2 × frames, every frame |
| 4 | Controls read for frame N move the ship in frame N | Through both ticks: ten units a frame |
| 5 | A move ends exactly where it says | The missile's 42 ticks of OUT_CUBIC end at (930, 480), its launch point plus its offset, to a hundredth |
| 6 | FACE faces | After 18 ticks of INOUT_SINE its heading is the angle to the crosshair, to a thousandth of a radian |
| 7 | THRUST reaches its speed, on the line | After 60 ticks of IN_EXPO its speed is 2400, its heading unchanged, and it lies within half a unit of the line from where it turned to the crosshair. Then its program is over and it coasts |
| 8 | The level's pace is eased, and what rides the level rides it exactly | The anchor's position and the scroll sum to 1760 in every frame; for the 40 frames the level stands the scroll does not change by a bit; the anchor has stopped at 1501, which is where 129.5 ticks at full pace put it |
| 9 | Accuracy is counted where it happens | 14 shots and 2 missiles fired; with nothing to hit, 16 left the playfield and none is flying. And the level came 520 |
| 10 | The traffic is Root down and Events up; a frame of two ticks is five passes and two draws | Counters, and the draw pulls the 610 sprites the shaders lay out |
| 11 | A press comes from its message | A key down between frames is pressed and held for one frame and not the next; the keyboard repeating a key is not a press; a pad's press is the edge of what it holds |
| 12 | A stall is not chased | With the clock set a second back, a frame earns eight ticks and owes nothing after; the next earns none |
| 13 | A body can be hurried, and still ends each move where it says | The first missile's twin is told to go twice as quick, which is how rank hurries what is hostile. Its offset takes 21 ticks and not 42: it is still in it at frame 29 and done at frame 30, exactly at its own, mirrored, offset |

Then the script reads `build\myhits_motion.curves.bin`, the 31 curves by 65
samples the device wrote where the CPU could read them, and holds each to
[curves.cs](04_motion/curves.cs): the same curves written the long way, one
formula each as easings.net gives them, in double precision. The two share
no code and no structure.

Last result here, GTX 1080 Ti, default and validation alike: all thirteen
hold, and the device's curves are within 4.9 × 10⁻⁷ of the second implementation
(the worst is OUT_ELASTIC). The tables it runs are under a kilobyte.

**The checks bite.** An offset of 41 for the missile's 40 fails check 5 at
frame 40. A back constant of 1.70258 for 1.70158 puts OUT_BACK 1.5 × 10⁻⁴
from the second implementation, over the bound of 10⁻⁴.

**Finding: `kind` is not a word a table can begin a line with.** A macro is
seen by every line of every source, on every pass. `kind` is a field of half
the structures in the tree, and a macro of that name took all of them. The
tables say `mover NAME` and still number them KIND_NAME.

**Finding: a joined name reaches a macro unjoined.** `shared EASE_IN_#family`
defined the right symbol and wrote `EASE_IN_#QUAD` into the shader header,
because the header line is made from the argument's text. The curve names
are spelled by a macro of their own.

**Finding: a pass that reaches no memory is not a fault.** Proof 01 demanded
that every shader use pointers. The plot of a curve needs none: it computes.
The demand is now what it should have been: nothing is bound.

## 05 hits

Collision by masks, and what comes of it: shots that strike what they are
drawn to strike, bodies that take hits and die of them, particles, the sounds
asked for, and the ship being hurt.

```bat
build\myhits_hits.exe
build\myhits_hits.exe --self-test
```

**To look at.** A ring stands in the middle and nothing can break it. Space
or the left button fires at it: each shot stops at the ring's edge, not at
the square its picture fills, and throws sparks back the way it came. Move up
or down until your shots just clear the ring: they pass through the corner of
its picture and fly on. Shift or the right button throws a lance, which is
fast enough to be on one side of the ring's wall at one tick and far past it
at the next; it strikes the wall all the same. The skull above takes three
hits, flashing white at each, and bursts on the third. Now and then two
rammers cross: the first passes just over the ship and does nothing, the
second comes along its row, and the ship flashes as it is hurt, once. Enter
asks for 500 particles at once and gets the 128 its style allows in a tick.
The title counts shots fired, struck and missed, the score, the hurts and the
particles alive.

**How it is made.** A point is tested against a picture by taking it into
the picture's own texels, with the inverse of the turn and scale that set the
picture down, and reading one bit of its mask. No mask is ever turned or
scaled, so a hit is exact at any angle and size. A shot is not a point but
the step it took this tick, seen from its target, which has moved too; the
step is walked a texel at a time. Circles reject first. A body against the
ship sets every sixth solid texel of the ship down on the playfield and looks
each up in the body's mask.

A tick is now five passes. After `direct` and `update` come `collide`, one
invocation a shot, which finds the nearest thing its step struck, writes its
own death, and reports the rest by atomics: damage to the target's slot,
sparks into the particle ring, a sound; then `resolve`, one invocation a
body, which takes its damage, dies of it or not, and says whether it touches
the ship; then `drift`, one invocation a particle. Particles are a ring of
16,384. Any pass may ask for some; each style admits only so many a tick.
They are drawn with no texel at all: a particle is its own falloff, and adds.

**The checks**, on 280 scripted frames:

| # | Claim | How it is held |
| --- | --- | --- |
| 1 | Events arrive in order, one frame late | As in the spine |
| 2 | What is drawn is what is hit | At start, every texel of every frame is set down on the playfield as the draw sets it and brought back as a hit is, through four poses (plain; turned 37° at 1.5; turned 143° at 0.75 and mirrored; on its side at 2). It comes back solid exactly where its mask is, and through each pose the cut frames' solid texels number what the packer counted in the PNGs |
| 3 | Every shot is accounted for | In every frame, fired = struck + escaped + flying |
| 4 | A shot strikes where the picture begins | Four shots along the ring's middle row are logged between 1332.4 and 1334.1: the ring's first solid texel there is at 1332.5, and the walk meets it within a texel |
| 5 | Nothing is too fast | A lance covers 50 units a tick and the ring's wall is 12 thick: it is never inside the wall at a tick, on either side of the ring. It strikes, at the same place |
| 6 | The corner of a picture is not the picture | Four shots 70 above the ring's middle pass through its picture's square, clear of the ring, and strike nothing |
| 7 | Three hits kill | The drone is alive after two, dead at the third for its 150, and the fourth shot passes where it was |
| 8 | A touch hurts, once; a near miss does not | A rammer 110 above the ship is inside its circle and outside its mask: nothing. One along its row hurts it once, though it is inside the ship for a dozen ticks, and the rumble in the events says so for half a second after |
| 9 | Particles are exactly what was asked for | Six sparks a hit and 48 for the death; 500 asked of a style in one tick, 128 let in; 224 in all, and by the end every one has lived its life and gone |
| 10 | The sounds are the events | Summed over the run, the triggers are 12 shots, 1 launch, 8 hits, 1 death, 1 hurt: what happened |
| 11 | The traffic is Root down and Events up; a frame of two ticks is eleven passes and two draws | Counters |
| 12 | Nothing slips through a corner | A wall one texel thick lying across the diagonal, whose texels touch only at their corners. Of 400 crossings square to it, each a little farther along it than the last, so that some go through the middle of a texel and some exactly between two, every one strikes |

Last result here, GTX 1080 Ti, default and validation alike: all twelve hold.
52,469 solid texels come back through each of the four poses. 13 fired, 8
struck, 5 escaped.

**The checks bite.** Testing only where a shot lands, not its step, fails
check 4 at frame 31 (so that run never reached check 5, which the same change
should also fail). Taking a hit into the picture mirrored fails check 2 at
once. Using circles in place of masks for the ship fails check 8 at frame 198,
when the near miss hurts.

**Finding: `sound` cannot name an iterate's parameter.** The loop that adds
up the triggers read `Events.sound` with a parameter called `sound`, which
made it `Events.SOUND_SHOT`. The trap is the old one; it is easier to fall
into from `iterate` than from a macro.

**Finding: three shaders reach no memory now, and the check names them.** A
particle's fragment computes its own light. Proof 01 lists the shaders that
may reach nothing; any other that stops reaching memory fails it.

## 06 sound

The game's sounds are not files. Each is a recipe in
[tables.inc](../tables.inc): a wave whose pitch sweeps from one frequency to
another along an easing curve, risen in a few milliseconds and fallen away
along another curve, with a share of noise. The device renders them all once,
into memory the CPU can read, and XAudio2 plays from there.

```bat
build\myhits_sound.exe
build\myhits_sound.exe --self-test
build\myhits_sound.bank.wav
```

**To look at, and to hear.** Run it without arguments: this one makes noise.
Each row is a sound, drawn from its samples and as wide as it is long. Space
or the left mouse button plays the shot; Shift or the right button the
launch; Enter the hit, the burst and the hurt in turn. A sound is played
where the mouse is, from the left speaker to the right. Hold the mouse still
and tap Space quickly: no two shots are quite the same pitch. The title shows
how long the last sound took from its controls being read to being on a
voice, and what the engine says it adds after that.

The checks write the bank as `build\myhits_sound.bank.wav`: every sound,
end to end, exactly as the device made them, for any player. To change a
sound, change its line in tables.inc, build, and listen to that file.

**How it is made.** One compute pass at start writes every sample: the pitch
is the area under its curve, summed by Simpson's rule, and the noise is a
hash of the sample's place, so the bank is the same on every run. A frame's
events carry, for each sound, how many times it was asked for and the sum of
where; when the next frame begins the CPU gives each sound asked for to the
next of sixteen voices, once, louder for being many, set between the speakers
at the mean of where, and a little off pitch. XAudio2 is called from the
assembly through its interfaces' tables; nothing else stands between.

**The checks**, on 100 scripted frames, with the mastering voice at nothing:

| # | Claim | How it is held |
| --- | --- | --- |
| 1 | Events arrive in order, one frame late | As in the spine |
| 2 | The bank is well formed | The device examines its own: every sound begins at silence, ends within a hundredth of its gain of it, is never louder than its gain, and reaches at least a quarter of it |
| 3 | What a frame asks for goes to a voice as the next begins | Frames 10 to 50 ask for each sound once, as scripted; each is one more sound on a voice when that frame's events are read |
| 4 | Many in a frame are one voice, louder, at their mean | Five hits at 200 to 1000 are one voice at 600: 0.882 of it left and 0.471 right, at twice one hit's level |
| 5 | The voices are a ring | Twenty shots in twenty frames after five others: 25 sounds on 16 voices, and no voice refused one |
| 6 | The engine plays what it is given | Where there is an audio device, soon after the run no voice has a buffer left |
| 7 | The traffic is Root down and Events up; a frame is one pass and one draw | Counters. The bank comes back once, at start |

Then the script holds the device's bank to [bank.cs](06_sound/bank.cs), which
makes the same sounds a second way: in double precision, with the sweep
summed sixteen times a sample, and with the curves of proof 04's second
implementation. A sample may differ by a five-hundredth of full scale; a
thousandth of them may differ by more, since a square or a saw has edges and
a sample on one can fall either side in single precision.

Last result here, GTX 1080 Ti, default and validation alike: all seven hold.
14 sounds, 213,120 samples, 4.44 seconds. One sample differs from the second
implementation by more than a five-hundredth, on the edge of a square wave,
where a thousandth of them may; it is nearly all of the 3.0 × 10⁻⁴ rms
between the two. 25 sounds went to 16 voices and were played out. The engine
reports 1,937 samples of its own latency, 40 ms.

**The checks bite.** Swapping left and right fails check 4 at frame 30.
Summing the sweep over 31 intervals in place of 32 puts 62,005 samples
outside the allowance.

**Finding: the engine's own latency is 40 ms here, not 10.** The plan
reckoned a frame plus XAudio2's 10 ms quantum. XAudio2 reports 1,912 samples
between a voice starting and its sound leaving, on this machine's output.
From controls to voice the program adds a frame; the rest is the engine's and
the device's, and is the larger part. The plan says so now.

**Finding: XAudio2's structures are packed to the byte.** Its header packs
them, so `XAUDIO2_BUFFER` is 44 bytes with its last pointer at 36, not the 48
and 40 a compiler would lay out by default. And a voice is not a COM object:
its table begins with its own methods, with no three for the interface first.

**Finding: a voice forgets what it has played.** `SamplesPlayed` returns to
nothing when a stream ends, so it cannot show afterwards that a sound was
played. Check 6 asks instead whether anything is still waiting.

## 07 game

From here the proof is the game. [myhits.asm](../myhits.asm) and
[myhits.slang](../myhits.slang) put everything the proofs above settled into
one world, and its own scripted run holds it to the rules of play.

```bat
build\myhits.exe
build\myhits.exe --windowed
build\myhits.exe --fullscreen
build\myhits.exe --self-test
rem Change the tables under a running game (see "Reloading", below):
powershell -File source\myhits\tools\watch.ps1 -Play
rem Keep a run as it is played; play it back, and go on from where it ended:
build\myhits.exe --record
build\myhits.exe --replay
rem The scripted run as it sounded, and how loud everything in it is:
build\myhits_run.wav
build\myhits_checks\default\game\run.md
build\myhits_music.wav
```

**To look at, and to play.** Arrows, WASD or a pad move; Space or the left
mouse button fires; Shift or the right button launches a pair of missiles at
the crosshair, which follows the mouse; Ctrl, the middle button or a pad's
right shoulder dashes. P pauses and resumes; F11 or Alt+Enter gives the
window the whole of its monitor and takes it back; Esc ends. What comes is in the `squad` lines of
[tables.inc](../tables.inc): three swoopers, four weavers, then the worm, a
head and nine segments that uncoil from where it came in and follow it
through every turn. Shoot the head ten times and the worm goes segment after
segment, from the head back. Then two turrets ride in on the level, the level
stops for them, and they fire at where you are; when the divers come it
moves on. Then the dragon: a head and twelve segments that come in and go
round and round on the right, the head chasing its tail and loosing three
shots your way each half turn. The level stops for it and nothing else comes
until its head is dead; then the table begins again, in a new place, a
little quicker for every pip of rank: everything hostile goes about its
moves faster the higher rank is. A hit on the ship costs one of three
lives and two seconds of blinking in which nothing more can hurt. With none
left the run is over, and the world goes on without you until Enter. The
score, the lives and rank are on the screen, drawn by the device from its
own game block: the score rolls up to what it is and its digits jump when it
grows; a life lost shrinks away red; rank is ten pips, green to red. A hurt
is felt: the world stops for four ticks, the picture is thrown about for
half a second, its edges redden, and a pad shakes.

A kill may leave a bonus, more often the higher rank is, and it drifts back
toward you; come near it and it is yours. RAPID halves the wait between
shots; SPREAD makes each three; SHIELD takes the next hurt, and turns round
the ship while it lasts; NOVA strikes everything on the playfield at once, in
a flash; DOUBLE doubles what a kill is worth. Each has a slot along the
bottom of the screen that jumps when it is taken, each in its own way, shows
its time running out in pips, and blinks before it goes.

Behind it all is the backdrop: clouds far off, a lattice of diamonds, a
ridge along the bottom with its echo along the top, and rails at the very
edges, each passing at its own rate, the nearer the faster. It is the
level's: when the level slows for the turrets all of it slows, and when the
level stops it stands. Each time the table of squads has been gone through
its inks change, from blue to magenta to green.

There is music, and it listens. Three voices, each thirty-two notes in
[tables.inc](../tables.inc), composed on the device after the sounds: a bass
that is always there, drums that come in as the playfield fills, and a lead
over them when it is full. Where the music is in its beat goes back down to
the device, and the lattice's nodes strike with it. The checks write the
three together as `build\myhits_music.wav`.

And you do not stay alone. Kill the worm's head and something comes out of
where it died: a companion, joined to the ship by a thread of light. At
first it is only where you were: it keeps 150 behind you along your own
path, and fires when you fire. The next head makes it act for itself: its
gun turns to whatever is nearest and fires, and its guard, an arc of light,
turns to face the nearest shot coming and stops what reaches it there. The
third gives its gun to you: it points from wherever the companion is to the
crosshair, and fires while you do. Its shots are its own: they do not count
for or against your accuracy.

**Charge.** Under rank's pips are eight more: charge, full when a run
begins. A pair of missiles costs a quarter of it and a dash a fifth; with
too little there is a click and nothing happens. It comes back by killing (6
hundredths a kill), by taking a bonus (12), and by flying close: a hostile
shot that passes within 95 of the ship's middle and does not strike pays 3,
once, and flashes as it does.

**The dash** is 320 units in an eighth of a second, the way the ship is
going, or ahead if it is going nowhere. While it lasts and for a moment
after, the ship is half there and hostile shots pass through it. Bodies do
not, and bursts do not.

**The hail-mary.** Hurt a diver past half and leave it alive, and it does
one last thing. It stops, trailing embers, and fixes on the ship: brackets
appear round the ship, shaking, closing in, and following wherever the ship
goes. After a second they stop where the ship is and become crosshairs, as
wide as what is coming will reach. A third of a second later the diver
looses one heavy shot at the crosshairs and is thrown back the other way by
it, and goes. The shot leaves slowly and gathers speed; the crosshairs fade
as it comes, all there at its launch and gone as it lands; and where they
were, it bursts. Be outside the crosshairs when it lands and there is no
harm. That is the only answer. Killing the diver does not stop the shot: one
that dies before it has fired looses it as it dies, at where its fix then
is, or at where the ship is if it had not begun to fix. The kill chooses
when the crosshairs fall; then the ship has to go. A nova, which strikes
everything for three, leaves every diver on the field at exactly half.

**The window.** It has no caption and no frame. The first time, it takes the
whole of its monitor; after that it comes back as it was left, a window
where it was or the whole monitor, which the registry keeps under
`HKEY_CURRENT_USER\Software\vk.fasmg\myhits`. `--windowed` and
`--fullscreen` say otherwise for one run. As a window it is the playfield's
own 1920 by 1080 where there is room to spare for that, and 1280 by 720
where there is not, until it is sized; a pixel of it is a pixel of the
monitor whatever Windows scales other programs by. While the game plays,
the pointer is the crosshair: the arrow is hidden and cannot leave the
window, so a press cannot land on another program. P pauses, and so does
leaving for another program (Alt+Tab, the Windows key) or making it an icon;
coming back does not resume, P does. Paused, the picture dims under two
bars and says what the keys are, the arrow is back and free, and the window
is all handle: press and
hold anywhere on it to move it, or within ten pixels of an edge or a corner
to size it. Over the whole monitor it does not move. That is an ordinary
window still, not exclusive and not topmost: other windows come and go over
it. A paused window draws one frame and then waits, using nothing.

**How it is made.** Before anything, one pass copies the header and the
tables from where the CPU wrote them to memory of the device's own. A tick
is the five passes of proof 05. The director
alone reads the wave table, eases the level's pace, looks at the shooting
once a second to move rank, and makes every body, the ones other bodies
asked for among them. A hostile asks in cells that are its own, four for
what its program fires and two for what its death does, and the director
reads the cells in order: nothing is contended for, nothing overflows, and
what is made where does not depend on which thread ran first. And the
director looks for room: a new body goes where nothing is, a chain where a
whole run is free, and what there is no room for is refused and counted,
except one of a squad, which waits. A chain's head lays its path into a ring of points eight units
apart; a segment reads its head as the head stood last tick and takes the
point its own distance back.

**Reloading.** The tables are also a file, `build\myhits_tables.bin`, and a
game started with `--watch` takes them from it whenever it is written:
`source\myhits\tools\watch.ps1` writes it whenever `tables.inc` is saved.
A number changed there is on the screen a second or two later. The game says
TABLES TAKEN along the top, everything that was running by the old tables
goes, and the squad that was on the screen comes again from its first. What
cannot be taken so is a change to the names the shaders know: the game says
TABLES REFUSED and goes on with what it had. A watched game does not pause
when it is left for the editor. [plan2.md](../plan2.md) has the whole of it.

**The checks**, on 1,330 scripted frames of eight ticks: a first game played
badly to its end; a second that is given every bonus, earns the companion,
and is left to run until the dragon has come and gone; a third on a bare
stage, with no squads, where the script sets down what it wants seen; and a
short fourth, like the first, for the tables to be changed under.

| # | Claim | How it is held |
| --- | --- | --- |
| 1 | Events arrive in order, one frame late | As in the spine |
| 2 | What comes is what the table says, when it says | Nothing alive at frame 12; three swoopers at frame 37; the second and third squads begun by frames 100 and 145 |
| 3 | Every shot is accounted for | In every frame, fired = struck + escaped + flying |
| 4 | Rank reads the shooting | A second survived adds a hundredth. Eight shots at nothing take six thousandths off at each of the next two looks, to nothing. A look at which every resolved shot had struck adds thirty-four thousandths. A hurt takes fifteen hundredths, or all there is |
| 5 | A chain follows its head exactly | While the worm comes straight on, its first segment is 112 behind where the head stood a tick ago, on the head's line, to a twentieth of a unit. Once all of it is out and turning, all nine segments are alive and no two neighbors are more than 112.6 apart or less than 104 |
| 6 | A body cannot make a body | The first turret's FIRE is no pellet by frame 258 and one in frame 259: a request in one tick, a body in the next |
| 7 | A hurt costs a life, once | Hurts and lives always sum to three; no two hurts come within the grace; the run is over exactly when no life is left, and stays over until Enter, which begins another with three lives and no score |
| 8 | The level stops for what is anchored to it, and moves on | From frame 290 to 335 its pace is nothing and it has not come a bit farther; by frame 352 it is at full pace |
| 9 | Kill the head and the chain goes with it | In the second game the worm's head is shot as it comes; five frames after the frame it dies in, at least ten fewer are alive |
| 10 | Those things were seen | The rise and the falls of rank were each checked at least once, and the head did die |
| 11 | The sounds are the events | Each sound a frame asked for went to a voice once, none was refused, and every hurt was heard |
| 12 | The traffic is Root down and Events up; a frame of eight ticks is 41 passes and four draws | Counters |
| 13 | The score on the screen chases the real one | It is never more than the real one, and by the end of the run it is the same |
| 14 | A hurt is felt | Each stopped the world for exactly four ticks; and what the pad is told is what the events say: all of the heavy motor is 65535, half of the light one 32768 |
| 15 | A bonus is taken by coming near it, once | The second game is given one of each in front of the ship; each is in hand, and only one of it, a few frames after it was set down |
| 16 | The shield takes the next hurt | It is held from frame 418; a rammer comes along the ship's row; by frame 505 the shield is spent on it and all three lives remain |
| 17 | RAPID halves the wait and SPREAD makes each shot three | Three frames of fire are four shots plain; they are eight with RAPID, and twenty-four with both |
| 18 | A nova strikes everything, and DOUBLE doubles exactly | In the frame the nova is taken or the next, the drone set down for it dies with whatever swoopers were left; nothing that can be hit is alive after; and the score has grown by exactly twice their worth at the rank of the moment |
| 19 | The companion comes as a surprise, and grows | None until the worm's head is killed, and one two frames after. It is where the ship was: the first point of the ship's trail while the ship has not gone 150, then 10 past the corner once the ship has gone 160 on; and it has fired with the ship. Made more, its guard stops a pellet sent at it and its gun's shots strike while the player fires nothing. Made more again, its gun points from where it is to the crosshair, to a hundredth of a radian |
| 20 | The level waits for a boss | The dragon is the sixth squad of the second game. Long after it has come, it and its twelve segments are all there, no squad has come after it, and the level stands. The script strikes its head dead; ten frames on the chain is gone, and by frame 995 the table has begun again and the level is at full pace |
| 21 | The backdrop is the level's | Held on the pictures themselves, by the proof runner: along the top rail, frames 300 and 320 are the same to the pixel, the level having stood still between them; frames 235 and 300 are not |
| 22 | The music is its notes, and follows the play | The device finds every stem it rendered loud enough and no louder than its gain. With nothing happening only the bass is wanted, with everything all three, each at its own level. Where there is an audio device the stems are playing, and say where in the beat they are. And the proof runner holds the device's stems to a second synthesis of the same notes, as it does the sounds |
| 23 | The window has its manners | Asked of the window by its own messages, with no one at it. P pauses: the next frame is paid no ticks and carries `ROOT_PAUSED`. Paused, the window says its middle is a handle, its left edge an edge and its corner a corner; playing, or over the whole monitor, that all of it is the game's. F11 gives it exactly its monitor's rectangle and then exactly the one it had. Leaving it pauses it and coming back does not resume it. And the pointer was never taken |
| 24 | Charge is earned and spent | On the stage. A new run has all of it. A pair of missiles takes a quarter. A dash takes a fifth and carries the ship exactly 320, through a shot set down in its way: the shot is counted as passed through, once, and no life is lost. A shot sent by 85 above the ship pays three hundredths, once. A kill pays six. With 19 hundredths left a launch and then a dash are each refused: two clicks counted, nothing fired, nothing moved |
| 25 | The hail-mary is its beats | On the stage, three divers, each hurt to half by the script. The fix is where the ship is, frame after frame, while the ship is moved. It locks where the ship then was. The heavy shot's mark is the lock, and how much of its way is left grows less every frame; what loosed it is never nearer the lock than when it fired, and is seen to go. It bursts within a unit of the lock. The first time the ship has stayed: one life, by the burst. The second it has dashed 320 away after the lock: nothing. The third diver is struck dead while it is fixing, and the ship stays: its shot comes all the same, for where the fix was, bursts there, and costs a life. Three shots burst in all |
| 26 | The window is remembered | Under a name of the check's own, so what a player left is not disturbed. With nothing remembered it is to have the whole monitor. Left as a window at a place, it comes back to that place as a window. Left over the whole monitor, it comes back so, and to the same place when the monitor is given up |
| 27 | Nothing alive is written over | On the stage. A worm's head is struck dead and something else set down in its slot the tick after: the nine segments die of their head's death all the same, and none takes the newcomer for it. Then a flood. Of 400 hostile shots 384 are made and 16 refused. Of 400 drones as many are made as there were places free, and the rest refused. Five places side by side are emptied and a worm asked for: it needs ten, and is refused whole. Of ten drones asked for then, five are made and five refused. Every drone made is still itself afterwards, by the sum of the numbers they were given; and at the end of the run it is all as it was |
| 28 | Two runs are the same run | Held by the proof runner. The device sums everything it simulates, every body in its slot and the game with it, at the end of each of the four games. The script is run a second time at once, and again under validation: all three runs give the same four sums |
| 29 | A tick is within its budget | Held by the proof runner, from what the game measured of itself: the device's own clock, stamped after every pass, and its mean over the run for each of a tick's five passes held to a budget several times what it was when the budget was written. Under validation the numbers are shown and not held |
| 30 | The level's distance is exact however far it has come | Asked by the device at start, of the functions the backdrop is drawn by, with the level three thousand million units on: five months at full pace. The layers that repeat are, to the bit, what they are at the start. The layers that do not still move as the level does: twenty-five units more of travel is the far layer one unit to the left, and ten is the ridge three. Every speck is where it would be |
| 31 | A pause is in words | Held on the pictures, by the proof runner: where the line that says what the keys do is drawn, the frame drawn as a paused one has letters, pale on the dimmed picture, and a frame that is not paused has none |
| 32 | The tables are taken again while the game runs | Images of the tables are offered from files, between frames, as a watched game is offered them. One with the game's names and a few things changed (`07_game\tables_alt.asm`: a first squad of five and not three, a squad more, a shot's sound twice as long) is taken: the frame after says so; the device's own sum of the tables it holds is the file's, and what it makes of how many lines each table has is the file's too; the bank is another bank, in which the music is sample for sample what it was, further in; and the music is playing from there. One with a kind the game was not built with (`07_game\tables_bad.asm`) is refused, which is said, and nothing changes. The game's own, by the watcher: the device holds it and the bank is to the bit the bank made at start. The watcher again: the file is as it was and is not looked into. The game's own outright: no change. All of that is in the first game's first frames, before anything has come, and the three games after it sum to what they always did. The fourth game is where there is something to let go of. The changed image is taken in the very tick the first squad is due: the squad loses none to that. With two of its five out, the game's own: within the frame the two are gone and the squad has begun again, as three. With those three out and their squad done, the changed image again: the three are gone, the squad has begun again, and five come. Before the run, images spoiled five ways are each told for what they are: not an image, tables that do not come to what it says, a file shorter than it says, other names, too large. And a whole image of the game's names is still refused if anything in it points outside it: the game's own does not, and eight spoiled ones do, by a kind whose moves begin past the last, a picture that is none, a squad of no kind, a move that goes back past the first, a move that fires no kind, a sound that does not begin where the ones before it end, moves that do not end as a program ends, and a table gone altogether. And on the pictures: the frame after a taking has words along its top, and a frame long before has none |
| 33 | The run can be listened to, and nothing in it is out of line | Held by the proof runner. The scripted run keeps what every frame asked of the voices and of the music, and writes out the sounds as the device rendered them. [mix.cs](../tools/mix.cs) plays the first three games back into `build\myhits_run.wav` the way `audio.inc` would: sixteen voices in turn, a sound's level by how many asked, its place by where it happened, its pitch a little off, the stems coming and going with how much is happening. Every sound the run asked for is in what was kept; the mix's level is between 40 and 6 decibels under all a speaker goes to; fewer than one sample in ten thousand is louder than that, and none by three decibels; and no sound's level is more than twelve decibels from the middle of them. `run.md`, beside the run's pictures, is the table |
| 34 | A run that was recorded is the same run played back | Held by the proof runner. As the scripted run goes, every frame's ticks, steering, aim, buttons and flags go to a file, and so do the tables it takes on the way, whole: 70 KB for 1,330 frames and five takings. The game is then run from that file and not from its script. Every frame's sum of the world is folded into one number in each run, and the two numbers are the same |

Last result here, GTX 1080 Ti, default and validation alike: all
thirty-four hold. A tick costs the device 62 microseconds: 15 for the director, 8 for
the bodies, 31 for the shots, 4 for the struck, 4 for the particles. A
picture, at the unseen window's 960 by 540, costs 103, nearly all of it the
backdrop. (Of a device left idle. One just played on is a third quicker in
all of it: see the finding below.) The report, which in a scripted run sums the world and counts its
pools on one thread, costs 730; a played frame's report does neither. The run is 10,640 ticks, 54,530 passes and 5,320 draws, and takes about ten
seconds. The world is 855 KB on the device. The nova went off in frame 468
and the head died in frame 557; 186 sounds went to voices. In the third
game the first diver's shot burst in frame 1090 and cost a life; the
second's burst in 1145 with the ship 320 away; the third diver was struck
dead in frame 1164, and its shot burst in 1187 and cost another.

**Claim 32's checks bite.** Fifteen ways of getting it wrong were each seen
to fail it. Before the run: other names taken, too large an image taken, a
file cut short taken. In the first game: a device never told, and the
counts of the game's own tables kept for an image that has one squad more
(frame 3); a refusal not said (5); tables not laid down at all (7); a
watcher that forgets what it saw (9); a bank not rendered again, music not
begun again, voices not stopped first, and the same tables taken for a
change (11). In the fourth: squads asked for in the tick the tables are
taken, which costs the squad its first (1272); bodies not let go, and a
squad not brought again (1273). And eight more before the run, one for each
way an image can point outside itself: with any one of those questions not
asked, a spoiled image passes for a sound one.

**Claim 33's checks bite.** A blast four times as loud stands 15.9 dB from
the rest and cuts off 2,672 samples; a bass four times as loud cuts off
52,368; and a run that keeps only every other frame has 95 of its 186
sounds. Each fails it.

**Claim 34's checks bite.** Presses not played back, tables in the record
not taken again, an aim not recorded, and one frame of 1,330 not recorded:
each comes to another number, the last to another count of frames too.

**What 34 cannot hold.** That a run somebody played comes back: the script's
frames are all of eight ticks and none of them paused, and a played run's
are of none, one, two or more as the clock has it. The record keeps every
frame, the empty ones too, so that nothing has to be argued; but it has not
been seen.

- [ ] `build\myhits.exe --record`, play a minute, be hurt, end it with Esc.
  `build\myhits.exe --replay`: the same minute, the same hurt, and then the
  ship is yours again where the record stopped.

**What 33 cannot hold.** That the mix is what XAudio2 plays: `mix.cs` is
`audio.inc`'s rules told a second time, and nothing holds the one to the
other but reading them side by side. And that any of it sounds good:

- [ ] Play `build\myhits_run.wav`. It is the scripted run, eighty-five
  seconds of it: a first game played badly, a second with every bonus, a
  third on the stage with three heavy shots. Is anything too loud, too
  quiet, too like something else? `run.md` says which sound is which level.

**Finding: the mix runs out of room.** Its level is 21.7 dB under all a
speaker goes to, and its peak is 1.1 dB over: five samples of eight million,
37.4 seconds in, where bursts and the music land together. Nothing limits
what sixteen voices and three stems add up to. It is five samples; it is
also the first number anyone has had for how loud this game is.

**Finding: a broken program can break more than itself.** One mutation was
not among those fifteen as it was first written: the counts of the tables
never written at all. It seemed to pass. It had not: the game could not
start, left no report, and the harness read the report of the run before.
It was run twice more, to see why. Each of the three runs left the device
reading counts that were never set, each put a burst of errors from the
display driver in the system's log, and the machine was restarted to be rid
of what that left behind. So, since then: a change that would leave the
device with garbage is reasoned about and not run, and the counts' check is
bitten instead by counts that are valid and wrong; the harness deletes the
last report before it runs anything; and a program that dies on the device
is not run again to see. And the game itself now asks first: no image is
laid down, from a file or from a record, until `tables_sound` has found
that nothing in it points outside it.

**Finding: a voice is emptied when the engine comes round to it.** Stopped,
emptied, given the music again and started, each stem's voice was asked at
once how many runs of samples it held, and said two: the old one was still
there. A moment later it said one, and that one was the new: the voice
names what it is playing, and it is where the music now is in the bank. The
check waits for that, a quarter of a second at most. Without the stopping
and emptying it never comes: the new music waits for ever behind a loop
that does not end, which is one of the fifteen.

**Finding: nothing that has not come can be disturbed.** Four offers of
tables in the first game's first frames, two of them taken, changed nothing
that followed: the three games after them were held to every claim they
were held to before there was such a thing as taking tables, and summed to
the same three numbers.

**The checks bite.** Each of these was made and seen to fail the check it
should: segments a tenth too far apart (5, at frame 150); the director
ignoring requests (6, at 259); a grace of half a second (7, at 312); rank
moved by a twentieth (4, at 29); the level ignoring a squad's pace (8, at
290); segments that outlive their head (9, at 567); a bonus that cannot be
reached (15, at 418); a shield that takes nothing (16, at 505); a RAPID
that changes nothing (17, at 432); a DOUBLE that changes nothing (18, at
469); a companion 100 behind and not 150 (19, at 568); a guard that stops
nothing (19, at 600); a gun that ignores the aim (19, at 630); a squad that
holds nothing (20, at 900); and a drum's thump a semitone sharp puts 24,140
of the music's 576,000 samples outside the allowance. Seven ways of getting
charge wrong each fail 24: missiles that are free (at frame 1006); a dash a
tick short, or one that slips nothing (1014); a near miss that pays every
tick it is near (1036); a kill that pays nothing (1204); a launch, and a
dash, with no charge to pay for it (1210, 1216). Twelve of getting the
hail-mary wrong each fail 25: a fix that does not follow the ship (1050), or
never locks (1067); a diver thrown forward and not back, and crosshairs that
do not fade (1068); a shot that follows the ship after the lock (1125); a
burst sixty to one side of the lock (1090), one that hurts nobody (1091),
one that reaches 400 (1146); a dying diver's shot sent at its own wreck and
not its mark (1164); a third diver left alive (1172); and, at the end, where
the turns are counted, a diver that being hurt to half changes nothing in,
and a kill that cancels the shot, which is how it was first built. Three ways of forgetting the window each fail 26: its
place, whether it had the monitor, and that the first time it is to. Four
ways of making room wrongly each fail 27: taking the next slot whatever is
in it, making a chain where only its first place is free, and refusing
without counting (all at frame 1236); and segments that follow whatever is
in their head's slot (1228). And for 28, a body that lets the order its
thread arrived in move it a hundredth of a unit: no check inside the run
notices, and two runs' sums differ at the end of every game. For 30, a
share of the level's travel taken with a float: by a layer that repeats, by
a layer of noise, by the specks. And
nine ways of getting the window wrong each fail 23: a pause that does not say so, or
still pays ticks; a paused window that is not a handle, or has no edges; one
over the whole monitor that still is a handle; a whole monitor a pixel
short; a window that comes back a pixel off; leaving that does not pause;
and coming back that resumes.

**What 23 cannot hold, and a hand must.** The check asks the window what it
would do; it cannot be the hand that does it, and it runs with no one at it,
so that the pointer is never taken is true of it for more than one reason.
These want trying, once, by whoever plays:

- [ ] Playing, the arrow is gone and the pointer cannot leave the window, on
  any side, with more than one monitor.
- [ ] P, Alt+Tab and the Windows key each give the pointer back at once, and
  the picture shows the two bars.
- [ ] Paused, a press and hold in the middle moves the window, to another
  monitor too; near an edge or a corner it sizes it, and the picture fits
  the new size when the button is let go.
- [ ] F11 and Alt+Enter each take the whole of the monitor the window is
  mostly on, and give back the place and size it had. Over the whole
  monitor, paused, a press and hold moves nothing.
- [ ] Other windows brought over it stay over it; it does not flash, change
  the monitor's mode, or jump in front.
- [ ] On a monitor Windows scales (125%, 150%), the picture is sharp, not
  stretched.
- [ ] The first run of all takes the whole monitor. Left as a window
  somewhere, the next run is a window there; left over the monitor, the next
  run is over it, on the same monitor.

**What 32 cannot hold, and a hand must.** The script offers tables; it does
not save a file in an editor, hear a sound, or leave the game for another
window. Once, by whoever is changing the tables:

- [ ] `powershell -File source\myhits\tools\watch.ps1 -Play`. In
  `tables.inc`, make the first squad's 3 a 6 and save. Within two seconds
  the game says TABLES TAKEN, what was on the screen is gone, and six come.
- [ ] Click the editor: the game goes on behind it, and does not pause.
- [ ] Change SHOT's pitches and save; fire. It sounds different, and the
  music did not stumble for longer than a blink.
- [ ] Add a `tone` line and save: TABLES REFUSED, and the game goes on as it
  was. Take the line out again and save: TABLES TAKEN.
- [ ] Put a mistake in a line and save: the tool shows the assembler's
  complaint, and the game goes on with what it had.
- [ ] Start the game without `--watch` and save the tables: nothing happens.

**What 24 and 25 cannot hold, and play must.** The checks hold that these
things happen as written. Whether they are any good is not a thing a check
can say:

- [ ] The dash: is 320 far enough to matter and near enough to aim? Does it
  go when asked? Is the click of an empty meter understood?
- [ ] Charge: does it run out, and does flying close and killing bring it
  back fast enough to want to?
- [ ] The hail-mary: is the fix seen in time, among everything else? Is the
  lock heard? Is the second and a half enough, too much? Does a hurt diver
  now get finished first, which is the point of it?
- [ ] The sounds of all of it, which the checks play to nobody.

**Finding: a check may ask the wrong question and be answered yes.** The
level's distance was a float that only grew. It is now whole units and a
part, and each layer takes its share in whole numbers. The first check of
the layers that do not repeat asked whether, with the level very far on,
they still changed from each pixel to the next: a float's travel was
expected to make them stand in steps. With the float put back for them, the
check passed. In this arithmetic a float's travel does not coarsen the
layer in space; it coarsens when the layer moves, in steps of thirteen
pixels. The check now asks that: that so much more travel is the layer so
much to the left. Three ways of taking a share with a float each fail it.

**Finding: what a pass costs depends on what the device did a minute
ago.** The layer's own device, command and presentation code replaced the
examples', and the first measuring run after it put the picture at 103
microseconds where this page said 85. The old code, built again and measured
at once, said 73. Neither was the code. Run turn and turn about, old and new
cost the same to within a few parts in a hundred, and both drift together by
a third: a device that has just been played on is at its full clocks, and
one left idle is not. So a cost is compared only with one measured beside
it, in turns; and the budgets of claim 29 are several times the cost for
this as much as for anything.

**Finding: one thread on the device is slow, and the check could not see
it.** The first way of reading requests in order had the director walk every
hostile's cells: 2,304 steps a tick. Nothing looked wrong, every claim held
and the run took nine seconds as before, because the run is held to the
display's rate and not to the device's speed. Then the passes were timed.
The director took 565 microseconds a tick, sixty times what it had; cut
short before the walk, 10. A lone thread on the device spends about a
quarter of a microsecond on every step of a loop that reads memory. So the
director walks no pool now. A hostile that asks raises a bit, and the
director reads twelve words of bits; the companion's nearest hostile and
nearest shot are found by those pools' own threads, each saying how near it
is and an atomic minimum keeping the least; and the report sums and counts
only in a scripted run. The director is 15 microseconds again, and claim 29
holds every pass to a budget from now on.

**Finding: where the tables are makes no difference that can be measured.**
The header and the tables were in memory the CPU can see, and every pass
read them there. A pass now copies them to memory of the device's own at
start, which was the plan's long-standing answer to a cost it expected. The
passes cost the same before and after, to the microsecond. It is kept: it is
the right place for them, and it leaves the CPU's copy free for reloading.

**Finding: a run that is over is still a world.** The first script meant to
stop the squads when the last life went. But then the level, stopped for the
turrets, would never be told to move on, and the script's later checks would
depend on when the player happened to die. The squads come whoever is
playing; only the player's ship, and fire aimed at it, wait for Enter.

**Finding: a stop showed that the script's ship had been hurt all along.**
The hit-stop of milestone 6 failed the chain's check at frame 162, where no
hurt was expected: a weaver clips the ship there, and had done since the
game first ran. The check compares the head "a tick ago" with a segment now,
and in a tick the world stands still the head a tick ago is where it is. The
check skips frames that held a stop; the chain was never wrong.

**Finding: a picture that turns with its heading ends up on its head.** The
dragon goes round, and half the way round its head was upside down: a
picture that looks left, turned to go right, is turned over. Kinds marked to
keep the right way up are now mirrored instead, and since a hit must be
taken into the picture the same way it was set down, the mirror is in both;
proof 05's third pose is mirrored to hold them together.

**Finding: a check that cannot fail is not one.** The backdrop's first check
ran on the device: each layer, asked for a point with the level farther on,
against the same layer asked for the point moved that far. It passed, and
would have passed whatever the layers did, because both sides were the same
sum. It was taken out. What holds the backdrop to the level now is the
pictures: the same row of two frames, the same to the pixel when the level
stood still between them and different when it did not.

**Finding: an angle that only ever turns can end up anywhere.** The
companion's gun was turned a quarter of the way to its target each tick, by
the shortest way, and never brought back within a turn. After a while of
following targets it pointed the right way at an angle a whole turn off, and
the check, which compared numbers, said it was wrong. It was the code that
was: an angle kept is an angle kept within a turn.

**Finding: the ship cannot be kept safe by standing still.** Every row of
the playfield is crossed by something. The script's checks of lives are
therefore rules that hold whenever a hurt comes, not hurts expected at
frames.

## Writing the next one

A proof is a directory here, a row in the table above, and a section saying
what it claims, what to look at and what its checks are. It should fail by
number, as the spine does, so a report says which claim broke. And it should
leave pictures: define MACHINE_SNAPSHOT, keep the frame's draws in
`draw_world`, and ask for the frames worth seeing
([snapshot.inc](../../common/snapshot.inc)). The one kind of proof that cannot is one
whose fragments count themselves, as 02's and 03's do.

These assembler traps have cost time; each now has a comment where it bit:

- A macro parameter is substituted inside dotted names too. A parameter named
  `alignment` turns `boundary.alignment` into `boundary.8`.
- A dotted constant such as `Root.frame` is found from inside a procedure only
  if `Root` itself is a defined symbol.
- A `proc` nothing refers to is not assembled. A test of a procedure in
  isolation passes vacuously unless the procedure is made `public`.
- `frame` is proc64's, in any case: no symbol may be called `Frame`.
- A macro takes every line that begins with its name, in every source. Name
  table macros with words nothing else begins a line with.
- An included file with no `section` of its own goes into whatever section
  is open. `bitmap.inc` included after a data section put its code there, and
  the first call to it was an access violation.
- A variable may not have an instruction's name. `monitor MONITORINFO ...`
  assembles as the instruction, defines nothing, and every use of it then
  says the symbol is undefined.
