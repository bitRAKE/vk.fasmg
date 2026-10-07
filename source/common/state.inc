; What a program remembers from one run to the next: values by name, in the
; registry, under HKEY_CURRENT_USER\Software\vk.fasmg\<MACHINE_NAME>.
;
;	state_get	name, place, bytes	nonzero if a value of exactly that size
;						was there; it is then at `place`
;	state_put	name, place, bytes	nonzero if it was written
;	state_drop	name			forget it
;
; Each opens the key, does its work and closes it: these are for a few times
; in a run, not for a frame. A value is at most STATE_LIMIT bytes.
STATE_ROOT := -7FFFFFFFh		; HKEY_CURRENT_USER: 80000001h, sign-extended as the headers have it
STATE_ACCESS := 2001Fh			; to read and to write
STATE_BINARY := 3
STATE_LIMIT := 64

iterate function,RegCreateKeyExW,RegQueryValueExW,RegSetValueExW,RegDeleteValueW,RegCloseKey
	extrn function:qword
end iterate

section '.text$state' code readable executable align 16

; The key, made if it was not there. Returns Windows' error: zero is none.
proc state_open
	fastcall RegCreateKeyExW,STATE_ROOT,addr state_path,0,0,0,STATE_ACCESS,0,addr state_key,0
	ret
endp

proc state_get uses rbx rsi rdi,name,place,bytes
	mov rbx,rcx
	mov rsi,rdx
	mov edi,r8d
	fastcall state_open
	test eax,eax
	jnz .none
	; Into a place of its own first: a value of another size is not half-taken.
	mov [state_size],STATE_LIMIT
	fastcall RegQueryValueExW,[state_key],rbx,0,addr state_type,addr state_scratch,addr state_size
	mov ebx,eax
	fastcall RegCloseKey,[state_key]
	test ebx,ebx
	jnz .none
	cmp [state_type],STATE_BINARY
	jne .none
	cmp [state_size],edi
	jne .none
	mov ecx,edi
	mov rdi,rsi
	lea rsi,[state_scratch]
	rep movsb
	mov eax,1
	ret
.none:
	xor eax,eax
	ret
endp

proc state_put uses rbx rsi rdi,name,place,bytes
	mov rbx,rcx
	mov rsi,rdx
	mov edi,r8d
	fastcall state_open
	test eax,eax
	jnz .failed
	mov [state_size],edi
	fastcall RegSetValueExW,[state_key],rbx,0,STATE_BINARY,rsi,[state_size]
	mov ebx,eax
	fastcall RegCloseKey,[state_key]
	test ebx,ebx
	jnz .failed
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc state_drop uses rbx,name
	mov rbx,rcx
	fastcall state_open
	test eax,eax
	jnz .done
	fastcall RegDeleteValueW,[state_key],rbx
	fastcall RegCloseKey,[state_key]
.done:
	ret
endp

section '.data$state' data readable writeable align 8
state_key dq 0
state_type dd 0
state_size dd 0
state_scratch:
	rb STATE_LIMIT
state_path GLOBWSTR 'Software\vk.fasmg\',MACHINE_NAME,0
