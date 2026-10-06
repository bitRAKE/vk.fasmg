; Stands in for vulkan-1.lib in the lazy trampoline probe.  Its resolver
; records what it was asked, wrecks every volatile register, and hands back a
; function that records what it was called with.
include 'newcoff.inc'

public fake_import as '__imp_vkGetInstanceProcAddr'
public resolver_handle
public resolver_name
public resolver_calls
public probe_arguments

section '.text$t' code readable executable align 16

; RCX = dispatch handle, RDX = function name.
fake_resolver:
	mov [resolver_handle],rcx
	mov [resolver_name],rdx
	inc [resolver_calls]
	lea rax,[fake_resolver]
	cmp dword [rdx+5],'Devi'		; vkGetDeviceProcAddr resolves to
	jne .function				; this same resolver
	cmp dword [rdx+11],'Proc'
	je .wreck
.function:
	lea rax,[probe]
.wreck:
	or rcx,-1
	or rdx,-1
	or r8,-1
	or r9,-1
	or r10,-1
	or r11,-1
	pcmpeqd xmm0,xmm0
	pcmpeqd xmm1,xmm1
	pcmpeqd xmm2,xmm2
	pcmpeqd xmm3,xmm3
	pcmpeqd xmm4,xmm4
	pcmpeqd xmm5,xmm5
	ret

probe:
	mov [probe_arguments],rcx
	mov [probe_arguments+8],rdx
	mov [probe_arguments+16],r8
	mov [probe_arguments+24],r9
	mov rax,[rsp+40]			; the fifth argument
	mov [probe_arguments+32],rax
	movss dword [probe_arguments+40],xmm0
	movss dword [probe_arguments+44],xmm1
	movss dword [probe_arguments+48],xmm2
	movss dword [probe_arguments+52],xmm3
	mov eax,600Dh
	ret

section '.data$t' data readable writeable align 16

fake_import dq fake_resolver
resolver_handle dq 0
resolver_name dq 0
probe_arguments rq 7
resolver_calls dd 0
