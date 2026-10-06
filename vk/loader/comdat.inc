; Lazy binding for any number of objects, with no loader object and nothing
; built last.  Every function gathered so far becomes an instruction that
; calls through its slot:
;
;	vkCreateInstance addr info, 0, addr instance
;
; Each object emits the slots it refers to, one COMDAT section apiece under
; the function's __imp_ name, and the linker keeps one copy of each across the
; program.  A slot's section holds its eight bytes and nothing else, so the
; linker's grouping of equally named sections lays every slot of the program
; side by side: a dense table, in whatever order the linker met them.
;
; No order means no second table can mirror the first.  A slot instead starts
; out pointing at a few bytes of its own, off the run-time path, that hand its
; name to the resolver (see lazy.inc).
;
; One object defines and publishes the qwords `instance` and `device`.

include 'lazy.inc'

iterate class, instance,device
	irpv functions, loader_functions_#class
		iterate function, functions
			calminstruction function line&
				arrange line, =fastcall [=function], line
				assemble line
			end calminstruction
			match =vkGetInstanceProcAddr, function
				if used function
					extrn '__imp_' bappend `function as function:qword
				end if
			else
				define vk_comdat.list.class function
			end match
		end iterate
		restore loader_functions_#class
	end irpv
end iterate

postpone

	iterate class, instance,device
		vk_comdat.count.class = 0
		irpv function, vk_comdat.list.class
			if used function
				section '.data$vk' data readable writeable comdat any align 8
				label function:qword
				public function as '__imp_' bappend `function
				dq vk_comdat.first.function

				section '.text$vkn' code readable executable comdat any align 1
				label vk_comdat.first.function
				public vk_comdat.first.function as '__lazy_' bappend `function
					lea r10,[vk_comdat.name.function]
					jmp vk_comdat.resolve.class
				vk_comdat.name.function db `function,0

				vk_comdat.count.class = vk_comdat.count.class + 1
			end if
		end irpv
	end iterate

	if vk_comdat.count.instance
		if ~ definite instance
			extrn instance:qword
		end if
		section '.text$vk' code readable executable comdat any align 16
		vk_comdat.resolve.instance:
		public vk_comdat.resolve.instance as '__lazy_instance'
			vk_lazy.enter
			mov rdx,r10
			mov rcx,[instance]
			call [vkGetInstanceProcAddr]
			vk_lazy.leave
	end if

	if vk_comdat.count.device
		if ~ definite device
			extrn device:qword
		end if
		section '.text$vk' code readable executable comdat any align 16
		vk_comdat.resolve.device:
		public vk_comdat.resolve.device as '__lazy_device'
			vk_lazy.enter
			mov rdx,r10
			mov rcx,[device]
			call [vkGetDeviceProcAddr]	; itself a slot, as lazy as any
			vk_lazy.leave
	end if

end postpone
