# The `vk\` projection

`tools\gen-vulkan-functions.ps1` projects the Vulkan registry (`vk.xml`,
`video.xml`) into fasmg includes for the Windows x64 ABI. This document says
what the includes contain, what they expect of the source that includes them,
and why. How the functions become callable is in [loaders.md](loaders.md).

## Layout

```
vk\              core.inc: constants, types and functions through Vulkan 1.4
                 vulkan-1.def: every function, for a delay-load import library
    khr\ ext\ nv\ ...   one file per extension, in its author's directory:
                        VK_EXT_debug_utils -> ext\debug_utils.inc
                        VK_NV_mesh_shader  -> nv\mesh_shader.inc
    video\       one file per video std header:
                        vulkan_video_codec_h264std -> codec_h264std.inc
    loader\      hand-written; see loaders.md
```

Everything but `loader\` is generated locally and ignored by Git. The generator
empties each directory it writes of `*.inc` first, so an extension that leaves
the registry leaves the tree.

## Requirements

| Requirement | Reason |
| --- | --- |
| fasm2, with the NEWCOFF object format (`newcoff.inc`) | The loaders use COMDAT sections and section names longer than eight characters, neither of which classic COFF has. |
| The project's `macro\struct.inc`, included before any other | Members named like instructions; see below. |
| Each generated file included at most once | The files carry no guards. |
| A file's needs included as well | See *One owner per definition*. |

`newcoff.inc` meets the first two.

## Include order is the build option

A source selects its API surface by what it includes, and a loader turns what
has been gathered so far into function interfaces:

```asm
include 'newcoff.inc'
include 'vk\core.inc'
include 'vk\ext\debug_utils.inc'
include 'vk\loader\static.inc'
```

The generated files have no include guards, no nested includes and no
conditional definitions. Nothing is switched by a symbol; a definition exists
because its file was included.

## One owner per definition

Without guards a definition cannot be repeated by every file that requires it,
so each constant, type and function is emitted by exactly one file. 87 are
required by more than one extension. Among the candidates the owner is, in
order of preference:

1. a video header, for the types it defines;
2. an extension that requires the definition outright, rather than inside a
   `<require depends="...">` block describing an interaction with another
   extension, or through a struct member;
3. the lowest registry number, which is the order the C headers define things
   in.

A file says in its header comment where the rest of what it requires lives:

```
; VK_EXT_shader_object, device extension 483. Generated from vk.xml; do not edit.
; in vk/ext/extended_dynamic_state3.inc: VkColorBlendAdvancedEXT, vkCmdSetPolygonModeEXT, ...
```

```
; VK_KHR_get_surface_capabilities2, instance extension 120. Generated from vk.xml; do not edit.
; needs vk/khr/surface.inc
```

`in` names definitions the extension provides that another file emits:
including that file is how a source gets them. `needs` is stronger: a struct
here embeds one defined there, and the file does not assemble without it. The
order of the two includes does not matter; fasmg resolves the reference in a
further pass when the embedded definition comes later.

Including a file does not enable its extension. It adds definitions, and names
to the loader lists; with a lazy loader an unused name costs nothing.

`tests\vk\report.txt` lists every shared definition and every `needs`. Today
25 files draw on another, the graph has no cycle, and three files are drawn on
by more than one (`khr\acceleration_structure.inc`, `khr\surface.inc`,
`khr\video_queue.inc`). Nested includes would have to cope with those three
being reached twice.

## What an include does not say

The registry relates extensions in more ways than the tree acts on. A file's
header carries the registry's `depends`, `promotedto`, `deprecatedby` and
`obsoletedby`; the files themselves neither nest nor guard on any of them,
because none of these relations means "include this too":

- **Overlap.** 34 functions are provided outright by more than one extension,
  the dynamic-state setters by `VK_EXT_extended_dynamic_state*` and by
  `VK_EXT_shader_object` among them. One file lists each; a program after the
  other provider's functions includes that file without wanting its extension.
- **Interactions.** 36 functions exist only when a second extension is present
  as well, 18 of them among the 31 that `ext\extended_dynamic_state3.inc`
  lists. The file lists them regardless.
- **Numbers are not levels.** Of 23 extensions numbered after a predecessor,
  the registry makes the predecessor a dependency of 5. The rest are siblings
  (`extended_dynamic_state3` needs neither 1 nor 2; no `maintenance` needs the
  one before) or replacements (`present_id2`).
- **Features and versions.** An enabled extension, or a supported version,
  still gates each capability on a feature the program queries. `core.inc`
  lists everything through 1.4 whatever a device reports.

So the includes state vocabulary: which names a source may write. What is
present is a run-time question the program asks of each device, and the
relations above are documented for the programmer rather than enforced.

Extensions promoted into the 1.4 core keep their file. Their types and
constants are in `core.inc`, so the file is left with the extension's name,
its version and any functions that exist only under the extension's spelling.

## What a file contains

```
VK_OBJECT_TYPE_DEBUG_UTILS_MESSENGER_EXT := 1000128000
define VK_EXT_DEBUG_UTILS_EXTENSION_NAME 'VK_EXT_debug_utils'
sizeof.VkDebugUtilsMessengerEXT := 8
struct VkDebugUtilsLabelEXT
	sType dd ?
	rb 4
	pNext dq ?
	pLabelName dq ?
	color rd 4
ends
define loader_functions_instance	vkCreateDebugUtilsMessengerEXT,...
define loader_functions_device	vkCmdBeginDebugUtilsLabelEXT,...
```

- **Constants** are numeric (`:=`) or, for strings, symbolic (`define`).
- **Scalar types** (handles, enums, bitmasks, function pointers) get a
  `sizeof.` constant.
- **Structs** follow the Windows x64 C layout with every padding byte written
  out. An array is reserved in units of its element's alignment, so a field's
  unit states the boundary it needs: `memoryTypes rd 64` is 32 structs of two
  dwords.
- **Unions** are opaque storage of the right size.
- **Bit-fields** have no fasmg counterpart. Each C storage unit is one field,
  `bits0`, `bits1`, ..., with a comment giving the bit range of every field it
  packs. Using them is left to the source: a local macro, or an interface
  layer above.

  ```
  	bits0 dd ?	; instanceCustomIndex:0-23 mask:24-31
  ```
- **Functions** are names appended to two lists; see [loaders.md](loaders.md).

Records whose members belong to platform headers with no Windows x64 ABI
(Xlib, XCB, Fuchsia, GGP, NvSci) are left out and listed in
`tests\vk\unsupported-types.txt`.

## Members named like instructions, and `macro\struct.inc`

Inside `struct`, a line is a member when it starts with a name that is not an
instruction. The generator keeps a list of names fasm2 would take as
instructions; four of them occur as members (`size`, `format`, `data`,
`display`), 87 times across 33 files. A leading `?` tells fasmg to take the
name as a name:

```
struct VkImageViewCreateInfo
	...
	?format dd ?
```

The `?` belongs to the declaration. The member is `VkImageViewCreateInfo.format`
everywhere else, including in an initializer (`format: VK_FORMAT_R8G8B8A8_UNORM`).

fasm2's `struct` can check each member against its natural boundary. The check
is off unless `Struct.CheckAlignment` is set, which fasm2's own Win32 headers
(`win64a.inc`, `win64w.inc`) do. As shipped, the check spells the member the
way it was declared, `VkImageViewCreateInfo.?format`, inside an expression,
which is not a valid name: `vk\core.inc` then does not assemble.

The project therefore carries its own `macro\struct.inc`: fasm2's file with one
change, in `struct?.check`, that drops the `?` before using the name. Two
things make a source get that copy rather than fasm2's:

- **Location.** fasmg looks for an included file beside the file that includes
  it, then under the working directory, then along `INCLUDE`. `newcoff.inc`
  sits beside `macro\`, so its `include 'macro/struct.inc'` finds the project's.
- **Order.** fasm2's headers sit beside fasm2's `macro\` and find their own
  copy. `struct.inc` guards itself, so whichever is included first is the one
  in effect and the other becomes nothing. `newcoff.inc` includes the
  project's before anything else.

A source that brings in fasm2's `struct.inc` ahead of `newcoff.inc`, directly
or through a Win32 header, is back to the shipped check.

The alternative was to declare every generated struct `packed`, which declines
the check. The fix was preferred because the check then has something to say:
with it on, all 1812 structs assemble without a warning, and it still reports
a real misalignment, behind an escaped name or not. `tests\vk\everything.asm`
assembles the whole tree with the check on and fails on any warning.

The copy has to follow fasm2: when `include\macro\struct.inc` changes there,
take the new file and reapply the change, which is marked in the file's
header. The change belongs upstream; once fasm2 has it, the copy and this
section can go.

## Testing

The includes assert nothing. What holds them to the SDK lives with the tests:

- `tools\verify-vulkan-projection.ps1` has clang lay out every record for the
  MSVC x64 ABI and compares size, alignment, member offsets and bit-field
  positions with `tests\vk\layouts.txt`, and compiles every constant the SDK
  headers also define as a C static assertion.
- `tests\vk\layout_asserts.inc` asserts every struct's size and member offsets
  as fasmg sees them, which ties the emitted structs to that manifest.
- `tests\vk\everything.asm` includes every file in one unit with those asserts.
  A definition emitted twice, or a struct whose embedded type no file defines,
  fails there.
- `tests\verify-vk-tree.ps1` runs that unit and the loader tests.

```bat
rem Regenerate when the generator or registry is newer; verify against the SDK:
build.cmd api
rem Also assemble, link, and run the projection and loader tests:
build.cmd check-api
```
