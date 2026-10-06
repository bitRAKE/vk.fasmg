# NMAKE: generate and verify the Vulkan projection, then build loader/debug examples.
# Override FASM2 and CLANG on the command line for other toolchain locations.

!IFNDEF FASM2
FASM2 = ..\fasm2\fasm2.cmd
!ENDIF
!IFNDEF CLANG
CLANG = $(PROGRAMFILES)\LLVM\bin\clang.exe
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

VULKAN_DELAY_DEF = vk\vulkan-1.def
VULKAN_DELAY_LIB = $(BUILD)\vulkan-1-delay.lib
VULKAN_DELAY_OBJ = $(BUILD)\vk_delay.obj

all: $(LOADER_EXAMPLES) $(DEBUG_EXAMPLES)

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

check: check-api check-debug

# Generated includes and manifests survive clean; the next build reuses them.
clean:
	$(POWERSHELL) -Command "if (Test-Path -LiteralPath '$(BUILD)') { if ((Resolve-Path -LiteralPath '$(BUILD)').Path -ne (Join-Path (Get-Location).Path 'build')) { throw 'Refusing to clean outside the repository build directory' }; Remove-Item -LiteralPath '$(BUILD)' -Recurse -Force }"
