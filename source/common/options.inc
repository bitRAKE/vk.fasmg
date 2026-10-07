; What the command line asks for.
;
;	command_option	name (UTF-16)	nonzero if it is one of the arguments
;	command_value	name, place, room
;					the argument after it, if it is one of the
;					arguments and what follows is not another
;					option (begins with no dash): copied to
;					`place` with its end, `room` characters at
;					most. How many characters, or none
;
; An argument is the whole of what stands between two spaces: --no-wait does
; not ask for --no. A value may be in quotes, and then may have spaces in it.
section '.text$options' code readable executable align 16

; Where on the command line the argument `name` ends, or nothing.
proc option_after uses rbx rsi rdi,name
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
	lea rax,[rsi+rcx*2]
	ret
.absent:
	xor eax,eax
	ret
endp

proc command_option name
	fastcall option_after,rcx
	test rax,rax
	setnz al
	movzx eax,al
	ret
endp

proc command_value uses rbx rsi rdi,name,place,room
	mov rdi,rdx
	mov ebx,r8d
	fastcall option_after,rcx
	test rax,rax
	jz .none
	mov rsi,rax
	; (A quote that closed the name's own argument; then the gap.)
	cmp word [rsi],'"'
	jne .gap
	add rsi,2
.gap:
	movzx eax,word [rsi]
	cmp eax,' '
	je .wider
	cmp eax,9
	jne .begins
.wider:
	add rsi,2
	jmp .gap
.begins:
	test eax,eax
	jz .none
	cmp eax,'-'
	je .none
	mov edx,' '			; what ends it: a space, or the quote it opened with
	cmp eax,'"'
	jne .copy
	mov edx,'"'
	add rsi,2
.copy:
	xor ecx,ecx
.character:
	movzx eax,word [rsi+rcx*2]
	test eax,eax
	jz .copied
	cmp eax,edx
	je .copied
	cmp edx,' '
	jne .kept
	cmp eax,9
	je .copied
.kept:
	lea r8d,[ecx+1]
	cmp r8d,ebx
	jae .none			; too long to be kept whole is not a value
	mov [rdi+rcx*2],ax
	inc ecx
	jmp .character
.copied:
	mov word [rdi+rcx*2],0
	mov eax,ecx
	ret
.none:
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
