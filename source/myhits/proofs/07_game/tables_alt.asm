; Assembled to build\myhits_tables_alt.bin: the game's tables with two things
; changed, for the scripted run to take in place of its own and be held to
; (claim 32). Its names are the game's, so the game takes it.
;
;	the first squad is five, not three
;	the shot's sound is twice as long: so the sounds come to more, and
;	the music begins further into the bank
;
; (A macro that is defined again may call what it was: that is all this is.)
include '..\..\..\common\shared.inc'
include 'build\myhits_art.inc'
include '..\..\tables.inc'

macro squad gap*,what*,many*,rest&
	if table.waves = 0
		squad gap,what,5,rest
	else
		squad gap,what,many,rest
	end if
end macro
macro tone name*,seconds*,rest&
	match =SHOT, name
		tone name,(seconds)*2,rest
	else
		tone name,seconds,rest
	end match
end macro

include '..\..\tables_image.inc'
