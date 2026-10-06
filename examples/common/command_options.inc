; Compare complete arguments, so --no-address-commands leaves --no-address off.
extrn CommandLineToArgvW:qword
extrn LocalFree:qword
extrn lstrcmpiW:qword
section '.text$options' code readable executable align 16
proc read_options
	fastcall GetCommandLineW
	fastcall CommandLineToArgvW,rax,addr option_count
	mov [option_arguments],rax
	ret
endp

proc command_option uses rbx rsi rdi,name
	mov rdi,rcx
	mov rsi,[option_arguments]
	mov ebx,1
	test rsi,rsi
	jz .absent
.argument:
	cmp ebx,[option_count]
	jae .absent
	fastcall lstrcmpiW,[rsi+rbx*8],rdi
	test eax,eax
	jz .found
	inc ebx
	jmp .argument
.found:
	mov eax,1
	ret
.absent:
	xor eax,eax
	ret
endp

proc free_options
	cmp [option_arguments],0
	je .done
	fastcall LocalFree,[option_arguments]
	mov [option_arguments],0
.done:
	ret
endp

; Complete ASCII name=value argument. Returns 1 and EDX=value, 0 if absent,
; or -1 for an empty, malformed, or overflowing unsigned decimal value.
proc command_option_uint uses rbx rsi rdi,name
	mov rdi,rcx
	mov rsi,[option_arguments]
	mov ebx,1
.argument:
	cmp ebx,[option_count]
	jae .absent
	mov r8,rdi
	mov r9,[rsi+rbx*8]
.prefix:
	movzx eax,word [r8]
	test eax,eax
	jz .value
	movzx ecx,word [r9]
	or eax,20h
	or ecx,20h
	cmp eax,ecx
	jne .next
	add r8,2
	add r9,2
	jmp .prefix
.next:
	inc ebx
	jmp .argument
.value:
	xor edx,edx
	xor r8d,r8d
	mov r10d,-1
.digit:
	movzx eax,word [r9]
	test eax,eax
	jz .number
	sub eax,'0'
	cmp eax,9
	ja .invalid
	imul rdx,rdx,10
	add rdx,rax
	cmp rdx,r10
	ja .invalid
	inc r8d
	add r9,2
	jmp .digit
.number:
	test r8d,r8d
	jz .invalid
	mov eax,1
	ret
.absent:
	xor eax,eax
	ret
.invalid:
	mov eax,-1
	ret
endp
section '.data$options' data readable writeable align 8
option_arguments dq 0
option_count dd 0
