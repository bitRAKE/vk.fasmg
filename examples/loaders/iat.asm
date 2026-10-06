; The import table.  Windows binds every function the program refers to before
; it starts; the program carries no loader code and no table of its own.
;
; Only what vulkan-1.dll exports can be bound this way: the core API and the
; window-system extensions.  debug_utils is not among them, so its file is
; left out here.
;
;	fasm2 examples\loaders\iat.asm build\loader_iat.obj
;	link build\loader_iat.obj build\loader_console.obj vulkan-1.lib kernel32.lib
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/loader/iat.inc'

public mainCRTStartup

include 'instance.inc'
include 'device.inc'

binding_text db 'import table: Windows bound every function before the program started',0
