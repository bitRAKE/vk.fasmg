# Graceful fallback and legacy Vulkan

Keep application features available as Vulkan capabilities change. Prefer newer
operations when their routes are available, translate the workload onto older
operations when the semantics fit, and use an application alternate when they
do not. The boundary to push is what the application can accomplish within the
reported limits. Unsupported feature bits, commands, and oversized resources
remain outside that boundary.

The [legacy examples](../examples/legacy/README.md) put this into a Mandelbrot
explorer. Pan, zoom, palette changes, and full-size image export work with modern
Vulkan, older Vulkan operations, or CPU rendering. Rendering reports its actual
implementation rather than presenting software work as a native GPU feature.

## What legacy means

Khronos keeps legacy functionality in the specification, while newer features
may omit interactions with it. The official categories include physical-device
queries, device layers, render-pass functionality, and synchronization. Prefer
the extensible physical-device queries and instance layers; use dynamic
rendering and synchronization2 when available. The original entry points remain
useful implementation tools for a compatibility path.
[Khronos legacy appendix](https://docs.vulkan.org/spec/latest/appendices/legacy.html).

Other useful migrations include copy commands2, timeline semaphores, inline
shader code with maintenance5, push descriptors, more dynamic pipeline state,
and newer structure-taking binding commands. These are separate capabilities.
A shader-object extension or descriptor strategy is not a universal desktop
baseline, and an API redesign alone does not establish a performance advantage.
Measure the workload before making claims about descriptor or pipeline costs.

Inline shader code specifically requires the enabled `maintenance5` feature;
otherwise create shader modules, use them to create the pipeline, and destroy
them afterward. The resulting pipeline still owns the compiled shader work.
[Shader module rules](https://docs.vulkan.org/spec/latest/chapters/shaders.html).

## Probe, choose, then enable

Keep route selection separate from application policy. Each capability needs
its core version, extension name and dependencies, feature structure and bit
when applicable, and the entry-point names for each route. Use the lower of the
instance's requested version and the physical device's supported version when
choosing a core route.

The explorer's descriptors negotiate these five independent operations:

| Capability | Core route | Extension route used by these examples | Alternate |
| --- | --- | --- | --- |
| Dynamic rendering | 1.3 | `VK_KHR_dynamic_rendering`, effective API at least 1.2 | Reused render pass/framebuffer |
| Synchronization2 | 1.3 | `VK_KHR_synchronization2`, effective API at least 1.2 | Explicit legacy barriers and submission |
| Copy commands2 | 1.3 | `VK_KHR_copy_commands2`, effective API at least 1.2 | Image-to-buffer copy1 |
| Inline shader code | 1.4 | `VK_KHR_maintenance5`, effective API at least 1.3 | Create/destroy shader modules |
| Timeline completion | 1.2 | `VK_KHR_timeline_semaphore`, effective API at least 1.1 | Resettable completion fence |

These extension floors deliberately keep dependency handling small. Dynamic
rendering below 1.2 needs additional dependencies; maintenance5 below 1.3 needs
an extension route for dynamic rendering. The examples choose their older
implementation instead of claiming to implement that dependency closure.
[Dynamic-rendering dependencies](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_dynamic_rendering.html),
[maintenance5 dependencies](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_maintenance5.html).

Build the query chain from eligible descriptors, inspect the returned feature
bits, and rebuild the device-create chain with only selected supported bits.
Clear unrelated core features populated by the query. Querying is not enabling:
`VkPhysicalDeviceFeatures2` controls enabled features only when used in device
creation. Do not put both an aggregate Vulkan-version feature structure and an
individual structure describing the same features into the create chain.
[Feature-chain contract](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceFeatures2.html),
[feature rules](https://docs.vulkan.org/spec/latest/chapters/features.html).

The earlier blanket claim that every unrecognized query `sType` is invalid is
too broad. Follow the rules for the particular query and creation chain, keep
query outputs initialized, and avoid requesting unsupported features. Filtering
the chain here makes negotiation explicit; it is not permission to enable
unreported bits.

Resolve commands using the chosen core or KHR names after device creation.
Device-procedure pointers, including core functions, belong to that device and
its children. A non-null pointer alone does not authorize using a command from
a higher unrequested core version.
[Device-procedure contract](https://docs.vulkan.org/refpages/latest/refpages/source/vkGetDeviceProcAddr.html).

## Three implementation tiers

**Translation** preserves the particular operation's semantics. Copy2 without
extra chained behavior can use copy1; inline shader code can use temporary
modules. For this renderer, synchronization2's high `COPY` stage becomes legacy
`TRANSFER`, and the initial discard barrier uses `TOP_OF_PIPE` in place of a
source `NONE`. Color-write, transfer-read/write, and host-read scopes are
explicit. This is a small, audited set of transitions.

A general synchronization2 translator needs much more than truncating masks:
new stage/access bits, layouts, queue restrictions, and semaphore scopes all
matter. Submit2 permits a signal-stage scope that submit1 cannot express
directly. The explorer uses `ALL_COMMANDS` completion, which fits both forms.
[Synchronization2 migration guide](https://docs.vulkan.org/guide/latest/extensions/VK_KHR_synchronization2.html).

**Reuse or emulation** costs state and possibly time. The explorer reuses one
render pass and framebuffer for its one color attachment. A larger renderer
would need compatible cache keys and object-lifetime handling. Descriptor-set
rings and pipeline permutation caches are possible future examples, provided
their supported semantics are stated explicitly.

The timeline alternate here is one reusable fence for a serial sequence of
submit-and-host-wait operations. It preserves completion needed by image
readback. It does not emulate arbitrary timeline semaphore counter queries,
future waits, multiple queues, host signals, or external payloads; a fence pool
alone is not a general replacement for that API.
[Timeline semantics](https://docs.vulkan.org/spec/latest/chapters/synchronization.html).

**Application alternates** preserve user-visible functionality when native API
semantics cannot be supplied. GPU float precision eventually stops resolving
nearby coordinates. The explorer changes to SSE2 double precision while keeping
its camera, palette, and exporter. Missing Vulkan runtime, unusable GPU setup,
or a failed render also selects CPU rendering. This does not report an emulated
`shaderFloat64` feature.

Resource limits are a decomposition problem when the algorithm permits it.
The compatibility example renders a 512 by 384 result through a reusable image
of at most 128 by 128, then assembles the tiles into the full output. Actual
image-format and physical-device limits further bound allocation. Shader
coordinates retain the full-image origin, so tiling does not lower export
resolution or remove controls. The forced ceiling is a test policy, not a
claim that the driver reports a smaller hardware limit.

## Build contracts and regression checks

A fasmg build can remove fallback branches when its deployment contract
requires the chosen operations. A core-version floor must still request the
right version and enable needed features. Vulkan 1.3 guarantees support for
dynamic rendering and synchronization2, but does not enable them automatically.
Some other promoted features remain optional. Such pruning removes a policy
branch; Vulkan command dispatch can still use indirect function pointers.
[Required feature support](https://docs.vulkan.org/spec/latest/chapters/features.html#features-requirements).

The current three profiles retain runtime dispatch and shared implementations;
they are not examples of compile-time removal of all unused GPU code. A strict
modern-only build would be a separate capability contract, with an explicit
startup failure or an application alternate when it cannot be met.

Keep downgrade controls from the start. The explorer masks individual
capabilities, forces advertised KHR routes, and can request an API 1.2 ceiling.
Its tests drive real GUI command handlers, compare complete exports across GPU
paths, check CPU precision and reset/recovery, and test an unavailable driver.
Khronos core and synchronization validation check every route. The tests report
when no GPU is available rather than claiming GPU coverage from CPU output.

The [Vulkan ExtensionLayer project](https://github.com/KhronosGroup/Vulkan-ExtensionLayer)
is useful reference material for broader emulation. An application using such
layers must arrange their deployment and validate their actual coverage. These
examples use the normal Vulkan loader and need no emulation layer.
