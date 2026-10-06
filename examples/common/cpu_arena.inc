; One startup arena for allocator metadata. Large pages are optional; no policy
; changes or elevation are performed. Call arena_take only during initialization.
CPU_ARENA_BYTES = 2*1024*1024
CPU_MEM_LARGE_PAGES = 20000000h
section '.text$arena' code readable executable align 16
proc create_cpu_arena uses rbx
	mov edx,[cpu_arena_configured_bytes]
	mov [cpu_arena_bytes],rdx
	cmp [large_pages_requested],0
	je .ordinary
	fastcall GetLargePageMinimum
	test rax,rax
	jz .ordinary
	mov [large_page_minimum],rax
	lea rdx,[rax-1]
	mov ecx,[cpu_arena_configured_bytes]
	add rdx,rcx
	neg rax
	and rdx,rax
	mov [cpu_arena_bytes],rdx
	fastcall OpenProcessToken,-1,20h or 8,addr arena_token
	test eax,eax
	jz .fallback_error
	fastcall LookupPrivilegeValueW,0,<W,'SeLockMemoryPrivilege'>,addr arena_privileges+4
	test eax,eax
	jz .close_fallback
	fastcall SetLastError,0
	fastcall AdjustTokenPrivileges,[arena_token],0,addr arena_privileges,sizeof_arena_privileges,addr arena_previous,addr arena_previous_bytes
	test eax,eax
	jz .close_fallback
	fastcall GetLastError
	test eax,eax
	jnz .close_fallback
	fastcall VirtualAlloc,0,[cpu_arena_bytes],MEM_COMMIT or MEM_RESERVE or CPU_MEM_LARGE_PAGES,PAGE_READWRITE
	mov rbx,rax
	test rax,rax
	jnz .restore
	fastcall GetLastError
	mov [large_pages_error],eax
.restore:
	; Restore the token's prior privilege state after the startup allocation.
	fastcall AdjustTokenPrivileges,[arena_token],0,addr arena_previous,0,0,0
	fastcall CloseHandle,[arena_token]
	mov [arena_token],0
	test rbx,rbx
	jz .ordinary
	mov [cpu_arena],rbx
	mov [large_pages_active],1
	jmp .ready
.close_fallback:
	fastcall GetLastError
	mov [large_pages_error],eax
	fastcall CloseHandle,[arena_token]
	mov [arena_token],0
	jmp .ordinary
.fallback_error:
	fastcall GetLastError
	mov [large_pages_error],eax
.ordinary:
	mov edx,[cpu_arena_configured_bytes]
	mov [cpu_arena_bytes],rdx
	fastcall VirtualAlloc,0,rdx,MEM_COMMIT or MEM_RESERVE,PAGE_READWRITE
	mov [cpu_arena],rax
.ready:
	cmp [cpu_arena],0
	setnz al
	movzx eax,al
	ret
endp

; Returns a 16-byte-aligned zero-initialized region, or zero when exhausted.
proc arena_take bytes
	mov rax,[cpu_arena_used]
	add rcx,15
	jc .failed
	and rcx,-16
	add rcx,rax
	jc .failed
	cmp rcx,[cpu_arena_bytes]
	ja .failed
	mov [cpu_arena_used],rcx
	add rax,[cpu_arena]
	ret
.failed:
	xor eax,eax
	ret
endp

proc destroy_cpu_arena
	cmp [cpu_arena],0
	je .done
	fastcall VirtualFree,[cpu_arena],0,MEM_RELEASE
	mov [cpu_arena],0
.done:
	ret
endp

section '.data$arena' data readable writeable align 8
cpu_arena dq 0
cpu_arena_bytes dq 0
cpu_arena_used dq 0
large_page_minimum dq 0
large_pages_requested dd 1
large_pages_active dd 0
large_pages_error dd 0
cpu_arena_configured_bytes dd CPU_ARENA_BYTES
arena_token dq 0
; TOKEN_PRIVILEGES has four-byte alignment: count, LUID, attributes.
arena_privileges dd 1,0,0,2
sizeof_arena_privileges = $ - arena_privileges
arena_previous rb sizeof_arena_privileges
arena_previous_bytes dd 0
