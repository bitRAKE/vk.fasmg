# NMAKE: generate/verify the projection and build loader/debug/legacy examples.
# Override FASM2 and CLANG on the command line for other toolchain locations.

!IFNDEF FASM2
FASM2 = ..\fasm2\fasm2.cmd
!ENDIF
!IFNDEF CLANG
CLANG = $(PROGRAMFILES)\LLVM\bin\clang.exe
!ENDIF
!IFNDEF SLANGC
SLANGC = $(VULKAN_SDK)\Bin\slangc.exe
!ENDIF

POWERSHELL = powershell -NoProfile -ExecutionPolicy Bypass
BUILD = build
BUILD_READY = $(BUILD)\.ready
VK_XML = $(VULKAN_SDK)\share\vulkan\registry\vk.xml
VIDEO_XML = $(VULKAN_SDK)\share\vulkan\registry\video.xml
VULKAN_LIB = "$(VULKAN_SDK)\Lib\vulkan-1.lib"
VK_GENERATED = tests\vk\.generated
VK_VALIDATED = tests\vk\.validated

ASSEMBLE = $(POWERSHELL) -File tools\assemble.ps1 -Fasm2 "$(FASM2)"
OBJECT_BASE = newcoff.inc macro\struct.inc tools\assemble.ps1
EXAMPLE_STRINGS = examples\strings.inc
LOADER_SOURCES = vk\loader\loader.asm vk\loader\lazy.inc $(OBJECT_BASE)
CONSOLE_OBJ = $(BUILD)\loader_console.obj
LOADER_EXAMPLE_BODY = examples\loaders\instance.inc examples\loaders\device.inc $(EXAMPLE_STRINGS) $(OBJECT_BASE) $(VK_VALIDATED) $(BUILD_READY)
LINK_EXAMPLE = link /NOLOGO /SUBSYSTEM:CONSOLE /ENTRY:mainCRTStartup /NODEFAULTLIB /OPT:REF /OPT:ICF
LOADER_EXAMPLE_LINK = $(LINK_EXAMPLE) /MAP:$(@R).map /OUT:$@
LOADER_EXAMPLES = $(BUILD)\loader_iat.exe $(BUILD)\loader_delay.exe $(BUILD)\loader_static.exe $(BUILD)\loader_mixed.exe $(BUILD)\loader_dynamic.exe $(BUILD)\loader_comdat.exe
DEBUG_LOGGER_OBJ = $(BUILD)\debug_logger.obj
DEBUG_BODY = examples\debug\context.inc examples\debug\sink.inc $(EXAMPLE_STRINGS) $(OBJECT_BASE) vk\loader\static.inc vk\loader\lazy.inc $(VK_VALIDATED) $(BUILD_READY)
DEBUG_EXAMPLES = $(BUILD)\debug_lifecycle.exe $(BUILD)\debug_outputs.exe $(BUILD)\debug_objects.exe
DEBUG_SINK_PROBE = $(BUILD)\debug_sink_probe.exe
# Every example that negotiates a device shares these; the contract of vulkan_routes.inc shapes each of them.
SHARED_EXAMPLE_BODY = examples\common\vulkan_routes.inc examples\common\vulkan_context.inc examples\common\vulkan_memory.inc examples\common\vulkan_pools.inc examples\common\range_allocator.inc examples\common\cpu_arena.inc examples\common\vulkan_commands.inc examples\common\vulkan_barriers.inc examples\common\vulkan_wsi.inc examples\common\vulkan_wsi_retirement.inc examples\common\command_options.inc examples\common\bitmap.inc $(DEBUG_BODY)
LEGACY_BODY = examples\legacy\explorer.inc examples\legacy\view.inc examples\legacy\tour.inc examples\legacy\gpu.inc examples\legacy\export.inc $(SHARED_EXAMPLE_BODY)
LEGACY_SHADERS = $(BUILD)\legacy_fullscreen.spv $(BUILD)\legacy_fractal.spv $(BUILD)\legacy_fractal64.spv $(BUILD)\legacy_fractal32x2.spv
LEGACY_EXAMPLES = $(BUILD)\legacy_adaptive.exe $(BUILD)\legacy_compatibility.exe $(BUILD)\legacy_modern.exe
LINK_WINDOW = link /NOLOGO /SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup /NODEFAULTLIB /OPT:REF /OPT:ICF /MAP:$(@R).map /OUT:$@ $** kernel32.lib user32.lib comdlg32.lib shell32.lib advapi32.lib
CUBE_BODY = examples\noAPI_cube\features.inc examples\noAPI_cube\scene.inc examples\noAPI_cube\gpu.inc examples\noAPI_cube\target.inc examples\noAPI_cube\capture.inc examples\noAPI_cube\present_test.inc examples\noAPI_cube\memory_test.inc examples\noAPI_cube\material.inc examples\noAPI_cube\pipeline.inc examples\common\math3d.inc $(SHARED_EXAMPLE_BODY)
CUBE_SHADERS = $(BUILD)\noAPI_cube_bindings.spv $(BUILD)\noAPI_cube_pointer.spv $(BUILD)\noAPI_cube_fragment.spv $(BUILD)\noAPI_cube_heap_vertex.spv $(BUILD)\noAPI_cube_heap_fragment.spv
CUBE_EXAMPLE = $(BUILD)\noAPI_cube.exe
RANGE_PROBE = $(BUILD)\vk_ranges_test.dll

# myhits: the boundary header is assembled first, the shaders are compiled against it, then the programs embed them.
MYHITS = source\myhits
MYHITS_HEADER = $(BUILD)\myhits_shared.slang
MYHITS_SLANG = "$(SLANGC)" -I $(BUILD) -target spirv -profile spirv_1_5 -emit-spirv-directly -fvk-use-scalar-layout
MYHITS_VALIDATE = "$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.3 --scalar-block-layout
MYHITS_MACHINE = $(MYHITS)\machine.inc $(MYHITS)\input.inc $(MYHITS)\shared.inc $(SHARED_EXAMPLE_BODY)
STYLE_SLANG = $(MYHITS)\proofs\01_style\style.slang
STYLE_SHADERS = $(BUILD)\myhits_style_collide.spv $(BUILD)\myhits_style_vertex.spv $(BUILD)\myhits_style_fragment.spv
SPINE_SLANG = $(MYHITS)\proofs\02_spine\spine.slang
SPINE_SHADERS = $(BUILD)\myhits_spine_seed.spv $(BUILD)\myhits_spine_direct.spv $(BUILD)\myhits_spine_advance.spv $(BUILD)\myhits_spine_mote_vertex.spv $(BUILD)\myhits_spine_mote_fragment.spv
MYHITS_ART = $(BUILD)\myhits_art.inc
MYHITS_PICTURES = $(MYHITS)\pictures.inc $(MYHITS)\pictures.slang $(MYHITS_ART)
GALLERY_SLANG = $(MYHITS)\proofs\03_pictures\gallery.slang
GALLERY_SHADERS = $(BUILD)\myhits_pictures_develop.spv $(BUILD)\myhits_pictures_chart.spv $(BUILD)\myhits_pictures_census.spv $(BUILD)\myhits_pictures_direct.spv $(BUILD)\myhits_pictures_sprite_vertex.spv $(BUILD)\myhits_pictures_sprite_fragment.spv
MYHITS_PROOFS = $(STYLE_SHADERS) $(BUILD)\myhits_spine.exe $(BUILD)\myhits_pictures.exe

VULKAN_DELAY_DEF = vk\vulkan-1.def
VULKAN_DELAY_LIB = $(BUILD)\vulkan-1-delay.lib
VULKAN_DELAY_OBJ = $(BUILD)\vk_delay.obj

all: $(LOADER_EXAMPLES) $(DEBUG_EXAMPLES) $(LEGACY_EXAMPLES) $(CUBE_EXAMPLE) $(MYHITS_PROOFS)

$(BUILD_READY):
	if not exist "$(BUILD)" mkdir "$(BUILD)"
	$(POWERSHELL) -Command "New-Item -ItemType File -Force -Path '$@' | Out-Null"

# Invalidate verification before generation, and stamp only a complete projection.
$(VK_GENERATED): tools\gen-vulkan-functions.ps1 "$(VK_XML)" "$(VIDEO_XML)"
	$(POWERSHELL) -Command "if (Test-Path -LiteralPath '$(VK_GENERATED)') { Remove-Item -LiteralPath '$(VK_GENERATED)' -Force }; if (Test-Path -LiteralPath '$(VK_VALIDATED)') { Remove-Item -LiteralPath '$(VK_VALIDATED)' -Force }"
	$(POWERSHELL) -File tools\gen-vulkan-functions.ps1 -Registry "$(VK_XML)" -VideoRegistry "$(VIDEO_XML)" -Output vk -TestOutput tests\vk
	$(POWERSHELL) -Command "New-Item -ItemType File -Force -Path '$@' | Out-Null"

$(VK_VALIDATED): $(VK_GENERATED) tools\verify-vulkan-projection.ps1
	$(POWERSHELL) -Command "if (Test-Path -LiteralPath '$@') { Remove-Item -LiteralPath '$@' -Force }"
	$(POWERSHELL) -File tools\verify-vulkan-projection.ps1 -Clang "$(CLANG)"
	$(POWERSHELL) -Command "New-Item -ItemType File -Force -Path '$@' | Out-Null"

api: $(VK_VALIDATED)

check-api: $(VK_VALIDATED) $(LOADER_EXAMPLES)
	$(POWERSHELL) -File tests\verify-vk-tree.ps1 -Fasm2 "$(FASM2)" -BuildDir "$(BUILD)" -LoaderExamples "$(LOADER_EXAMPLES)"

$(CONSOLE_OBJ): examples\loaders\console.asm $(EXAMPLE_STRINGS) $(OBJECT_BASE) $(BUILD_READY)
	$(ASSEMBLE) -Source examples\loaders\console.asm -Output $@

$(VULKAN_DELAY_LIB): $(VK_VALIDATED) $(BUILD_READY)
	lib /NOLOGO /DEF:$(VULKAN_DELAY_DEF) /MACHINE:X64 /OUT:$@

$(VULKAN_DELAY_OBJ): vk\loader\delay.asm $(OBJECT_BASE) $(BUILD_READY)
	$(ASSEMBLE) -Includes newcoff.inc -Source vk\loader\delay.asm -Output $@

# One program under each loader. Only the includes and binding steps differ.
$(BUILD)\loader_iat.obj: examples\loaders\iat.asm vk\loader\iat.inc $(LOADER_EXAMPLE_BODY)
	$(ASSEMBLE) -Source examples\loaders\iat.asm -Output $@

$(BUILD)\loader_iat.exe: $(BUILD)\loader_iat.obj $(CONSOLE_OBJ)
	$(LOADER_EXAMPLE_LINK) $** $(VULKAN_LIB) kernel32.lib

$(BUILD)\loader_delay.obj: examples\loaders\delay.asm vk\loader\iat.inc $(LOADER_EXAMPLE_BODY)
	$(ASSEMBLE) -Source examples\loaders\delay.asm -Output $@

$(BUILD)\loader_delay.exe: $(BUILD)\loader_delay.obj $(VULKAN_DELAY_OBJ) $(CONSOLE_OBJ) $(VULKAN_DELAY_LIB)
	$(LOADER_EXAMPLE_LINK) $** kernel32.lib /DELAYLOAD:vulkan-1.dll

$(BUILD)\loader_static.obj: examples\loaders\static.asm vk\loader\static.inc vk\loader\lazy.inc $(LOADER_EXAMPLE_BODY)
	$(ASSEMBLE) -Source examples\loaders\static.asm -Output $@

$(BUILD)\loader_static.exe: $(BUILD)\loader_static.obj $(CONSOLE_OBJ)
	$(LOADER_EXAMPLE_LINK) $** $(VULKAN_LIB) kernel32.lib

$(BUILD)\loader_mixed.obj: examples\loaders\mixed.asm vk\loader\iat.inc vk\loader\static.inc vk\loader\lazy.inc $(LOADER_EXAMPLE_BODY)
	$(ASSEMBLE) -Source examples\loaders\mixed.asm -Output $@

$(BUILD)\loader_mixed.exe: $(BUILD)\loader_mixed.obj $(CONSOLE_OBJ)
	$(LOADER_EXAMPLE_LINK) $** $(VULKAN_LIB) kernel32.lib

$(BUILD)\loader_dynamic_app.obj: examples\loaders\dynamic_app.asm vk\loader\dynamic.inc $(LOADER_EXAMPLE_BODY)
	$(ASSEMBLE) -Source examples\loaders\dynamic_app.asm -Output $@

$(BUILD)\loader_dynamic_device.obj: examples\loaders\dynamic_device.asm vk\loader\dynamic.inc $(LOADER_EXAMPLE_BODY)
	$(ASSEMBLE) -Source examples\loaders\dynamic_device.asm -Output $@

$(BUILD)\loader_dynamic_loader.obj: $(LOADER_SOURCES) $(BUILD)\loader_dynamic_app.obj $(BUILD)\loader_dynamic_device.obj $(BUILD_READY)
	$(ASSEMBLE) -Includes "newcoff.inc;$(BUILD)\loader_dynamic_app.vkuse;$(BUILD)\loader_dynamic_device.vkuse" -Source vk\loader\loader.asm -Output $@

$(BUILD)\loader_dynamic.exe: $(BUILD)\loader_dynamic_app.obj $(BUILD)\loader_dynamic_device.obj $(BUILD)\loader_dynamic_loader.obj $(CONSOLE_OBJ)
	$(LOADER_EXAMPLE_LINK) $** $(VULKAN_LIB) kernel32.lib

$(BUILD)\loader_comdat_app.obj: examples\loaders\comdat_app.asm vk\loader\comdat.inc vk\loader\lazy.inc $(LOADER_EXAMPLE_BODY)
	$(ASSEMBLE) -Source examples\loaders\comdat_app.asm -Output $@

$(BUILD)\loader_comdat_device.obj: examples\loaders\comdat_device.asm vk\loader\comdat.inc vk\loader\lazy.inc $(LOADER_EXAMPLE_BODY)
	$(ASSEMBLE) -Source examples\loaders\comdat_device.asm -Output $@

$(BUILD)\loader_comdat.exe: $(BUILD)\loader_comdat_app.obj $(BUILD)\loader_comdat_device.obj $(CONSOLE_OBJ)
	$(LOADER_EXAMPLE_LINK) $** $(VULKAN_LIB) kernel32.lib

loaders: $(LOADER_EXAMPLES)
	$(POWERSHELL) -File examples\loaders\compare.ps1 -Executables "$(LOADER_EXAMPLES)"

# Headless VK_EXT_debug_utils examples, with one Vulkan-calling object apiece.
$(DEBUG_LOGGER_OBJ): examples\debug\logger.asm $(DEBUG_BODY)
	$(ASSEMBLE) -Source examples\debug\logger.asm -Output $@

$(BUILD)\debug_lifecycle.obj: examples\debug\00_lifecycle.asm $(DEBUG_BODY)
	$(ASSEMBLE) -Source examples\debug\00_lifecycle.asm -Output $@

$(BUILD)\debug_outputs.obj: examples\debug\01_outputs.asm $(DEBUG_BODY)
	$(ASSEMBLE) -Source examples\debug\01_outputs.asm -Output $@

$(BUILD)\debug_objects.obj: examples\debug\02_objects.asm $(DEBUG_BODY)
	$(ASSEMBLE) -Source examples\debug\02_objects.asm -Output $@

$(BUILD)\debug_lifecycle.exe: $(BUILD)\debug_lifecycle.obj $(DEBUG_LOGGER_OBJ) $(CONSOLE_OBJ)
	$(LINK_EXAMPLE) /MAP:$(@R).map /OUT:$@ $** $(VULKAN_LIB) kernel32.lib

$(BUILD)\debug_outputs.exe: $(BUILD)\debug_outputs.obj $(DEBUG_LOGGER_OBJ) $(CONSOLE_OBJ)
	$(LINK_EXAMPLE) /MAP:$(@R).map /OUT:$@ $** $(VULKAN_LIB) kernel32.lib

$(BUILD)\debug_objects.exe: $(BUILD)\debug_objects.obj $(DEBUG_LOGGER_OBJ) $(CONSOLE_OBJ)
	$(LINK_EXAMPLE) /MAP:$(@R).map /OUT:$@ $** $(VULKAN_LIB) kernel32.lib

$(BUILD)\debug_sink_probe.obj: tests\debug\sink_probe.asm examples\debug\sink.inc $(EXAMPLE_STRINGS) $(OBJECT_BASE) $(VK_VALIDATED) $(BUILD_READY)
	$(ASSEMBLE) -Source tests\debug\sink_probe.asm -Output $@

$(DEBUG_SINK_PROBE): $(BUILD)\debug_sink_probe.obj $(DEBUG_LOGGER_OBJ)
	$(LINK_EXAMPLE) /OUT:$@ $** kernel32.lib

debug: $(DEBUG_EXAMPLES) $(DEBUG_SINK_PROBE)
	$(POWERSHELL) -File tests\verify-debug-examples.ps1 -BuildDir "$(BUILD)"

check-debug: $(DEBUG_EXAMPLES) $(DEBUG_SINK_PROBE)
	$(POWERSHELL) -File tests\verify-debug-examples.ps1 -BuildDir "$(BUILD)" -Validation

$(BUILD)\legacy_fullscreen.spv: examples\legacy\fullscreen.vert $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\glslangValidator.exe" -V --target-env vulkan1.0 -o $@ examples\legacy\fullscreen.vert
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.0 $@

$(BUILD)\legacy_fractal.spv: examples\legacy\fractal.frag $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\glslangValidator.exe" -V --target-env vulkan1.0 -o $@ examples\legacy\fractal.frag
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.0 $@

$(BUILD)\legacy_fractal64.spv: examples\legacy\fractal64.frag $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\glslangValidator.exe" -V --target-env vulkan1.0 -o $@ examples\legacy\fractal64.frag
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.0 $@

$(BUILD)\legacy_fractal32x2.spv: examples\legacy\fractal32x2.frag $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\glslangValidator.exe" -V --target-env vulkan1.0 -o $@ examples\legacy\fractal32x2.frag
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.0 $@

# One explorer under each build contract. Only the contract lines differ.
$(BUILD)\legacy_adaptive.obj: examples\legacy\00_adaptive.asm $(LEGACY_BODY) $(LEGACY_SHADERS)
	$(ASSEMBLE) -Source examples\legacy\00_adaptive.asm -Output $@

$(BUILD)\legacy_compatibility.obj: examples\legacy\01_compatibility.asm $(LEGACY_BODY) $(LEGACY_SHADERS)
	$(ASSEMBLE) -Source examples\legacy\01_compatibility.asm -Output $@

$(BUILD)\legacy_modern.obj: examples\legacy\02_modern.asm $(LEGACY_BODY) $(LEGACY_SHADERS)
	$(ASSEMBLE) -Source examples\legacy\02_modern.asm -Output $@

$(BUILD)\legacy_adaptive.exe: $(BUILD)\legacy_adaptive.obj $(DEBUG_LOGGER_OBJ)
	$(LINK_WINDOW)

$(BUILD)\legacy_compatibility.exe: $(BUILD)\legacy_compatibility.obj $(DEBUG_LOGGER_OBJ)
	$(LINK_WINDOW)

$(BUILD)\legacy_modern.exe: $(BUILD)\legacy_modern.obj $(DEBUG_LOGGER_OBJ)
	$(LINK_WINDOW)

legacy: $(LEGACY_EXAMPLES)
	$(POWERSHELL) -File tests\verify-legacy-examples.ps1 -Fasm2 "$(FASM2)" -BuildDir "$(BUILD)"

check-legacy: $(LEGACY_EXAMPLES)
	$(POWERSHELL) -File tests\verify-legacy-examples.ps1 -Fasm2 "$(FASM2)" -BuildDir "$(BUILD)" -Validation

$(BUILD)\noAPI_cube_bindings.spv: examples\noAPI_cube\cube.vert $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\glslangValidator.exe" -V --target-env vulkan1.0 -DPOINTER_VERTICES=0 -o $@ examples\noAPI_cube\cube.vert
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.0 $@

$(BUILD)\noAPI_cube_pointer.spv: examples\noAPI_cube\cube.vert $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\glslangValidator.exe" -V --target-env vulkan1.2 -DPOINTER_VERTICES=1 -o $@ examples\noAPI_cube\cube.vert
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.2 $@

$(BUILD)\noAPI_cube_fragment.spv: examples\noAPI_cube\cube.frag $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\glslangValidator.exe" -V --target-env vulkan1.0 -o $@ examples\noAPI_cube\cube.frag
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.0 $@

$(BUILD)\noAPI_cube_heap_vertex.spv: examples\noAPI_cube\cube.slang $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\slangc.exe" examples\noAPI_cube\cube.slang -target spirv -profile spirv_1_5 -emit-spirv-directly -fvk-use-entrypoint-name -fvk-use-c-layout -matrix-layout-row-major -capability spvDescriptorHeapEXT -entry vertexMain -stage vertex -o $@
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.4 --scalar-block-layout $@

$(BUILD)\noAPI_cube_heap_fragment.spv: examples\noAPI_cube\cube.slang $(BUILD_READY)
	"$(VULKAN_SDK)\Bin\slangc.exe" examples\noAPI_cube\cube.slang -target spirv -profile spirv_1_5 -emit-spirv-directly -fvk-use-entrypoint-name -fvk-use-c-layout -matrix-layout-row-major -capability spvDescriptorHeapEXT -entry fragmentMain -stage fragment -o $@
	"$(VULKAN_SDK)\Bin\spirv-val.exe" --target-env vulkan1.4 --scalar-block-layout $@

$(BUILD)\noAPI_cube.obj: examples\noAPI_cube\cube.asm examples\noAPI_cube\lunarg_logo_256x256.rgba8 $(CUBE_BODY) $(CUBE_SHADERS)
	$(ASSEMBLE) -Source examples\noAPI_cube\cube.asm -Output $@

$(CUBE_EXAMPLE): $(BUILD)\noAPI_cube.obj $(DEBUG_LOGGER_OBJ)
	$(LINK_WINDOW)

noAPI_cube: $(CUBE_EXAMPLE)
	$(POWERSHELL) -File tests\verify-noAPI-cube.ps1 -BuildDir "$(BUILD)"

$(BUILD)\ranges_probe.obj: tests\ranges_probe.asm examples\common\cpu_arena.inc examples\common\range_allocator.inc $(EXAMPLE_STRINGS) $(OBJECT_BASE) $(BUILD_READY)
	$(ASSEMBLE) -Source tests\ranges_probe.asm -Output $@

$(RANGE_PROBE): $(BUILD)\ranges_probe.obj tests\ranges_probe.def
	link /NOLOGO /DLL /NOENTRY /NODEFAULTLIB /OUT:$@ /IMPLIB:$(BUILD)\vk_ranges_test.lib /DEF:tests\ranges_probe.def $(BUILD)\ranges_probe.obj kernel32.lib advapi32.lib

check-noAPI_cube: $(CUBE_EXAMPLE) $(RANGE_PROBE)
	$(POWERSHELL) -File tests\verify-noAPI-cube.ps1 -BuildDir "$(BUILD)" -Validation

$(MYHITS_HEADER): $(MYHITS)\shared.asm $(MYHITS)\shared.inc tools\assemble.ps1 $(BUILD_READY)
	$(ASSEMBLE) -Source $(MYHITS)\shared.asm -Output $@

# Proof 01: the pointer style compiles and is valid SPIR-V. Nothing runs.
$(BUILD)\myhits_style_collide.spv: $(STYLE_SLANG) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry collide -stage compute -o $@ $(STYLE_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_style_vertex.spv: $(STYLE_SLANG) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry sprite_vertex -stage vertex -o $@ $(STYLE_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_style_fragment.spv: $(STYLE_SLANG) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry sprite_fragment -stage fragment -o $@ $(STYLE_SLANG)
	$(MYHITS_VALIDATE) $@

# Proof 02: the boundary end to end, on the device.
$(BUILD)\myhits_spine_seed.spv: $(SPINE_SLANG) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry seed -stage compute -o $@ $(SPINE_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_spine_direct.spv: $(SPINE_SLANG) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry direct -stage compute -o $@ $(SPINE_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_spine_advance.spv: $(SPINE_SLANG) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry advance -stage compute -o $@ $(SPINE_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_spine_mote_vertex.spv: $(SPINE_SLANG) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry mote_vertex -stage vertex -o $@ $(SPINE_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_spine_mote_fragment.spv: $(SPINE_SLANG) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry mote_fragment -stage fragment -o $@ $(SPINE_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_spine.obj: $(MYHITS)\proofs\02_spine\spine.asm $(MYHITS_MACHINE) $(SPINE_SHADERS)
	$(ASSEMBLE) -Source $(MYHITS)\proofs\02_spine\spine.asm -Output $@

$(BUILD)\myhits_spine.exe: $(BUILD)\myhits_spine.obj $(DEBUG_LOGGER_OBJ)
	$(LINK_WINDOW) xinput.lib

# The art: the PNGs art.txt names, packed with the table of every frame. The
# .bin and the .slang are written with the .inc.
$(MYHITS_ART): $(MYHITS)\art\art.txt $(MYHITS)\art\*.png $(MYHITS)\tools\art.cs $(MYHITS)\tools\pack-art.ps1 $(BUILD_READY)
	$(POWERSHELL) -File $(MYHITS)\tools\pack-art.ps1 -BuildDir "$(BUILD)"

$(BUILD)\myhits_pictures_develop.spv: $(GALLERY_SLANG) $(MYHITS_PICTURES) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry develop -stage compute -o $@ $(GALLERY_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_pictures_chart.spv: $(GALLERY_SLANG) $(MYHITS_PICTURES) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry chart -stage compute -o $@ $(GALLERY_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_pictures_census.spv: $(GALLERY_SLANG) $(MYHITS_PICTURES) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry census -stage compute -o $@ $(GALLERY_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_pictures_direct.spv: $(GALLERY_SLANG) $(MYHITS_PICTURES) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry direct -stage compute -o $@ $(GALLERY_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_pictures_sprite_vertex.spv: $(GALLERY_SLANG) $(MYHITS_PICTURES) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry sprite_vertex -stage vertex -o $@ $(GALLERY_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_pictures_sprite_fragment.spv: $(GALLERY_SLANG) $(MYHITS_PICTURES) $(MYHITS_HEADER)
	$(MYHITS_SLANG) -entry sprite_fragment -stage fragment -o $@ $(GALLERY_SLANG)
	$(MYHITS_VALIDATE) $@

$(BUILD)\myhits_pictures.obj: $(MYHITS)\proofs\03_pictures\gallery.asm $(MYHITS_MACHINE) $(MYHITS_PICTURES) $(GALLERY_SHADERS)
	$(ASSEMBLE) -Source $(MYHITS)\proofs\03_pictures\gallery.asm -Output $@

$(BUILD)\myhits_pictures.exe: $(BUILD)\myhits_pictures.obj $(DEBUG_LOGGER_OBJ)
	$(LINK_WINDOW) xinput.lib

myhits-proofs: $(MYHITS_PROOFS)
	$(POWERSHELL) -File $(MYHITS)\proofs\run.ps1 -BuildDir "$(BUILD)"

# What this machine offers that the plan leans on; nothing is built.
myhits-survey:
	$(POWERSHELL) -File $(MYHITS)\proofs\00_survey\survey.ps1

check-myhits: $(MYHITS_PROOFS)
	$(POWERSHELL) -File $(MYHITS)\proofs\run.ps1 -BuildDir "$(BUILD)" -Validation

check: check-api check-debug check-legacy check-noAPI_cube check-myhits

# Generated includes and manifests survive clean; the next build reuses them.
clean:
	$(POWERSHELL) -Command "if (Test-Path -LiteralPath '$(BUILD)') { if ((Resolve-Path -LiteralPath '$(BUILD)').Path -ne (Join-Path (Get-Location).Path 'build')) { throw 'Refusing to clean outside the repository build directory' }; Remove-Item -LiteralPath '$(BUILD)' -Recurse -Force }"
