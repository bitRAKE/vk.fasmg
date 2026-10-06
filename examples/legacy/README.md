# Vulkan Atlas: graceful fallback in a fractal explorer

Three Windows x64 GUI programs share a Mandelbrot camera, eight palettes,
click-to-center navigation, and a 512 by 384 BMP exporter. Every rendering path
keeps those controls. The status line identifies the backend and Vulkan routes.

| Source | Executable in `build\` | Policy |
| --- | --- | --- |
| `00_adaptive.asm` | `legacy_adaptive.exe` | Prefer available core/KHR routes; fall back independently |
| `01_compatibility.asm` | `legacy_compatibility.exe` | Mask all five optional routes; reuse a render pass/framebuffer, shader modules, legacy barriers/copy/submission, and a fence; tile at most 128 pixels |
| `02_software.asm` | `legacy_software.exe` | Start directly with CPU double precision; no Vulkan runtime needed |

## Build and run

From the repository root:

```bat
build.cmd legacy
build\legacy_adaptive.exe
build\legacy_compatibility.exe
build\legacy_software.exe
rem Repeat all cases with core and synchronization validation:
build.cmd check-legacy
```

The standard repository toolchain is sufficient. The Vulkan SDK's
`glslangValidator.exe` compiles the two GLSL shaders for Vulkan 1.0, and
`spirv-val.exe` validates them before assembly. There is no shader download or
additional external source tree. The GPU backend needs a Vulkan 1.1 runtime and
graphics device. The application can run entirely in software if they are
absent. Vulkan is loaded explicitly rather than listed in the PE imports.

| Input | Action |
| --- | --- |
| Wheel, `+`, `-`, zoom buttons | Zoom around the current center |
| Arrow keys | Pan |
| Left click on image | Move that location to the center |
| `P`, Palette | Cycle palette |
| `R`, Reset | Restore initial camera and palette |
| `D`, Deep zoom | Visit the precision fallback bookmark |
| `C`, CPU / GPU | Toggle the software override |
| `S`, Export BMP | Save the full image with a native file dialog |

The camera uses doubles in all profiles. Views narrower than `0.0001` use CPU
double precision; zooming back out permits Vulkan again. This is an application
alternate for shader float precision, and does not require `shaderFloat64`.
Rendering uses 192 escape iterations. CPU and GPU arithmetic can produce
different escape counts at boundary pixels.

## What the fallback demonstrates

`capabilities.inc` probes five route descriptors: dynamic rendering,
synchronization2, copy commands2, maintenance5 inline shader code, and timeline
semaphores. It filters feature-query structures, rebuilds the device-create
chain, and resolves selected device commands through their core or KHR names.
Only selected supported feature bits are enabled.

`gpu.inc` renders offscreen to BGRA, reads the image through a host-visible
staging buffer, and waits for completion before reading each tile. Non-coherent
memory gets invalidated. Win32 GDI presents the same pixels that the exporter
writes; this set focuses on capability fallback rather than swapchain handling.
Image-format and physical-device extent limits constrain allocations. The
compatibility policy's 128-pixel ceiling forces twelve tiles for the complete
512 by 384 image on normal hardware.

The synchronization translator and timeline/fence alternate cover this serial
single-queue workload. The render-pass/framebuffer cache has one entry. They
are not general implementations of every modern API semantic. Descriptor
fallbacks, shader objects, multiple queues, arbitrary timeline operations, and
compile-time pruning are future topics described in
[the reviewed design notes](../../docs/legacy.md).

## Forcing routes and checking results

The adaptive executable accepts independently composable switches:

```bat
build\legacy_adaptive.exe --no-rendering --no-inline
build\legacy_adaptive.exe --no-sync2
build\legacy_adaptive.exe --no-timeline
build\legacy_adaptive.exe --no-copy2
build\legacy_adaptive.exe --force-khr
build\legacy_adaptive.exe --api-1.2
```

`--force-khr` selects only advertised extension routes whose dependencies fit
the effective API version; a missing extension selects its fallback. API 1.2
uses KHR rendering/sync2/copy2 when available, core timeline completion, and
explicit shader modules. No switch forces an unsupported feature on.

`--self-test` creates the real window hidden, sends toolbar commands through its
window procedure, and exits. It saves baseline, zoom, pan, palette, reset, deep,
and CPU-override exports, a GUI snapshot, and a UTF-16 capability report in
`build\legacy_<profile>*`. The test script archives each run under
`build\legacy_checks\<mode>\<case>\`, along with actual Windows debugger output.
Run the executables from the repository root for these relative test paths.

Tests require complete opaque images, changed pixels for each navigation and
palette action, exact reset restoration, exact GPU output across fallbacks,
and identical CPU output across profiles. CPU/GPU baseline differences may
occupy less than two percent of pixels to allow float boundary rounding.
The missing-driver case sets `VK_DRIVER_FILES` to an absent manifest for the
child process and verifies the complete software application; it does not
modify an installed runtime or driver.

`check-legacy` additionally enables `VK_LAYER_KHRONOS_validation` and
`VK_LAYER_VALIDATE_SYNC=1`, checks that both activate, and rejects validation
warnings/errors. It restores the invoking environment afterward. The sync
setting follows the
[Khronos validation migration guidance](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/main/docs/updating_from_VK_EXT_validation_features.md).
If no usable GPU exists, the script reports that GPU equivalence coverage was
unavailable while still checking the software GUI and recovery.
