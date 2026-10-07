; The blocks that cross between the CPU and the shaders, defined once.
;
; A `boundary` gives the assembly its offsets (Name.member, sizeof.Name).
; Assembled through shared.asm, the same lines write the Slang header the
; shaders include, so the two sides cannot disagree. Layout is scalar: a
; member sits at the next multiple of its own scalar size, which is what
; slangc is told with -fvk-use-scalar-layout. Anything misaligned stops here.

macro shader_line text&
	if definite SHADER_HEADER
		db text,13,10
	end if
end macro

macro shared? name*,value*
	name := value
	repeat 1, decimal:value
		shader_line 'static const uint ',`name,' = ',`decimal,';'
	end repeat
end macro

define boundary.current
macro boundary? name*
	; The name itself must be a defined symbol, or its members cannot be found
	; from inside a procedure's namespace.
	name := 0
	redefine boundary.current name
	boundary.offset = 0
	boundary.alignment = 4
	shader_line 'struct ',`name
	shader_line '{'
end macro

macro end?.boundary?!
	assert boundary.offset mod boundary.alignment = 0
	match name, boundary.current
		sizeof.name := boundary.offset
	end match
	shader_line '};'
end macro

; One member: `count` items of `bytes` each, aligned to `unit`. (A parameter
; must not share a name with any part of a dotted symbol used here.)
macro boundary.place field*,bytes*,unit*,count*,type&
	assert boundary.offset mod unit = 0
	if unit > boundary.alignment
		boundary.alignment = unit
	end if
	match name, boundary.current
		name.field := boundary.offset
	end match
	; Each line carries its offset, so a check can hold the compiler to it.
	repeat 1, at:boundary.offset, decimal:count
		if count = 1
			shader_line '    ',type,' ',`field,';',9,'// ',`at
		else
			shader_line '    ',type,' ',`field,'[',`decimal,'];',9,'// ',`at
		end if
	end repeat
	boundary.offset = boundary.offset + bytes * count
end macro

macro u32? field*,count:1
	boundary.place field,4,4,count,'uint'
end macro
macro i32? field*,count:1
	boundary.place field,4,4,count,'int'
end macro
macro f32? field*,count:1
	boundary.place field,4,4,count,'float'
end macro
macro f32x2? field*,count:1
	boundary.place field,8,4,count,'float2'
end macro
; A GPU address. The pointee is the shaders' business.
macro ptr? field*,type*
	boundary.place field,8,8,1,`type,'*'
end macro
; `count` of an earlier boundary.
macro block? field*,type*,count:1
	boundary.place field,sizeof.type,4,count,`type
end macro

shader_line '// Written by source\common\shared.asm from shared.inc. Do not edit.'

shared PLAYFIELD_WIDTH,1920
shared PLAYFIELD_HEIGHT,1080
shared SOUND_KINDS,32
shared EVENT_SLOTS,4			; a power of two
; The simulation steps this many times a second, whatever the display's rate.
shared TICK_RATE,120
shader_line 'static const float TICK_SECONDS = 1.0 / float(TICK_RATE);'

; The sounds a pass may ask for are SOUND_ in tables.inc: each is a Trigger of
; Events.sound and a Recipe the device renders into the bank, at this rate.
shared SOUND_RATE,48000
shared WAVE_SINE,0
shared WAVE_SQUARE,1
shared WAVE_SAW,2
shared WAVE_TRIANGLE,3
shared WAVE_DRUM,4			; a stem's only: its notes are 1 a thump, 2 a crack, 3 a tick
; The music is stems of this many steps, each this many samples: two bars of
; sixteenths at 120 to the minute. A beat is four steps.
shared MUSIC_STEPS,32
shared MUSIC_STEP_SAMPLES,6000
shared MUSIC_SAMPLES,192000
; Root.held and Root.pressed
shared BUTTON_FIRE,1
shared BUTTON_SECOND,2
shared BUTTON_START,4
shared BUTTON_THIRD,8
; Root.flags
shared ROOT_PAUSED,1
shared ROOT_SCRIPTED,2
shared ROOT_RELOADED,4			; the tables were laid down again before this frame: what ran by the old ones goes
shared ROOT_REFUSED,8			; tables were offered that this program cannot take: it says so
shared ROOT_GHOST,16			; nothing hurts: for looking at what a program does without having to survive it

; CPU to GPU, every frame, as push constants.
boundary Root
	ptr world,World			; everything else is reached from here
	ptr events,Events		; this frame's slot
	f32 time			; seconds of simulation the picture shows
	f32 blend			; where it stands between the last two ticks: 1 is the last
	u32 frame
	u32 ticks			; how many ticks this frame runs; often 0 or 2
	f32x2 view			; the playfield's size on screen, in pixels
	f32x2 move			; -1..1
	f32x2 aim			; the crosshair, in playfield units
	u32 held
	u32 pressed			; went down this frame
	f32 beat			; music phase 0..1
	u32 flags
end boundary
assert sizeof.Root <= 128		; the push-constant size every device has

; A sound trigger is a count and a sum of positions, not a queue entry.
boundary Trigger
	u32 count
	i32 pan				; sum of playfield x offsets from the center
end boundary

; GPU to CPU, every frame, read once the frame has retired.
boundary Events
	u32 frame			; echo of Root.frame
	u32 state
	u32 score
	u32 wave
	u32 lives
	u32 multiplier
	f32 rank
	f32 shield
	f32 intensity			; drives the music mix
	f32 rumble_low
	f32 rumble_high
	u32 flags
	u32 debug,4
	block sound,Trigger,SOUND_KINDS
	u32 reserved,16
	u32 report,32			; what a program's last pass tells its checks
end boundary
assert sizeof.Events = 512

; One frame: a run of texels and a mask of the solid ones. With FRAME_LIGHT a
; plane of normals follows the texels. The packer writes the table; the device
; makes its own copy, with what it found in place of what it was told.
shared FRAME_LIGHT,1			; lit from one side however it turns
shared FRAME_GLOW,2			; light: its halo adds to what is behind it
shared FRAME_SYMMETRIC,4		; the same mirrored left to right
shared RECIPE_BAKED,0			; cut from a sheet and packed
shared RECIPE_MADE,1			; computed on the device
shared RECIPE_DRAWN,2			; rasterized on the device from strokes
boundary Picture			; (Frame is taken: proc64's frame)
	u32 texels			; its first, among all texels
	u32 mask			; its first word, among all masks; a row is (width + 31) / 32 words
	u32 width
	u32 height
	u32 flags
	u32 recipe
	u32 argument			; made: the generator. drawn: first stroke, and the count << 16
	u32 solid			; texels its mask holds
	u32 checksum
end boundary

; A capsule from `start` to `finish`; a disc when they meet. `outline` is half
; the width of its edge, or zero when it is filled. Texels from the top left.
boundary Stroke
	f32x2 start
	f32x2 finish
	f32 radius
	f32 outline
	u32 color
end boundary

; What the device found when it made the pictures.
boundary Census
	u32 baked			; frames from the packer
	u32 baked_wrong			; whose solid count or checksum is not the packer's
	u32 baked_solid
	u32 made			; frames made or drawn on the device
	u32 made_wrong			; empty, or drawn with another area than its strokes have
	u32 made_solid
	u32 lopsided			; mask bits of symmetric frames that differ from their mirror
	u32 pad
end boundary

; Where the pictures are. A program's World begins with this, written once.
boundary Pictures
	ptr frames,Picture
	ptr texels,uint
	ptr masks,uint
	ptr census,Census
	ptr packed_frames,Picture		; these three are the packer's, in host-visible
	ptr packed_texels,uint		; memory: read while the pictures are made and
	ptr strokes,Stroke		; never after
	u32 count			; frames
	u32 baked_texels
	u32 texel_count
	u32 mask_words
end boundary

; The easing curves: one library for motion, the HUD's pops, particle sizes,
; the level's own pace. LINEAR, then IN, OUT and INOUT of each family.
shared EASE_LINEAR,0
; (A name joined with # reaches a macro unjoined, so these are spelled here.)
macro shared_curve form*,family*,value*
	EASE_#form#_#family := value
	repeat 1, decimal:value
		shader_line 'static const uint EASE_',`form,'_',`family,' = ',`decimal,';'
	end repeat
end macro
iterate family, QUAD,CUBIC,QUART,QUINT,SINE,EXPO,CIRC,BACK,ELASTIC,BOUNCE
	shared_curve IN,family,%*3-2
	shared_curve OUT,family,%*3-1
	shared_curve INOUT,family,%*3
end iterate
shared EASE_CURVES,31

; What a move does, over its ticks and along its curve. A body always coasts
; along its heading at its speed; a move changes something on top of that.
shared MOVE_HOLD,0			; nothing; with no ticks, for good: how a program ends
shared MOVE_OFFSET,1			; slide by (a, b) on the playfield
shared MOVE_ALONG,2			; slide a ahead and b to its right
shared MOVE_TO,3			; slide to its target, plus (a, b)
shared MOVE_FACE,4			; turn to face its target
shared MOVE_TURN,5			; turn by a degrees
shared MOVE_THRUST,6			; bring its speed to a
shared MOVE_AGAIN,7			; go back `target` moves
shared MOVE_DIE,8			; and with `a`, burst: what is within `a` of it is hurt
shared MOVE_FIRE,9			; ask the director for a body of kind `target`, sent at the player, within `a` degrees;
					; or, by a body whose mark is locked, sent at its mark, which the new body takes
shared MOVE_MARK,10			; fix on its target: its mark follows the target and it turns to face it;
					; when the move is over the mark is locked where it stands
; What a move aims at.
shared TARGET_HEADING,0			; straight ahead
shared TARGET_PLAYER,1
shared TARGET_CROSSHAIR,2
shared TARGET_MARK,3			; its own mark
; A body's mark: a point it means to strike, and shows.
shared MARK_FOCUS,1			; being fixed: it follows its target still
shared MARK_LOCKED,2			; fixed
boundary Move
	u32 action
	u32 curve
	u32 ticks			; none: at once, and the next move follows in the same tick
	u32 target
	f32 a
	f32 b				; mirrored for a body whose seed is odd
end boundary

shared KIND_FACES_LEFT,1		; its picture looks left; its heading is where it looks
shared KIND_RIDES,2			; it belongs to the level, and is carried at its pace
shared KIND_FOLLOWS,4			; a segment: it goes where its head went (chains.slang)
shared KIND_PICKUP,8			; a bonus: nothing hits it, and the ship takes it by touch
shared KIND_KEEPS_UP,16			; going the other way it is mirrored, not turned on its head
shared KIND_LOBBED,32			; a shot thrown over the field: it touches nothing on its way
boundary Kind
	u32 first			; its first move
	u32 picture			; FRAME_
	f32 scale
	u32 flags
	f32 health			; hits it takes; none: nothing can hit it
	u32 worth			; what it scores
	u32 links			; segments that follow one of these; none for most
	u32 link_kind			; what they are,
	u32 tail_kind			; what the last of them is,
	f32 link_spacing		; and how far apart along the head's path
	u32 wounded_first		; the first move of what it does once it is hurt enough; none: nothing else
	f32 wounded			; and how little health that is
end boundary

; What comes, and when: so long after the squad before, so many of a kind,
; each so long after the last and so far below it; and the share of its full
; pace the level eases to, so long after they begin (less than none: as it was).
boundary Wave
	u32 after
	u32 kind
	u32 count
	u32 stagger
	f32 y
	f32 spread
	f32 pace
	u32 pace_after
	u32 holds			; nothing more comes until none of these is left: a boss
end boundary

; A head lays a point of its path every so many units, into a ring of this many.
shared TRAIL_STEP,8
shared TRAIL_POINTS,256

; A style of particle: how one looks and goes, from birth to death.
boundary Style
	u32 color_from			; R G B A, as a texel; A is how bright
	u32 color_to
	f32 size_from			; across, in playfield units
	f32 size_to
	u32 size_curve			; EASE_
	u32 life			; ticks
	u32 life_spread			; and up to this many more
	f32 speed			; at birth, units a second
	f32 speed_spread		; and up to this much more
	f32 spread			; radians either side of where it is thrown; pi: all round
	f32 drag			; the share of its speed lost in a second
	f32 gravity			; units a second, each second, down
	f32 pull			; the same, toward the player
	u32 cap				; the most admitted in one tick
end boundary
shared STYLE_LIMIT,16
; What the device keeps of these two is the shaders' business; the assembly
; only needs their sizes: Body in motion.slang, Particle in particles.slang.
shared BODY_BYTES,100
shared PARTICLE_BYTES,32
shared REQUEST_BYTES,32			; Request in myhits.slang: what a FIRE asks the director for

; The game's tables, authored in tables.inc. A program's World holds this.
; A sound, as a recipe: a wave whose pitch sweeps from one to another along a
; curve, risen in `attack` seconds and fallen away along another, with a share
; of noise. The device renders every recipe once, into one run of samples.
boundary Recipe
	u32 samples			; its length
	u32 first			; where it begins in the bank
	u32 wave			; WAVE_
	u32 pitch_curve			; EASE_
	f32 pitch_from			; hertz
	f32 pitch_to
	f32 attack			; seconds
	u32 fall_curve			; EASE_: how its level goes from all to nothing
	f32 noise			; its share, 0..1
	f32 gain
end boundary

; One voice of the music: a wave, how loud, how each note falls away, and a
; note for every step, as its number on a keyboard (69 is the A above middle
; C) or nothing for a rest. Rendered after the sounds, into the same bank.
boundary Stem
	u32 wave
	f32 gain
	u32 fall_curve
	u32 notes,32
end boundary

; Something said on the screen: its letters, four to a word, and how many.
shared SAY_LETTERS,64
boundary Say
	u32 letters,16
	u32 count
end boundary

boundary Tables
	ptr moves,Move
	ptr kinds,Kind
	ptr styles,Style
	ptr sounds,Recipe
	ptr waves,Wave
	ptr stems,Stem
	ptr says,Say
	u32 move_count
	u32 kind_count
	u32 style_count
	u32 sound_count
	u32 wave_count
	u32 stem_count
	u32 say_count
	u32 sound_samples		; what the sounds come to in the bank: the stems begin there
end boundary
