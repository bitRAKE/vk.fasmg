# source\common: a layer for applications

What an application built on the projection needs that is not the
application's alone. It was made by writing one, [myhits](../myhits/plan.md),
and taking out of it whatever the next one would want too. It is for modern
Vulkan only: the contract below is required, and nothing it replaces is
assembled.

`examples\common` is something else: what the examples share, written to
show one operation under three contracts. Nothing here changes it, and
nothing here includes it: a program built on this layer is one object,
assembled from the projection and these files.

## The contract

Vulkan 1.3 with maintenance5, or 1.4, on a discrete adapter: dynamic
rendering, synchronization2, shader code given inline to the pipeline,
timeline semaphores, buffer device addresses, scalar block layout. No
descriptors of any kind. A pipeline's whole interface is one block of push
constants, the root, and everything else is reached from it through
addresses.

## What is here

| File | What it is |
| --- | --- |
| [machine.inc](machine.inc) | The window, the device under the contract, pipelines from SPIR-V whose only interface is the root, and the frame: real time paid out in fixed ticks, the root down, a block of events back a frame later. What a frame costs: the device's clock stamped wherever the program asks, and a file of the means. The window's manners: pause, the whole monitor and back, and for a program that asks, no caption, a held pointer, and a place it remembers |
| [device.inc](device.inc) | Vulkan loaded by hand, so that its absence is a failure the program can report; an instance; the first discrete adapter that has everything the contract asks, with a queue that draws, computes and presents; the device. What the loader and the validation layers say, to the debugger |
| [work.inc](work.inc) | One command buffer and one timeline. A submission's name is the value it raises the timeline to; whether it is done is two numbers compared. The barriers between passes |
| [present.inc](present.inc) | The surface, and a swapchain for the window as it is: an image to draw to, and the frame's work and that image to the monitor |
| [memory.inc](memory.inc) | Buffers, asked for by who touches them: `MEMORY_DEVICE`, `MEMORY_UPLOAD`, `MEMORY_READBACK`. Each is its own allocation; nothing pools or defers. An image, for the snapshots |
| [state.inc](state.inc) | What a program remembers between runs: values by name in the registry, under `HKEY_CURRENT_USER\Software\vk.fasmg\<program>` |
| [input.inc](input.inc) | A pad by XInput, over the keys and the mouse; rumble |
| [audio.inc](audio.inc) | XAudio2 called from assembly: sixteen voices for sounds asked for by count and place, looping voices for stems of music mixed by a level, and where the music is in its beat |
| [snapshot.inc](snapshot.inc) | Chosen frames of a scripted run, redrawn at the playfield's own size and written out: what a program nobody is watching looked like |
| [strings.inc](strings.inc), [options.inc](options.inc) | Text written in the middle of a call; what the command line asks for |
| [shared.inc](shared.inc), [shared.asm](shared.asm) | The blocks both sides of the boundary read, written once: the assembly takes their offsets from here, and the shaders a header assembled from here. Every shader module's offsets are checked against it |
| [pictures.inc](pictures.inc), [pictures.slang](pictures.slang) | Pictures cut, made or drawn; their masks and normals made on the device; drawn by pulling texels through addresses, sharp at any angle |
| [tables.inc](tables.inc) | The words a game's tables are written in: kinds and their programs of moves, particles, sounds, music, squads. None of it is code |
| [common.slang](common.slang) | The root, a hash, a frame's events and how a sound is asked for |
| [ease.slang](ease.slang) | Thirty-one easing curves, held to a second implementation |
| [motion.slang](motion.slang) | A body, and one tick of the program its kind gives it; marks; how it is shown between two ticks |
| [hits.slang](hits.slang) | Whether things touch, by their masks, at any angle, size and speed |
| [particles.slang](particles.slang) | A ring of particles in styles, with a cap a tick for each |
| [chains.slang](chains.slang) | A head and segments that go exactly where it went |
| [sounds.slang](sounds.slang) | Sounds and stems rendered from recipes, on the device |
| [letters.slang](letters.slang) | Words with no texels behind them: a letter is some of twenty strokes in its cell, sharp at any size; what is said is in the tables |

Each is proved by a program in [myhits\proofs](../myhits/proofs/README.md),
which is also where to see it run.

## What it is made of, and what it leaves out

The machine was first built on the examples' modules for the device, for
commands and for presentation. Those are written to negotiate: each of five
capabilities may be the core's, an extension's or absent, and every
operation has a route for each. Under a contract that requires all five,
one route of each is left, and what an application needs of them turns out
to be small. The layer's own are a third the size, 995 lines for 2,598, and
say less:

- **Nothing is negotiated.** An adapter has the contract or it is passed
  over; what the first discrete one lacked is in the failure's message.
- **One frame at a time.** The machine begins a frame when the device has
  finished the one before, so that events are a frame late and never more.
  One command buffer is therefore enough, recorded over and over; one
  timeline semaphore names every submission; and the semaphore an image is
  acquired with is free again by the time the next is wanted.
- **A swapchain is replaced with the device idle.** It is the one place the
  machine waits for everything, and it happens when a window changes size,
  not while a frame is owed. Nothing is kept of the old one to be collected
  later.
- **Nothing is deleted while frames run,** so nothing defers a deletion.
- **A surface that is lost is a failure,** as a device that is lost is.

What this cost, measured: nothing. Run turn and turn about with what it
replaced, the scripted run's passes and its picture cost the same, to within
what two runs of either differ by; the CPU's part of a frame is a little
less; and the world sums to what it did.

## What making it has found

Things that were in the way. Each is worked round here, and each is a
question for the projection, the examples or the tools.

| Found | Where | What was done here |
| --- | --- | --- |
| A program cannot say which adapter will do. The context takes the first with a queue that can present, and if that one lacks a required capability it fails rather than trying the next | `examples\common\vulkan_context.inc` | `device.inc` asks an adapter everything before it takes it |
| Nothing checks that the queue chosen for drawing can compute | the same | `device.inc` takes a queue that draws, computes and presents, or none |
| No memory that only the device touches; cached memory is chosen by a usage bit the buffer does not need | `examples\common\vulkan_pools.inc` | `memory.inc`, which asks who touches a buffer |
| The command and presentation modules call the pools' deferred deletion by name, whether or not a program has pools | `vulkan_commands.inc`, `vulkan_wsi_retirement.inc` | `work.inc` and `present.inc` call nothing of memory's |
| The presentation module takes a table from the startup arena, so a program must make an arena to present | `vulkan_wsi.inc` | `present.inc` keeps its eight images where they are |
| The loader's lazy binding finds the instance and the device by the names `instance` and `device` | `vk\loader\static.inc` | They are called that |
| A parameter of `iterate` is replaced after a dot too: one named `format` turns `VkSurfaceFormatKHR.format` into something else | fasmg | Parameters are given names no member has |
| `GWL_STYLE`, `SWP_FRAMECHANGED` and `SWP_NOOWNERZORDER` are not in the 64-bit equates | fasm2's `equates\user64.inc` | Defined in the machine |
| A structure or variable may not have a name the assembler has a use for: `Frame` is proc64's `frame`, `monitor` is an instruction, and a macro named `kind` takes every `kind dd ?` in the tree | fasm2 | Other names; a note where each bit |
| `SV_VertexID` and `SV_InstanceID` bring in a capability the contract does not ask for | Slang to SPIR-V | `SV_VulkanVertexID`, `SV_VulkanInstanceID` |
| The supplied clang compiles HLSL to SPIR-V but refuses pointers | the LLVM build | The SDK's `slangc` |
