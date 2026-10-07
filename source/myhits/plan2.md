# myhits: plan 2

[plan.md](plan.md) built the game: seven milestones, each proved and kept.
This plan is what comes after. Its aim is a game that is worth playing and
quick to change, in that order of dependence: the tools come before the
content they make cheap. Nothing settled in plan.md is reopened here except
where a line says so.

Written 2026-10-06, on `worktree-legacy-vulkan`.

## Where it stands

- The game runs: squads from a table, chains, a boss the level waits for,
  rank that reads the shooting, bonuses, a companion in three stages, a
  backdrop that is the level's, music that listens. Twenty-three numbered
  claims hold on a scripted run, under validation too.
- Its content is thin: 23 kinds, 6 squads in one loop, 7 sounds, 3 stems of
  two bars, 2 particle styles, one place in three inks.
- It has never been tuned. Nobody has judged its difficulty, its pace, how
  generous it is or how loud. The author of its code has not heard it or
  played it.
- Changing anything costs a rebuild and a restart, and seeing the result
  means playing to it.

The last two are what this plan is about.

## Done on the way in

These were asked for with this plan, and are built and checked.

- **One design for the shared memory pools.** The two branches had each added
  device-local buffers to `examples\common\vulkan_pools.inc`, differently.
  This branch now carries the other's: `create_buffer_domain(owner, bytes,
  usage, addressable, domain)` with `BUFFER_DEVICE`, `BUFFER_UPLOAD` and
  `BUFFER_READBACK`. It is the more general of the two, it maps a block by
  what its memory type is rather than by which call made it, and
  `create_buffer` behaves as before for the examples. Every buffer myhits
  makes now names its domain. That fixed one thing in passing: the sound
  bank, which the audio voices read continuously, was in whatever
  host-visible memory came first, and is now in cached memory like the events.
- **Both of the other branch's switches in `vulkan_context.inc`.** Yes, both.
  `GPU_REQUIRE_COMPUTE` is a correction: these programs dispatch compute on
  the queue they draw with, and nothing checked that the queue could.
  `GPU_DISCRETE_ONLY` is the plan's own hardware rule made true: the context
  takes the first adapter with a graphics queue that can present and fails
  if that one lacks the contract, so where Windows lists an integrated
  adapter first the game would have run on it or refused to start. Both are
  compile-time, off for the examples, and cost nothing. The three shared
  files are now the same in both working trees.
- **The window.** No caption; the pointer hidden and held inside while the
  game plays; P to pause, and leaving the window pauses it; paused, a press
  and hold anywhere moves it and its edges size it; F11 or Alt+Enter for the
  whole monitor, as an ordinary window and not an exclusive one. Claim 23,
  and a list of what only a hand can check, in
  [proofs\README.md](proofs/README.md).

## The other branch, read again

`myhits-codex` has no commits yet; its work is in the main checkout. It was
read there on 2026-10-06, after its seventh proof.

### What its playtests say

Its notes record what was said after playing it. That is evidence about
taste, and worth more than anything in either branch's code.

| Said of that build | What it did | What it means here |
| --- | --- | --- |
| Controls responsive; star layers give depth | Nothing | Keep the one-frame latency and the layered backdrop |
| Fire and pickups too dense | Fire at 5 a second (8.3 in overdrive). A pickup at most every 2.8 s falling to 1.25 s with rank, 5 to 10 alive at once, each gone in 10 s | This game fires 20 a second, 40 with RAPID, and a kill leaves a bonus 22% to 62% of the time, with no limit on how many are out and each segment shot off a chain counting as a kill. It is very likely too dense in the same way |
| Standing still and firing is too easy | After 2 s within a ship's width, a telegraphed aimed shot every 1.65 s | Here every row is crossed by something, but nothing hunts a ship that does not move |
| Chains had gaps | Segments 48 apart with aligned phases | Here neighbors overlap, by a fifth of their width on the worm and a third on the dragon; to be looked at in play all the same |
| Art flat; sound like a piano | Cutouts from the creature atlas; shorter sounds made of noise bursts, sweeps and blast tails | The art here is from the same atlas, with normals. The sounds here are single oscillators with one envelope, and the lead is a square wave: likely the same complaint |
| The arrow, the window, clicks outside it | Borderless, pointer clipped, F11 | Done here now, as above |
| Wanted: tough heads, bodies that die in cascade, guns on the body that can be shot off, a level that slows or stops | All four | The first, second and fourth are here. Guns on a chain's body are not |
| "That seems the right amount of difficulty" | Kept as its baseline | Its numbers are the best starting point there is for tuning this one |

### What it does that this plan takes, differently

| Idea | There | Here |
| --- | --- | --- |
| Nothing alive is overwritten | Complete admission or rejection, counted | The same rule. The director looks for free slots instead of advancing a ring, and counts what it turns away |
| A link cannot follow a stranger | Handles of index and generation in separate banks | A segment already carries its head's birth tick as its seed. It checks it. No new field |
| An attack is announced | A windup marker; a barrel that locks for 480 ms | A move that aims and shows it, in the tables, usable by any kind |
| Guns mounted on a body | Assemblies of 21 nodes and 4 guns, with leases | A kind that rides a segment, with its own health and program |
| Numbers before opinions | GPU time by pass, ages of input and events, memory by domain | A measuring run, and budgets set from what it reports |
| A checklist beside each proof | Its own files | A "what a hand must check" list under each proof that needs one, as under 23 |

### What it does that this plan declines, and why

| Idea | Why not here |
| --- | --- |
| 240 ticks a second | 120 with drawing between the last two ticks shows the same motion for half the passes. A shot is swept against masks, so nothing is missed at 120 |
| Seven passes a tick, a snapshot, compaction and indirect draws a frame | Five passes and a report do the same work here. A segment reads its head as it stood a tick ago, which saves the chain pass. Dead instances cost a vertex shader's early return; at 1,266 sprites and 16,384 particles that is less than compaction would be |
| A grid for the broad phase from the start | Only the player's shots are tested against hostiles: 256 against 384 is at most 98,000 circle tests a tick, nearly all rejected, over 34 KB that stays in cache. A grid adds a pass and atomics every tick. It is measured first; and if something is needed, rows suit a horizontal shooter better than cells (below) |
| Chains that split and rejoin through request queues and leases | Nobody asked for it, and that branch's own encounters do not use it. A cheaper form is listed under action, uncommitted |
| A machine that fails by parts: gun, drive, power | It is that branch's own idea, not from the brief. It may be fun; it is not known to be, and it multiplies what must be balanced |
| A C++ bridge for sound; Python for art | This branch calls XAudio2 from assembly and has no runtime or build dependency beyond the SDKs |
| Opening over the whole monitor by default | Here the window opens as a window, and `--fullscreen` or F11 changes that. One word to change if the other is wanted |

### A collision to settle before either merges

Both branches keep their work in `source\myhits\`, and both have a `plan.md`
and a `proofs\README.md` there, a `myhits` build target and a `check-myhits`.
The shared modules no longer conflict; these do, completely. One of the two
has to move, or one has to be chosen. That is not this plan's to decide.

## Open problems

What plan.md left open, and what reading the code again for this plan found.
Each has an answer, a milestone, and the check that will hold it.

| # | Problem | Answer | When | Held by |
| --- | --- | --- | --- | --- |
| 1 | A new body can overwrite a living one. Shots, pellets and hostiles each take the next slot of a ring; a bonus dropped while the hostile ring wraps can land on a segment of the dragon | The director looks for free slots, bounded, from its cursor; a chain needs a free run. What cannot be placed is refused and counted, per pool | 8 | A flood script: nothing alive is ever replaced; refusals equal what did not fit |
| 2 | A segment trusts its head's slot | It compares its seed with the head's birth tick and checks that the slot holds a head | 8 | A head's slot reused in the tick it died: the old segments die; none follows the newcomer |
| 3 | The order of requests in a tick depends on which thread won | A body's requests go in cells that are its own; the director reads them in slot order. No atomic, no overflow | 8 | The game's two scripted runs, default and validation, report the same hash of the world |
| 4 | Nothing is timed. Pool sizes and pass costs are guesses | A measuring run: timestamps round every kind of pass, the CPU's time to record and submit, memory by domain. Budgets are written from its first report | 8 | The report is checked against the budgets, so a regression fails |
| 5 | Shots are tested against every hostile | Measured first (4), at the full pools. If it must be cut: rows. Shots fly along the playfield, so a shot stays in one or two bands of height; hostiles are listed by band and a shot tests its bands only | 8, if at all | The same hits as the whole scan, on every frame of the script |
| 6 | A shot's sweep takes one sample a texel on its longer side, and could pass a diagonal wall one texel thick | The walk visits both texels at each crossing | 8 | Proof 05: a one-texel diagonal stops a lance at every offset |
| 7 | Bodies read their tables from host-visible memory every tick | A pass copies the tables to the device at start, as the pictures are; the staging is then free for the tools (below) | 8 | The measuring run shows the difference; steady state reads no host memory |
| 8 | How far the level has come is a float that only grows | A layer keeps whole periods of its own pattern as an integer and the rest as a float below one period; each lattice adds its share of the periods to its cell number in integers, where wrapping is harmless | 8 | With a billion periods added, the periodic layers are the same to the pixel and the others as sharp |
| 9 | The thread between the ship and its companion is a row of sparks | It becomes a thing: drawn as one shape, and swept against masks like a shot. See "the pair" | 13 | Its own claims |
| 10 | There are no letters. A pause, a run that is over, a stage's name and every tool's readout need them | Sixteen-segment letters: a table of forty words in the shader and no texels, sharp at any size. Strings live in the tables | 8 | Pictures; and the pause says what P, F11 and Esc do |
| 11 | Missiles are free and unlimited | They cost charge. See "action" | 10 | Its own claims |
| 12 | The pad's layout is provisional and nothing can be rebound. A pad cannot pause | Back pauses. A settings file beside the program holds bindings, the window's place and size, and volumes | 13 | Unit checks on made-up states, as now; a hand for the rest |
| 13 | The ship is a stand-in from another sheet. No convention for rendered art | Under "art" | 9, 11 | The art report |
| 14 | A stopped world's sounds and loops cannot be expressed: events carry counts of one-shots | Loops are levels in the events, as the music's intensity is | 11 | Proof 06 |
| 15 | Nobody has heard it or played it | The tools make listening and looking cheap, and leave numbers the author can check without ears: loudness, clipping, a picture of a whole level | 9 | Their reports |

## Tools

The rule for all of them: **the proofs are the tools.** The gallery already
shows every picture over its mask. The range already runs the tables'
programs. The board already draws and plays every sound. Each becomes the
place where its kind of asset is made, by one addition they share.

### Reloading

Today the tables are assembled into the program. They will also be written as
a file, `build\myhits_tables.bin`, with a fingerprint of the names the
shaders know them by. A running program started with `--watch` looks at that
file once a second. When it has changed and its fingerprint matches, the CPU
copies it to the staging buffer and one pass settles it into the device's
tables: movers, squads, styles, recipes, notes. A changed recipe renders
again; the voices are stopped first. `tools\watch.ps1` reassembles the file
when `tables.inc` is saved, which takes about a second. The packed art gets
the same treatment.

So a number changed in `tables.inc` is on the screen, or in the speakers,
about a second after it is saved, in the program that was already running.
A change the fingerprint does not cover, such as a new kind the shaders
name, says so and waits for a build.

This is startup traffic, not a frame's: the claim that a frame is Root down
and Events up stays as it is.

### Art

What hurts now: a cut is four numbers found by eye in a paint program; a new
picture is seen only by building; there is one frame to a picture; the ship
does not match the creatures; nothing checks that a new picture belongs with
the rest.

| Tool | What it does | What it leaves |
| --- | --- | --- |
| The slicer | Finds the cells of a sheet by their frames and writes each as a ready `cut` line beside a numbered contact sheet | `build\myhits_art\cells.png`, `cells.txt`: adding a picture is copying a line |
| The gallery, watching | Reloads on a saved `art.txt` or PNG. Shows the picked picture large, over its mask, with its reach, lit by a light the mouse carries, at the game's scale beside the ship, on each stage's backdrop | Nothing: it is the look before the commit |
| Frames | A picture may be a strip: `frames n`. A kind picks its frame by time, by heading, or by health, so a thing can be animated, banked, or visibly damaged | The strip in the pack |
| Rendered art | One Blender script renders a model to a strip: orthographic, two pixels to a texel, colour without lighting, and its normals as a second strip. `baked` in `art.txt` | Settles the convention plan.md left open; replaces the packer's inflated normals where the art has real ones |
| Inks | A kind may name an ink: the same picture, tinted. An elite is its ordinary cousin in another ink | A column in `mover` |
| The art report | Every picture at the game's scale on every backdrop, and a table: texels across, share that is solid, which way its normals say the light comes from, whether its edge is premultiplied clean | `build\myhits_art\report.png`, `report.md`. A picture lit from the wrong side, or half the size of its kin, is a line in a table |

The atlas is modular: heads, bodies, tails, joints, cores, orbs. The mounted
guns of milestone 10 and the bosses of 12 are assemblies of those parts, so
the gallery will show a kind with what rides it, not only a frame.

### Sound

What hurts now: a sound is one oscillator, a share of noise and one
envelope; hearing a change means a build and a run; nothing says whether a
sound is too loud against the rest; the music is one two-bar loop; and the
description "like a piano" probably fits.

| Tool | What it does | What it leaves |
| --- | --- | --- |
| The board, watching | Reloads on a saved `tone`. Any sound from the keyboard, alone or repeated as play repeats it. Draws its samples, as now, and beside them where its energy is by pitch over time | The place a sound is made |
| Layers | `layer` lines after a `tone`, each an oscillator with its own sweep, envelope and delay, summed. A shot is a click, a body and a tail | Still one line a part |
| Noise with a colour | Noise averaged over a window of samples whose length is eased: bright to dull, or a band. It is a sum of hashes, so every sample is still computed alone | The blast tail and the hiss the first set lacks |
| Modulation | One oscillator bending another's phase, or multiplying it: metal, growl, bell. A soft clip for weight. Two oscillators a few cents apart for width | Three numbers on a line |
| Echo | The recipe evaluated again at earlier times and added, quieter: a few taps make a tail | No state: a recipe can be asked for any sample |
| Loops | `loop` lines: a sound whose length is a whole number of its periods. Events carry a level for each, as they carry the music's intensity: an engine by speed, the thread's hum, a boss's presence, an alarm at the last life | 14 above |
| Songs | Patterns of notes and an order to play them in, a section to a stage and one for a boss; a stinger that waits for the next sixteenth, so a bonus rings in time | More than two bars |
| `tools\notes.ps1` | Reads a MIDI file's track into `notes` lines | Music from any editor |
| The mix | The scripted run's events played into a file: every sound and stem at the level and time the game asked | `build\myhits_run.wav`: the game can be listened to without playing it |
| The loudness report | Level and peak of every sound and of the mix; how many samples clip; which sound stands furthest from the rest | A table the author can check without ears; a sound 12 dB hot fails |

The second synthesis in `bank.cs` follows every addition, as it follows the
recipes now: the bank on the device is still held to a reference.

### Levels

What hurts now: a level is one list of squads, one after another, each a row
of the same kind at a height and a spacing. There is no second thing
happening, no formation, no place with its own things in it, and no way to
see minute three without playing two.

**The language.** Still lines in `tables.inc`, still nothing that is code.

| Line | Says |
| --- | --- |
| `stage NAME, ...` to `end stage` | A place: its backdrop, its inks, its section of the music, its squads |
| `squad ...` with `form`, `from` | As now, and in a shape (line, vee, column, ring, wall with a gap) and from a side (ahead, above, below, behind) |
| `both` | The next squad comes with the last, not after it |
| `calm seconds` | A breath: nothing comes, and what was dropped can be gathered |
| `until clear`, `after kills n` | What a squad waits for, beyond time |
| `scenery distance, KIND, y` | Something that belongs to the place: it appears when the level has come that far, however long that took. A level that stops makes it wait |
| `boss KIND` | A squad that holds, as now, with a bar and a name |
| `deck` and `card KIND, count, cost` | What the director may draw when the list is silent, to a budget that rank raises: endless play that is not a loop |

Two clocks, then: squads by time, scenery by distance. That is the idea of a
level that can slow or stop, carried through.

**The theatre** is the game started with `--theatre`.

| Control | Does |
| --- | --- |
| `--stage n --from seconds` | Starts there. The run is replayed from its start without drawing. The scripted run already does 1,100 ticks a second with its draws, so a minute of level should cost a few seconds at most; the measuring run will say |
| `[` and `]`, `,` and `.` | Slower and faster; one tick back or on. Back is the replay again, one tick shorter |
| G | A ghost: nothing hurts |
| `-` and `=` | Rank down and up a pip |
| Tab and a click | A kind, by name; one of it where the crosshair is |
| The overlay | The squad's name, what is alive, the budget, what was refused |

**The strip.** `tools\strip.ps1` runs a stage unseen and tiles a picture every
two seconds into one wide image with the squads' names: a level on a page,
to be read, compared before and after an edit, and looked at by someone who
cannot play it.

**Runs kept.** `--record` writes what the controls were, tick for tick;
`--replay` plays it back. With problem 3 solved, a replay is the same run.
A bug is a file. And every run appends a line to `build\myhits_runs.csv`:
how long, the score, rank over time, accuracy, hurts and what did each,
bonuses taken by kind, kills by kind. Tuning then has numbers to start from.

## Presentation

What there is: one place in three inks, sprites lit from one side, two styles
of spark, a HUD of digits and pips. What would make it various, cheapest
first.

| What | How | Cost |
| --- | --- | --- |
| Light from what happens | Up to eight lights a frame: the ship's muzzle, each burst, a nova, a boss's mouth. Every picture with normals takes them; so does the ridge of the backdrop | A loop of eight in one fragment shader. The normals are already there |
| Things break as themselves | A death throws the dead thing's own texels: sparks placed on its mask and coloured from its picture | One flag on a kind and one on a style |
| Things show damage | Frames by health; a glow through the mask where it has been struck | Frames, from the art tools |
| Danger has a language | Hostile light is warm and the player's cool, everywhere. An attack shows its line before it comes. A squad shows where it will enter | Inks and one made picture |
| Words | Letters (problem 10): a pause that explains itself, a stage's name, a boss's name over its bar, what a bonus is as it is taken, a title, a run's end with its numbers, the best scores | The letters; a small file for the scores |
| Numbers that move | What a kill was worth, rising from where it died. A multiplier that grows and drains | Sprites the HUD already knows how to make |
| Places | Three to start: the rails that exist; a hive, close and cellular, with pillars that are scenery; open storm, with lightning that is a light. Between two, the level surges and the backdrop streaks | A layer function a place, as now |
| Time | A boss's death runs slow for a third of a second. Tempo is already a number every hostile obeys | One number for everything |
| The frame | The picture pushed in a little on a great blow, as it is shaken now | A scale in the vertex shaders |
| The window's margins | Where the window is not 16:9, the backdrop goes on to its edges and only the play is kept to the playfield | A second scissor |

**Not planned, and why.** Bloom and a shockwave that bends the picture both
need the finished picture as an image a shader can sample, and an image
needs a descriptor: the one thing every pipeline here does without. Glow is
done in the scene, by sprites that add, and reads well. This is listed under
decisions.

## Action

What a fight is made of now: things come from the right on programs, some
fire at where the ship is, and the ship fires right. It is all there is of
it. These are what would make it a game of decisions. Each is mostly lines
in the tables; where it needs the shaders, the last column says how much.

### The grammar of a fight (milestone 10)

| What | Why | Needs |
| --- | --- | --- |
| **An attack is announced.** A move that aims: it fixes on where the ship is, shows the line it will take, and holds. A diver shows its dive, a turret its shot | A hit the player saw coming is the player's fault, and that is what makes it fair. Rank may shorten the warning but never below a floor | One move, one made picture |
| **Fire is a pattern.** `fire` takes a count, a spread, a turn between shots and a rhythm: fans, bursts, spirals, walls with a gap. And it may fire any kind, so a carrier looses drones | Most of an enemy's character is how it fires | The request already carries a kind; the director stops assuming it is a pellet |
| **Guns ride bodies.** A kind that sits on a chain's segment, with its own health and program. Shoot the guns off the dragon, or go for the head through their fire | Asked for of the other build. It is the first choice a boss offers | One flag; the rider reads its segment as a segment reads its head |
| **Standing still is hunted.** Two seconds within a ship's width and something aimed and announced comes for that spot, and again | Said of the other build; nothing here answers it | A count in the director |
| **Charge.** One meter. Kills, near misses and bonuses fill it. Missiles spend it; so does the dash | Missiles are free now, so there is no reason not to hold the button. A meter makes the second button a decision | A float in the game block; a bar |
| **The dash.** A third button: a short burst the way the ship is going, through shots but not through bodies, at a cost in charge | An answer to a wall of shots that is not "be elsewhere already" | A few lines in the director; a third bit in the buttons |
| **The near miss.** A hostile shot that passes close without striking pays charge and a tick of sound | It rewards flying where the danger is, which is the opposite of standing still | The pass that tests a shot against the ship already knows how near it came |
| **The chain of kills.** Kills close together raise a multiplier; a pause drains it; a hurt ends it | Rank reads accuracy. This reads tempo. Together they pay for aggression that is also precise | Two numbers; a meter |

With these the first tuning pass is made, from the other build's accepted
numbers: fire near 5 a second, bonuses spaced and capped, each gone in ten
seconds. They are one line each in the tables, and with reloading each can
be tried in a second.

### More, once that stands (milestones 12 and 13)

| What | Sketch |
| --- | --- |
| Weapons as bonuses | A lance that pierces; a swarm that homes, on the missile's slow start; a shot that rebounds from the rails; cutters that orbit the ship; mines. Each is a mover's program and at most a flag |
| Armour with a facing | A kind that takes hits only from behind or the side: the mask's normals already say which way a struck texel faces |
| Things that react | A formation that scatters when one of it dies. A thing that dies into two smaller. A dying thing that fires once, at high rank |
| Scenery that matters | Rocks and gates with masks: they stop shots from both sides and hurt to touch. A gate that opens on the music's beat. The level at double pace through a gap; the level running backwards, and what comes then comes from behind |
| Bosses in phases | A program that jumps when health crosses a line. Guns that must go before the head can be hurt. A boss that, kept waiting, starts the level creeping again |
| Bonuses with a choice | One that changes kind each time it is shot. One that pays triple and raises rank. All of them drawn toward a ship that is not firing |
| Rank with a face | Higher rank draws elites, in their own ink, from the deck. After a hurt, a breath. The pips say which is happening |
| A worm that divides | Kill a middle segment and the tail becomes a head with a trail of its own. Cheap here, since every segment follows a trail by distance. Uncommitted: nobody has asked for it |

### The pair (milestone 13)

The brief was a ship and a companion with something between them. The
companion exists; what is between them is decoration. This is the part of
the game no other shooter has, so it should be what the game is about.

- **The thread is a thing.** It is swept against masks every tick, as a shot
  is. What crosses it is cut; hostile shots that cross it are stopped, at a
  cost in charge.
- **Where the two are is the weapon.** The companion keeps to where the ship
  was, so the thread lies along the ship's own path: fly round a squad and
  it is caught in the loop. The longer the thread the thinner it cuts.
- **Its three stages stay,** and each changes the thread as well as the gun.
- **It is drawn as one shape,** bright where it is cutting, and it lights
  what it passes.

## Milestones

Each ends with something to run and a short list for a hand. A milestone is
done when its claims hold and its list has been tried.

| # | Result | For a hand |
| --- | --- | --- |
| 8 | **Ground.** Nothing alive overwritten; links checked; requests in order, and two runs the same; the measuring run and its budgets; the sweep that cannot miss; tables on the device; the level's distance exact; letters, and a pause that says what the keys do | Play ten minutes. Is anything different? It should not be, except the pause |
| 9 | **Tools.** Reloading. The gallery, the board and the theatre watching their files. The slicer and the art report. The mix and the loudness report. The strip. Runs recorded, replayed and logged | Change a squad's count with the theatre open. Change a sound with the board open. Listen to `myhits_run.wav`. Read the strip |
| 10 | **A fight has a grammar.** Announced attacks, patterns of fire, guns on bodies, the hunt for a still ship, charge, the dash, the near miss, the chain of kills. The first tuning pass | Play. Is a hurt your fault? Is the dash an answer? Is it too much or too little, of what? |
| 11 | **It looks and sounds like something.** Lights, deaths in a thing's own texels, damage shown, the language of danger, words, moving numbers. Sounds in layers; loops; a song in sections with stingers on the beat | Look at the strip beside the last one. Listen to the mix beside the last one. Then play |
| 12 | **Levels.** The language, the deck, three stages with their places, scenery that matters, a boss in phases to each | Play all three. Which minute is dull? The runs file should agree |
| 13 | **The pair.** The thread as a thing; weapons as bonuses; the pad and the settings file; a title and the best scores; a run of hours with nothing drifting | Play with the companion. Is it the point of the game yet? |

Milestones 8 and 9 change nothing a player should notice. They are first
because everything after them is content, and content is cheap or dear
according to them.

## Rules that stay

- A frame is 72 bytes down and 512 up. A third button is a bit that exists;
  a tool's command is a few bits of the flags. What a tool reads beyond the
  events it reads at the end of a run, or when asked, never every frame.
- Five passes a tick and a report a frame, until a measurement argues for
  another.
- Nothing bound: every pipeline's interface is the root block.
- The tables hold no code. A kind, a sound, a squad, a string is a line.
- Every claim is numbered, was seen to fail when the code was broken, and
  says what it does not cover.
- No runtime dependency beyond Vulkan, XAudio2 and XInput; no build
  dependency beyond the SDKs, fasm2 and what Windows carries. Blender is
  needed only to render art again, never to build.

## Decisions wanted

1. **Which branch keeps `source\myhits\`.** Above.
2. **The other build's accepted numbers as this one's starting point.** This
   plan assumes yes, at milestone 10.
3. **The window opens as a window.** `--fullscreen` to open over the monitor.
   The other build does the opposite.
4. **A third button for the dash**, and missiles that cost charge. Keys
   Space, Shift, Ctrl; mouse left, right, middle; pad A, X, right bumper.
5. **One sampled image, for bloom and distortion.** It would be the only
   descriptor in the program. This plan says no, and does light in the
   scene. If the look at milestone 11 wants more, it is one push descriptor
   in one pipeline, and the style proof would name it as the exception.
6. **Lives stay.** The other build has hull, shield and charge. Here a hurt
   costs a life and is felt; charge is added for the second and third
   buttons only.

## Risks

- **The tools are work that is not the game.** Two milestones show nothing
  new on the screen. They are kept small by being the proofs that exist,
  watching a file.
- **Reloading can show a state no fresh start would reach,** such as a body
  half-way through a program that has changed under it. A reload therefore
  clears what is hostile, and the theatre replays to where it was.
- **Two runs the same is a claim about one device and driver.** It is held
  for the GTX 1080 Ti. A record made on one machine may not replay on
  another; the file says what made it.
- **More kinds of thing per tick may break the five-pass tick.** Riders read
  a segment that read a head: two ticks behind what they sit on unless the
  order is arranged. The measuring run and the chain's own exactness check
  will say.
- **Tuning by numbers from another build can mislead.** They were right for
  its speeds and sizes. They are where tuning starts, with reloading to make
  the next step quick, and the runs file to say what happened.
- **The author still cannot hear or feel.** The mix, the loudness report and
  the strip are for that; they check that nothing is broken, not that it is
  good. That stays with whoever plays.
