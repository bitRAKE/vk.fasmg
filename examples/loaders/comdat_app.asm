; Lazy slots merged by the linker, first of two objects.  Each object emits the
; slots it refers to as COMDAT sections; the linker keeps one of each and lays
; them out side by side.  No loader object, no reports, nothing built last.
;
;	fasm2 examples\loaders\comdat_app.asm build\loader_comdat_app.obj
;	fasm2 examples\loaders\comdat_device.asm build\loader_comdat_device.obj
;	link the two objects with build\loader_console.obj vulkan-1.lib kernel32.lib
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/comdat.inc'

public mainCRTStartup
public instance
public device
extrn run_device:qword

include 'instance.inc'

binding_text GLOBSTR 'lazy slots the linker merged from two objects',0
