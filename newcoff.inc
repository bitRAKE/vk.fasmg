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
prologue@proc equ static_rsp_prologue
epilogue@proc equ static_rsp_epilogue
close@proc equ static_rsp_close

end if
