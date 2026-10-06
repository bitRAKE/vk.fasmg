; Pool inline fastcall strings away from the instruction stream.
; Vulkan and byte-oriented helpers use UTF-8 by default; <W,...> selects UTF-16.
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
	; Stack arguments also need the new address classified as memory. proc64's
	; previous operand state can still describe the literal as an immediate.
	x86.parse_operand@src [text]
end macro

postpone
	section '.rdata$strings' data readable align 2
	GLOBWSTR.here
	GLOBSTR.here
end postpone
