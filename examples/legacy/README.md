# Vulkan Atlas: legacy Vulkan in a fractal explorer

A Windows x64 Mandelbrot explorer whose every frame is Vulkan's: drawn into the
acquired swapchain image and presented from there. Five operations each have a
modern route and the original operation it replaced, and one optional feature
has an alternate. Pan, zoom, eight palettes, deep zoom, an animated tour and
full-size export work on every combination. There is **no software renderer**:
where Vulkan cannot do the work, the program says why and exits.

One program is built under three contracts. A contract is three lines ahead of
`include 'explorer.inc'`, and it decides what gets assembled:

| Source | Executable in `build\` | Contract |
| --- | --- | --- |
| `00_adaptive.asm` | `legacy_adaptive.exe` | May select every route; both sides of each operation are assembled and chosen between when the device is created |
| `01_compatibility.asm` | `legacy_compatibility.exe` | The original operations alone; no modern route is assembled. Images the program allocates stay within 128 pixels |
| `02_modern.asm` | `legacy_modern.exe` | The five modern routes are required; nothing they replace is assembled, and a device without them is reported at startup |

## Build and run

From the repository root:

```bat
build.cmd legacy
build\legacy_adaptive.exe
build\legacy_compatibility.exe
build\legacy_modern.exe
rem Repeat all cases with core and synchronization validation:
build.cmd check-legacy
```

The standard repository toolchain is sufficient. The Vulkan SDK's
`glslangValidator.exe` compiles the four GLSL shaders for Vulkan 1.0 and
`spirv-val.exe` validates them before assembly. Running needs a Vulkan 1.1
device with Win32 presentation and a UNORM surface format; the modern contract
needs the five routes as well, core or KHR. Vulkan is loaded explicitly rather
than listed in the PE imports, so a missing runtime is reported like any other
failure.

| Input | Action |
| --- | --- |
| Left click | Zoom in at the point |
| Right click | Zoom out at the point |
| Wheel | More iterations, or fewer |
| `+`, `-` | Zoom about the center |
| Arrow keys | Pan |
| `P` | Next palette |
| `R` | Restore the first view, palette and iteration count |
| `D` | Go to the deep-zoom bookmark |
| `T` | Tour: travel to the next well-known place; pressed on the way, pass that one by |
| `S` | Export the view as a BMP, at the size of the client area |
| `Esc` | Stop a tour where it is; with none under way, close |

A click keeps the point under the cursor where it is, so the other button at
the same spot undoes it. A wheel notch forward is a quarter more iterations and
a notch back a fifth fewer, between 16 and 2048; the count starts at 192 and is
a push constant like the rest of the view. The title bar is the status line:
the contract, the side of each operation in use, the arithmetic of the current
view, the picture's size, the palette, the iteration count, and where a tour is
heading or resting.

## The operations

| Operation | Route | Alternate |
| --- | --- | --- |
| Rendering | Dynamic rendering | One render pass, and a framebuffer for each target |
| Barriers and submission | Synchronization2 | `vkCmdPipelineBarrier` and `vkQueueSubmit` |
| Readback copy | Copy commands2 | `vkCmdCopyImageToBuffer` |
| Shader code | Chained to the pipeline's stages (maintenance5) | Shader modules, destroyed once the pipeline exists |
| Completion | Timeline semaphores | Fences |
| Deep-zoom arithmetic | `shaderFloat64` | Pairs of float32 in the fragment shader |

The first five are the routes `vulkan_context.inc` negotiates: core where the
device's version has them, the KHR extension where it is advertised and its
dependencies fit, the alternate otherwise. Only reported features are enabled.
Two more pairs follow from the contract or the device rather than a route of
their own. Present fences from swapchain maintenance retire a replaced
swapchain; without them a resize waits for the device to idle. And the
compatibility contract, selecting no feature-bearing route, uses the original
physical-device queries and `pEnabledFeatures` where the others chain feature
structures to the `2` queries.

In the sources each side is a block. This is all of an image barrier:

```asm
	route CAP_SYNC,.legacy
		...
		vkCmdPipelineBarrier2 [command_buffer],addr transition_dependency
		ret
	end route
	alternate CAP_SYNC
	.legacy:
		...
		vkCmdPipelineBarrier [command_buffer],[source_stage],[destination_stage],0,0,0,0,0,1,addr transition1
		ret
	end alternate
```

A `route` is assembled if the contract can select the capability, an
`alternate` if the contract can decline it, and the test of the negotiated
capabilities behind the label only while both remain possible. The blocks are
defined in `..\common\vulkan_routes.inc` and used through the shared modules
as well, so a contract reaches all the way down: command submission,
presentation and retirement lose their unused halves too.

## What a contract assembles

The static loader gives a slot to each Vulkan function an object refers to, and
the link map names them, so the map shows what a build can call. With Vulkan
SDK 1.4.363, `build.cmd legacy` prints:

| Contract | Vulkan functions | Of ten modern | Of eleven original | Exe bytes |
| --- | ---: | ---: | ---: | ---: |
| adaptive | 86 | 10 | 11 | 68608 |
| compatibility | 78 | 0 | 11 | 63488 |
| modern | 75 | 10 | 0 | 63488 |

The ten are the commands of the five routes with the `2` physical-device
queries; the eleven are render-pass and framebuffer creation and use, the first
barrier, submission and copy commands, and shader modules. The check requires
each executable to hold every function its contract allows and none it
excludes. It also assembles thirteen contracts no source ships, with each
capability required alone, each permitted alone, all and none: a block that
leaned on its counterpart would stop assembling once the counterpart is gone.

- **adaptive** runs on any Vulkan 1.1 device and uses what it finds. It carries
  both sides of every operation and a test at each of them.
- **compatibility** is what a program written against the first operations
  looks like. It cannot call a promoted command, which makes it the reference
  the other builds must match pixel for pixel.
- **modern** has the fewest functions and no branch on a route. Its price is
  the contract: on a device without dynamic rendering, synchronization2, copy
  commands2, maintenance5 and timeline semaphores it does not start, and says
  which are missing.

## Deep zoom

The camera is double precision in every build. Views wider than `0.0001` use
the float32 shader. Narrower ones use `fractal64.frag` when the device reports
`shaderFloat64`, which is optional although it is as old as Vulkan 1.0
([feature definition](https://docs.vulkan.org/refpages/latest/refpages/source/VkPhysicalDeviceFeatures.html)).
Without it `fractal32x2.frag` carries each coordinate as the unevaluated sum of
two floats, about 48 significant bits, through error-free additions and
multiplications. That arithmetic is exact only if every operation is rounded
and ordered as written, so each is `precise`, SPIR-V `NoContraction`; the check
confirms the decoration on every add, subtract and multiply and that the module
declares no `Float64` capability. On the local GTX 1080 Ti the bookmark's two
renderings differ in one pixel of 448,000. Zoom stops where a pixel is still
several steps of the arithmetic wide: `1e-13` with doubles, `1e-10` with pairs.

## The tour

`T` sets out from wherever the view is. The tour rests three seconds at each
stop and goes on by itself; the last stop is the first view, where it ends.

| Stop | Center | View height |
| --- | --- | ---: |
| Seahorse Valley | -0.7453, 0.1127 | 0.0065 |
| A seahorse tail | -0.743643887037151, 0.13182590420533 | 0.00001 |
| Elephant Valley | 0.285, 0.0125 | 0.012 |
| Quad Spiral Valley | 0.274, 0.482 | 0.01 |
| Triple Spiral Valley | -0.088, 0.654 | 0.012 |
| Double Scepter Valley | -0.1002, 0.8383 | 0.01 |
| A Mandelbrot beyond the bulb | -0.1592, 1.0317 | 0.03 |
| Scepter Valley | -1.3775, 0.012 | 0.02 |
| The Mandelbrot on the needle | -1.7548776662466927, 0 | 0.06 |
| The whole set | -0.5, 0 | 3 |

Zoom and center change together. A leg eases the scale along its logarithm, a
steady pace per halving that starts and ends at rest, and eases the stop's
offset on screen to nothing, so the motion looks the same at any depth. A stop
that is out of sight is first brought into it: the leg backs out about the
center it has until the stop is within reach, then closes in. The second stop
is narrower than float32 resolves, so the picture changes arithmetic on the
way, to `shaderFloat64` or to float pairs, and back on the way out.

The tour is the one thing that draws continuously. Each of its frames is
acquired, drawn and presented like any other, paced by FIFO presentation and
timed by the performance counter; a timer carries it through Windows' own move
and size loops. Palette and wheel work during a tour. Any control that moves
the view takes over from it, and `Esc` stops it where it is.

## Export and tiles

Frames on screen never leave the GPU. Export draws the view again into an
offscreen image, copies that to a host-visible buffer and waits for the
submission before reading; non-coherent memory is invalidated. The image is at
most `tile_size` on a side: the least of the contract's `TILE_CEILING`, the
device's image limits and `--tile-limit`. A larger picture is drawn in tiles,
each with its origin in the push constants, so the shader computes the same
coordinates and a tiled export has the pixels of an untiled one. The
compatibility contract's 128-pixel ceiling and the switch are policy, there to
exercise the decomposition; they are not limits a driver reported.

## Switches and checks

Each switch takes something away; none forces a feature on.

```bat
build\legacy_adaptive.exe --no-rendering --no-inline
build\legacy_adaptive.exe --no-sync2
build\legacy_adaptive.exe --no-timeline
build\legacy_adaptive.exe --no-copy2
build\legacy_adaptive.exe --no-float64
build\legacy_adaptive.exe --force-khr
build\legacy_adaptive.exe --api-1.2
build\legacy_adaptive.exe --api-1.1
build\legacy_adaptive.exe --no-present-fences
build\legacy_adaptive.exe --tile-limit=100
```

`--force-khr` selects only advertised extension routes whose dependencies fit
the effective API version. `--api-1.2` leaves rendering, synchronization2 and
copy2 to their KHR extensions and shader code to modules; `--api-1.1` leaves
the timeline extension alone. The switches work on every build, within its
contract: the compatibility build has no route for them to take away, and the
modern build declines to start without one it requires.

`--self-test` keeps the window hidden, sends it real key, wheel, button, timer
and size messages, and exports the view after each step: first view, zoom, pan,
palette, reset, left click, right click, wheel, deep zoom, a tour stopped by
`Esc`, the tour's first stop once it is taken up again, then wide, short and
narrow client areas. Scripted runs step the tour a tenth of a second per timer
message instead of by the clock, so every run draws the same frames. It writes
the bitmaps and a UTF-16 report to `build\legacy_<contract>*`; the test script
archives each run with its debugger output under
`build\legacy_checks\<mode>\<case>\`. `--tour-test` runs the whole tour the
same way and exports each stop. Run the executables from the repository root
for these relative paths.

`build.cmd legacy` runs fourteen cases: the three contracts, the adaptive
build under each switch, and the modern build on KHR routes. Every case must
present the same frames, one for each message that changes the picture and one
for each step of the tour, and none once `Esc` has stopped it. It must export
fourteen complete opaque pictures of the client area's size, change the
picture with each control, restore it exactly on reset, and undo a left click
with a right click at the same point. All thirteen float32 pictures must equal
the first case's, pixel for pixel, across routes, contracts and tile sizes; so
must the float64 deep view, and the float-pair one may differ from it in at
most half a percent of pixels, where an orbit barely escapes. The whole tour
then runs twice, with float64 and with float pairs: it must reach all ten
stops, show a different place at each, and end on the first view exactly; only
its deep stop may depend on the arithmetic. Then the failures: the modern build without
synchronization2 must name it and exit, malformed tile limits must be rejected,
and with `VK_DRIVER_FILES` pointing at an absent manifest every build must
report that Vulkan is unavailable and shut down cleanly. That last case
changes only the child process's environment.

`check-legacy` repeats everything with `VK_LAYER_KHRONOS_validation` and
`VK_LAYER_VALIDATE_SYNC=1`, checks that both activate and rejects any
diagnostic
([validation settings](https://github.com/KhronosGroup/Vulkan-ValidationLayers/blob/main/docs/updating_from_VK_EXT_validation_features.md)).

## Modules

`explorer.inc` owns the window, controls and options; `view.inc` the camera and
the push constants of the three shaders; `tour.inc` the stops and the motion
between them; `gpu.inc` pipelines, the swapchain target and frames;
`export.inc` the tiled readback. Negotiation, commands,
barriers, memory and presentation come from the
[shared modules](../common/README.md), which the
[NoGraphicsAPI cube](../noAPI_cube/README.md) uses under an adaptive contract of
its own. [The design notes](../../docs/legacy.md) say what each alternate does
and does not stand in for.
