; The words a game's tables are written in: what there is, and how it behaves.
; Variety is cheap here: a new kind is a few lines, and none of them is shader
; code. A game's own tables.inc includes this and writes its tables with it.
;
;	mover NAME, FRAME, scale, flags, health, worth
;						a kind of body (KIND_NAME), its picture,
;						the hits it takes and what it scores
;		chain count, KIND, KIND, spacing	it is a head: so many of the first kind follow
;						it and one of the second, so far apart
;		move seconds, CURVE, ACTION, a, b, TARGET
;		fire KIND, degrees		ask for one of these, sent at the player, or within so many degrees of that;
;						with its mark locked, sent at the mark instead
;		again count			go back that many moves
;		blast reach			end here, in a burst that hurts what is within reach
;		wounded share			from here on is what it does once its health is down to
;						that share: whatever move it was in, it leaves
;	end mover				and coast from there on
;
; A move lasts `seconds`, eased by EASE_<CURVE>, and does MOVE_<ACTION>; what
; `a`, `b` and TARGET_<TARGET> mean to each action is beside MOVE_ in
; shared.inc. A move of no seconds happens at once, and the next follows in
; the same tick.
;
;	spray NAME, color from, to, size from, to, CURVE, seconds, more, speed, more, degrees, drag, gravity, pull, cap
;						a style of particle (STYLE_NAME); see Style
;
;	tone NAME, seconds, WAVE, hertz from, to, CURVE, attack, FALL, noise, gain
;						a sound (SOUND_NAME); see Recipe
;	stem NAME, WAVE, gain, FALL		one voice of the music; then
;		notes n, n, ...			thirty-two of them, a rest being 0
;	squad after, KIND, count, apart, y, spread, pace, pace after, holds
;						what comes, and when; see Wave. Times in seconds
;	say NAME, 'text'			something to be said on the screen (SAY_NAME): capitals,
;						digits, and - + / . : ! '; see letters.slang
;
; A program includes this and, in a data section, lays the tables down:
;
;	table_moves:
;		game_tables
;	table_kinds:
;		kinds_table
;	table_styles:
;		game_styles
;	table_sounds:
;		game_sounds
;	table_waves:
;		game_waves
;	table_stems:
;		game_music
;	table_says:
;		game_says
;
; The game's tables.asm assembles the same lines into build\myhits_tables.slang,
; which gives the shaders the KIND_ numbers.
;
; Laid down between `table_image` and `end table_image`, the tables are an
; image: a few numbers that say what follows (TableImage), and then the
; tables, in the order above, which is the order Tables has them in. An image
; can be assembled into a program, or to a file, and a program that is
; running can take one in place of the one it has (reload.inc):
;
;	table_image moves, kinds, styles, sounds, waves, stems, says
;						how many lines of each; none for a table it has not
;		...
;	end table_image
;
; What may differ between the image a program was built with and one it takes
; is every number, every program of moves and every squad. What may not is
; what the shaders know by name: the kinds, styles, sounds, stems and things
; said, in their order. The image's print is made of those names and of the
; sizes of the lines, and a program takes no image whose print is not its own.
TABLE_MAGIC := 'TBLS'
TABLE_SORTS := 7
TableImage := 0				; (so that what follows is found from inside a procedure)
TableImage.magic := 0
TableImage.print := 4
TableImage.bytes := 8			; of the tables, which follow at once
TableImage.samples := 12		; what the sounds come to in the bank
TableImage.counts := 16			; lines of each table, in order
TableImage.spare := 44
sizeof.TableImage := 48

table.print = 2166136261
; A name the shaders know goes into the print.
macro table_name text*
	table.print = ((table.print xor ((text) mod 4294967291)) * 16777619) and 0FFFFFFFFh
end macro
macro table_image counts*&
	dd TABLE_MAGIC,TABLE_PRINT,TABLE_IMAGE_BYTES,TABLE_SAMPLES
	dd counts
	dd 0
	table.image = $
end macro
macro end?.table_image!
	TABLE_IMAGE_BYTES := $ - table.image
	TABLE_SAMPLES := table.samples
	; And the lines' sizes, and what a second and a step of the music are.
	iterate size, sizeof.Move,sizeof.Kind,sizeof.Style,sizeof.Recipe,sizeof.Wave,sizeof.Stem,sizeof.Say,TICK_RATE,SOUND_RATE,MUSIC_STEPS,MUSIC_STEP_SAMPLES
		table.print = ((table.print xor (size)) * 16777619) and 0FFFFFFFFh
	end iterate
	TABLE_PRINT := table.print
end macro

macro table_line text&
	if definite TABLE_HEADER
		db text,13,10
	end if
end macro
macro table_data values&
	if ~ definite TABLE_HEADER
		dd values
	end if
end macro

table.kinds = 0			; kind 0 is nothing: an empty slot
table.moves = 0

; (Parameters are named so that none is part of a dotted name used below; and
; the macros so that none is a word other sources begin a line with: kind is
; a field of half the structures in the tree.)
macro mover name*,art*,size:1.0,bits:0,toughness:0,prize:0
	table.kinds = table.kinds + 1
	repeat 1, n:table.kinds
		KIND_#name := n
		table.first_#n := table.moves
		table.picture_#n := art
		table.scale_#n := 1.0*(size)
		table.flags_#n := bits
		table.health_#n := 1.0*(toughness)
		table.worth_#n := prize
		table.links_#n = 0
		table.link_kind_#n = 0
		table.tail_kind_#n = 0
		table.spacing_#n = 0.0
		table.wounded_first_#n = 0
		table.wounded_#n = 0.0
		table_name `name
		table_line 'static const uint KIND_',`name,' = ',`n,';'
	end repeat
end macro
macro end?.mover!
	move 0,LINEAR,HOLD
end macro
macro move seconds*,curve*,action*,a:0,b:0,target:HEADING
	table_data MOVE_#action,EASE_#curve,trunc ((seconds)*TICK_RATE+0.5),TARGET_#target,1.0*(a),1.0*(b)
	table.moves = table.moves + 1
end macro
; Inside a mover: it is the head of a chain.
macro chain many*,body_kind*,last_kind*,apart*
	repeat 1, n:table.kinds
		table.links_#n = many
		table.link_kind_#n = KIND_#body_kind
		table.tail_kind_#n = KIND_#last_kind
		table.spacing_#n = 1.0*(apart)
		; A tail must find its place in the ring before the head writes over it.
		assert (many)*(apart) <= (TRAIL_POINTS-32)*TRAIL_STEP
	end repeat
end macro
macro fire what*,fan:0
	table_data MOVE_FIRE,EASE_LINEAR,0,KIND_#what,1.0*(fan),0.0
	table.moves = table.moves + 1
end macro
macro again back*
	table_data MOVE_AGAIN,EASE_LINEAR,0,back,0.0,0.0
	table.moves = table.moves + 1
end macro
macro blast reach*
	table_data MOVE_DIE,EASE_LINEAR,0,TARGET_HEADING,1.0*(reach),0.0
	table.moves = table.moves + 1
end macro
; Inside a mover: what it had been doing ends here, and what follows is for
; when it is hurt down to `share` of its health.
macro wounded share*
	move 0,LINEAR,HOLD
	repeat 1, n:table.kinds
		table.wounded_first_#n = table.moves
		table.wounded_#n = (share)*table.health_#n
	end repeat
end macro

macro kinds_table
	table_data 0,0,0.0,0,0.0,0,0,0,0,0.0,0,0.0
	repeat table.kinds, n:1
		table_data table.first_#n,table.picture_#n,table.scale_#n,table.flags_#n,table.health_#n,table.worth_#n, \
			table.links_#n,table.link_kind_#n,table.tail_kind_#n,table.spacing_#n,table.wounded_first_#n,table.wounded_#n
	end repeat
	TABLE_KINDS := table.kinds + 1
	TABLE_MOVES := table.moves
	; (The shaders are told how many kinds there are, which their names
	; settle, and not how many moves: that is the image's to say.)
	repeat 1, kinds:table.kinds+1
		table_line 'static const uint TABLE_KINDS = ',`kinds,';'
	end repeat
end macro

table.styles = 0
macro spray name*,tint_from*,tint_to*,wide_from*,wide_to*,curve*,seconds*,more_seconds*,pace*,more_pace*,degrees*,slowing*,falling*,drawn*,limit*
	repeat 1, n:table.styles
		STYLE_#name := n
		table_name `name
		table_line 'static const uint STYLE_',`name,' = ',`n,';'
	end repeat
	table_data tint_from,tint_to,1.0*(wide_from),1.0*(wide_to),EASE_#curve,trunc ((seconds)*TICK_RATE+0.5),trunc ((more_seconds)*TICK_RATE+0.5), \
		1.0*(pace),1.0*(more_pace),(degrees)*3.14159265/180.0,1.0*(slowing),1.0*(falling),1.0*(drawn),limit
	table.styles = table.styles + 1
	assert table.styles <= STYLE_LIMIT
end macro

table.sounds = 0
table.samples = 0
macro tone name*,seconds*,shape*,pitch_from*,pitch_to*,curve*,rise*,fall*,hiss*,loud*
	repeat 1, n:table.sounds
		SOUND_#name := n
		table_name `name
		table_line 'static const uint SOUND_',`name,' = ',`n,';'
	end repeat
	table_data trunc ((seconds)*SOUND_RATE+0.5),table.samples,WAVE_#shape,EASE_#curve,1.0*(pitch_from),1.0*(pitch_to),1.0*(rise),EASE_#fall,1.0*(hiss),1.0*(loud)
	table.samples = table.samples + trunc ((seconds)*SOUND_RATE+0.5)
	table.sounds = table.sounds + 1
	assert table.sounds <= SOUND_KINDS
end macro

table.stems = 0
macro stem name*,shape*,loud*,fall*
	repeat 1, n:table.stems
		STEM_#name := n
		table_name `name
		table_line 'static const uint STEM_',`name,' = ',`n,';'
	end repeat
	table_data WAVE_#shape,1.0*(loud),EASE_#fall
	table.stems = table.stems + 1
end macro
macro notes list*&
	table.noted = 0
	iterate note, list
		table_data note
		table.noted = table.noted + 1
	end iterate
	assert table.noted = MUSIC_STEPS
end macro

table.says = 0
macro say name*,text*
	local start,size
	repeat 1, n:table.says
		SAY_#name := n
		table_name `name
		table_line 'static const uint SAY_',`name,' = ',`n,';'
	end repeat
	if ~ definite TABLE_HEADER
		start = $
		db text
		size = $ - start
		assert size <= SAY_LETTERS
		db SAY_LETTERS - size dup 0
		dd size
	end if
	table.says = table.says + 1
end macro

table.waves = 0
macro squad gap*,what*,many*,apart*,high*,down*,share:-1.0,share_gap:0,waits:0
	table_data trunc ((gap)*TICK_RATE+0.5),KIND_#what,many,trunc ((apart)*TICK_RATE+0.5),1.0*(high),1.0*(down),1.0*(share),trunc ((share_gap)*TICK_RATE+0.5),waits
	table.waves = table.waves + 1
end macro
