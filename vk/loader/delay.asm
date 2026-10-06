; The helper behind the linker's delay-load mechanism, taught to ask Vulkan.
;
; Objects built with iat.inc need nothing more in their source.  The program
; is linked against an import library made from vk\vulkan-1.def, which names
; every function whether vulkan-1.dll exports it or not, with
; /DELAYLOAD:vulkan-1.dll, and with this object:
;
;	fasm2 -iinclude('program.inc') delay.asm delay.obj
;	lib /DEF:vk\vulkan-1.def /MACHINE:X64 /OUT:vulkan-1-delay.lib
;	link ... delay.obj vulkan-1-delay.lib /DELAYLOAD:vulkan-1.dll
;
; where program.inc stands for whatever selects the output format.  The linker
; then builds the slots, their names and a thunk per function; on a slot's
; first call the thunks set the argument registers aside and call the helper
; here, which is all the mechanism leaves to the program.  It answers with
; vkGetInstanceProcAddr, so with the Vulkan loader's entry points: functions
; the library does not export are reached, and a device function serves any
; device.
;
; vulkan-1.dll is loaded on the first call of any function.  While it cannot
; be, every function returns VK_ERROR_INITIALIZATION_FAILED, so a program
; whose first call is vkCreateInstance fails the ordinary way.  A function
; the implementation does not have resolves to null.
;
; The application publishes the qword `instance`, zero until there is one.

public vk_delay_helper as '__delayLoadHelper2'

extrn __ImageBase
extrn '__imp_LoadLibraryA' as vk_delay_LoadLibraryA:qword
extrn '__imp_GetProcAddress' as vk_delay_GetProcAddress:qword
extrn instance:qword

section '.text$vk' code readable executable align 16

; __delayLoadHelper2: RCX = the library's delay-load descriptor, RDX = the
; slot.  Returns the address the thunk is to jump to.
vk_delay_helper:
	push rbx
	push rsi
	push rdi
	push r12
	sub rsp,40
	mov rbx,rcx
	mov rsi,rdx
	lea rdi,[__ImageBase]

	; The slot's place in the delay import address table is its name's
	; place in the name table.  Both are image-relative in the descriptor.
	mov eax,[rbx+12]
	lea rcx,[rdi+rax]
	mov rax,rsi
	sub rax,rcx
	mov ecx,[rbx+16]
	add rcx,rdi
	mov rax,[rcx+rax]
	lea r12,[rdi+rax+2]

	; The one function taken from the library's export table.
	mov rax,[vk_delay_resolver]
	test rax,rax
	jnz .resolve
	mov eax,[rbx+4]
	lea rcx,[rdi+rax]
	call [vk_delay_LoadLibraryA]
	test rax,rax
	jz .absent
	mov rcx,rax
	lea rdx,[vk_delay_resolver_name]
	call [vk_delay_GetProcAddress]
	test rax,rax
	jz .absent
	mov [vk_delay_resolver],rax

.resolve:
	mov rcx,[instance]
	mov rdx,r12
	call rax
	test rax,rax
	jz .done
	mov [rsi],rax
.done:
	add rsp,40
	pop r12
	pop rdi
	pop rsi
	pop rbx
	ret

.absent:
	lea rax,[vk_delay_absent]
	jmp .done

; Stands in for every function while there is no library; the slot is left
; alone, so a later call tries again.
vk_delay_absent:
	mov eax,-3				; VK_ERROR_INITIALIZATION_FAILED
	ret

section '.rdata$vk' data readable align 8

vk_delay_resolver_name db 'vkGetInstanceProcAddr',0

section '.bss$vk' readable writeable align 8

vk_delay_resolver dq ?
