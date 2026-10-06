# myhits proofs

Each idea the [plan](../plan.md) rests on is proved here before the game is
built on it, and the proof stays: a small program or script, the claims it
checks, and what to look at when you run it yourself. When a proof surprised
us, the surprise is written down under it.

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

| # | Proof | Claim | State |
| --- | --- | --- | --- |
| 00 | [survey](00_survey/survey.ps1) | The target GPU, the system libraries and the shader compiler offer what the plan uses | Passes here |
| 01 | [style](01_style/style.slang) | The shader toolchain accepts the pointer-only style, and lays the boundary blocks out as the assembly does | Passes |
| 02 | [spine](02_spine/spine.asm) | The whole CPU–GPU boundary works on the device within the plan's traffic budget | Passes, with two findings |

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

## Writing the next one

A proof is a directory here, a row in the table above, and a section saying
what it claims, what to look at and what its checks are. It should fail by
number, as the spine does, so a report says which claim broke.

Three assembler traps cost time on the spine; each now has a comment where it
bit:

- A macro parameter is substituted inside dotted names too. A parameter named
  `alignment` turns `boundary.alignment` into `boundary.8`.
- A dotted constant such as `Root.frame` is found from inside a procedure only
  if `Root` itself is a defined symbol.
- A `proc` nothing refers to is not assembled. A test of a procedure in
  isolation passes vacuously unless the procedure is made `public`.
