; Text in the middle of a call: `fastcall f,'text'` and `fastcall f,<W,'text'>`
; put the text with the program's other strings, once however often it is
; written, and pass where it is. Bytes by default, for Vulkan; <W,...> for
; the UTF-16 Windows wants.
GLOBSTR.reuse := 1
GLOBWSTR.reuse := 1
include 'macro/globwstr.inc'
include 'macro/globstr.inc'
include 'encoding/utf8.inc'

macro fastcall?.inline_string var
	local text
	match =A =, value,var
		text GLOBSTR value,0
	else match =W =, value,var
		text GLOBWSTR value,0
	else
		text GLOBSTR var,0
	end match
	redefine var text
	; An argument that goes on the stack must be seen as memory too: proc64
	; may still think of the literal as a number.
	x86.parse_operand@src [text]
end macro

postpone
	section '.rdata$strings' data readable align 2
	GLOBWSTR.here
	GLOBSTR.here
end postpone
