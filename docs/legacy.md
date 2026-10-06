# Graceful fallback and legacy Vulkan

Keep application features available as Vulkan capabilities change. Prefer newer
operations when their routes are available, translate the workload onto older
operations when the semantics fit, and use an application alternate when they
do not. The boundary to push is what the application can accomplish within the
reported limits. Unsupported feature bits, commands, and oversized resources
remain outside that boundary.

The [legacy examples](../examples/legacy/README.md) put this into a Mandelbrot
explorer. Pan, zoom, palette changes, deep zoom, an animated tour, and
full-size image export work with modern Vulkan and with the operations it
superseded, and the title
bar names the side of each operation in use. All of it is Vulkan. Running
without Vulkan is a different subject with a different answer; these examples
have no software renderer and report a device they cannot use.

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
| Dynamic rendering | 1.3 | `VK_KHR_dynamic_rendering`, effective API at least 1.2 | Reused render pass, framebuffer per target |
| Synchronization2 | 1.3 | `VK_KHR_synchronization2`, effective API at least 1.2 | Original barriers and submission |
| Copy commands2 | 1.3 | `VK_KHR_copy_commands2`, effective API at least 1.2 | Image-to-buffer copy1 |
| Inline shader code | 1.4 | `VK_KHR_maintenance5`, effective API at least 1.3 | Create/destroy shader modules |
| Timeline completion | 1.2 | `VK_KHR_timeline_semaphore`, effective API at least 1.1 | Fences tracking the same submissions |

The sixth capability is the optional core 1.0 `shaderFloat64` feature. Query
and enable it before creating the double-precision shader pipeline. Normal
views retain float32 rendering; deep zoom uses float64 where it is enabled and
a float-pair shader where it is not.
[Core feature definition](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceFeatures.html).

These extension floors deliberately keep dependency handling small. Dynamic
rendering below 1.2 needs additional dependencies; maintenance5 below 1.3 needs
an extension route for dynamic rendering. The examples choose their older
implementation instead of claiming to implement that dependency closure.
[Dynamic-rendering dependencies](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_dynamic_rendering.html),
[maintenance5 dependencies](https://docs.vulkan.org/refpages/latest/refpages/source/VK_KHR_maintenance5.html).

Build the query chain from eligible descriptors, inspect the returned feature
bits, and rebuild the device-create chain with only selected supported bits.
Clear unrelated core features populated by the query, keeping only selected
`shaderFloat64` support. Querying is not enabling:
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
modules. The barriers here are written once, with stage and access bits both
forms have: color-attachment output with no access as the source of a
discarding transition, the transfer stage around a copy, host read after it.
One argument list then serves `vkCmdPipelineBarrier2` and
`vkCmdPipelineBarrier`. Synchronization2's own values, a `NONE` stage or the
finer `COPY` stage, would need translating on the way down, to `TOP_OF_PIPE`
and `TRANSFER`. This is a small, audited set of transitions.

A general synchronization2 translator needs much more than truncating masks:
new stage/access bits, layouts, queue restrictions, and semaphore scopes all
matter. Submit2 permits a signal-stage scope that submit1 cannot express
directly. The examples use `ALL_COMMANDS` completion, which fits both forms.
[Synchronization2 migration guide](https://docs.vulkan.org/guide/latest/extensions/VK_KHR_synchronization2.html).

**Reuse or emulation** costs state and possibly time. The explorer reuses one
render pass for its one color attachment and keeps a framebuffer for each
swapchain image and one for the export target, replaced when the window is
resized. A larger renderer would need compatible cache keys and object-lifetime
handling. Descriptor-set rings and pipeline permutation caches are possible
future examples, provided their supported semantics are stated explicitly.

Completion is two counters every submission advances: work, and the retirement
of the command buffer and resources behind it. On the timeline route they are
two semaphores, signalled by the work batch and by a second, signal-only batch.
The alternate keeps the counters and tracks them with a fence for each frame
context and one for serial work, polled or waited in submission order. That
preserves what context reuse, deferred destruction and readback need. It does
not emulate arbitrary timeline semaphore counter queries, future waits,
multiple queues, host signals, or external payloads; a fence pool alone is not
a general replacement for that API.
[Timeline semantics](https://docs.vulkan.org/spec/latest/chapters/synchronization.html).

Presentation has the same shape one level up. Present fences from swapchain
maintenance say when a replaced swapchain's images are no longer in use; where
the extension or its feature is missing, a resize waits for the device to idle.
The fence establishes safe reclamation, not the moment a frame is visible.

**Application alternates** preserve user-visible functionality when native API
semantics cannot be supplied, and here they stay on the GPU. Float32 eventually
stops resolving nearby coordinates. The explorer uses `shaderFloat64` where it
is enabled; otherwise a second fragment shader carries each coordinate as the
unevaluated sum of two floats and computes with error-free additions and
multiplications. That gives about 48 significant bits to a double's 53, so the
zoom floor is higher, and it is exact only where float32 addition, subtraction
and multiplication are correctly rounded to nearest and performed as written.
`precise`, SPIR-V `NoContraction`, forbids contraction and reassociation; the
checks confirm the decoration and compare the two renderings on the running
device. The alternate does not report or emulate the `shaderFloat64` feature.
It is a different shader for the same picture.

Resource limits are a decomposition problem when the algorithm permits it.
Export draws into an image no larger than the contract's ceiling, the device's
image-format limits and a run-time switch allow, and assembles a larger picture
from tiles. Shader coordinates retain the full-image origin, so tiling does not
lower export resolution or change a pixel. The swapchain's images are the
surface's and are not subject to that ceiling. A forced ceiling is a test
policy, not a claim that the driver reports a smaller hardware limit.

## Build contracts and regression checks

A fasmg build can remove fallback branches when its deployment contract
requires the chosen operations. A core-version floor must still request the
right version and enable needed features. Vulkan 1.3 guarantees support for
dynamic rendering and synchronization2, but does not enable them automatically.
Some other promoted features remain optional. Such pruning removes a policy
branch; Vulkan command dispatch can still use indirect function pointers.
[Required feature support](https://docs.vulkan.org/spec/latest/chapters/features.html#features-requirements).

A contract here is two masks. `CAP_MASK` names the capabilities a build may
select and `CAP_REQUIRED` those it cannot do without. Code that depends on a
capability is written in a `route` block and its replacement in an `alternate`
block; a route is assembled only if the contract can select it, an alternate
only if the contract can decline it, and the run-time test between them only
while both remain possible. The data each side needs sits in the same blocks,
so a reference that crosses a contract's boundary is an assembly error rather
than a dead branch. Negotiation follows the masks: a masked route is never a
candidate, and a required route that is not selected ends negotiation before a
device is created, with the missing bits recorded for the application's error.

The three explorer builds are such contracts. The adaptive build may select
everything and requires nothing. The compatibility build may select none of
the five routes; it assembles no promoted command, no route descriptor and no
feature chain, and queries the device with the original functions. The modern
build requires all five and assembles none of what they replace. Core and KHR
routes satisfy a requirement alike, since the contract is about operations and
the names are resolved at run time. Each executable's link map lists the
Vulkan functions it has slots for, and the checks hold every build to its
contract in both directions. A contract narrows what a build can do on a
device; it never enables something the device did not report.

Keep downgrade controls from the start. The explorer masks individual
capabilities, forces advertised KHR routes, can request an API 1.2 or 1.1
ceiling, drops present fences and lowers the tile ceiling. Its tests drive the
real window procedure, compare complete exports across every route, contract
and tile size to the pixel, compare the float64 and float-pair deep views, and
check the errors for an unmet contract and an unavailable driver. Khronos core
and synchronization validation check every case. The checks need a Vulkan
device and fail without one; they do not substitute other output for it.

The [Vulkan ExtensionLayer project](https://github.com/KhronosGroup/Vulkan-ExtensionLayer)
is useful reference material for broader emulation. An application using such
layers must arrange their deployment and validate their actual coverage. These
examples use the normal Vulkan loader and need no emulation layer.
