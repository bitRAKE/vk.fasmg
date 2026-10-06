; The lazy trampoline behind static.inc, loader.asm and comdat.inc.
;
; Every slot starts out pointing at a resolver.  The first `call [slot]` lands
; there: the call's rip-relative operand locates the slot, the slot leads to
; its name, and the function's address replaces the resolver before the call
; goes through.  Later calls never come here.
;
;	+ a function is resolved when the run-time path first needs it
;	- the slots stay writable
;	- a slot may only be reached by `call [slot]`
;
; One instance and one device.  The resolvers read the qwords `instance` and
; `device`, which the application defines and fills; `instance` is zero until
; there is one, which is what the functions that precede it resolve against.
; vkGetInstanceProcAddr cannot be resolved this way; it is always an import.

; Entered as the target of `call [slot]`.  Sets the arguments aside and leaves
; the slot's address in RAX, ready for a resolver call.
macro vk_lazy.enter
	mov [rsp+8],rcx			; the caller's home space holds
	mov [rsp+16],rdx		; the register arguments
	mov [rsp+24],r8
	mov [rsp+32],r9
	mov rax,[rsp]			; return address, just past the
	movsxd rdx,dword [rax-4]	; operand of `call [slot]`
	add rax,rdx
	push rax
	sub rsp,32+4*16
	movaps [rsp+32],xmm0		; float arguments survive too
	movaps [rsp+48],xmm1
	movaps [rsp+64],xmm2
	movaps [rsp+80],xmm3
end macro

; With the function's address in RAX: fills the slot and goes there.
macro vk_lazy.leave
	movaps xmm0,[rsp+32]
	movaps xmm1,[rsp+48]
	movaps xmm2,[rsp+64]
	movaps xmm3,[rsp+80]
	add rsp,32+4*16
	pop rcx
	mov [rcx],rax
	mov rcx,[rsp+8]
	mov rdx,[rsp+16]
	mov r8,[rsp+24]
	mov r9,[rsp+32]
	jmp rax
end macro

; Takes every function gathered so far: an instruction for each, and a place
; in the tables vk_lazy.build emits.
macro vk_lazy.take
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
					; Objects reporting to one loader name a function once each.
					if ~ definite vk_lazy.taken.function
						vk_lazy.taken.function := 1
						define vk_lazy.list.class function
					end if
				end match
			end iterate
			restore loader_functions_#class
		end irpv
	end iterate
end macro

; Emits the slots, their names and the resolvers.  A provider serves other
; objects: it defines every slot it was told of and publishes each as its
; __imp_ symbol.  Otherwise only the slots this object refers to exist.
macro vk_lazy.build provider*

	section '.data$vk' data readable writeable align 64

	vk_lazy.slots:
	iterate class, instance,device
		vk_lazy.count.class = 0
		irpv function, vk_lazy.list.class
			if provider | used function
				; The name is an instruction by now, so it cannot lead the line.
				label function:qword
				dq vk_lazy.resolve.class
				vk_lazy.count.class = vk_lazy.count.class + 1
				if provider
					public function as '__imp_' bappend `function
				else
					; Not for linking: it names the slot in the link map.
					public static function as '__imp_' bappend `function
				end if
			end if
		end irpv
	end iterate

	section '.rdata$vk' data readable align 8

	; Mirrors the slots, entry for entry.
	vk_lazy.names:
	iterate class, instance,device
		irpv function, vk_lazy.list.class
			if provider | used function
				dq vk_lazy.name.function
			end if
		end irpv
	end iterate
	iterate class, instance,device
		irpv function, vk_lazy.list.class
			if provider | used function
				vk_lazy.name.function db `function,0
			end if
		end irpv
	end iterate

	if provider & vk_lazy.count.instance
		extrn instance:qword
	end if
	if provider & vk_lazy.count.device
		extrn device:qword
	end if

	section '.text$vk' code readable executable align 16

	if vk_lazy.count.device
		vk_lazy.resolve.device:
			mov r10d,1
			jmp vk_lazy.resolve
	end if
	if vk_lazy.count.instance
		vk_lazy.resolve.instance:
			xor r10d,r10d
	end if
	if vk_lazy.count.instance | vk_lazy.count.device
		vk_lazy.resolve:
			vk_lazy.enter
			lea rcx,[vk_lazy.slots]
			sub rax,rcx
			lea rcx,[vk_lazy.names]
			mov rdx,[rcx+rax]
		if vk_lazy.count.device
			test r10d,r10d
			jz vk_lazy.resolve.by_instance
			mov rcx,[device]
			call [vkGetDeviceProcAddr]	; itself a slot, as lazy as any
			jmp vk_lazy.resolve.done
		end if
		vk_lazy.resolve.by_instance:
		if vk_lazy.count.instance
			mov rcx,[instance]
			call [vkGetInstanceProcAddr]
		end if
		vk_lazy.resolve.done:
			vk_lazy.leave
	end if

end macro
