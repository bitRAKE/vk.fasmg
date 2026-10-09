if ~ definite NEWCOFF_INC
NEWCOFF_INC := 1

use AMD64

; Declare the primary output before a source creates named virtual sidecars.
format binary as 'obj'
format MS64 NEWCOFF

; The project's macro/struct.inc, found beside this file ahead of fasm2's.
; It comes first so that its guard settles which struct.inc a source gets.
include 'macro/struct.inc'

include 'macro/proc64.inc'

PAGE_SIZE := 1000h
TeStackLimit := 0010h

; RSP already names the desired frame. Touch each lower stack page so a
; large allocation cannot skip Windows' guard page. RAX and flags are scratch;
; the four Win64 ABI parameter registers remain intact.
macro __chkstk
	local try,lower
	mov rax,[gs:TeStackLimit]
	jmp try
lower:
	sub rax,PAGE_SIZE
	cmp byte [rax],0
try:
	cmp rsp,rax
	jc lower
end macro

; Reuse the toolkit frame calculation and saves, then probe before any
; initialized local or procedure body can touch a distant stack address.
macro probed_static_rsp_prologue procname,flag,parmbytes,localbytes,reglist
	static_rsp_prologue procname,flag,parmbytes,localbytes,<reglist>
	if framebytes@proc > PAGE_SIZE
		__chkstk
	end if
end macro

prologue@proc equ probed_static_rsp_prologue
epilogue@proc equ static_rsp_epilogue
close@proc equ static_rsp_close

end if
