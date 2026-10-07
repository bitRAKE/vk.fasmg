; Whole files, in and out, by name: what a tool needs of a file and no more.
;
;	file_stamp	name (UTF-16)		when the file was last written, or 0 if there is none
;	file_take	name, place, room	the whole of it into memory: how many bytes, or 0
;						if there is none, or more than room, or not all of it came
;	file_put	name, place, bytes	the whole of it from memory, in place of what was
;						there: nonzero if all of it went
;	file_more	place, bytes		more, to the file file_put left open when it was
;						asked for none: nonzero if all of it went
;	file_done				and that file closed: nonzero if it closed
;
; A program includes this after machine.inc. A file that could not be written
; is the program's to answer for: these only say so.
iterate function, GetFileAttributesExW,ReadFile,GetFileSizeEx
	extrn function:qword
end iterate

section '.text$files' code readable executable align 16

proc file_stamp name
	fastcall GetFileAttributesExW,rcx,0,addr file_attributes
	test eax,eax
	jz .none
	mov rax,qword [file_attributes+20]	; ftLastWriteTime
	ret
.none:
	xor eax,eax
	ret
endp

; (A file someone is still writing may not open, or may come short: both are
; nothing. And it is opened so as to be in nobody's way: whoever writes the
; file may write it, or put another in its place, while it is being read.)
proc file_take uses rbx rsi rdi,name,place,room
	mov rsi,rdx
	mov edi,r8d
	fastcall CreateFileW,rcx,GENERIC_READ,FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE,0,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .none
	mov rbx,rax
	fastcall GetFileSizeEx,rbx,addr file_size
	test eax,eax
	jz .close
	mov rax,[file_size]
	test rax,rax
	jz .close
	cmp rax,rdi
	ja .close
	mov edi,eax
	fastcall ReadFile,rbx,rsi,rdi,addr file_moved,0
	test eax,eax
	jz .close
	cmp [file_moved],edi
	jne .close
	fastcall CloseHandle,rbx
	mov eax,edi
	ret
.close:
	fastcall CloseHandle,rbx
.none:
	xor eax,eax
	ret
endp

; With bytes it is all of the file, and the file is closed. With none, the
; file is left open for file_more to fill, and file_done closes it: for a
; file made of more than one piece of memory.
proc file_put uses rbx rsi,name,place,bytes
	mov rsi,rdx
	mov ebx,r8d
	fastcall CreateFileW,rcx,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .none
	mov [file_open],rax
	mov eax,1
	test ebx,ebx
	jz .done
	fastcall file_more,rsi,rbx
	mov ebx,eax
	fastcall file_done
	and eax,ebx
.done:
	ret
.none:
	mov [file_open],0
	xor eax,eax
	ret
endp

; (WriteFile may take less than it is given.)
proc file_more uses rbx rsi,place,bytes
	mov rsi,rcx
	mov ebx,edx
	cmp [file_open],0
	je .failed
.more:
	test ebx,ebx
	jz .all
	fastcall WriteFile,[file_open],rsi,rbx,addr file_moved,0
	test eax,eax
	jz .failed
	mov eax,[file_moved]
	test eax,eax
	jz .failed
	add rsi,rax
	sub ebx,eax
	jmp .more
.all:
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc file_done
	xor eax,eax
	cmp [file_open],0
	je .done
	fastcall CloseHandle,[file_open]
	mov [file_open],0
	test eax,eax
	setnz al
	movzx eax,al
.done:
	ret
endp

section '.data$files' data readable writeable align 8
file_open dq 0
file_size dq 0
file_moved dd 0
file_attributes rb 36			; WIN32_FILE_ATTRIBUTE_DATA
