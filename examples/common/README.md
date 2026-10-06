# Shared example modules

The examples use one Vulkan instance/device and one UI/render thread per
process, matching the static loader's lifetime contract. These includes reuse
that negotiated context; they do not create hidden devices or global output
handles for the debug callback.

| Include | Contract |
|---|---|
| `vulkan_routes.inc` | Capability bits, and the `route`/`alternate` blocks that assemble each side of an operation only if the build's contract leaves it possible. Define `CAP_MASK`, and `CAP_REQUIRED` for a build that cannot do without some of it, then include this before the modules below. |
| `vulkan_context.inc` | Loads Vulkan explicitly; selects a graphics queue, supported core/KHR routes, memory properties, and optional debug messenger. A masked route is never a candidate; a required one that is not selected fails negotiation with `missing_caps` set. Define `TILE_CEILING`; include core, debug-utils, the static loader, pooled strings, and `DebugSink` first. |
| `vulkan_memory.inc` | Selects compatible memory types, then includes the pools. |
| `vulkan_pools.inc` | Included by `vulkan_memory.inc`. `GpuBuffer`/`GpuImage` keep handles, memory, and mappings together; creators return a Boolean and destroyers accept partial creation. `create_buffer` gives mapped host-visible memory; `create_device_buffer` gives device-local memory that is never mapped, for what only shaders touch. Persistent blocks separated by type, flags, and buffer/image class; atom-aligned mapped ranges that prefer host caching for readback, required dedicated allocations, bounded metadata, and deferred resource deletion. Initialize after the CPU arena/device; destroy after graphics retirement and resource destruction. |
| `cpu_arena.inc` | Fixed startup arena with optional large pages and ordinary-page fallback. Configure before `create_cpu_arena`; use `arena_take` only for startup metadata. Link `advapi32.lib` and supply its Win32 imports. |
| `range_allocator.inc` | Single-threaded segregated free ranges with alignment, splitting, coalescing, and a fixed node inventory from the CPU arena. Tokens identify live allocations; release each token exactly once. Heap destruction returns metadata nodes. |
| `vulkan_commands.inc` | Owns one resettable serial command buffer and the two counters every submission advances: work completion and private retirement, each a timeline semaphore, or fences tracking the same submission sequence. Creation/begin/submission return `VkResult`; serial submission waits before reuse. Resources may be queued for deletion only after their last use is submitted. |
| `vulkan_barriers.inc` | Image transitions and global memory barriers for the stage/access bits shared by sync1 and sync2. Calls use the negotiated command buffer. |
| `vulkan_wsi.inc` | Win32 surface/format/queue negotiation, FIFO swapchain, two-to-eight retirement-protected command contexts, and one presentation semaphore per image. Define `GPU_WSI`; provide the CPU arena, `window`, `module`, `frame_width`/`frame_height`, and surface/Win32/swapchain/swapchain-maintenance projection includes. Begin returns 1 for an image, 2 for resize/retry, 0 for failure; submit returns a Boolean. `wsi_wait_work` waits for graphics retirement; `wsi_drain` additionally waits for presentation. |
| `vulkan_wsi_retirement.inc` | Included by WSI. Negotiates KHR/EXT maintenance, retires old swapchains through graphics retirement plus present fences, and provides the unextended device-idle fallback. Present-fence completion permits reclamation and does not imply display timing. |
| `math3d.inc` | SSE2 row-major 4x4 multiplication; output must not alias either input. |
| `command_options.inc` | Parses Windows arguments once, matches complete case-insensitive flags and unsigned decimal `name=value` options, and frees argv. Numeric lookup returns 1/value, 0/absent, or -1/invalid. Link `shell32.lib`. |
| `bitmap.inc` | Checked top-down BGRA export; the caller supplies the BMP header, write-count fields, and application I/O status. |

Device negotiation accepts optional application hooks: `GPU_EXTRA_FORMATS`
calls `choose_formats` while considering adapters; `GPU_EXTRA_FEATURES` calls
query/enable/resolve helpers around device creation; `GPU_REMEMBER_CORE_FEATURES`
preserves application core-feature query results before clearing enabled bits.
`GPU_APP_NAME` customizes application/debug labels. `GPU_HARDWARE_ONLY` skips
CPU adapters. `GPU_WSI` adds Win32 surface/swapchain negotiation, including
separate present queues.

Both the explorer and the cube present through WSI, keep the serial command
buffer for uploads and export, and allocate from the pools; the commands,
pools and WSI includes call one another and are included together. The cube's
contract is adaptive. The explorer is built under three, so every `route` and
`alternate` block here is assembled both alone and beside its counterpart.
The fixed inventories report exhaustion rather than silently allocating more
CPU metadata. Drain before destroying commands, memory pools, the CPU arena, or
the Vulkan device.
