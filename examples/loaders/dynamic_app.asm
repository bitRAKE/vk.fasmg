; Lazy slots in a loader object, first of two objects.  Neither object defines
; a slot: each reports the functions it refers to in <object>.vkuse, and the
; loader object is assembled over both reports once both objects exist.  The
; program gets one ordered table holding each function once.
;
;	fasm2 examples\loaders\dynamic_app.asm build\loader_dynamic_app.obj
;	fasm2 examples\loaders\dynamic_device.asm build\loader_dynamic_device.obj
;	fasm2 -iinclude('newcoff.inc') -iinclude('build\loader_dynamic_app.vkuse') -iinclude('build\loader_dynamic_device.vkuse') vk\loader\loader.asm build\loader_dynamic_loader.obj
;	link the three objects with build\loader_console.obj vulkan-1.lib kernel32.lib
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/khr/surface.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/dynamic.inc'

public mainCRTStartup
public instance
public device
extrn run_device:qword

include 'instance.inc'

binding_text db 'lazy slots in a loader object assembled from two objects'' reports',0
