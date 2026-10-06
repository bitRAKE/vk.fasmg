; Minimal stdout support for the loader examples, without a C runtime.
include 'newcoff.inc'

public console_initialize
public console_write_string
public console_write_line

extrn GetStdHandle:qword
extrn WriteFile:qword

STD_OUTPUT_HANDLE := -11

section '.text$loader_console' code readable executable align 16

proc console_initialize
	fastcall GetStdHandle,STD_OUTPUT_HANDLE
	mov [console_output],rax
	ret
endp

proc console_write_string uses rbx rsi, text
	mov [text],rcx
	mov rsi,rcx
	xor ebx,ebx
measure_string:
	cmp byte [rsi+rbx],0
	je write_string
	inc ebx
	jmp measure_string
write_string:
	test ebx,ebx
	jz string_done
	mov rax,[console_output]
	test rax,rax
	jz string_done
	cmp rax,-1
	je string_done
	fastcall WriteFile,rax,[text],rbx,addr console_written,0
string_done:
	ret
endp

proc console_write_line text
	mov [text],rcx
	fastcall console_write_string,[text]
	fastcall console_write_string,console_newline
	ret
endp

section '.bss$loader_console' readable writeable align 8

console_output dq ?
console_written dd ?

section '.rdata$loader_console' data readable align 2

console_newline db 13,10,0
