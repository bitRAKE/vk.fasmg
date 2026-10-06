# Debug-utils examples

Three headless Windows x64 programs in this folder exercise every command in
`VK_EXT_debug_utils`. They use the generated projection and `static.inc`, with
one instance and device per process. They need Vulkan 1.1 and the instance
extension, with no window, surface, shader, or device extension.

From the repository root:

```bat
build.cmd debug
build.cmd check-debug
```

`debug` builds and verifies the examples. `check-debug` also repeats them with
`VK_LAYER_KHRONOS_validation`, supplied by the Vulkan SDK. The default build
includes them, and `build.cmd check` runs the loader and debug checks together.
For the complete console stream, run an individual executable from the root:

```bat
build\debug_lifecycle.exe
build\debug_outputs.exe
build\debug_objects.exe
```

## Lifecycle logging: `00_lifecycle.asm`

A `VkDebugUtilsMessengerCreateInfoEXT` in `VkInstanceCreateInfo.pNext` handles
loader, driver, and layer diagnostics emitted during `vkCreateInstance` and
`vkDestroyInstance`. Its callback code and user data stay alive until destruction
returns. A separately created messenger handles the intervening calls and is
destroyed before the instance.

The application submits explicit create/destroy events for its instance,
messenger, device, and semaphore with `vkSubmitDebugUtilsMessageEXT`. Vulkan
does not promise a diagnostic for every object creation or destruction; this
extension is a message channel, not an automatic lifetime tracer. Instance
boundary records go directly to stdout because a valid instance is required to
submit an application message. All successfully created resources are cleaned
up on both success and failure. Loader INFO messages can make the console stream
long; the check saves the complete stream under `build\debug_checks\`.

[Instance creation/destruction callbacks](https://docs.vulkan.org/refpages/latest/refpages/source/VK_EXT_debug_utils.html#_examples)

## Severity and output: `01_outputs.asm`

Console, debugger, and file are independent destinations. Three messengers use
the same callback with different severity masks and `pUserData` sink descriptors:

| Severity | Console | Debugger | File |
| --- | --- | --- | --- |
| Verbose | | | yes |
| Info | | yes | yes |
| Warning | yes | yes | yes |
| Error | yes | yes | yes |

All three accept GENERAL, VALIDATION, and PERFORMANCE message types. The example
submits four GENERAL messages to demonstrate filtering. Its ERROR message is
synthetic and does not represent invalid Vulkan usage. The bootstrap callback
accepts warning/error diagnostics during instance creation and destruction.

- Console: `GetStdHandle` and `WriteFile`, including redirected stdout.
- Debugger: convert callback UTF-8 to UTF-16 and call `OutputDebugStringW`.
  Observe it in an attached debugger or a compatible debug-output viewer.
- File: `build\debug_outputs.log`, UTF-8 without a BOM, replaced on each run.
  The file opens before instance creation and closes after instance destruction.

The callback records severity, message types, both message IDs, object types,
64-bit handles, names, and queue/command label stacks. It consumes callback data
synchronously, returns `VK_FALSE`, and calls no Vulkan commands. An SRW lock
protects the bounded 4096-byte record buffer, counters, and complete writes.
Oversized records are truncated; Win32 write/conversion failures and actual
validation warnings/errors cause a failing exit status.

[Messenger filtering and callback threading](https://docs.vulkan.org/refpages/latest/refpages/source/VkDebugUtilsMessengerCreateInfoEXT.html)

## Names, tags, and labels: `02_objects.asm`

The program creates and names a device, queue, command pool, command buffer, and
buffer with `vkSetDebugUtilsObjectNameEXT`, then renames and clears the buffer's
name. `vkSetDebugUtilsObjectTagEXT` attaches an application-defined binary tag
containing `asset-id:42`; a tool must understand that tag's numeric identifier
and payload format to interpret it. Names and tags have no Vulkan getter.

It records nested, colored command-buffer regions plus an inserted checkpoint,
and submits the label-only command buffer inside a queue region with a queue
checkpoint. All six queue/command label functions are used. The buffer needs no
memory because the recorded commands never access it. Queue completion precedes
resource destruction.

Application messages supply explicit `pObjects` and label arrays mirroring live
handles and active regions. The console demonstrates formatting that metadata;
it does not claim to query names/tags back from Vulkan or manufacture a
validation error. Validation layers and capture tools can separately use the
names and recorded labels when reporting actual diagnostics or displaying work.

[Object naming](https://docs.vulkan.org/refpages/latest/refpages/source/vkSetDebugUtilsObjectNameEXT.html),
[object tags](https://docs.vulkan.org/refpages/latest/refpages/source/vkSetDebugUtilsObjectTagEXT.html),
[callback metadata](https://docs.vulkan.org/refpages/latest/refpages/source/VkDebugUtilsMessengerCallbackDataEXT.html)

## Validation

`tests\verify-debug-examples.ps1` checks lifecycle order, the exact severity
routing to stdout and the file, UTF-8/UTF-16 text, live named handles, rename/clear,
and label metadata. Its small Win32 helper in `tests\capture-debug-output.cs`
launches the output example as a debuggee and reads real
`OUTPUT_DEBUG_STRING_EVENT` records. This verifies debugger output independently
of the program's callback counters, without installing a debugger.

The script saves stdout, file, and debugger logs under
`build\debug_checks\default\` and, with validation, `build\debug_checks\validation\`.
Link maps confirm that the examples contain slots for all eleven extension
commands. The validation run also checks that the Khronos layer was observed,
and rejects validation diagnostics. The helper requires x64 Windows PowerShell
and uses its built-in `Add-Type`; it introduces no external build path.
