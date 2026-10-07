; What the command line asks for.
;
;	command_option	name (UTF-16)	nonzero if it is one of the arguments
;
; An argument is the whole of what stands between two spaces: --no-wait does
; not ask for --no.
section '.text$options' code readable executable align 16

proc command_option uses rbx rsi rdi,name
	mov rdi,rcx
	fastcall GetCommandLineW
	mov rsi,rax
	test rax,rax
	jz .absent
	mov ebx,' '			; what came before: the line begins as if after a space
.at:
	movzx eax,word [rsi]
	test eax,eax
	jz .absent
	cmp ebx,' '
	je .here
	cmp ebx,9
	je .here
	cmp ebx,'"'
	jne .next
.here:
	xor ecx,ecx
.letter:
	movzx edx,word [rdi+rcx*2]
	movzx eax,word [rsi+rcx*2]
	test edx,edx
	jz .ended
	cmp eax,edx
	jne .next
	inc ecx
	jmp .letter
.ended:
	; The name is all there: is the argument over too?
	test eax,eax
	jz .found
	cmp eax,' '
	je .found
	cmp eax,9
	je .found
	cmp eax,'"'
	je .found
.next:
	movzx ebx,word [rsi]
	add rsi,2
	jmp .at
.found:
	mov eax,1
	ret
.absent:
	xor eax,eax
	ret
endp

; (Kept for the programs that ask before they look: there is nothing to read
; ahead of time and nothing to give back.)
proc read_options
	fastcall GetCommandLineW
	ret
endp
proc free_options
	ret
endp
