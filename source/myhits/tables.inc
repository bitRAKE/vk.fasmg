; The game's tables: what there is, and how it behaves. Variety is cheap here:
; a new kind is a few lines, and none of them is shader code.
;
;	mover NAME, FRAME, scale, flags		a kind of body (KIND_NAME), and its picture
;		move seconds, CURVE, ACTION, a, b, TARGET
;		again count			go back that many moves
;	end mover				and coast from there on
;
; A move lasts `seconds`, eased by EASE_<CURVE>, and does MOVE_<ACTION>; what
; `a`, `b` and TARGET_<TARGET> mean to each action is beside MOVE_ in
; shared.inc. A move of no seconds happens at once, and the next follows in
; the same tick.
;
; A program includes this and, in a data section, lays the tables down:
;
;	table_moves:
;		game_tables
;	table_kinds:
;		kinds_table
;
; tables.asm assembles the same lines into build\myhits_tables.slang, which
; gives the shaders the KIND_ numbers.

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
macro mover name*,art*,size:1.0,bits:0
	table.kinds = table.kinds + 1
	repeat 1, n:table.kinds
		KIND_#name := n
		table.first_#n := table.moves
		table.picture_#n := art
		table.scale_#n := 1.0*(size)
		table.flags_#n := bits
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
macro again back*
	table_data MOVE_AGAIN,EASE_LINEAR,0,back,0.0,0.0
	table.moves = table.moves + 1
end macro

macro kinds_table
	table_data 0,0,0.0,0
	repeat table.kinds, n:1
		table_data table.first_#n,table.picture_#n,table.scale_#n,table.flags_#n
	end repeat
	TABLE_KINDS := table.kinds + 1
	TABLE_MOVES := table.moves
	repeat 1, kinds:table.kinds+1, moves:table.moves
		table_line 'static const uint TABLE_KINDS = ',`kinds,';'
		table_line 'static const uint TABLE_MOVES = ',`moves,';'
	end repeat
end macro

SHOT_TICKS := 6			; between the player's shots while fire is held
table_line '// Written by source\myhits\tables.asm from tables.inc. Do not edit.'
table_line 'static const uint SHOT_TICKS = 6;'

macro game_tables
	; The player's shot: at speed from the first tick.
	mover SHOT,FRAME_BOLT,1.5
		move 0,LINEAR,THRUST,1800
	end mover
	; The missile is the model for all of this: it drifts out to a strike
	; position, settles its aim on the crosshair, and goes.
	mover MISSILE,FRAME_PLASMA,1.2
		move 0.35,OUT_CUBIC,OFFSET,40,-60
		move 0.15,INOUT_SINE,FACE,0,0,CROSSHAIR
		move 0.50,IN_EXPO,THRUST,2400
	end mover
	; Something that belongs to the level: it holds its ground, and the ground moves.
	mover ANCHOR,FRAME_CORE,1.6,KIND_RIDES
	end mover
	; Flies in, loops the loop, and leaves faster than it came.
	mover SWOOPER,FRAME_MANTIS_HEAD,1.2,KIND_FACES_LEFT
		move 0,LINEAR,THRUST,420
		move 0.9,LINEAR,HOLD
		move 1.3,INOUT_SINE,TURN,360
		move 0.6,IN_QUAD,THRUST,760
	end mover
	; Weaves from side to side as it comes.
	mover WEAVER,FRAME_WOLF_HEAD,1.2,KIND_FACES_LEFT
		move 0,LINEAR,THRUST,280
		move 0.35,OUT_SINE,ALONG,0,90
		move 0.7,INOUT_SINE,ALONG,0,-180
		move 0.7,INOUT_SINE,ALONG,0,180
		again 2
	end mover
	; Drifts in, rears back to look at the player, and dives.
	mover DIVER,FRAME_BEAST_HEAD,1.2,KIND_FACES_LEFT
		move 0,LINEAR,THRUST,240
		move 1.1,LINEAR,HOLD
		move 0.25,OUT_QUAD,THRUST,0
		move 0.45,OUT_BACK,FACE,0,0,PLAYER
		move 0.5,IN_EXPO,THRUST,1300
	end mover
end macro
