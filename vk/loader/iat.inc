; Import-table binding.  Every function gathered so far becomes an instruction
; that calls through its import slot:
;
;	vkCreateInstance addr info, 0, addr instance
;
; The slot, vkName, is declared when the object refers to it.  Windows fills
; the slots before the program starts, and will not start it when vulkan-1.dll
; lacks one.  vulkan-1.lib supplies the core API and the KHR window-system
; functions; another extension's function needs an object that publishes its
; __imp_ slot (see dynamic.inc).
;
; A loader takes the lists it finds.  Includes that follow start new ones, for
; a later loader to bind another way.

iterate class, instance,device
	irpv functions, loader_functions_#class
		iterate function, functions
			calminstruction function line&
				arrange line, =fastcall [=function], line
				assemble line
			end calminstruction
			if used function
				extrn '__imp_' bappend `function as function:qword
			end if
		end iterate
		restore loader_functions_#class
	end irpv
end iterate
