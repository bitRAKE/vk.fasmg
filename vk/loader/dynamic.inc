; Binding left to the loader object.  Every function gathered so far becomes
; an instruction that calls through its slot:
;
;	vkCreateInstance addr info, 0, addr instance
;
; The slots are link-time symbols, the same __imp_ names iat.inc declares.
; What this adds is a report: the functions the object refers to are written
; to <object>.vkuse, in the form the generated includes list them.  Assembling
; loader.asm over the reports of every object in the program, once all of them
; are built, yields the object that defines those slots.
;
; vkGetInstanceProcAddr is not reported; it is always an import.

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
			match =vkGetInstanceProcAddr, function
			else
				define vk_dynamic.list.class function
			end match
		end iterate
		restore loader_functions_#class
	end irpv
end iterate

postpone
	virtual as 'vkuse'
		iterate class, instance,device
			irpv function, vk_dynamic.list.class
				if used function
					db 'define loader_functions_',`class,9,`function,13,10
				end if
			end irpv
		end iterate
	end virtual
end postpone
