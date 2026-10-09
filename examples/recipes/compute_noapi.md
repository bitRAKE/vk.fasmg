# Compute through GPU pointers

`compute_noapi.asm` establishes a fixed Vulkan contract, allocates one mapped
GPU heap, creates one pipeline, and records its command buffer once. Subsequent
batches change data through CPU stores. The recurring Vulkan work is one
`vkQueueSubmit2` and one `vkWaitSemaphores` per batch.

This follows the [No Graphics API perspective](https://www.sebastianaaltonen.com/blog/no-graphics-api):
use API queries and validation to establish the machine, then give the shader
ordinary addresses and application-owned data. The recipe implements the
buffer portion of that model. Its scope is headless compute; image heaps,
samplers, graphics state, and presentation belong to a larger application.

From the repository root:

```bat
build.cmd compute-noapi
build\recipe_compute_noapi.exe
build.cmd check-compute-noapi
rem Build/check both compute recipes:
build.cmd recipes
build.cmd check-recipes
```

The SDK's Slang compiler builds `compute_noapi.slang` as SPIR-V 1.6 with scalar
layout. `spirv-val` checks it for Vulkan 1.4 before assembly embeds the bytes.
The makefile also verifies the generated projection against the SDK headers.
The executable uses Windows x64 assembly, the shared console helper, and
`kernel32.lib`/`user32.lib`; the Vulkan DLL is opened explicitly at startup.

The [import/storage policy](../../docs/binary-layout.md) uses direct Win32 IAT
calls by default. Query records, enumeration buffers, memory requirements,
loader version, and formatting text are declared directly in procedure
`locals`. Memory properties stay in the `create_base` frame across selection
and heap creation; helpers consume their address before that frame returns.
Startup initializes the query headers and chain links. The large extension
lookup frame uses `newcoff.inc`'s automatic stack probe. Persistent handles,
heap ownership, and diagnostic flags occupy BSS.

## One required contract

Each candidate must expose Vulkan 1.4, a non-CPU device, a compute queue,
`bufferDeviceAddress`, `scalarBlockLayout`, `timelineSemaphore`,
`synchronization2`, and `maintenance5`. The recipe queries those feature bits
and enables only the required bits. Its memory type must simultaneously be
device local, host visible, and host coherent, with enough heap capacity for
the allocation. After buffer creation, its actual `memoryTypeBits` and aligned
allocation size determine the compatible type.

Missing requirements reject the candidate. If every candidate fails, the
program reports the final candidate's rejection mask and exits with code 1.
There is one shader, binding protocol, memory protocol, and command protocol.
An older loader or an unavailable Vulkan driver also produces a normal
initialization error. Success returns 0. `VK_EXT_debug_utils` is optional
instrumentation; when present, validation/performance warnings and errors
make the run fail.

The rejection mask uses these bits:

| Hex bit | Required property |
| --- | --- |
| `001` | Vulkan 1.4 API version |
| `002` | Non-CPU physical device |
| `004` | Buffer device address |
| `008` | Scalar block layout |
| `010` | Timeline semaphore |
| `020` | Synchronization2 |
| `040` | Maintenance5 |
| `080` | Compatible coherent mapped GPU memory and sufficient heap capacity |
| `100` | Compute queue |

Version and device-type failures return immediately for that candidate; later
feature, memory, and queue failures accumulate. Allocation can still fail after
selection because capacity queries do not reserve memory.

## Data is the interface

One storage buffer backs a 12 MiB + 64-byte logical heap. Its memory allocation
uses `VK_MEMORY_ALLOCATE_DEVICE_ADDRESS_BIT`; the buffer uses
`VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT`. Vulkan's required alignment can
make the actual allocation larger. The CPU mapping and GPU address are
different address spaces, retained separately in `NoApiHeap`.

An eight-byte push constant holds the GPU address of `NoApiArguments` at heap
offset zero. A pipeline layout describes this one pointer range. This is the
recipe's Vulkan adaptation of the root interface. There are no descriptor
sets, pools, layouts, updates, or bindings. Maintenance5 accepts the embedded
shader bytes directly in pipeline creation through `VkShaderModuleCreateInfo`,
so setup also omits a separate shader-module object.

| Argument offset | Type | Meaning |
| --- | --- | --- |
| 0 | GPU pointer | Input A |
| 8 | GPU pointer | Input B |
| 16 | GPU pointer | Output C |
| 24 | `uint32` | Active element count |
| 28 | `uint32` | Addition bias |

The argument record occupies 32 bytes. A starts at heap offset 64; B and C
follow as adjacent arrays of 1,048,576 unsigned 32-bit elements. Assembly
assertions and SPIR-V checks verify the shared ABI. Slang uses
`Ptr<T, Access.Read>` for read-only pointees; these compile to physical storage
buffer pointers without requiring the `shaderInt64` feature.

For batch `k = 1..3`, the CPU writes `B[i] = 3*i + k`, `count = 1048576-k`,
and `bias = 1000*k`; A remains `i`. It fills C with a sentinel. The shader
calculates `C[i] = A[i] + B[i] + bias` for active elements. The independent CPU
oracle checks `4*i + 1001*k` and verifies that the final `k` elements still
hold the sentinel. Changing count and bias demonstrates that each execution
reads the current resident argument record. The fixed dispatch contains
16,384 workgroups of 64 threads; the shader bounds-checks its index.

## Ownership and synchronization

Setup binds the pipeline and root pointer, records one dispatch, and records
a synchronization2 barrier from compute shader writes to host reads. The
same executable command buffer is reused after each submission completes.
The batch loop resolves its two device function pointers during setup.

CPU stores finish with `sfence` before submission, covering write-combined
mapped memory. Submission makes prior coherent host writes available to the
device. A timeline semaphore signals completion; the CPU waits up to five
seconds before checking C or rewriting shared data. Coherence handles cache
visibility, while the barrier and completion wait establish the ordering.
The allocation remains mapped until it is freed. Cleanup waits for device
idle, destroys its objects, frees memory, destroys the device and instance,
and releases the DLL. Partial initialization uses the same cleanup path.

The mapped GPU memory contract can require BAR memory on a discrete GPU.
CPU reads can be uncached, and available mapped GPU capacity varies across
machines. This sample makes no speedup claim: it deliberately checks every
result on the CPU and serializes batches for clear ownership. For production
throughput, keep intermediate data on the GPU, measure representative work,
and partition memory into independently owned regions when overlapping CPU
and GPU work. Add new operations within an explicit modern contract.

`check-compute-noapi` checks results and tails, shader ABI, imports and command
dependencies, actual core/synchronization validation, and resource destruction.
The SDK API dump layer verifies one recording and three submit/wait pairs.
A Profiles-layer fixture masks BDA and verifies rejection before device
creation; a missing-driver fixture checks startup failure. These checks require
the SDK's validation, API dump, and Profiles layers. Evidence is saved in
`build/noapi_compute_checks/`.

The trace and feature-mask tests isolate implicit layers using
`VK_LOADER_LAYERS_DISABLE=~implicit~`; ordinary and core/synchronization runs
retain the normal layer environment. With SDK 1.4.363.0, an AMD-selected trace
intermittently faulted in API dump's `get_dispatch_key`/`vkDestroyDevice` with
NVIDIA's Optimus layer in the debugger call stack. Isolation keeps those
instrumentation checks reproducible. This follows the loader's
[layer-isolation diagnostic](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderDebugging.md#disable-layers).

The Vulkan [buffer device address sample](https://docs.vulkan.org/samples/latest/samples/extensions/buffer_device_address/README.html)
and [synchronization examples](https://docs.vulkan.org/guide/latest/synchronization_examples.html)
describe the pointer and host/device visibility rules used here.
