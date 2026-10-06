# Vulkan projection and examples for fasmg

This is a minimal Windows x64 repository for projecting the Vulkan registry
into fasmg/fasm2 includes and demonstrating how to bind the resulting functions.
It contains the projection generator, ABI verification, five loader strategies
demonstrated by six console programs, three debug-utils examples, and their
focused tests.

## Requirements

- Windows x64 and a Vulkan SDK with `VULKAN_SDK` set.
- Visual Studio C++ tools (`nmake`, `link`, `lib`, and `dumpbin`).
- LLVM clang, used to verify the Windows x64 ABI against the SDK headers.
- [fasm2](https://github.com/tgrysztar/fasm2) with AMD64 NEWCOFF support.
- A Vulkan 1.1 capable driver for running the loader examples, including
  `VK_KHR_surface` and, except for the IAT example, `VK_EXT_debug_utils`.
- The Vulkan SDK's Khronos validation layer for `check-debug` and `check`.

The makefile defaults to `..\fasm2\fasm2.cmd` and
`%ProgramFiles%\LLVM\bin\clang.exe`. Override either when needed:

```bat
build.cmd "FASM2=C:\tools\fasm2\fasm2.cmd" "CLANG=C:\tools\LLVM\bin\clang.exe"
```

## Build and validation

Run from the repository root:

```bat
rem Generate, verify against the SDK, and build loader/debug examples:
build.cmd
rem Generate and verify the projection only:
build.cmd api
rem Build, run, and compare all six loader examples:
build.cmd loaders
rem Build and verify the three debug-utils examples:
build.cmd debug
rem Repeat debug checks with the Khronos validation layer:
build.cmd check-debug
rem Run all projection, loader, and debug checks:
build.cmd check
rem Run just the projection and loader checks:
build.cmd check-api
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
against a stand-in resolver that clobbers volatile registers. It runs all six
examples, checks their imports and dense slot tables, and links the delay-load
example against an absent DLL to verify its ordinary initialization failure.
It also verifies the [debug-utils examples](examples/debug/README.md), including
actual Windows debugger events and runs under the Khronos validation layer.

## Repository layout

```text
tools/                 projection generator, SDK verifier, assembler wrapper
vk/loader/             handwritten IAT, delay, static, dynamic, COMDAT loaders
examples/loaders/      six builds of one instance/device program; stdout helper
examples/debug/        lifecycle, severity/output routing, object names/tags/labels
tests/                 projection/loader/debug checks, probes, debugger capture
macro/struct.inc       fasm2 struct macro with escaped-member alignment fix
newcoff.inc            common AMD64 NEWCOFF and procedure setup
docs/                  projection format and loader contracts
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
and [the six loader examples](examples/loaders/README.md). The
[debug-utils examples](examples/debug/README.md) demonstrate message callbacks,
console/debugger/file sinks, and object/workload annotations.
