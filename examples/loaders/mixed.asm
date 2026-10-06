; Two loaders in one object.  A loader takes what was included ahead of it, so
; the exported functions go through the import table and debug_utils, which
; cannot, through lazy slots.
;
;	fasm2 examples\loaders\mixed.asm build\loader_mixed.obj
;	link build\loader_mixed.obj build\loader_console.obj vulkan-1.lib kernel32.lib
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/loader/iat.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/static.inc'

public mainCRTStartup

include 'instance.inc'
include 'device.inc'

binding_text db 'core and surface through the import table, debug_utils through lazy slots',0
