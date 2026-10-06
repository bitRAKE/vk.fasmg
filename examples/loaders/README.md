# Loader examples

One program, built under each loader in `vk\loader`.  Its two source halves,
`instance.inc` and `device.inc`, are the same text in every build.  A build is
the handful of include lines ahead of them, and those lines are the whole
difference between one binding and another.

```bat
build.cmd loaders
```

builds the six executables, runs them and prints what each is made of.

The program creates an instance and calls one function of each kind a loader
has to deal with:

- `vkEnumerateInstanceVersion`, which needs no instance, first called once
  there is one;
- `vkDestroySurfaceKHR`, from an extension `vulkan-1.dll` exports;
- three `VK_EXT_debug_utils` functions, from an extension it does not export:
  a messenger is created, sent one message, which it prints, and destroyed;
- device functions, after creating a device on the first adapter.

## The six builds

| Example | Sources | Loaders, in include order |
| --- | --- | --- |
| `loader_iat.exe` | `iat.asm` | `iat.inc` |
| `loader_delay.exe` | `delay.asm` | `iat.inc`, linked for delay-load with `vk\loader\delay.asm` |
| `loader_static.exe` | `static.asm` | `static.inc` |
| `loader_mixed.exe` | `mixed.asm` | `iat.inc` after core and surface, `static.inc` after debug_utils |
| `loader_dynamic.exe` | `dynamic_app.asm`, `dynamic_device.asm` | `dynamic.inc` in both, then `vk\loader\loader.asm` over their reports |
| `loader_comdat.exe` | `comdat_app.asm`, `comdat_device.asm` | `comdat.inc` in both |

Each source's header gives its commands; the makefile rules named
`$(BUILD)\loader_*` are the same commands with dependencies.

## What comes out

With Vulkan SDK 1.4.363.0 and the minimal stdout helper:

| Example | Objects | Imports | Delayed | Slots | Support bytes | Exe bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| iat | 1 | 8 | 0 | 0 | 0 | 4608 |
| delay | 2 | 0 | 11 | 0 | 1242 | 6656 |
| static | 1 | 1 | 0 | 12 | 539 | 5120 |
| mixed | 1 | 9 | 0 | 3 | 259 | 5120 |
| dynamic | 3 | 1 | 0 | 12 | 539 | 5120 |
| comdat | 2 | 1 | 0 | 12 | 663 | 5120 |

- **Objects**: Vulkan program and loader objects; the shared stdout helper is
  omitted. The second object of `delay` is the helper, the third of `dynamic`
  the loader object.
- **Imports**: Vulkan functions Windows binds before the program starts.
- **Delayed**: Vulkan functions in slots the linker built for delay-loading.
  One fewer than the lazy builds have slots: nothing here asks for
  `vkGetDeviceProcAddr`.
- **Slots**: function slots the program defines for itself, eight bytes each.
  In every build that has them they lie side by side as one table, and the
  link map names each one `__imp_vkName`.
- **Support bytes**: what serves the slots: resolver code and names; for
  `comdat` the first-call stubs; for `delay` the helper and the linker's
  thunks, descriptor and name tables.

## What each is for

**iat.**  Nothing of the program's own stands between a call and Vulkan: no
resolver, no table, no first call that costs more than the rest.  A function
the installed `vulkan-1.dll` lacks is reported by Windows before the program
runs.  The price is reach: only exported functions can be bound, so this build
leaves `debug_utils` out and says so when it runs, and every function the
program refers to must exist for it to start at all.

**delay.**  The import-table source, bound by the linker's own lazy
mechanism.  It reaches every function, starts whether or not `vulkan-1.dll`
is installed, and fails at `vkCreateInstance` the ordinary way if it is not.
Its slots serve any number of devices, and may be reached any way a program
likes.  The price is the most bytes of any build, 1242 here, a device call
that goes through the Vulkan loader instead of straight to the device, and an
import library built from `vk\vulkan-1.def`.

**static.**  Any extension's functions, with `vkGetInstanceProcAddr` as the
only import.  A function is bound when it is first called, so one on a path
never taken is never asked for, and its absence costs nothing.  The price is
539 bytes of resolver and names, slots that stay writable, and a first call
that goes through the resolver.  One object: a second object using
`static.inc` would get tables of its own.

**mixed.**  The import table for what it can reach, lazy slots for the rest:
the three `debug_utils` functions.  It carries the least machinery of any
build that reaches them, 259 bytes, at the price of the import table's
start-up condition for the eight exported functions.

**dynamic.**  Several objects, one table.  Neither object defines a slot;
each reports what it calls, and the loader object holds every function once,
however many objects call it, in list order.  The price is in the build: the
loader object is assembled after the other two, from their reports, and again
whenever a report changes.

**comdat.**  Several objects with nothing built last.  Each object is complete
on its own; the linker merges the slots and still lays them out as one table.
The price is 124 more bytes than the loader object here, a first-call stub per
function where the loader object has a name pointer, and an object format with
COMDAT sections.

Under all six the call sites are identical, `vkName arguments` assembling to
`call [vkName]`.  All but `delay` need `vulkan-1.dll` to start.
[docs/loaders.md](../../docs/loaders.md) describes the loaders themselves.
