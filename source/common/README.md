# source\common: a layer for applications

What an application built on the projection needs that is not the
application's alone. It was made by writing one, [myhits](../myhits/plan.md),
and taking out of it whatever the next one would want too. It is for modern
Vulkan only: the contract below is required, and nothing it replaces is
assembled.

`examples\common` is something else: what the examples share, written to
show one operation under three contracts. Nothing here changes it. Some of it
is still borrowed, as it stands; that is listed below, with what is to be
done about it.

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
| [memory.inc](memory.inc) | Buffers, asked for by who touches them: `MEMORY_DEVICE`, `MEMORY_UPLOAD`, `MEMORY_READBACK`. Each is its own allocation; nothing pools or defers. An image, for the snapshots |
| [state.inc](state.inc) | What a program remembers between runs: values by name in the registry, under `HKEY_CURRENT_USER\Software\vk.fasmg\<program>` |
| [input.inc](input.inc) | A pad by XInput, over the keys and the mouse; rumble |
| [audio.inc](audio.inc) | XAudio2 called from assembly: sixteen voices for sounds asked for by count and place, looping voices for stems of music mixed by a level, and where the music is in its beat |
| [snapshot.inc](snapshot.inc) | Chosen frames of a scripted run, redrawn at the playfield's own size and written out: what a program nobody is watching looked like |
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

## What is borrowed, and what is to be done

The machine still includes these from `examples\common`, unchanged:
`vulkan_routes.inc`, `vulkan_context.inc`, `vulkan_commands.inc`,
`vulkan_barriers.inc`, `vulkan_wsi.inc` with `vulkan_wsi_retirement.inc`,
`cpu_arena.inc`, `command_options.inc`, `bitmap.inc`; and the debug sink and
strings beside them.

They work, and under a required contract only their modern side is
assembled. But they are the examples', made to negotiate what this layer
requires, and they reach each other by name in ways an application has to
answer for. Writing this layer's own is the first part of
[plan 2](../myhits/plan2.md)'s milestone 8.

## What making it has found

Things that were in the way. Each is worked round here, and each is a
question for the projection, the examples or the tools.

| Found | Where | What was done here |
| --- | --- | --- |
| A program cannot say which adapter will do. The context takes the first with a queue that can present, and if that one lacks a required capability it fails rather than trying the next | `examples\common\vulkan_context.inc` | The one question the context does ask of each adapter, which surface format, is answered no for an adapter that is not discrete |
| Nothing checks that the queue chosen for drawing can compute | the same | Checked by the machine once the device stands |
| No memory that only the device touches; cached memory is chosen by a usage bit the buffer does not need | `examples\common\vulkan_pools.inc` | `memory.inc`, which asks who touches a buffer |
| The command and presentation modules call the pools' deferred deletion by name, whether or not a program has pools | `vulkan_commands.inc`, `vulkan_wsi_retirement.inc` | `memory.inc` answers to the name with nothing |
| The presentation module takes a table from the startup arena, so a program must make an arena to present | `vulkan_wsi.inc` | The arena is made |
| `GWL_STYLE`, `SWP_FRAMECHANGED` and `SWP_NOOWNERZORDER` are not in the 64-bit equates | fasm2's `equates\user64.inc` | Defined in the machine |
| A structure or variable may not have a name the assembler has a use for: `Frame` is proc64's `frame`, `monitor` is an instruction, and a macro named `kind` takes every `kind dd ?` in the tree | fasm2 | Other names; a note where each bit |
| `SV_VertexID` and `SV_InstanceID` bring in a capability the contract does not ask for | Slang to SPIR-V | `SV_VulkanVertexID`, `SV_VulkanInstanceID` |
| The supplied clang compiles HLSL to SPIR-V but refuses pointers | the LLVM build | The SDK's `slangc` |
