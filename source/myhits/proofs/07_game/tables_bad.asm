; Assembled to build\myhits_tables_bad.bin: the game's tables with a kind the
; game was not built with. It is a whole image and a well-made one, but its
; names are not the game's, and the scripted run is to see it refused (claim
; 32): a shader that knows a kind by its number would be wrong about every
; number after the stranger's.
include '..\..\..\common\shared.inc'
include 'build\myhits_art.inc'
include '..\..\tables.inc'

macro game_tables
	mover STRANGER,FRAME_NOVA
	end mover
	game_tables
end macro

include '..\..\tables_image.inc'
