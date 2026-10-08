# myhits: plan 2

[plan.md](plan.md) built the game: seven milestones, each proved and kept.
This plan is what comes after. Nothing settled there is reopened here except
where a line says so.

First written 2026-10-06; rewritten 2026-10-07 around the decisions below.

## What this is for

The game is the occasion, not the whole of the purpose. The work is a modern,
performant application on the Vulkan projection, and three things come of
making one:

- **It finds what is wanting** in the projection, the examples and the tools,
  by leaning on them. What it has found so far is listed in
  [source\common\README.md](../common/README.md).
- **It leaves a layer**: what any such application needs on top of Vulkan.
  That is [source\common](../common/README.md) now, and it is this branch's
  own design.
- **It leaves libraries beside the layer**: pictures, motion, hits, particles,
  chains, sound, input, the words tables are written in.

So a thing is done well here when the next application could use it, and the
game is how it is known to work.

## Decisions

Given on 2026-10-07, in answer to the six this plan first asked.

| # | Decided | What follows |
| --- | --- | --- |
| 1 | There is no branch to choose. This one champions its own ideas; common code belongs in `source\common`; nothing need be adopted from another worktree | `examples\common` is as main has it. The layer has its own home and its own memory. The other branch's designs are no longer a reference here |
| 2 | Different mechanics want different tuning | Nothing is tuned to another build's numbers. This game is tuned by playing this game, with tools that make a change quick to try |
| 3 | The whole monitor by default; what is remembered between runs is in the registry | Built: the first run takes the monitor, and after that the window comes back as it was left. Bindings, volumes and scores will be kept the same way |
| 4 | A third button for the dash, and missiles that cost charge: test it | Built, to be played: Ctrl, the middle button or a pad's right shoulder |
| 5 | There is plenty of GPU memory at present | Read here as: the finished picture may be kept and worked on. It will be, and without a descriptor: see "The picture as memory" |
| 6 | Lives stay | Nothing to do |

And one thing given as an example of what is wanted: the hail-mary shot. It
is built, and it is what "Choreography" below is written from.

Said of the first build of it, which let a kill cancel the shot: that takes
the danger out of it. **Killing is not enough; the player has to move.** It
is now the first rule of every choreography here.

## Where it stands

- The game runs: squads from a table, chains, a boss the level waits for,
  rank that reads the shooting, bonuses, a companion in three stages, a
  backdrop that is the level's, music that listens; and now charge, a dash,
  the near miss, and the first choreographed attack. Thirty-five numbered
  claims hold on a scripted run of four games, under validation too.
- Milestone 8, the ground, is built: each of its problems below is done, or
  was measured and found not to need doing. Its list for a hand is untried.
- Its content is thin: 24 kinds, 6 squads in one loop, 14 sounds, 3 stems of
  two bars, 4 particle styles, 41 pictures, one place in three inks. The
  strip put a number on thin: the whole table of squads is thirty-two
  seconds, and someone who can play clears it, dragon and all, in those
  thirty-two seconds without losing a life.
- It has never been tuned. The author of its code has not heard it or played
  it.
- Changing a number in the tables no longer costs a rebuild and a restart:
  a watched game takes it in a second. Changing a picture, a shader or a
  name still does; and seeing a late squad still means playing to it.

## Done since plan 1

- **The window.** No caption; the pointer hidden and held inside while the
  game plays; P pauses, and so does leaving; paused, a press and hold moves
  it and its edges size it; F11 or Alt+Enter for the whole monitor, as an
  ordinary window. It opens over the whole monitor the first time and as it
  was left after that. Claims 23 and 26.
- **The layer has a home.** `source\common` holds the machine, memory,
  state, input, audio, snapshots, pictures, the boundary blocks, the table
  words and the Slang libraries. The game keeps its tables, backdrop and art.
- **Its own memory.** A buffer is asked for by who touches it and is its own
  allocation. It replaces the examples' pools here.
- **Its own device, work and presentation.** `device.inc`, `work.inc` and
  `present.inc`: nothing negotiated, one command buffer, one timeline, and a
  swapchain replaced with the device idle. The machine includes nothing of
  the examples' and links nothing of theirs; the proof runner holds it to
  that.
- **Charge, the dash, the near miss.** Claim 24.
- **The hail-mary.** Claim 25.
- **Room.** The director looks for room and refuses what there is none
  for; a hostile asks in cells of its own, read in order. Claim 27.
- **Two runs are the same run.** Claim 28, held across three runs of the
  script every time the proofs are run.
- **The measuring run.** The device's clock stamped after every pass and
  draw, in any run that asks (`--measure`) and every scripted one; a file of
  what each cost; budgets on a tick's passes. Claim 29. It found a
  sixty-fold regression in the director the day it was written.
- **A sweep that cannot slip through a corner.** Proof 05, claim 12.
- **The header and the tables in device memory.**
- **The level's distance, exact however far.** Claim 30.
- **Letters.** `letters.slang` in the layer: twenty strokes to a letter and
  no texels. What is said is `say` lines in the tables. A pause says what
  the keys do and a run that is over says how to begin another. Claim 31.
- **Reloading the tables.** `--watch`, `build\myhits_tables.bin` and
  `source\myhits\tools\watch.ps1`; `reload.inc` in the layer. Claim 32.
  The first of milestone 9's tools, and the one the others stand on.
- **Runs kept.** `--record` and `--replay`, held to the record frame by
  frame; frames that are run and not shown. Claim 34.
- **The strip, and the ghost.** A run on a page. Claim 35.
- **The mix and the loudness report.** The scripted run, as it sounded, in
  `build\myhits_run.wav`, and every sound's level in a table. Claim 33. It
  found the mix a decibel over full scale in five samples.
- **Text, as a side quest.** `text.inc` and `text.slang` in the layer:
  strings shaped by DirectWrite in any script and drawn from their outlines
  on the device by the Slug algorithm, at any size and angle, with no
  texels. Proof 08, thirteen claims, its pictures held to GDI+. The game
  does not use it yet: its words are still the letters of twenty strokes.
  Where it would earn its place is the things said in a language, a title,
  and a score table; a number that changes every frame wants glyphs set
  down by the device first.

## Choreography

What a fight was made of: things come from the right on programs, some fire
at where the ship is, and the ship fires right. A hit or a miss, and nothing
in between to read or to answer.

What is wanted instead is choreography: a thing that happens in beats, each
of which the player can see and hear, with time between them in which what
the player does changes how it ends. An enemy with a choreography has a
character, and the player answers the character rather than the sprite.

Two rules hold for all of it.

- **The answer is to move.** Firing is what the player does anyway. A danger
  that firing can cancel is a thing to shoot sooner, and the ship stays
  where it is. So nothing begun is stopped by a kill: what firepower buys is
  a say in when and where, and the rest is flying.
- **Every harm has a tell,** and a floor under how short the tell may be.

### The reference: the hail-mary

A diver hurt past half and left alive throws one.

| Beat | What happens | What is seen and heard | How long |
| --- | --- | --- | --- |
| Hurt | It stops whatever it was doing | Embers; an alarm; it trails sparks from here on | 0.3 s to stop |
| Fix | It fixes on the ship, and the fix follows the ship | Brackets round the ship, shaking, closing in as the fix tightens; the diver turns to face it | 1.1 s |
| Lock | The fix stops where the ship is | The brackets become crosshairs, as wide as the burst will reach; a hard blip | 0.3 s |
| Shot | One heavy shot, at the lock. The diver is thrown back the other way, and goes | The shot leaves slowly and gathers speed; the crosshairs fade as it comes: all there at its launch, gone as it lands | 1.5 s |
| Burst | It bursts at the lock. What is within 140 is hurt | The burst; a low boom | |

What the player can do about it, and so what it changes:

- **Leave the lock.** That is the answer, and the only one. After the lock
  there are 1.8 seconds to be 140 away: a quarter of a second's flying, or
  one dash. The crosshairs show exactly how far is far enough.
- **Kill it, and still leave.** A diver that dies before it has fired looses
  the shot as it dies, at where its fix then is, or at where the ship is if
  it had not yet begun to fix. The kill does not stop the shot. It decides
  when the lock falls: the player may pick the moment, and then has the
  shot's second and a half to be elsewhere.
- **Not shrug it off.** A dash slips shots; it does not slip a burst.

So a hurt diver is not a thing to finish quickly and forget. Finished or
not, it puts crosshairs on the ship, and the ship has to go.

The scripted run holds every beat: the fix is where the ship is while the
ship moves; the lock is where the ship then was and does not move again; the
shot's mark is the lock and fades every frame; the diver goes the other way;
the burst is at the lock; a ship that stayed loses a life and one that dashed
away loses nothing; and a ship that struck the third diver dead while it was
fixing, and stayed, loses a life to the shot it loosed as it died.

### What it took

Five words in the tables, each a few lines in the shaders, each now there
for any kind to use:

| Word | Says |
| --- | --- |
| `wounded share` | From here on is what this kind does once it is hurt down to that share of its health. It leaves whatever move it was in |
| a `MARK` move | Fix on the target: the body's mark follows it and the body turns to face it. When the move ends the mark is locked |
| `fire` with a locked mark | What is fired is sent at the mark and carries it; the firer shows it no longer |
| `blast reach` | The program ends here in a burst that hurts what is within reach |
| a lobbed kind | A shot thrown over the field: it touches nothing on its way |

The diver's whole hail-mary is the word `wounded` and six lines of
[tables.inc](tables.inc), and the heavy shot two. That is the measure to keep: a choreography costs words,
not code, and a word once made is everyone's.

### The words still wanted

| Word | For |
| --- | --- |
| `alone`, `near distance`, `struck`, `after seconds` | More ways into a second part than being hurt: the last of a squad; the ship come close; a hit taken; time run out |
| `cue SOUND` | A beat that is heard without a body having to be made or hurt |
| Marks with a shape | A line for a dive or a beam, a cone for a spray: the picture of the mark is the reach of the harm, as the crosshairs are |
| `fire` any kind | A carrier looses drones; a thing dies into two smaller |
| A kind that rides a segment | Guns on a chain's body, each with its own health and program |
| A beam | A segment swept against masks for as long as it lasts, as a shot is swept for a tick |
| Who is in my squad | A leader, and what the rest do when it dies |
| `slow share, seconds` | A beat that takes the whole world's tempo down for a moment |

### What to choreograph next

Each is a few beats and an answer it should teach. None is built.

| Name | Beats | What it changes |
| --- | --- | --- |
| The last launch | A carrier hurt to half opens, shows what is in it, and looses all of it at once. Killed sooner, it spills them where it dies | Where to be when it opens: behind it, not in front |
| The gather | A turret draws light to itself; the line of its beam appears; the beam holds and sweeps. A hit while it gathers knocks its aim: the line jumps, and is shown again | Get off the line, and watch where it goes next |
| The broken rank | A formation's leader dies; the rest scatter, and then come back as rammers, each showing its line | Kill the leader from where the lines will not cross |
| The last one | The last of a squad turns, marks the ship, and comes faster than any of them did | A fight's end is when to be moving most |
| The chain | A volatile thing bursts when killed, a moment after showing how far; others near it go too | Kill it from outside its ring, and its neighbours' |
| The feint | A diver shows its line, and at high rank the line snaps to another at the last | A tell is read to its end, on the move |
| The thief | Something takes a bonus and runs for the edge | A chase the other way |
| The rear | A dragon draws its head back before it sweeps; where its head will pass is shown | A boss is flown round, not stood in front of |

Each is written so that the second rule's tell is also the first rule's
reason to move. On the floor under a tell: rank hurries everything hostile,
so a tell at full rank is two thirds of what the table says. A floor is a
number in the tables; the stage's claims measure the time from tell to harm
and hold it.

### How a choreography is proved

The scripted run's third game is a bare stage: no squads, only what the
script sets down. It sets down an actor, provokes it, and the claims follow
the beats frame by frame, by what the device reports of the actor, its mark
and its shot. A new choreography is a new scene on that stage, a few
pictures of it, and the ways of breaking it that were tried.

## Charge, the dash, the near miss

Built to be tried. Every number here is a first guess.

| | |
| --- | --- |
| Charge | One meter, full at the start of a run. Eight pips under rank's |
| It is earned by | A kill, 6 hundredths. A hostile shot that passes within 95 of the ship's middle and does not strike, 3, once a shot. A bonus, 12 |
| Missiles | A pair costs 25. Without it there is a click, and nothing leaves |
| The dash | Ctrl, the middle button, a pad's right shoulder. Costs 20. 320 units in 16 ticks, the way the ship is going, or ahead if it is going nowhere |
| What a dash slips | Hostile shots, while it lasts and 6 ticks after. Not bodies, not bursts |

To be found out by playing: whether charge should start full; whether 320 is
far enough to matter and near enough to aim; whether the slip is too kind;
whether the near miss pays enough to fly for.

## Open problems

What plan.md left open and what reading the code again found. Each has an
answer, a milestone, and the check that will hold it. Those marked done are
built as written, and their check is a numbered claim of the game's.

| # | Problem | Answer | When | Held by |
| --- | --- | --- | --- | --- |
| 1 | The layer borrowed the examples' context, commands, barriers and presentation: modules written to negotiate what this layer requires, reaching each other by name | This layer's own, for the modern contract only: a device, one command buffer and one timeline, a swapchain replaced with the device idle. A third the size, and nothing measured changed | done | Every proof as before, under validation too; a program is one object, and no source includes one of the examples' |
| 2 | A new body can overwrite a living one. Shots, pellets and hostiles each take the next slot of a ring; a bonus dropped while the hostile ring wraps can land on a segment of the dragon | The director looks for free slots, bounded, from its cursor; a chain needs a free run. What cannot be placed is refused and counted, per pool | done | A flood on the stage: nothing alive is ever replaced; refusals equal what did not fit |
| 3 | The order of requests in a tick depends on which thread won | A body's requests go in cells that are its own; the director reads them in slot order. No atomic, no overflow | done | The run's two modes, default and validation, report the same hash of the world |
| 4 | Nothing is timed. Pool sizes and pass costs are guesses | A measuring run: timestamps round every kind of pass, the CPU's time to record and submit, memory by domain (which `memory.inc` already counts). Budgets are written from its first report | done | The report is checked against the budgets, so a regression fails |
| 5 | The player's shots are tested against every hostile: 256 by 384 a tick at most | Measured, and left as it is: the pass that does it, for every shot of both sides, costs 31 microseconds of a tick's 62. Rows would save a part of that | not needed | The measuring run |
| 6 | A shot's sweep takes one sample a texel on its longer side, and could pass a diagonal wall one texel thick | The walk visits both texels at each crossing | done | Proof 05: a one-texel diagonal stops a lance at every offset |
| 7 | Bodies read their tables from host-visible memory every tick | A pass copies the header and the tables to device memory at start; the CPU's copy is then free for reloading. It made no difference that could be measured | done | The measuring run, before and after |
| 8 | How far the level has come is a float that only grows | A layer keeps whole periods of its own pattern as an integer and the rest as a float below one period; each lattice adds its share of the periods to its cell number in integers, where wrapping is harmless | done | With a billion periods added, the periodic layers are the same to the pixel and the others as sharp |
| 9 | There are no letters. A pause, a run's end, a stage's name and every tool's readout need them | Sixteen-segment letters: a table of forty words in the shader and no texels, sharp at any size. Strings live in the tables | done | Pictures; the pause says what the keys do |
| 10 | A chain's segment follows the head in its slot. It does compare its seed with the head's birth tick, but no claim holds that | A scene on the stage: a head's slot reused in the tick it died | done | The old segments die; none follows the newcomer |
| 11 | Rank shortens every tell with everything else | A floor in the tables under each tell | 10 | The stage measures tell to harm |
| 12 | The thread between the ship and its companion is a row of sparks | It becomes a thing. See "The pair" | 13 | Its own claims |
| 13 | The pad's layout is provisional, nothing can be rebound, a pad cannot pause | Back pauses. Bindings are a value in the registry, as the window's place is | 13 | Unit checks on made-up states; a hand for the rest |
| 14 | The ship is a stand-in from another sheet. No convention for rendered art | Under "Art" | 9, 11 | The art report |
| 15 | Sounds that last cannot be expressed: events carry counts of one-shots | Loops are levels in the events, as the music's intensity is | 11 | Proof 06 |
| 16 | Nobody has heard it or played it | The tools make listening and looking cheap, and leave numbers the author can check without ears | 9 | Their reports |

## Tools

The rule for all of them: **the proofs are the tools.** The gallery already
shows every picture over its mask. The range already runs the tables'
programs. The board already draws and plays every sound. The game's third
scripted game is already a stage. Each becomes the place where its kind of
thing is made, by one addition they share.

### Reloading

Built, for the tables. They are assembled into the game as before, and they
are also a file, `build\myhits_tables.bin`: the same image, a few numbers
that say what follows and then the tables. A game started with `--watch`
looks at the file once a second. When it has been written since, and is an
image the game can take, the CPU lays it down beside the header and one pass
settles both into the device's tables; the voices are stopped, the bank is
rendered again from the new recipes and notes, and the music begins again
from wherever the sounds' new lengths have put it.
`source\myhits\tools\watch.ps1` assembles the file again whenever
`tables.inc` is saved, which takes about a second.

So a number changed in `tables.inc` is on the screen, or in the speakers,
a second or two after it is saved, in the game that was already running.

**What goes when the tables change.** A body half-way through a program
that has changed under it is a state no fresh start would reach. So in the
tick the device is told, every body goes: hostiles, their shots, the
player's shots in flight, which are counted as having got away. The squad
that was on the screen, or on its way, comes again from its first: that is
what someone changing a squad wants to see. The game says TABLES TAKEN along
the top for two seconds.

**What may change, and what may not.** Every number; every program of moves,
longer or shorter; every squad, and how many squads; every recipe, and so
how long each sound is; every note; everything said. Not the names: the
kinds, styles, sounds, stems and things said, in their order, are what the
shaders know by number. An image carries a print made of those names, and a
game takes no image whose print is not its own: it says TABLES REFUSED, goes
on with what it had, and waits for a build. The tables may grow to twice
what the game was built with and the sounds to twice and two seconds more;
past that is a build too. And an image is looked through before it is laid
down: one in which anything points outside it, a kind at a move there is
not, a squad at a kind there is not, is refused like one of other names.
The tools do not make such an image; a mistake might, and the device would
read what is not there.

**A watched game goes on when it is left.** An ordinary game pauses when
another program comes in front, and someone changing a table is in an
editor. Started with `--watch` it does not pause; it takes no key or button
while it is behind, so its ship stands still, and a run that is over is
still a world for squads to come to.

This is startup traffic, not a frame's: the claim that a frame is the root
down and the events up stays as it is, and what a reload sends is counted
apart. Claim 32 holds all of it, in the scripted run, and fifteen ways of
getting it wrong each fail it. What it cannot hold is a hand at an editor:
the list for that is with the claim, in the proofs.

Still to come: the packed art by the same road; the gallery, the range and
the board watching as the game does; and the theatre, which will bring a
changed squad back without playing to it.

The game's tools are in `source\myhits\tools`, beside the art packer. The
repository's own `tools\` is the projection's.

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

The atlas is modular: heads, bodies, tails, joints, cores, orbs. Riders and
bosses are assemblies of those parts, so the gallery will show a kind with
what rides it, not only a frame.

### Sound

What hurts now: a sound is one oscillator, a share of noise and one
envelope; hearing a change means a build and a run; nothing says whether a
sound is too loud against the rest; the music is one two-bar loop.

| Tool | What it does | What it leaves |
| --- | --- | --- |
| The board, watching | Reloads on a saved `tone`. Any sound from the keyboard, alone or repeated as play repeats it. Draws its samples, as now, and beside them where its energy is by pitch over time | The place a sound is made |
| Layers | `layer` lines after a `tone`, each an oscillator with its own sweep, envelope and delay, summed. A shot is a click, a body and a tail | Still one line a part |
| Noise with a colour | Noise averaged over a window of samples whose length is eased: bright to dull, or a band. It is a sum of hashes, so every sample is still computed alone | The blast tail and the hiss the first set lacks |
| Modulation | One oscillator bending another's phase, or multiplying it: metal, growl, bell. A soft clip for weight. Two oscillators a few cents apart for width | Three numbers on a line |
| Echo | The recipe evaluated again at earlier times and added, quieter: a few taps make a tail | No state: a recipe can be asked for any sample |
| Loops | `loop` lines: a sound whose length is a whole number of its periods. Events carry a level for each: an engine by speed, a fix being held on the ship, a boss's presence, an alarm at the last life | Problem 15 |
| Songs | Patterns of notes and an order to play them in, a section to a stage and one for a boss; a stinger that waits for the next sixteenth, so a bonus rings in time | More than two bars |
| `tools\notes.ps1`, with the game's tools | Reads a MIDI file's track into `notes` lines | Music from any editor |
| The mix (built) | The scripted run's events played into a file: every sound and stem at the level and time the game asked. `source\myhits\tools\mix.cs`, from what the run keeps of what it asked | `build\myhits_run.wav`: the game can be listened to without playing it |
| The loudness report (built) | Level and peak of every sound and of the mix; how many samples clip; which sound stands furthest from the rest | `run.md`, beside the run's pictures: a table the author can check without ears; a sound 12 dB hot fails. Claim 33 |

The second synthesis in `bank.cs` follows every addition, as it follows the
recipes now.

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

**The theatre** is the stage, opened to a hand: the game started with
`--theatre`.

| Control | Does |
| --- | --- |
| `--stage n --from seconds` | Starts there. The run is replayed from its start without drawing: the machine has frames that are run and not shown, and 68 seconds of a played run cost under two that way |
| `[` and `]`, `,` and `.` | Slower and faster; one tick back or on. Back is the replay again, one tick shorter |
| G | A ghost: nothing hurts |
| `-` and `=` | Rank down and up a pip |
| Tab and a click | A kind, by name; one of it where the crosshair is. H hurts it to half, which is how a choreography is rehearsed |
| The overlay | The squad's name, what is alive, the budget, what was refused; for a marked thing, the time from its tell |

**The strip.** Built: `source\myhits\tools\strip.ps1` plays a run back
unseen but for a picture every few seconds, and tiles the pictures into one
image with the time, the squad, the score and the lives under each: a level
on a page, to be read, compared before and after an edit, and looked at by
someone who cannot play it. With no run given it makes one: a ghost, which
nothing hurts (`ROOT_GHOST`), doing nothing or firing ahead. With one, it
is that run on a page. Two minutes of play are a page in four seconds.
Claim 35.

**Runs kept.** Built: `--record` writes what the device was given in every
frame, as it is played, the tables taken on the way, and what each frame
came to; `--replay` plays it back, held to that, and then hands the ship
over where the record stopped. Either may name its file, and both together
play a run back and go on keeping it. With problem 3 solved a replay is the
same run: claim 34 holds the scripted run to that frame for frame, and a
run somebody played. A bug is a file, and its last frame is in it. Still to
come: every run appends a line to `build\myhits_runs.csv`:
how long, the score, rank over time, accuracy, hurts and what did each,
bonuses taken by kind, kills by kind, charge spent on what. Tuning then has
numbers to start from, and they are this game's.

## Presentation

What there is: one place in three inks, sprites lit from one side, four
styles of spark, a HUD of digits and pips. What would make it various,
cheapest first.

| What | How | Cost |
| --- | --- | --- |
| Light from what happens | Up to eight lights a frame: the ship's muzzle, each burst, a nova, a heavy shot on its way. Every picture with normals takes them; so does the ridge of the backdrop | A loop of eight in one fragment shader. The normals are already there |
| Things break as themselves | A death throws the dead thing's own texels: sparks placed on its mask and coloured from its picture | One flag on a kind and one on a style |
| Things show damage | Frames by health; a glow through the mask where it has been struck. A wounded thing already trails embers | Frames, from the art tools |
| Danger has a language | Hostile light is warm and the player's cool, everywhere: the heavy shot is the violet of every hostile shot now, and should not be. A mark is the shape of its harm | Inks and pictures |
| Words | Letters (problem 9): a pause that explains itself, a stage's name, a boss's name over its bar, what a bonus is as it is taken, a title, a run's end with its numbers, the best scores | The letters; a value in the registry for the scores |
| Numbers that move | What a kill was worth, rising from where it died. A multiplier that grows and drains | Sprites the HUD already knows how to make |
| Places | Three to start: the rails that exist; a hive, close and cellular, with pillars that are scenery; open storm, with lightning that is a light. Between two, the level surges and the backdrop streaks | A layer function a place, as now |
| Time | A boss's death runs slow for a third of a second. Tempo is already a number every hostile obeys | One number for everything |
| The frame | The picture pushed in a little on a great blow, as it is shaken now | A scale in the vertex shaders |
| The window's margins | Where the monitor is not 16:9, the backdrop goes on to its edges and only the play is kept to the playfield | A second scissor |

### The picture as memory

Bloom, and a shockwave that bends what is behind it, need the finished
picture as something a shader can read. The usual way is to sample it as an
image, and an image needs a descriptor, which nothing here has.

There is memory to spare, so the picture can be read the way everything else
is: as memory, through an address.

1. The frame is drawn to an image of the playfield's own size, 1920 by 1080,
   whatever the window's. That is an attachment, not a descriptor.
2. The image is copied to a buffer: 8 MB a frame at eight bits, 16 at
   sixteen. The snapshots already do exactly this, once in a while.
3. Compute passes make smaller, blurred copies of it in more buffers.
4. The last pass draws to the window, pulling from those buffers by address
   and filtering by hand, as the sprites already pull their texels.

It costs a copy of the picture every frame and about a third as much again
in smaller copies. It gives bloom, a shockwave, the picture drawn once at
one size however large the monitor, and a last pass that can do whatever is
wanted to the whole of it. The measuring run of milestone 8 comes first, so
that what it costs is a number.

## More action

Beyond the choreographies above; each is mostly lines in the tables.

| What | Sketch |
| --- | --- |
| Fire is a pattern | `fire` takes a count, a spread, a turn between shots and a rhythm: fans, bursts, spirals, walls with a gap |
| Standing still is hunted | Two seconds within a ship's width and something aimed and announced comes for that spot. It is the first rule made into an enemy: a choreography with the ship's stillness for its tell |
| The chain of kills | Kills close together raise a multiplier; a pause drains it; a hurt ends it. Rank reads accuracy; this reads tempo |
| Weapons as bonuses | A lance that pierces; a swarm that homes, on the missile's slow start; a shot that rebounds from the rails; cutters that orbit the ship; mines |
| Armour with a facing | A kind that takes hits only from behind or the side: the mask's normals already say which way a struck texel faces |
| Scenery that matters | Rocks and gates with masks: they stop shots from both sides and hurt to touch. A gate that opens on the music's beat. The level at double pace through a gap; the level running backwards |
| Bosses in phases | A program that jumps when health crosses a line: `wounded` is the first of these. Guns that must go before the head can be hurt |
| Bonuses with a choice | One that changes kind each time it is shot. One that pays triple and raises rank. All of them drawn toward a ship that is not firing |
| Rank with a face | Higher rank draws elites, in their own ink, from the deck. After a hurt, a breath. The pips say which is happening |

### The pair

The brief was a ship and a companion with something between them. The
companion exists; what is between them is decoration. This is the part of
the game no other shooter has, so it should be what the game is about.

- **The thread is a thing.** It is swept against masks every tick, as a shot
  is. What crosses it is cut; hostile shots that cross it are stopped, at a
  cost in charge.
- **Where the two are is the weapon.** The companion keeps to where the ship
  was, so the thread lies along the ship's own path: fly round a squad and
  it is caught in the loop. A dash lays 320 of it in an instant.
- **Its three stages stay,** and each changes the thread as well as the gun.
- **It is drawn as one shape,** bright where it is cutting, and it lights
  what it passes.

## Milestones

Each ends with something to run and a short list for a hand. A milestone is
done when its claims hold and its list has been tried.

| # | Result | For a hand |
| --- | --- | --- |
| 8 | **Ground.** The layer's own device, timeline and swapchain. Nothing alive overwritten; requests in order, and two runs the same; the measuring run and its budgets; the sweep that cannot miss; tables on the device; the level's distance exact; letters, and a pause that says what the keys do | Play ten minutes. Is anything different? It should not be, except the pause |
| 9 | **Tools.** Reloading. The gallery, the board and the theatre watching their files. The slicer and the art report. The mix and the loudness report. The strip. Runs recorded, replayed and logged | Change a squad's count with the theatre open. Change a sound with the board open. Rehearse the hail-mary with H. Listen to `myhits_run.wav`. Read the strip |
| 10 | **Choreography.** The words still wanted. Four or five more choreographies on the stage, each with its tell, its floor and its claim. Fire as a pattern; the hunt for a still ship; the chain of kills. The first tuning, by play | Play. Which enemies have a character? Is a hurt your fault? Is it too much or too little, of what? |
| 11 | **It looks and sounds like something.** Lights, deaths in a thing's own texels, damage shown, the language of danger, words, moving numbers. The picture as memory: bloom and a shockwave. Sounds in layers; loops; a song in sections with stingers on the beat | Look at the strip beside the last one. Listen to the mix beside the last one. Then play |
| 12 | **Levels.** The language, the deck, three stages with their places, scenery that matters, a boss in phases to each | Play all three. Which minute is dull? The runs file should agree |
| 13 | **The pair.** The thread as a thing; weapons as bonuses; the pad, and bindings remembered; a title and the best scores; a run of hours with nothing drifting | Play with the companion. Is it the point of the game yet? |

Milestones 8 and 9 change little a player should notice. They are first
because everything after them is content, and content is cheap or dear
according to them.

## Rules that stay

- A frame is 72 bytes down and 512 up. A button is a bit that exists; a
  tool's command is a few bits of the flags. What a tool reads beyond the
  events it reads at the end of a run, or when asked, never every frame.
- Five passes a tick and a report a frame, until a measurement argues for
  another.
- The director walks no pool. One thread on the device spends a quarter of a
  microsecond on each step of a loop that reads memory; what a pool has to
  tell the director, its own threads tell it, with a bit or an atomic
  minimum. A tick's passes are held to budgets.
- Nothing bound: every pipeline's interface is the root block.
- The tables hold no code. A kind, a sound, a squad, a string is a line.
- Every claim is numbered, was seen to fail when the code was broken, and
  says what it does not cover.
- No runtime dependency beyond Vulkan, XAudio2 and XInput; no build
  dependency beyond the SDKs, fasm2 and what Windows carries. Blender is
  needed only to render art again, never to build.
- What the next application would want goes in `source\common`.

## Risks

- **The tools are work that is not the game.** Two milestones show little
  new on the screen. They are kept small by being the proofs that exist,
  watching a file.
- **The layer's own presentation is younger than what it replaced.** The
  borrowed module handled resizing, retirement and a lost surface, and took
  time to get right. Its replacement passes every proof that resizes and
  presents, under validation, and has been played on; it treats a lost
  surface as a failure, and has met one monitor and one driver.
- **Reloading can show a state no fresh start would reach,** such as a body
  half-way through a program that has changed under it. A reload therefore
  clears what is hostile, and the theatre replays to where it was.
- **Two runs the same is a claim about one device and driver.** A record made
  on one machine may not replay on another; the file says what made it.
- **A choreography that is fair on the stage may not be in a crowd.** Three
  hail-marys at once are three locks to leave, and since a kill no longer
  cancels one, a nova or a volley through a squad of divers sets them all
  off together. The floor under a tell is per thing; whether there should be
  one across the field is for play to say.
- **The author still cannot hear or feel.** The mix, the loudness report, the
  strip and the stage are for that; they check that nothing is broken, not
  that it is good. That stays with whoever plays.
