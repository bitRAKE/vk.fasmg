# Loaders

The generated includes name functions; they do not make them callable. Each
file appends the functions it owns to one of two lists, and a loader, an
include from `vk\loader\`, turns the lists into interfaces. Which loader, and
where its include sits, is the build option. The includes themselves are
described in [vulkan.md](vulkan.md).

## The lists

```
define loader_functions_instance	vkCreateInstance,vkDestroyInstance,vkEnumeratePhysicalDevices,...
define loader_functions_device	vkDeviceWaitIdle,vkCmdDraw,...
```

A function is listed by the resolver that serves it:

- `loader_functions_device`: what dispatches from a `VkDevice`, `VkQueue`,
  `VkCommandBuffer` or a child of one. `vkGetDeviceProcAddr` serves these.
- `loader_functions_instance`: everything else. `vkGetInstanceProcAddr` serves
  these: what dispatches from a `VkInstance` or `VkPhysicalDevice`, given the
  instance, and the functions that precede any instance, given none.
  `vkGetDeviceProcAddr` itself is here.

The pre-instance functions (`vkCreateInstance` and the three
`vkEnumerateInstance...`) share the instance list because a lazy loader resolves
against whatever instance exists at the first call, which for them is normally
none. The Khronos loader also resolves them against a live instance
(checked on 1.4.363); the specification only promises a null one.

## What a loader does

A loader takes the lists it finds and empties them. Includes that follow start
new lists, for a later loader to bind another way, so position decides what a
loader binds.

For every function it takes, a loader defines an instruction and, once the
object refers to it, a qword slot of the same name. The instruction calls
through the slot:

```asm
vkCreateInstance addr instance_info, 0, addr instance	; fastcall [vkCreateInstance], ...
```

`vkGetInstanceProcAddr` is what the others are resolved with. It is an import
under every loader, except that a delay-load link takes it from the library
when it loads it.

| Include | Slots live | Bound | Objects |
| --- | --- | --- | --- |
| `iat.inc` | in the import table | by Windows, before the program starts | any number |
| `iat.inc`, linked for delay-load | in a table the linker builds | lazily, through `loader\delay.asm` | any number |
| `static.inc` | in the object, for the functions it refers to | lazily | one |
| `dynamic.inc` + `loader.asm` | in a loader object built last | lazily | any number |
| `comdat.inc` | in COMDAT sections the linker merges | lazily | any number |

Every loader gives a slot the symbol `__imp_vkName`. An object's reference
therefore binds to whichever defines that symbol: an object's definition if
there is one, `vulkan-1.lib` otherwise. The same object code links either way,
and the link map names every slot a program defines.

`examples\loaders` builds one program under each loader and compares the
executables; `build.cmd loaders` runs it.

## `iat.inc`

Declares the functions the object refers to as imports. Nothing runs at
start-up; Windows fills the slots, and does not start the program if
`vulkan-1.dll` lacks one of them.

It works for whatever `vulkan-1.lib` exports, extensions included: their
includes only have to come before `iat.inc`. As of SDK 1.4.363 the library
exports 265 functions, which are all of `core.inc` and all of exactly eight
extension files:

| File | Functions |
| --- | --- |
| `khr\surface.inc` | 5 |
| `khr\swapchain.inc` | 9 |
| `khr\display.inc` | 7 |
| `khr\display_swapchain.inc` | 1 |
| `khr\get_surface_capabilities2.inc` | 2 |
| `khr\get_display_properties2.inc` | 4 |
| `khr\win32_surface.inc` | 2 |
| `ext\headless_surface.inc` | 1 |

No other extension file has an exported function. Calling one that was taken
by `iat.inc` fails at link time with an unresolved `__imp_` symbol; including
its file without calling it costs nothing.

Binding the core API through the import table and the rest lazily is a matter
of position:

```asm
include 'vk\core.inc'
include 'vk\khr\surface.inc'
include 'vk\khr\win32_surface.inc'
include 'vk\khr\swapchain.inc'
include 'vk\loader\iat.inc'		; everything above
include 'vk\ext\debug_utils.inc'
include 'vk\loader\static.inc'		; everything since
```

## Delay-load: `iat.inc` with `loader\delay.asm`

Windows has a lazy binder of its own. Linked with `/DELAYLOAD:vulkan-1.dll`,
a program's imports from that library are no longer bound before it starts.
The linker gives each a slot in a table of its own and points the slot at a
thunk. On the first call the thunk sets the argument registers aside, XMM0 to
XMM3 included, calls a helper with the slot, and jumps to what the helper
returns. That is the lazy trampoline below, built by the linker.

It was designed for a library, or an export, that may not be there. Vulkan
asks two things more of it, and both can be supplied:

- **Most functions are not exports.** `vulkan-1.dll` exports 265 of the 842.
  The linker makes slots only for names an import library has, so the
  generator writes `vk\vulkan-1.def`, naming every function, and `lib` turns
  it into an import library that takes the place of `vulkan-1.lib`.
- **Addresses come from `vkGetInstanceProcAddr`, not from the export table.**
  The helper is the mechanism's one replaceable part. `loader\delay.asm`
  provides it: on first use it loads the library, takes
  `vkGetInstanceProcAddr` from its export table, and answers every slot with
  that function and the qword `instance`. The helper Visual C++ ships asks the
  export table only, and wants parts of the C run-time these programs do not
  link.

Nothing changes in the sources: they use `iat.inc`. The link does it:

```bat
fasm2 -iinclude('newcoff.inc') vk\loader\delay.asm build\vk_delay.obj
lib /DEF:vk\vulkan-1.def /MACHINE:X64 /OUT:build\vulkan-1-delay.lib
link ... build\vk_delay.obj build\vulkan-1-delay.lib /DELAYLOAD:vulkan-1.dll
```

What that buys:

- Every function, exported or not, in any number of objects, with no loader
  object and no COMDAT sections: to the linker these are ordinary imports.
- The program starts without `vulkan-1.dll`. While the library cannot be
  loaded every function returns `VK_ERROR_INITIALIZATION_FAILED`, so a program
  whose first call is `vkCreateInstance` fails the ordinary way.
- The thunk knows its slot without looking at the call, so a slot may be
  reached any way at all, not only by `call [slot]`.
- Every address is one of the Vulkan loader's entry points, which dispatch on
  the handle they are given: any number of devices.

What it costs:

- The most bytes of any binding: a descriptor, a name with a hint and a
  twelve-byte thunk per function, beside the slots.
- A device call goes through the Vulkan loader's dispatch, where a lazy device
  slot holds the device's own entry.
- An import library to build, once per registry rather than per program.
- An executable whose delay-import table names functions `vulkan-1.dll` does
  not export, which tools that list imports will show.

It is still one instance, and a function the implementation does not have
still resolves to null.

## The lazy trampoline

`static.inc`, `loader.asm` and `comdat.inc` share it (`lazy.inc`). Every slot
starts out pointing at a resolver. The first `call [slot]` lands there. The
resolver finds the slot from the call's rip-relative operand and the name from
the slot, asks `vkGetInstanceProcAddr` or `vkGetDeviceProcAddr`, stores the
answer in the slot and jumps to it. Later calls go straight through.

What that asks of the program:

- **`call [slot]` is the only way to a slot.** The resolver reads the four
  bytes before the return address as the operand of that instruction. A slot's
  value copied elsewhere and called, or a `jmp [slot]`, sends it astray. The
  instructions the loaders define always use the right form.
- **`instance` and `device`.** The resolvers read two qwords by those names,
  which the application defines and fills: zero until the instance exists,
  then the handles. One instance and one device per process. With more than
  one object, the object that defines them publishes them.
- **The slots stay writable.**
- **A function the implementation does not have resolves to null.** The call
  then jumps to address zero. Enable the extension before its first call.

What the resolver preserves:

- **The integer arguments.** RCX, RDX, R8 and R9 are parked in the home space
  the caller already reserved; stack arguments are not touched.
- **The float arguments.** XMM0 to XMM3 are saved across the resolver call,
  which is free to clobber them. This matters: five functions take floats by
  value, in XMM1 to XMM3, and without the save their first call would pass
  whatever the resolver left behind.

  | Function | Float parameters |
  | --- | --- |
  | `vkCmdSetLineWidth` | `lineWidth` |
  | `vkCmdSetDepthBias` | `depthBiasConstantFactor`, `depthBiasClamp`, `depthBiasSlopeFactor` |
  | `vkCmdSetDepthBounds` | `minDepthBounds`, `maxDepthBounds` |
  | `vkCmdSetExtraPrimitiveOverestimationSizeEXT` | `extraPrimitiveOverestimationSize` |
  | `vkSetDeviceMemoryPriorityEXT` | `priority` |

`tests\vk\lazy_probe.asm` checks all of this against a stand-in resolver that
wrecks every volatile register, with no Vulkan involved.

## `static.inc`

The trampoline for a single object. Slots exist only for the functions the
object refers to, in one table with a mirrored table of names. Each object
that includes it gets its own tables and resolver, so it suits a program
whose Vulkan calls are in one object.

## `dynamic.inc` and `loader.asm`

For a program of several objects sharing one table.

`dynamic.inc` declares the slots as external symbols and, at the end of the
source, writes the functions the object refers to into a named `virtual`,
which fasmg saves as `<object>.vkuse`. The report is in the form the generated
includes use:

```
define loader_functions_instance	vkCreateInstance
define loader_functions_device	vkDeviceWaitIdle
```

`loader.asm` is assembled once every object exists, with the reports put ahead
of it:

```bat
fasm2 -iinclude('newcoff.inc') -iinclude('build/a.vkuse') -iinclude('build/b.vkuse') vk\loader\loader.asm build\loader.obj
```

It defines a slot for every function a report names, once however many objects
named it, plus `vkGetDeviceProcAddr` whenever a device function is present,
and publishes the slots. The table is as dense and as ordered as a single
object's. The cost is in the build: the loader object depends on every other
object, and is rebuilt when any report changes.

## `comdat.inc`

For a program of several objects with nothing built last.

Each object emits the slots it refers to, one COMDAT section apiece, selected
`any`, under the function's `__imp_` name. The linker keeps one copy of each
across the program. A slot's section, `.data$vk`, holds the slot's eight bytes
and nothing else; the linker places equally named sections together, so the
slots of the whole program end up side by side: a table the linker built, as
dense as the loader object's. In the loader examples twelve slots from two
objects occupy 96 bytes.

The linker gives that table no particular order, so a second table cannot
mirror it. A slot instead starts out pointing at a few bytes of its own, in
another COMDAT section, that hand its name to the resolver:

```
__lazy_vkDeviceWaitIdle:
	lea r10,[name]
	jmp __lazy_device
name	db 'vkDeviceWaitIdle',0
```

Those bytes run once and sit apart from the slots. Nothing depends on how the
linker orders or spaces sections: an incremental link sets the slots 16 bytes
apart instead of 8, and the program still runs.

Against the loader object, per function: about twelve bytes of code where the
mirrored table has an eight-byte pointer, and two sections and two symbols in
every object that uses the function.

## More than one device

No loader here keeps a table per device. What exists reaches further than its
single `device` suggests, and the rest is a layer a program puts on top of a
loader, not another loader.

**What already serves any number of devices.** A function bound by `iat.inc`,
delay-loaded or not, is the Vulkan loader's own entry point, which dispatches
on the handle it is given. So does anything `vkGetInstanceProcAddr` returns: the lazy instance
slots serve every physical device and device of the one instance.

**What does not.** A lazy device slot holds what `vkGetDeviceProcAddr`
returned for the device in `device`. The specification makes that address
valid for that device and its children only. Two devices on one adapter
shared it when tried; devices of different drivers cannot be expected to.

**Binding device functions through the instance.** A program that wants
several devices and can spare an indirect jump per call hands the device list
to the instance resolver before a loader takes it:

```asm
include 'vk\core.inc'
include 'vk\khr\swapchain.inc'

irpv functions, loader_functions_device
	define loader_functions_instance functions
	restore loader_functions_device
end irpv

include 'vk\loader\static.inc'
```

Every slot is then resolved by `vkGetInstanceProcAddr`, whose answer for a
device function is an entry point that dispatches on the handle; `device` is
no longer read. This works under `static.inc`, `dynamic.inc` and `comdat.inc`
alike, and was checked with two devices. It is still one instance.

**A table per device.** The direct path on each of several devices takes a
table of slots per device and call sites that say which table, such as
`call [rbx + slot]`. That is a different interface from `vkName arguments`,
which is why it belongs to the program. The lists give it what it needs:
walked before a loader takes them, `loader_functions_device` yields the
functions to lay out as a table and to fill, once per device, with
`vkGetDeviceProcAddr`.

## Choosing

| | `iat.inc` | delay-load | `static.inc` | `dynamic.inc` + `loader.asm` | `comdat.inc` |
| --- | --- | --- | --- | --- | --- |
| Code at run time | none | linker's thunks, helper | resolver | resolver | resolver |
| Extension functions | the eight exported files | all | all | all | all |
| Program starts without the function | no | yes | yes | yes | yes |
| Program starts without `vulkan-1.dll` | no | yes | no | no | no |
| Slot table | import table | linker's | dense | dense | dense |
| A device call goes | through the Vulkan loader | through the Vulkan loader | straight to the device | straight to the device | straight to the device |
| Devices | any number | any number | one | one | one |
| Build step beyond the objects | none | import library, once | none | loader object | none |
