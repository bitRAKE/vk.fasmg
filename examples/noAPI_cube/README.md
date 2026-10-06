# NoGraphicsAPI cube

A Windows x64 assembly port of the spinning textured cube in
`NoGraphicsAPI/examples/cube`. It keeps the original geometry, LunarG texture,
camera, perspective, depth testing, nearest sampling, and derivative-based
face lighting. Like the original, it renders directly into the acquired Vulkan
swapchain image. The render fills the client area and follows its aspect ratio.

```bat
build.cmd noAPI_cube
build\noAPI_cube.exe
build.cmd check-noAPI_cube
```

Space pauses animation; Left/Right turn the cube; R resets its angle; S opens
the BMP export dialog; Escape closes the window. The title identifies the
selected resource path. Export uses the full current render resolution.

## GPU fallback

Only reported features are enabled. The scene remains complete at every step:

| Operation | Preferred path | Alternate GPU path |
|---|---|---|
| Vertex fetch | Buffer device address in root data | Conventional vertex binding |
| Texture/sampler access | `VK_EXT_descriptor_heap`, native Slang heap indexing | Separate sampled-image/sampler descriptor-set bindings |
| Root arguments | `vkCmdPushDataEXT`, no pipeline layout | Push constants and a pipeline layout |
| Index/upload/readback addresses | `VK_KHR_device_address_commands` | Buffer-backed index and copy commands |
| Rendering | Dynamic rendering | Render pass/framebuffer |
| Barriers/submission | Synchronization2 | Legacy barriers/submission |
| Command/resource retirement | Separate work and private retirement timelines | Submission fences |
| Presentation retirement | KHR/EXT swapchain-maintenance present fences | Conventional device-idle fallback |
| Pipeline shader code | Maintenance5 inline SPIR-V | Shader modules |
| Depth | D32 float | D16 UNORM, then D24 UNORM/S8 |
| Color/texture encoding | Native sRGB formats | UNORM formats with explicit shader sRGB conversion |

The native heap path requires Vulkan 1.4, descriptor heaps, shader untyped
pointers, scalar block layout, shader draw parameters, buffer device addresses,
and the rendering/maintenance5 routes. Address commands require Vulkan 1.3,
buffer device addresses, synchronization2, and their extension feature.
Pointer vertex fetch uses Vulkan 1.2. The remaining GPU path requires Vulkan
1.1, Win32 surface/swapchain support, and color, texture, and depth attachments.

There is **no software renderer**. CPU Vulkan adapters are skipped. A missing
runtime, unavailable GPU, or unrecoverable GPU failure produces an error and
nonzero exit. Presentation uses `vkAcquireNextImageKHR` / `vkQueuePresentKHR`,
FIFO pacing, and a reusable command-context pool. Only reuse of an outstanding context,
resize, export, and shutdown wait for GPU completion. Depth is reused with a
GPU barrier, as in the original. Separate graphics/present queues are supported.
Normal animation allocates no CPU image or readback buffer and makes no GDI
display calls. Export renders an offscreen GPU image on demand; readback memory
prefers host caching and non-coherent memory is invalidated explicitly.

The root matches the original 72-byte ABI: an eight-byte vertex address at
offset zero and a 64-byte row-major transform at offset eight. The conventional
vertex path reserves the address slot. UNORM recovery uses one 32-bit
fragment-stage specialization constant, ID zero, set at pipeline
creation. Bit zero enables texture sRGB decoding; bit one enables target sRGB
encoding. Format choices do not enlarge the root or change it during animation.
The GLSL fallback reads the transform as sixteen scalars to preserve that ABI
without scalar block layout.

## Startup and memory pools

Startup allocates a fixed CPU arena for allocator metadata. It attempts large
pages by default, temporarily enabling an existing `SeLockMemoryPrivilege` and
restoring its previous state after allocation. Missing privilege, unsupported
large pages, or allocation failure selects ordinary pages. Startup debugger
output and the test report record the selected mode and fallback error.
The program does not change account policy or request elevation. This arena
holds allocator metadata; Vulkan manages GPU memory separately.

| Option | Default | Accepted values |
|---|---|---|
| `--large-pages` / `--no-large-pages` | Attempt large pages | Enable attempt / use ordinary pages |
| `--cpu-heap-mib=N` | 2 MiB | 2–1024 MiB, rounded up to large-page size when used |
| `--buffer-pool-mib=N` | 1 MiB | 1–1024 MiB per buffer block |
| `--image-pool-mib=N` | 4 MiB | 1–1024 MiB per optimal-image block |

For example:

```bat
build\noAPI_cube.exe --large-pages --cpu-heap-mib=4 --image-pool-mib=32
```

GPU buffers and images suballocate persistent memory blocks through a reusable
segregated range allocator. Blocks match memory type, allocation flags, and
resource class; ordinary buffers, descriptor-heap buffers, and optimal images
use separate pools. Host-visible blocks stay mapped. Non-coherent buffer ranges
respect atom alignment and use explicit flush/invalidate operations. Required
dedicated allocations receive their own blocks. If a default block allocation
fails, the allocator tries a smaller block and then, where needed, a dedicated
allocation. Larger requests grow the pool; all block metadata comes from the
startup arena. Range allocation, splitting, coalescing, and deferred-delete
records require no operating-system heap allocations.

Geometry, texture, descriptors, and pipeline live until shutdown. Command
contexts start at two and grow under pressure to a bound of eight, after which
reuse waits for retirement. Steady rendering reuses these resources without
new Vulkan memory allocations. Resize recreates the swapchain, depth attachment,
and compatibility framebuffers while reusing compatible memory ranges. Export
resources are allocated lazily and reused until resize or shutdown. Pool blocks
remain allocated until shutdown; large pages do not apply to exported pixels.

## Synchronization

Following NoGraphicsAPI, application work signals a work timeline, then a
second signal-only submission batch advances a private retirement timeline.
Context reuse and deferred resource deletion use the private timeline. The
acquire semaphore waits at all-commands scope. A per-image binary semaphore
signals rendering completion for presentation. Devices without timeline
support use submission fences and the same resource lifetime discipline;
devices without synchronization2 use legacy submissions and barriers.

KHR or EXT swapchain-maintenance present fences track presentation-resource
retirement when available. Resize waits for the latest graphics retirement,
replaces attachments, and queues old swapchains for deletion after both graphics
and presentation retire. This path avoids a device-wide idle on resize. Shutdown
drains graphics and presentation before destroying pools. When maintenance
fences are unavailable, resize and shutdown retain the conventional device-idle
fallback. Unextended presentation lacks an explicit retirement signal; see the
[Vulkan guide](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html).
Present fences establish safe resource reclamation, not the time a frame becomes
visible on the monitor.

The normal loop renders as presentation permits. A timer continues that same
Vulkan path inside Win32's modal move/resize loop. Pause and minimization suspend
animation; the original four-degree rotation step per frame is preserved.

## Modules and validation

`features.inc` negotiates scene-specific capabilities; `scene.inc` owns the
geometry and transform; `material.inc` owns uploads and descriptor bindings;
`pipeline.inc` selects compatible shaders/pipelines; `target.inc` owns format
selection and resizable attachments; `gpu.inc` records the scene; `capture.inc`
owns on-demand export; `cube.asm` owns the window and controls. The shared
`vulkan_wsi.inc` owns presentation; `cpu_arena.inc`, `range_allocator.inc`,
`vulkan_pools.inc`, and the retirement modules own memory and resource lifetimes.
The other
[shared modules](../common/README.md) also serve the fractal examples.

Builds need an SDK containing the descriptor-heap/address-command registry
entries, `glslangValidator`, `spirv-val`, and Slang with `spvDescriptorHeapEXT`
support. The build was verified with Vulkan SDK 1.4.363.0 and its bundled Slang.
The executable embeds its shaders and texture; it needs no NoGraphicsAPI
checkout, Slang installation, or asset paths at runtime.

`--self-test` exercises real timer, keyboard, and resize messages and writes
BMPs/reports under `build`. `--present-test` exercises hundreds of presentations
at 500×500, 1080p, and 4K, plus pause, minimization, and move-loop messages,
without allocating readback storage. `--compatibility` disables optional routes.
Individual masks are `--no-heap`, `--no-address`, `--no-address-commands`,
`--no-rendering`, `--no-sync2`, `--no-copy2`, `--no-inline`, and `--no-timeline`.
`--api-1.2`, `--api-1.1`, `--force-khr`, `--depth16`, and `--linear-formats`
exercise version, command-alias, depth, and format recovery independently.
`--no-present-fences` exercises unextended WSI retirement. `--small-pools`
explicitly selects the 4 MiB default image blocks. `--dedicated-memory` and
`--noncoherent` exercise dedicated allocations and explicit flush/invalidate
calls. The last option forces those
calls even on coherent memory; it does not simulate physically non-coherent RAM.

`check-noAPI_cube` runs twenty GPU configurations with and without core and
synchronization validation, compares all eight scene/resize exports, checks
animation/pause/turn/reset, and checks unavailable-driver cleanup. A disposable
test process has its large-page privilege removed to verify ordinary-page
fallback. A native allocator probe checks 100,000 randomized operations, full
coalescing, overflow, and metadata exhaustion. `--allocator-test` gates GPU work
on a timeline semaphore, verifies that a pending allocation cannot be reused,
then checks copied data and recycling after retirement; a fence variant checks
the same payload and recycling. It also runs
both modern and compatibility presentation stress with and without validation,
requires zero live readbacks and zero new memory allocations after warmup at
each resolution, and rejects GDI imports. It validates all five
SPIR-V modules and checks their root offsets and format specialization. Local
GTX 1080 Ti runs exercised GPU pointers and
bindings, modern/KHR/legacy commands, D16, and UNORM conversion. Descriptor
heaps and address commands were not advertised locally, so their native runtime
paths remain unverified on supporting hardware.

See [NOTICE.md](NOTICE.md) for source and texture licenses.
