; Assembled to build\myhits_tables_alt.bin: the game's tables with a few
; things changed, for the scripted run to take in place of its own and be
; held to (claim 32). Its names are the game's, so the game takes it.
;
;	the first squad is five, not three, and comes a tick sooner: which
;	is, in the script's fourth game, the very tick these tables are taken in
;	there is a squad more, after the first: so one table is longer
;	the shot's sound is twice as long: so the sounds come to more, and
;	the music begins further into the bank
;
; (A macro that is defined again may call what it was: that is all this is.)
include '..\..\..\common\shared.inc'
include 'build\myhits_art.inc'
include '..\..\tables.inc'

macro squad gap*,what*,many*,rest&
	if table.waves = 0
		squad 119.0/120.0,what,5,rest
	else if table.waves = 1
		; (Late enough to be no part of what the script looks at.)
		squad 6.0,SWOOPER,2,0.35,700,-180
		squad gap,what,many,rest
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
