; The game's tables: what there is, and how it behaves. Variety is cheap here:
; a new kind is a few lines, and none of them is shader code.
;
;	mover NAME, FRAME, scale, flags, health, worth
;						a kind of body (KIND_NAME), its picture,
;						the hits it takes and what it scores
;		move seconds, CURVE, ACTION, a, b, TARGET
;		again count			go back that many moves
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
	table_data 0,0,0.0,0,0.0,0
	repeat table.kinds, n:1
		table_data table.first_#n,table.picture_#n,table.scale_#n,table.flags_#n,table.health_#n,table.worth_#n
	end repeat
	TABLE_KINDS := table.kinds + 1
	TABLE_MOVES := table.moves
	repeat 1, kinds:table.kinds+1, moves:table.moves
		table_line 'static const uint TABLE_KINDS = ',`kinds,';'
		table_line 'static const uint TABLE_MOVES = ',`moves,';'
	end repeat
end macro

table.styles = 0
macro spray name*,tint_from*,tint_to*,wide_from*,wide_to*,curve*,seconds*,more_seconds*,pace*,more_pace*,degrees*,slowing*,falling*,drawn*,limit*
	repeat 1, n:table.styles
		STYLE_#name := n
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
		table_line 'static const uint SOUND_',`name,' = ',`n,';'
	end repeat
	table_data trunc ((seconds)*SOUND_RATE+0.5),table.samples,WAVE_#shape,EASE_#curve,1.0*(pitch_from),1.0*(pitch_to),1.0*(rise),EASE_#fall,1.0*(hiss),1.0*(loud)
	table.samples = table.samples + trunc ((seconds)*SOUND_RATE+0.5)
	table.sounds = table.sounds + 1
	assert table.sounds <= SOUND_KINDS
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
	mover ANCHOR,FRAME_CORE,1.6,KIND_RIDES,12,1000
	end mover
	; Flies in, loops the loop, and leaves faster than it came.
	mover SWOOPER,FRAME_MANTIS_HEAD,1.2,KIND_FACES_LEFT,2,200
		move 0,LINEAR,THRUST,420
		move 0.9,LINEAR,HOLD
		move 1.3,INOUT_SINE,TURN,360
		move 0.6,IN_QUAD,THRUST,760
	end mover
	; Weaves from side to side as it comes.
	mover WEAVER,FRAME_WOLF_HEAD,1.2,KIND_FACES_LEFT,3,300
		move 0,LINEAR,THRUST,280
		move 0.35,OUT_SINE,ALONG,0,90
		move 0.7,INOUT_SINE,ALONG,0,-180
		move 0.7,INOUT_SINE,ALONG,0,180
		again 2
	end mover
	; Drifts in, rears back to look at the player, and dives.
	mover DIVER,FRAME_BEAST_HEAD,1.2,KIND_FACES_LEFT,4,400
		move 0,LINEAR,THRUST,240
		move 1.1,LINEAR,HOLD
		move 0.25,OUT_QUAD,THRUST,0
		move 0.45,OUT_BACK,FACE,0,0,PLAYER
		move 0.5,IN_EXPO,THRUST,1300
	end mover

	; For proof 05. A ring nothing can break: something to shoot at.
	mover TARGET,FRAME_SHIELD,1.5,0,1000000000
	end mover
	; Stands its ground and takes three hits.
	mover DRONE,FRAME_SKULL_HEAD,1.2,KIND_FACES_LEFT,3,150
	end mover
	; Comes straight on, fast.
	mover RAMMER,FRAME_LARVA_HEAD,1.2,KIND_FACES_LEFT,2,100
		move 0,LINEAR,THRUST,1800
	end mover
	; A shot too fast to ever land inside a thin wall.
	mover LANCE,FRAME_BOLT,2.0
		move 0,LINEAR,THRUST,6000
	end mover
end macro

macro game_styles
	; What a shot throws back off what it strikes.
	spray SPARK,0ffc0f0ffh,0002040ffh,14,3,OUT_QUAD,0.18,0.12,180,420,70,3.0,0,0,96
	; What is left of something that died.
	spray BURST,0ff80d0ffh,0000828ffh,34,6,OUT_CUBIC,0.45,0.45,60,520,180,2.2,0,0,128
	TABLE_STYLES := table.styles
	repeat 1, styles:table.styles
		table_line 'static const uint TABLE_STYLES = ',`styles,';'
	end repeat
end macro

macro game_sounds
	; In the order the passes know them by.
	tone SHOT,0.11,SQUARE,1400,500,OUT_QUAD,0.002,OUT_CUBIC,0.15,0.35
	tone LAUNCH,0.45,SAW,180,900,IN_CUBIC,0.03,IN_QUAD,0.25,0.45
	tone HIT,0.07,SINE,900,300,OUT_QUAD,0.001,OUT_QUAD,0.6,0.5
	tone BURST,0.6,SINE,220,40,OUT_CUBIC,0.004,OUT_QUAD,0.85,0.8
	tone HURT,0.4,SAW,300,90,INOUT_SINE,0.005,IN_QUAD,0.3,0.6
	TABLE_SOUNDS := table.sounds
	BANK_SAMPLES := table.samples
	repeat 1, sounds:table.sounds, samples:table.samples
		table_line 'static const uint TABLE_SOUNDS = ',`sounds,';'
		table_line 'static const uint BANK_SAMPLES = ',`samples,';'
	end repeat
end macro
