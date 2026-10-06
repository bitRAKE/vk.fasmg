; Probes the lazy trampoline against lazy_fake.asm, with no Vulkan involved:
; a first call must reach its function with every argument register intact,
; ask the right resolver with the right handle, and never ask again.
; Exits with 0, or with the number of the check that failed.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/loader/static.inc'

public mainCRTStartup

extrn ExitProcess:qword
extrn resolver_handle:qword
extrn resolver_name:qword
extrn resolver_calls:dword
extrn probe_arguments:qword

INSTANCE := 0x1A57A9CE
DEVICE := 0xDE71CE

macro check condition&
	inc ebx
	cmp condition
	jne failed
end macro

section '.text$t' code readable executable align 16

load_arguments:
	mov rcx,0x1111
	mov rdx,0x2222
	mov r8,0x3333
	mov r9,0x4444
	mov qword [rsp+8+32],0x5555		; the caller's fifth argument slot
	movss xmm0,[floats]
	movss xmm1,[floats+4]
	movss xmm2,[floats+8]
	movss xmm3,[floats+12]
	ret

mainCRTStartup:
	sub rsp,56
	xor ebx,ebx

	; A device function with float arguments, resolved through
	; vkGetDeviceProcAddr, which is itself resolved on the way.
	call load_arguments
	call [vkCmdSetDepthBias]
	check eax,600Dh
	check [probe_arguments],0x1111
	check [probe_arguments+8],0x2222
	check [probe_arguments+16],0x3333
	check [probe_arguments+24],0x4444
	check [probe_arguments+32],0x5555
	mov rax,qword [floats]
	check [probe_arguments+40],rax
	mov rax,qword [floats+8]
	check [probe_arguments+48],rax
	check [resolver_handle],DEVICE
	mov rax,[resolver_name]
	check dword [rax+5],'SetD'
	check [resolver_calls],2

	; The slot now holds the function: no resolver on the second call.
	call load_arguments
	call [vkCmdSetDepthBias]
	check eax,600Dh
	check [resolver_calls],2

	; Before there is an instance its resolver is given none.
	call [vkEnumerateInstanceVersion]
	check [resolver_handle],0
	check [resolver_calls],3

	mov [instance],INSTANCE
	call [vkDestroyInstance]
	check [resolver_handle],INSTANCE
	check [resolver_calls],4

	xor ebx,ebx
failed:
	mov ecx,ebx
	call ExitProcess
	int3

section '.data$t' data readable writeable align 16

instance dq 0
device dq DEVICE
floats dd 1.5,-2.25,3.0e10,4.0e-10
