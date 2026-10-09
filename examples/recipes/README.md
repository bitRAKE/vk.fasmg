# Headless compute

Two complete Windows x64 assembly programs demonstrate different application
contracts:

| Recipe | Application model |
| --- | --- |
| `compute.asm` | Vulkan 1.1, descriptors, device-local work with staging, complete readback and optional timing |
| [`compute_noapi.asm`](compute_noapi.md) | Fixed Vulkan 1.4, GPU pointers and a resident argument record, coherent mapped GPU heap, one recorded command buffer reused across batches |

The [pointer compute guide](compute_noapi.md) explains the NoAPI recipe's
required contract and two-call recurring loop. Build it with
`build.cmd compute-noapi`; check it with `build.cmd check-compute-noapi`.

`compute.asm` is a complete Windows x64 assembly program that adds two arrays
on the GPU and verifies every result on the CPU. Start here when borrowing the
projection for a buffer operation: it needs no window, swapchain, graphics
queue, game platform, or presentation code.

From the repository root:

```bat
rem Set VULKAN_SDK; install Visual Studio C++ tools, clang, and fasm2.
build.cmd compute
build\recipe_compute.exe
rem Repeat with core and synchronization validation, plus a missing-driver test:
build.cmd check-recipes
```

The makefile generates and independently verifies the projection before
assembling the recipe. It compiles `compute.comp` with the SDK's
`glslangValidator`, validates SPIR-V for Vulkan 1.1, embeds the module in the
object, and links without a C runtime or Vulkan import library. Build tools
are the same as for the repository's other examples. The executable links
`kernel32.lib` for console/DLL operations and `user32.lib` for text formatting;
it creates no Windows UI.

Both recipes follow the [import/storage policy](../../docs/binary-layout.md).
Win32 calls go directly through IAT slots. Query records, enumeration arrays,
memory requirements, timestamp results, and formatting buffers are direct
procedure-local declarations. Required query headers are set before use;
memory properties pass to allocation helpers while their owning frame exists.
`host.inc` scopes the extension lookup and synchronous formatting. Its large
extension frame is automatically probed by `newcoff.inc` before use. Persistent
zero-initialized handles and flags live in BSS.

## Runtime contract

- Windows x64, `vulkan-1.dll`, and a GPU exposing Vulkan 1.1 or later.
- One queue with `VK_QUEUE_COMPUTE_BIT`; CPU Vulkan adapters are skipped.
- No optional device feature or device extension. The program considers each
  adapter's API version, storage-buffer limit, and queue support before choosing.
- One instance, device, queue, command buffer, submission, and fence.
- One 12 MiB device-local working buffer and one 12 MiB host-visible staging
  buffer, each in its own allocation. Memory requirements and type bits govern
  allocation; host caching is preferred but not required.
- `VK_EXT_debug_utils` is enabled when advertised. It routes messages to a
  Windows debugger and records validation/performance warnings or errors.
  It is optional for normal execution. Validation checks require the SDK layer.
- Queue timestamp support is optional. The result remains useful when no
  timestamp is available.

`vk/loader/static.inc` supplies lazy slots. `vk/loader/runtime.inc` explicitly
loads the DLL and finds `vkGetInstanceProcAddr`. This lets the executable
start and report step 1 when Vulkan cannot be loaded. Both required global
queries are first resolved before creating the instance. Vulkan failure,
unavailable GPU, result mismatch, and validation errors produce exit code 1;
complete success produces 0. Error output names the failing stage and result.

## The data path

The default workload is **1,048,576 unsigned 32-bit sums**. The CPU sets
`A[i] = i` and `B[i] = 3*i + 1`, so its independent oracle is `C[i] = 4*i + 1`.
The working and staging buffers each contain three adjacent arrays. A single
storage-buffer descriptor exposes the working buffer; a four-byte push
constant gives the shader the element count. The shader bounds-checks its
global invocation index and processes 64 elements per workgroup.

1. Fill the staging inputs. Flush the entire mapped allocation if its memory
   is not host coherent, using offset zero and `VK_WHOLE_SIZE`.
2. Copy the two inputs to device-local memory. A transfer-write to shader-read
   barrier makes them available to the compute shader.
3. Bind the compute pipeline, descriptor set, and count; dispatch the workgroups.
4. A shader-write to transfer-read barrier precedes copying the output to staging.
   A transfer-write to host-read barrier prepares the readback for the CPU.
5. Wait for the fence, invalidate the entire mapped allocation when noncoherent,
   and check every output element. Completion and cache handling precede reads.
6. Wait for device idle when unwinding, destroy the command/descriptor/pipeline
   objects and buffers, free allocations, destroy device/instance, then release
   the Vulkan DLL. Partial setup uses the same cleanup path.

`check-recipes` checks both recipes. For `compute.asm`, it repeats the operation under actual Windows debugger capture
with core and synchronization validation, verifies layer activation and the
absence of diagnostics, and checks the ordinary unavailable-driver error.
Logs are saved in `build/compute_checks/`.

## Adapt the operation

Edit the shader expression first, then change the CPU oracle to an independently
derived expected result. Keep the shader's workgroup size and assembly's
`WORKGROUP` consistent. `ELEMENTS`, the three-array layout, descriptor range,
dispatch count, and printed count must stay consistent when changing size.
For a different buffer shape, update the shader offsets, copy regions, and
verification loop together. A new algorithm may need different barriers or
features; retain the explicit per-candidate contract.

The optional GPU interval covers **upload + dispatch + readback for one batch**.
It excludes CPU setup, pipeline creation, submission overhead, and verification.
It is a timing illustration, not a claim that array addition beats a CPU:
the arithmetic is small and transfer costs dominate this workload. For an
application, keep the device, pipeline, descriptors, and working data alive;
batch enough useful work to amortize submissions and transfers. Establish a
CPU baseline and use repeated interleaved runs on the same adapter with
validation disabled before choosing an optimization.

For binding choices see [loaders](../../docs/loaders.md). For a workload that
also presents images, continue with the existing legacy/cube application
modules rather than expanding this recipe into a general framework.
