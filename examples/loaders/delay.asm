; The linker's delay-load mechanism.  The source is the import-table build
; with debug_utils added: every function is an import.  The link makes the
; difference.  An import library naming every function, exported or not, lets
; the linker build the slots and their first-call thunks; the helper object
; answers them through vkGetInstanceProcAddr.
;
;	fasm2 examples\loaders\delay.asm build\loader_delay.obj
;	fasm2 -iinclude('newcoff.inc') vk\loader\delay.asm build\vk_delay.obj
;	lib /DEF:vk\vulkan-1.def /MACHINE:X64 /OUT:build\vulkan-1-delay.lib
;	link build\loader_delay.obj build\vk_delay.obj build\loader_console.obj build\vulkan-1-delay.lib kernel32.lib /DELAYLOAD:vulkan-1.dll
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/iat.inc'

public mainCRTStartup
public instance

include 'instance.inc'
include 'device.inc'

binding_text db 'delay-loaded imports: the linker''s thunks, answered through vkGetInstanceProcAddr',0
