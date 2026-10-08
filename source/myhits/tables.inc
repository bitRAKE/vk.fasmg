; myhits' tables: every kind of thing in it and how it goes, its particles,
; its sounds, its music, and what comes when. The words are in
; ..\common\tables.inc.
include '..\common\tables.inc'

SHOT_TICKS := 6			; between the player's shots while fire is held
HEAVY_REACH := 140		; how far a heavy shot's burst reaches: its crosshairs are drawn this wide
table_line '// Written by source\myhits\tables.asm from tables.inc. Do not edit.'
table_line 'static const uint SHOT_TICKS = 6;'
table_line 'static const float HEAVY_REACH = 140.0;'

; How every bonus goes.
macro bonus_drift
	move 0,LINEAR,THRUST,150
	move 0.45,OUT_SINE,ALONG,0,22
	move 0.9,INOUT_SINE,ALONG,0,-44
	move 0.9,INOUT_SINE,ALONG,0,44
	again 2
end macro

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
	mover DIVER,FRAME_BEAST_HEAD,1.2,KIND_FACES_LEFT,6,400
		move 0,LINEAR,THRUST,240
		move 1.1,LINEAR,HOLD
		move 0.25,OUT_QUAD,THRUST,0
		move 0.45,OUT_BACK,FACE,0,0,PLAYER
		move 0.5,IN_EXPO,THRUST,1300
	; Hurt past half and left alive, it throws its hail-mary. It stops and
	; fixes on the ship: the fix is seen, shaking, closing in. The fix locks,
	; and is seen to. It looses one heavy shot at where the lock is, which is
	; no longer where the ship need be; and the shot throws it back the way
	; the shot did not go. Killing it before it fires does not stop the shot:
	; it looses it as it dies, at where the fix then is. The answer is to move.
	wounded 0.5
		move 0.3,OUT_QUAD,THRUST,0
		move 1.1,IN_QUAD,MARK,0,0,PLAYER
		move 0.3,LINEAR,HOLD
		fire HEAVY
		move 0,LINEAR,THRUST,-560
		move 2.5,OUT_QUAD,THRUST,-160
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

	; The worm: a head, eight bodies and a tail. It comes on, turns back on
	; itself one way and then the other, for as long as it lives. Kill the
	; head and the rest goes with it, segment after segment.
	mover WORM,FRAME_WORM_HEAD,1.5,KIND_FACES_LEFT,10,2000
		chain 9,WORM_BODY,WORM_TAIL,112
		move 0,LINEAR,THRUST,300
		move 1.6,LINEAR,HOLD
		move 2.4,INOUT_SINE,TURN,-200
		move 0.8,LINEAR,HOLD
		move 2.4,INOUT_SINE,TURN,200
		again 4
	end mover
	mover WORM_BODY,FRAME_WORM_BODY,1.5,KIND_FACES_LEFT or KIND_FOLLOWS,6,100
	end mover
	mover WORM_TAIL,FRAME_WORM_TAIL,1.5,KIND_FACES_LEFT or KIND_FOLLOWS,6,100
	end mover
	; Sits on the level and fires at the player.
	mover TURRET,FRAME_CORE,1.4,KIND_RIDES,8,800
		move 0.8,LINEAR,HOLD
		fire PELLET
		again 2
	end mover
	; What hostiles fire.
	mover PELLET,FRAME_NOVA,0.45
		move 0,LINEAR,THRUST,520
	end mover

	; The dragon: a boss. It comes in, and then goes round and round on the
	; right, a head chasing its own tail, loosing three shots at the player
	; each half of the way round. The level waits for it. Kill the head.
	mover DRAGON,FRAME_BEAST_HEAD,2.4,KIND_FACES_LEFT or KIND_KEEPS_UP,45,5000
		chain 12,DRAGON_BODY,DRAGON_TAIL,104
		move 0,LINEAR,THRUST,260
		move 2.4,LINEAR,HOLD
		move 2.0,INOUT_SINE,TURN,180
		fire PELLET,34
		fire PELLET,34
		fire PELLET,34
		move 0.6,LINEAR,HOLD
		again 5
	end mover
	mover DRAGON_BODY,FRAME_LARVA_BODY,1.7,KIND_FACES_LEFT or KIND_FOLLOWS,10,150
	end mover
	mover DRAGON_TAIL,FRAME_WORM_TAIL,1.7,KIND_FACES_LEFT or KIND_FOLLOWS,10,150
	end mover

	; The bonuses, in the order the game and the HUD know them by. Each comes
	; drifting back toward the player, bobbing, until it is taken or gone.
	; (Spelled out: a name joined by an iterate would reach `mover` unjoined.)
	mover BONUS_RAPID,FRAME_BONUS_RAPID,1.3,KIND_PICKUP
		bonus_drift
	end mover
	mover BONUS_SPREAD,FRAME_BONUS_SPREAD,1.3,KIND_PICKUP
		bonus_drift
	end mover
	mover BONUS_SHIELD,FRAME_BONUS_SHIELD,1.3,KIND_PICKUP
		bonus_drift
	end mover
	mover BONUS_NOVA,FRAME_BONUS_NOVA,1.3,KIND_PICKUP
		bonus_drift
	end mover
	mover BONUS_DOUBLE,FRAME_BONUS_DOUBLE,1.3,KIND_PICKUP
		bonus_drift
	end mover

	; What a hail-mary looses: slow away, to give whoever it is meant for
	; time, and gathering speed, to where the lock was. There it bursts, and
	; what is within its reach is hurt.
	mover HEAVY,FRAME_NOVA,1.5,KIND_LOBBED
		move 1.5,IN_QUAD,TO,0,0,MARK
		blast HEAVY_REACH
	end mover
end macro

; What comes, in order, and then again from the top.
macro game_waves
	squad 1.0,SWOOPER,3,0.35,260,180,1.0
	squad 4.0,WEAVER,4,0.5,200,210
	squad 4.5,WORM,1,0,420,0
	; Two turrets ride in; two seconds on, the level stops for them.
	squad 7.0,TURRET,2,0.6,330,400,0.0,2.0
	; And moves on when the divers come.
	squad 6.0,DIVER,3,0.6,240,260,1.0
	; Then the dragon. Three seconds after it shows, the level stops, and
	; nothing more comes until it is dead; the table begins again from there.
	squad 6.0,DRAGON,1,0,540,0,0.0,3.0,1
	TABLE_WAVES := table.waves
end macro

macro game_styles
	; What a shot throws back off what it strikes.
	spray SPARK,0ffc0f0ffh,0002040ffh,14,3,OUT_QUAD,0.18,0.12,180,420,70,3.0,0,0,96
	; What is left of something that died.
	spray BURST,0ff80d0ffh,0000828ffh,34,6,OUT_CUBIC,0.45,0.45,60,520,180,2.2,0,0,128
	; What something on its last legs leaves behind it.
	spray EMBER,0ff40a0ffh,0000410ffh,12,3,OUT_QUAD,0.5,0.3,20,70,180,1.0,0,0,16
	; A heavy shot's burst.
	spray BLAST,0ffa0e0ffh,0000820ffh,64,10,OUT_CUBIC,0.6,0.5,80,900,180,2.0,0,0,192
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
	tone BONUS,0.28,TRIANGLE,520,1560,OUT_QUAD,0.004,IN_QUAD,0.0,0.5
	tone BLOCK,0.22,SQUARE,240,720,OUT_CUBIC,0.002,OUT_QUAD,0.35,0.4
	; The dash; a launch or a dash there was no charge for; a shot that passed close.
	tone DASH,0.16,SAW,700,180,OUT_QUAD,0.002,OUT_CUBIC,0.75,0.4
	tone EMPTY,0.06,SQUARE,140,90,OUT_QUAD,0.001,OUT_QUAD,0.2,0.3
	tone GRAZE,0.05,SINE,2400,3200,OUT_QUAD,0.001,OUT_QUAD,0.1,0.22
	; The hail-mary: something fixes on the ship; the fix locks; the shot; its burst.
	tone FOCUS,0.5,SQUARE,620,930,INOUT_SINE,0.01,IN_QUAD,0.1,0.3
	tone LOCK,0.14,SQUARE,1250,1250,OUT_QUAD,0.001,OUT_QUAD,0.0,0.4
	tone HEAVY,0.5,SAW,110,55,OUT_CUBIC,0.004,OUT_QUAD,0.5,0.7
	tone BLAST,0.9,SINE,120,28,OUT_CUBIC,0.003,OUT_QUAD,0.9,0.9
	TABLE_SOUNDS := table.sounds
	BANK_SAMPLES := table.samples
	repeat 1, sounds:table.sounds
		table_line 'static const uint TABLE_SOUNDS = ',`sounds,';'
	end repeat
end macro

; The music: two bars in C minor, three voices. The bass is always there; the
; drums come in as the playfield fills, and the lead over them.
macro game_music
	stem BASS,TRIANGLE,0.55,IN_QUAD
		notes 36,0,0,36,0,0,36,0, 36,0,0,36,0,0,43,0, 34,0,0,34,0,0,34,0, 31,0,0,31,0,0,38,0
	stem DRUMS,DRUM,0.5,OUT_CUBIC
		notes 1,0,3,0, 2,0,3,0, 1,0,3,3, 2,0,3,0, 1,0,3,0, 2,0,3,0, 1,1,3,0, 2,0,3,3
	stem LEAD,SQUARE,0.2,OUT_QUAD
		notes 72,75,79,84, 79,75,72,75, 79,84,87,84, 79,75,72,0, 70,74,77,82, 77,74,70,74, 67,71,74,79, 74,71,67,0
	TABLE_STEMS := table.stems
	repeat 1, stems:table.stems
		table_line 'static const uint TABLE_STEMS = ',`stems,';'
	end repeat
end macro

; What is said on the screen. A pause says what the keys do, since the window
; has no caption to say it; a run that is over says how to begin another.
macro game_says
	; (They are set in type by the system, from UTF-8: any script will do, and
	; a glyph from a font of colors keeps its colors. At most SAY_LETTERS bytes.)
	say PAUSED,'PAUSED'
	say PAUSE_KEYS,'P RESUMES · F11 WHOLE MONITOR · ESC ENDS'
	say PAUSE_WINDOW,'HOLD AND DRAG TO MOVE THE WINDOW · ITS EDGES SIZE IT'
	say PAUSE_PLAY,'MOVE: ARROWS · FIRE: SPACE · MISSILES: SHIFT · DASH: CTRL'
	say OVER,'💥 THE RUN IS OVER'
	say OVER_KEYS,'ENTER BEGINS ANOTHER'
	; A game that is watching its tables' file says what became of a change.
	say TABLES_TAKEN,'✅ TABLES TAKEN'
	say TABLES_REFUSED,'⛔ TABLES REFUSED: THEY WANT A BUILD'
	TABLE_SAYS := table.says
	repeat 1, says:table.says
		table_line 'static const uint TABLE_SAYS = ',`says,';'
	end repeat
end macro
