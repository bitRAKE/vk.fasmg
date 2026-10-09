# Vulkan projection and examples for fasmg

This is a minimal Windows x64 repository for projecting the Vulkan registry
into fasmg/fasm2 includes and demonstrating how to bind the resulting functions.
It contains the projection generator, ABI verification, six loader strategies
and an explicit runtime bootstrap demonstrated by ten console programs,
two headless compute recipes, three debug-utils examples, a fractal
explorer built under three contracts over Vulkan's legacy operations, and a
GPU-only port of the NoGraphicsAPI textured cube, with focused tests.

## Requirements

- Windows x64 and a Vulkan SDK with `VULKAN_SDK` set.
- Visual Studio C++ tools (`nmake`, `link`, `lib`, and `dumpbin`).
- LLVM clang, used to verify the Windows x64 ABI against the SDK headers.
- [fasm2](https://github.com/tgrysztar/fasm2) with AMD64 NEWCOFF support.
- A Vulkan 1.1 capable driver for running the loader examples, including
  `VK_KHR_surface` and, except for the IAT/thunk examples, `VK_EXT_debug_utils`.
- For the headless compute recipe, a Vulkan 1.1 GPU with a compute queue.
  It needs no surface, window, device extensions, or optional features.
- For the NoAPI compute recipe, SDK Slang and a Vulkan 1.4 GPU with buffer
  device address, scalar layout, timeline semaphores, synchronization2,
  maintenance5, and coherent host-visible device-local memory. Its checks
  also use the SDK API dump and Profiles layers.
- The Vulkan SDK's `glslangValidator` and `spirv-val` for the explorer shaders.
  Running the explorer needs a Vulkan 1.1 device with Win32 presentation; its
  modern contract also needs the five promoted routes, core or KHR.
- For the cube, a recent SDK with descriptor-heap/address-command registry
  entries and bundled Slang supporting `spvDescriptorHeapEXT` (tested with
  SDK 1.4.363.0). Running the cube's fallback paths needs a Vulkan 1.1 GPU.
- The Vulkan SDK's Khronos validation layer for `check-recipes`, `check-debug`, `check-legacy`,
  `check-noAPI_cube`, and `check`.

The makefile defaults to `..\fasm2\fasm2.cmd` and
`%ProgramFiles%\LLVM\bin\clang.exe`. Override either when needed:

```bat
build.cmd "FASM2=C:\tools\fasm2\fasm2.cmd" "CLANG=C:\tools\LLVM\bin\clang.exe"
```

## Build and validation

Run from the repository root:

```bat
rem Generate, verify against the SDK, and build all examples:
build.cmd
rem Generate and verify the projection only:
build.cmd api
rem Build, run, and compare all ten loader examples:
build.cmd loaders
rem Build a headless GPU operation, then run its executable:
build.cmd compute
build\recipe_compute.exe
rem Use GPU pointers and reuse one recorded command buffer across batches:
build.cmd compute-noapi
build\recipe_compute_noapi.exe
rem Verify both recipes and repeat with synchronization validation:
build.cmd check-recipes
rem Build and verify the three debug-utils examples:
build.cmd debug
rem Repeat debug checks with the Khronos validation layer:
build.cmd check-debug
rem Build and check the fractal explorer under its three contracts:
build.cmd legacy
rem Repeat explorer checks with core and synchronization validation:
build.cmd check-legacy
rem Build and check the GPU-only textured cube and fallback routes:
build.cmd noAPI_cube
rem Repeat cube checks with core and synchronization validation:
build.cmd check-noAPI_cube
rem Build and run the proofs under the shooter in progress:
build.cmd myhits-proofs
rem Repeat them with core and synchronization validation:
build.cmd check-myhits
rem Run all projection, loader, recipe, debug, explorer, cube, and proof checks:
build.cmd check
rem Run just the projection and loader checks:
build.cmd check-api
rem Check automatic and explicit guard-page-safe stack growth:
build.cmd check-stack
rem Remove build artifacts; keep the generated projection:
build.cmd clean
```

`build.cmd` locates Visual Studio and initializes an x64 developer environment
when `nmake` is absent from PATH. From an existing x64 developer prompt,
`nmake /nologo` accepts the same targets and overrides.

The generated includes live under `vk\`, alongside the handwritten
`vk\loader\` sources. Generated manifests and layout assertions live under
`tests\vk\`. They are ignored by Git and regenerated when the generator or SDK
registry changes. Only a complete generation gets `tests\vk\.generated`, and
only successful SDK verification gets `tests\vk\.validated`. Every example
that calls Vulkan depends on that validation stamp. Assembly also requires a
fresh object file, so a failing fasm2 batch wrapper cannot hide a build failure.

`check` verifies unique function ownership, assembles every generated include
with layout assertions and alignment checking, and tests lazy resolution
against a stand-in resolver that clobbers volatile registers. It runs all ten
loader examples, checks imports, dense slot tables, and actual named-thunk
instructions, and verifies startup failures for absent DLLs and resolver exports.
It also checks `newcoff.inc`'s stack probing with large local and explicit
allocations; the compute recipes declare startup scratch directly in `locals`
and retain persistent zero-initialized state in BSS. See the
[import/storage policy](docs/binary-layout.md).
The [headless compute recipe](examples/recipes/README.md) checks 1,048,576 GPU
sums against a CPU oracle, repeats with core/synchronization validation, and
checks its unavailable-driver error.
The [NoAPI compute recipe](examples/recipes/compute_noapi.md) checks a fixed
modern contract, GPU pointer ABI, changing resident arguments, and guarded
tails across three batches. An API trace confirms that setup records commands
once and recurring work uses only submit/wait calls. A masked required feature
must cause rejection before device creation.
It also verifies the [debug-utils examples](examples/debug/README.md), including
actual Windows debugger events and runs under the Khronos validation layer.
The [legacy examples](examples/legacy/README.md) hold each executable to its
build contract through the Vulkan functions its link map names; compare full
exports to the pixel across contracts, modern, KHR, API-ceiling and original
routes, and tile sizes; compare float64 deep zoom with its float-pair
alternate; run the animated tour to every stop; and check the errors for an
unmet contract and an unavailable driver, all repeated under synchronization
validation.
The [NoGraphicsAPI cube](examples/noAPI_cube/README.md) compares GPU pointer,
binding, command, depth, and color-format fallbacks; checks animation, controls,
and resizes; and reports an explicit error when a GPU is unavailable. It renders
directly into a Vulkan swapchain, including during window movement, and checks
modern/compatibility presentation through 4K without CPU image readback.
It also checks a configurable large-page startup arena, pooled GPU allocations,
deferred range reuse, and graphics/presentation retirement.

## Repository layout

```text
tools/                 projection generator, SDK verifier, assembler wrapper
vk/loader/             IAT/thunk, delay, static, dynamic, COMDAT; runtime bootstrap
examples/loaders/      ten builds of one instance/device program; stdout helper
examples/recipes/      descriptor and GPU-pointer headless compute recipes
examples/debug/        lifecycle, severity/output routing, object names/tags/labels
examples/legacy/       fractal explorer under adaptive, compatibility, modern contracts
examples/noAPI_cube/   GPU-only textured cube with negotiated Vulkan fallbacks
examples/common/       shared build contract, context, memory, commands, WSI, math
examples/strings.inc   pooled UTF-8/UTF-16 literals for the examples
source/myhits/         a GPU-resident shooter in progress: plan, platform layer, proofs
tests/                 projection/loader/debug/explorer/cube checks and native probes
macro/struct.inc       fasm2 struct macro with escaped-member alignment fix
newcoff.inc            common AMD64 NEWCOFF and procedure setup
docs/                  projection format, loader contracts, fallback design
```

The following are generated locally:

```text
vk/core.inc            Vulkan core constants, types, and functions through 1.4
vk/<author>/*.inc      one file per extension
vk/video/*.inc         video standard header declarations
vk/vulkan-1.def        all function names for the delay-load import library
tests/vk/*.inc, *.txt   complete include list, layout assertions, SDK manifests
build/                 objects, reports, maps, executables, ABI verification logs
```

## Calling the projection

A source selects its API surface with explicit includes, then includes a loader
to turn the gathered function names into callable instructions:

```asm
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/static.inc'

; In a procedure, with instance_info and instance declared by the program:
vkCreateInstance addr instance_info, 0, addr instance
```

Each generated definition has one owner. The includes have no guards or nested
includes, so include each file once and include its declared dependencies first.
The loader include's position determines which functions it binds. The lazy
loaders read the program's `instance` and `device` qwords and resolve each slot
on its first call.

See [the projection format](docs/vulkan.md), [the loader contracts](docs/loaders.md),
[the import/storage policy](docs/binary-layout.md),
and [the loader examples](examples/loaders/README.md). Start with the
[compute recipe](examples/recipes/README.md) for a complete headless GPU operation.
The
[debug-utils examples](examples/debug/README.md) demonstrate message callbacks,
console/debugger/file sinks, and object/workload annotations.
The [legacy examples](examples/legacy/README.md) apply
[graceful fallback](docs/legacy.md) to one Vulkan application, and show a
contract deciding at assembly time which side of each operation exists.

`source\myhits` is a shooter being built on a modern-only contract, with its
world on the GPU and no descriptors. [Its plan](source/myhits/plan.md) says
where it is going; [its proofs](source/myhits/proofs/README.md) are each idea
it rests on, small, runnable and checked. They need the SDK's `slangc`.
