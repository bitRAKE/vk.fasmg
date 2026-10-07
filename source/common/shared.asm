; Assembles to the shader header itself:
;
;	fasm2 source\common\shared.asm build\myhits_shared.slang
;
; The output is text: the boundary blocks and constants of shared.inc as Slang.
SHADER_HEADER := 1
include 'shared.inc'
