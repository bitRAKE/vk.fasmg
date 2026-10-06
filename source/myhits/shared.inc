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

shader_line '// Written by source\myhits\shared.asm from shared.inc. Do not edit.'

shared PLAYFIELD_WIDTH,1920
shared PLAYFIELD_HEIGHT,1080
shared SOUND_KINDS,48
shared EVENT_SLOTS,4			; a power of two

; Root.held and Root.pressed
shared BUTTON_FIRE,1
shared BUTTON_SECOND,2
shared BUTTON_START,4
; Root.flags
shared ROOT_PAUSED,1
shared ROOT_SCRIPTED,2

; CPU to GPU, every frame, as push constants.
boundary Root
	ptr world,World			; everything else is reached from here
	ptr events,Events		; this frame's slot
	f32 time			; seconds
	f32 dt				; clamped; fixed in scripted runs
	u32 frame
	u32 seed
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
