; Lazy binding for a single object.  Every function gathered so far becomes an
; instruction that calls through its slot:
;
;	vkCreateInstance addr info, 0, addr instance
;
; A slot exists only for a function the object refers to, and resolves itself
; through vkGetInstanceProcAddr or vkGetDeviceProcAddr the first time it is
; called (see lazy.inc).  The application defines the qwords `instance` and
; `device`; only vkGetInstanceProcAddr is imported.
;
; Each object including this builds its own tables.  For several objects that
; share one set of slots use dynamic.inc and loader.asm.

include 'lazy.inc'

vk_lazy.take

postpone
	vk_lazy.build 0
end postpone
