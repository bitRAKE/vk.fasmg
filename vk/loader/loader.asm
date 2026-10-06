; The loader object of a program whose objects use dynamic.inc.  It is built
; last, over the reports the other objects wrote:
;
;	fasm2 -iinclude('program.inc') -iinclude('a.vkuse') -iinclude('b.vkuse') loader.asm loader.obj
;
; where program.inc stands for whatever selects the output format and brings
; macro/proc64.inc.  Every function a report names gets a lazy slot (see
; lazy.inc), published as its __imp_ symbol, so the linker binds the objects'
; calls here before it looks in vulkan-1.lib.
;
; The application publishes the qwords `instance` and `device`.

extrn '__imp_vkGetInstanceProcAddr' as vkGetInstanceProcAddr:qword

; The device resolver needs a function no object may have asked for.
irpv functions, loader_functions_device
	if % = 1
		define loader_functions_instance vkGetDeviceProcAddr
	end if
end irpv

include 'lazy.inc'

vk_lazy.take
vk_lazy.build 1
