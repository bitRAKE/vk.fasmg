; Lazy slots in one object.  Each function the program refers to gets a slot
; that resolves itself on its first call; vkGetInstanceProcAddr is the only
; import.  Any extension's functions can be bound, and one that is never
; reached is never asked for.
;
;	fasm2 examples\loaders\static.asm build\loader_static.obj
;	link build\loader_static.obj build\loader_console.obj vulkan-1.lib kernel32.lib
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/static.inc'

public mainCRTStartup

include 'instance.inc'
include 'device.inc'

binding_text GLOBSTR 'lazy slots in this object: each function binds at its first call',0
