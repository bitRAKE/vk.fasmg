; myhits: a horizontal shooter whose world lives on the GPU. The CPU reads the
; controls, sends 72 bytes a frame, reads 512 back, and plays the sounds they
; ask for. Everything else is in myhits.slang and the tables.
;
;	build\myhits.exe		play: arrows or WASD or a pad move, Space or the
;					left button fires, Shift or the right button
;					launches a pair of missiles at the crosshair
;					for a quarter of the charge, Ctrl or the
;					middle button dashes for a fifth of it, Enter
;					begins again when a run is over; P pauses, F11
;					or Alt+Enter takes or gives back the whole
;					monitor, Esc ends
;	build\myhits.exe --windowed	the same, as a window whatever it was last
;	build\myhits.exe --fullscreen	the same, over the whole monitor whatever it was last
;	build\myhits.exe --self-test	a scripted run of three games, every claim checked
;
; Its window has no caption. While it plays the pointer is the crosshair and
; cannot leave; paused, or left for another program (which pauses it), the
; pointer is free and the window moves by a press and hold anywhere on it.
; The first time it has the whole of its monitor; after that it is as it was
; left, which the registry keeps.
;
; What the scripted run holds the game to is in proofs\README.md, under 07.
MACHINE_NAME equ 'myhits'
MACHINE_TAG equ 'game'
MACHINE_SNAPSHOT := 1
MACHINE_BARE := 1
include '..\common\machine.inc'
include '..\common\pictures.inc'
include 'tables.inc'
include '..\common\audio.inc'

; These are myhits.slang's.
BODIES := 1024
SHOTS := 256
PELLETS := 384
HOSTILES := 384
PARTICLES := 16384
TRAILS := 32
REQUESTS := HOSTILES * 6			; a hostile's own cells to ask the director from
INSTANCES := 160 + BODIES + 16 + PELLETS + HOSTILES + 21 + 8 + 5 * 9
GAME_BYTES := 512
POOL_BYTES := 8 + STYLE_LIMIT * 4
WORLD_BYTES := GAME_BYTES + POOL_BYTES + 2 * BODIES * BODY_BYTES + BODIES * 4 + (TRAILS + 1) * TRAIL_POINTS * 8 + REQUESTS * REQUEST_BYTES + HOSTILES / 8 + PARTICLES * PARTICLE_BYTES
TICK_DISPATCHES := 5			; the director, the bodies, the shots, the struck, the particles
; What the measuring run tells apart: the five passes of a tick, the report,
; and the four draws.
iterate name, DIRECT,UPDATE,COLLIDE,RESOLVE,DRIFT,REPORT,BACKDROP,SCENE,PARTICLES,VEIL
	STAMP_#name := %
end iterate
STARTUP_DISPATCHES := PICTURES_PASSES + 3	; and the settling, the sounds, the beginning
GAME_TICKS := 8				; a scripted frame of the game runs this many: it has far to go
SCRIPT_FRAMES := 1250
RESTART_FRAME := 400			; the script presses Enter here; the first game is over by then
STAGE_FRAME := 1000			; and here: the second is over, and the third is on a bare stage
assert STAGE_FRAME = 1000		; the script's frames of the third are written out from it too
PAUSED_FRAME := 950			; and this frame's picture is a paused one's
assert RESTART_FRAME = 400		; the script's later frames are written out from it
public mainCRTStartup

; The world's header, which the CPU writes once: World in myhits.slang.
boundary GameWorld
	block pictures,Pictures
	block tables,Tables
	ptr bodies,Body
	ptr game,Game
	ptr damage,uint
	ptr particles,Particle
	ptr pool,ParticlePool
	ptr trails,float2
	ptr queue,Request
	ptr bank,float
	ptr ship_trail,float2
	u32 capacity
	u32 particle_capacity
	ptr staged,uint			; this header and the tables, where the CPU wrote them,
	ptr home,uint			; and where the device keeps them
	u32 words
	u32 spare
	ptr asking,uint
end boundary

section '.text$game' code readable executable align 16

; The first failed check, by number, and the frame (ESI) it failed in.
proc record_failure check
	cmp [proof_failure],0
	jne .already
	mov [proof_failure],ecx
	mov [proof_failure_frame],esi
.already:
	mov [app_io_failed],1
	ret
endp
macro fail check*
	fastcall record_failure,check
end macro
; Leave to `target` unless the float at `place` is within `slack` of the one at `value`.
macro unless_near place*,value*,slack*,target*
	movss xmm0,place
	subss xmm0,[value]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[slack]
	ja target
end macro
; At frame `when`, leave to `target` unless the count at `offset` of the events (RBX) is `value`.
macro at_frame when*,offset*,value*,target*
	local later
	cmp esi,when
	jne later
	cmp dword [rbx+offset],value
	jne target
later:
end macro

proc create_world uses rsi rdi
	mov [failure_stage],3
	; Only shaders touch the world: device-local memory, reached by address.
	require_ok fastcall create_buffer,addr world_buffer,WORLD_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_DEVICE
	; The CPU writes the header and the tables once, into memory it can see;
	; the device's first pass copies them to memory of its own, and that is
	; where every pass after reads them.
	require_ok fastcall create_buffer,addr header_buffer,HOME_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_UPLOAD
	require_ok fastcall create_buffer,addr home_buffer,HOME_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_DEVICE
	; And the device writes the sounds once where the CPU, and so the voices, can read them.
	require_ok fastcall create_buffer,addr bank_buffer,BANK_TOTAL*4,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_READBACK
	mov rdi,[header_buffer.mapped]
	require_ok fastcall pictures_create,rdi
	mov rax,[header_buffer.address]
	mov [rdi+GameWorld.staged],rax
	mov rax,[home_buffer.address]
	mov [rdi+GameWorld.home],rax
	mov dword [rdi+GameWorld.words],HOME_BYTES/4
	; The tables are found where the device will keep them.
	add rax,sizeof.GameWorld
	iterate <table,count,size>, moves,TABLE_MOVES,sizeof.Move, kinds,TABLE_KINDS,sizeof.Kind, styles,TABLE_STYLES,sizeof.Style, sounds,TABLE_SOUNDS,sizeof.Recipe, waves,TABLE_WAVES,sizeof.Wave, stems,TABLE_STEMS,sizeof.Stem
		mov [rdi+GameWorld.tables+Tables.table],rax
		add rax,(count)*(size)
	end iterate
	mov dword [rdi+GameWorld.tables+Tables.move_count],TABLE_MOVES
	mov dword [rdi+GameWorld.tables+Tables.kind_count],TABLE_KINDS
	mov dword [rdi+GameWorld.tables+Tables.style_count],TABLE_STYLES
	mov dword [rdi+GameWorld.tables+Tables.sound_count],TABLE_SOUNDS
	mov dword [rdi+GameWorld.tables+Tables.wave_count],TABLE_WAVES
	mov dword [rdi+GameWorld.tables+Tables.stem_count],TABLE_STEMS
	mov rax,[world_buffer.address]
	iterate <pool,bytes>, game,GAME_BYTES, pool,POOL_BYTES, bodies,2*BODIES*BODY_BYTES, damage,BODIES*4, trails,TRAILS*TRAIL_POINTS*8, ship_trail,TRAIL_POINTS*8, queue,REQUESTS*REQUEST_BYTES, asking,HOSTILES/8, particles,PARTICLES*PARTICLE_BYTES
		mov [rdi+GameWorld.pool],rax
		add rax,bytes
	end iterate
	mov rax,[bank_buffer.address]
	mov [rdi+GameWorld.bank],rax
	mov dword [rdi+GameWorld.capacity],BODIES
	mov dword [rdi+GameWorld.particle_capacity],PARTICLES
	add rdi,sizeof.GameWorld
	lea rsi,[table_moves]
	mov ecx,TABLE_BYTES
	rep movsb
	require_ok fastcall flush_buffer,addr header_buffer
	mov rax,[header_buffer.address]
	mov [root+Root.world],rax
	require_ok fastcall machine_compute,addr settle_code,settle_code.size,addr settle_pipeline
	require_ok fastcall machine_serial_open
	fastcall machine_dispatch,[settle_pipeline],(HOME_BYTES/4+63)/64
	require_ok fastcall machine_serial_close
	mov rax,[home_buffer.address]
	mov [root+Root.world],rax
	iterate name, begin,direct,update,collide,resolve,drift,report,render
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	require_ok fastcall machine_graphics,addr scene_vertex_code,scene_vertex_code.size,addr scene_fragment_code,scene_fragment_code.size,BLEND_PREMULTIPLIED,addr scene_pipeline
	require_ok fastcall machine_graphics,addr particle_vertex_code,particle_vertex_code.size,addr particle_fragment_code,particle_fragment_code.size,BLEND_PREMULTIPLIED,addr particle_pipeline
	require_ok fastcall machine_graphics,addr veil_vertex_code,veil_vertex_code.size,addr veil_fragment_code,veil_fragment_code.size,BLEND_PREMULTIPLIED,addr veil_pipeline
	require_ok fastcall machine_graphics,addr backdrop_vertex_code,backdrop_vertex_code.size,addr backdrop_fragment_code,backdrop_fragment_code.size,BLEND_OPAQUE,addr backdrop_pipeline
	require_ok fastcall pictures_develop
	require_ok fastcall machine_serial_open
	; The sounds and the music first: nothing of them is uploaded but their
	; recipes and their notes. Then the game, which listens to what was made.
	fastcall machine_dispatch,[render_pipeline],(BANK_TOTAL+63)/64
	fastcall machine_settle
	fastcall machine_dispatch,[begin_pipeline],1
	require_ok fastcall machine_serial_close
	require_ok fastcall invalidate_buffer,addr bank_buffer
	mov eax,[dispatch_count]
	mov [startup_dispatches],eax
	mov [dispatch_count],0
	mov [failure_stage],0
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc release_world
	fastcall audio_stop
	iterate name, settle,begin,direct,update,collide,resolve,drift,report,render,scene,particle,veil,backdrop
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	fastcall pictures_release
	fastcall destroy_buffer,addr bank_buffer
	fastcall destroy_buffer,addr header_buffer
	fastcall destroy_buffer,addr home_buffer
	fastcall destroy_buffer,addr world_buffer
	ret
endp

; One frame: as many ticks as real time has earned, the report, two draws.
proc play_frame uses rbx
	fastcall machine_await
	test eax,eax
	jz .stopped
	test dword [root+Root.flags],ROOT_SCRIPTED
	jz .sample
	; The script, in frames of eight ticks. The first game: up out of the way,
	; eight shots at nothing, a long wait, down to a turret's row, seven shots
	; at it; and then nothing, until it is over. The second: up to the worm's
	; row; three frames of fire with RAPID in force, and three with SPREAD
	; too; fire at the worm's head as it comes, which brings the companion;
	; then four frames to the right, for it to follow. The crosshair stays
	; where the companion's gun will be asked to point. The third, on a bare
	; stage: a pair of missiles; a dash upward, through a shot set down in its
	; way; down a little while the first diver fixes on the ship, and then
	; still, to be caught; a dash downward once the second has locked, to
	; get clear; and when the charge is nearly gone, a launch it can pay for
	; and then a launch and a dash it cannot.
	mov dword [root+Root.aim],1500.0
	mov dword [root+Root.aim+4],300.0
	mov dword [root+Root.move],0
	mov dword [root+Root.move+4],0
	mov dword [root+Root.held],0
	mov dword [root+Root.pressed],0
	mov eax,[root+Root.frame]
	iterate <from,to,way>, 0,10,-1.0, 250,255,1.0, 401,403,-1.0, 1010,1010,-1.0, 1050,1053,1.0, 1125,1125,1.0
		cmp eax,from
		jb .still_#from
		cmp eax,to
		ja .still_#from
		mov dword [root+Root.move+4],way
	.still_#from:
	end iterate
	cmp eax,570
	jb .along
	cmp eax,573
	ja .along
	mov dword [root+Root.move],1.0
.along:
	iterate <from,to>, 11,16, 290,294, 430,432, 442,444, 543,566
		cmp eax,from
		jb .quiet_#from
		cmp eax,to
		ja .quiet_#from
		mov dword [root+Root.held],BUTTON_FIRE
	.quiet_#from:
	end iterate
	; One frame is drawn as a paused one is, for its picture; the run goes on under it.
	and dword [root+Root.flags],not ROOT_PAUSED
	cmp eax,PAUSED_FRAME
	jne .unpaused
	or dword [root+Root.flags],ROOT_PAUSED
.unpaused:
	iterate <when,button>, 400,BUTTON_START, 1000,BUTTON_START, 1003,BUTTON_SECOND, 1010,BUTTON_THIRD, \
		1125,BUTTON_THIRD, 1200,BUTTON_SECOND, 1206,BUTTON_SECOND, 1212,BUTTON_THIRD
		cmp eax,when
		jne .unpressed_#when
		mov dword [root+Root.pressed],button
	.unpressed_#when:
	end iterate
.sample:
	fastcall machine_sample
	; The beat goes down with the controls: how lately the music struck one,
	; so the picture can strike with it. A scripted run hears none.
	mov dword [root+Root.beat],0
	test dword [root+Root.flags],ROOT_SCRIPTED
	jnz .open
	fastcall audio_beat
	xorps xmm1,xmm1
	ucomiss xmm0,xmm1
	jb .open
	movss xmm1,[felt_all]
	subss xmm1,xmm0
	movaps xmm0,xmm1
	mulss xmm0,xmm1
	mulss xmm0,xmm1
	movss dword [root+Root.beat],xmm0
.open:
	fastcall machine_open
	cmp eax,1
	jne .skipped
	mov ebx,[root+Root.ticks]
.tick:
	test ebx,ebx
	jz .ticked
	fastcall machine_dispatch,[direct_pipeline],1
	fastcall machine_settle
	fastcall machine_stamp,STAMP_DIRECT
	fastcall machine_dispatch,[update_pipeline],BODIES/64
	fastcall machine_settle
	fastcall machine_stamp,STAMP_UPDATE
	fastcall machine_dispatch,[collide_pipeline],(SHOTS+PELLETS)/64
	fastcall machine_settle
	fastcall machine_stamp,STAMP_COLLIDE
	fastcall machine_dispatch,[resolve_pipeline],HOSTILES/32
	fastcall machine_settle
	fastcall machine_stamp,STAMP_RESOLVE
	fastcall machine_dispatch,[drift_pipeline],PARTICLES/64
	fastcall machine_settle
	fastcall machine_stamp,STAMP_DRIFT
	dec ebx
	jmp .tick
.ticked:
	fastcall machine_dispatch,[report_pipeline],1
	fastcall machine_stamp,STAMP_REPORT
	fastcall machine_canvas
	fastcall draw_world
	; The scripted run leaves pictures of itself: the swoopers, the weavers,
	; the worm coming and turning, the turrets with the level stopped, the run
	; over; and of the second game three volleys with RAPID and SPREAD, the
	; nova going off, the shield about to take a rammer, and the worm's head
	; under fire.
	; And of the third: the dash, through a shot; a diver's fix on the ship,
	; shaking; its lock; its heavy shot on the way and the crosshairs fading;
	; the burst; the second's shot coming for where the ship no longer is; and
	; the third's, loosed as it died, coming for a ship that only killed it.
	iterate when, 37,110,165,235,300,320,395,444,468,500,555,568,596,625,900,PAUSED_FRAME, \
		1011,1056,1066,1082,1091,1136,1176
		cmp dword [root+Root.frame],when
		jne .no_#when
		fastcall snapshot_take,when
	.no_#when:
	end iterate
	fastcall machine_close
	ret
.skipped:
	; 2: no image this turn, which is not a failure.
	shr eax,1
.stopped:
	ret
endp

; Everything a frame draws: the backdrop; the sprites and the HUD among them;
; the light; then the veil a hurt or the end of a run draws over it all.
proc draw_world
	fastcall machine_draw,[backdrop_pipeline],6,1
	fastcall machine_stamp,STAMP_BACKDROP
	fastcall machine_draw,[scene_pipeline],6,INSTANCES
	fastcall machine_stamp,STAMP_SCENE
	fastcall machine_draw,[particle_pipeline],6,PARTICLES
	fastcall machine_stamp,STAMP_PARTICLES
	fastcall machine_draw,[veil_pipeline],6,1
	fastcall machine_stamp,STAMP_VEIL
	ret
endp

; A finished frame's events: its sounds to the voices, its numbers to the
; title, and in a scripted run every one of them held to the rules.
proc consume_events uses rbx rsi rdi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	fastcall audio_events,rbx,addr table_sounds,[bank_buffer.mapped]
	; And what should be felt, to the pad.
	movss xmm0,dword [rbx+Events.rumble_low]
	movss xmm1,dword [rbx+Events.rumble_high]
	cmp [paused],0
	je .felt_now
	; A hurt does not go on being felt for as long as a pause lasts.
	xorps xmm0,xmm0
	xorps xmm1,xmm1
.felt_now:
	fastcall pad_rumble
	; And how much is happening, to the music.
	movss xmm0,dword [rbx+Events.intensity]
	fastcall audio_mix
	xor edi,edi
	repeat TABLE_SOUNDS
		cmp dword [rbx+Events.sound+(%-1)*sizeof.Trigger+Trigger.count],0
		setne al
		movzx eax,al
		add edi,eax
	end repeat
	add [sounds_asked],edi
	mov eax,[rbx+Events.sound+SOUND_HURT*sizeof.Trigger+Trigger.count]
	add [heard_hurts],eax
	iterate <name,offset>, last_score,Events.score, last_lives,Events.lives, last_wave,Events.wave, last_state,Events.state, last_rank,Events.rank, \
		last_fired,Events.reserved+4, last_struck,Events.reserved+12, last_kills,Events.reserved+20, last_hurts,Events.reserved+24, last_alive,Events.reserved+28
		mov eax,[rbx+offset]
		mov [name],eax
	end iterate
	mov eax,[root+Root.frame]
	sub eax,esi
	mov [last_latency],eax
	cmp eax,[worst_latency]
	jbe .counted
	mov [worst_latency],eax
.counted:
	cmp [test_mode],0
	je .done
	; 1: events arrive once each, in frame order, in hand when the next frame begins.
	cmp esi,[events_seen]
	jne .order_wrong
	cmp [last_latency],1
	je .order
.order_wrong:
	fail 1
.order:
	; 2: what comes is what the table says, when it says: three swoopers by
	; frame 37 and nothing else; the fourth squad's turn by frame 145.
	at_frame 12,Events.reserved+28,0,.waves_wrong
	at_frame 37,Events.reserved+28,3,.waves_wrong
	at_frame 37,Events.wave,1,.waves_wrong
	at_frame 100,Events.wave,2,.waves_wrong
	at_frame 145,Events.wave,3,.waves_wrong
	jmp .waves
.waves_wrong:
	fail 2
.waves:
	; 3: every shot is accounted for, in every frame.
	mov eax,[rbx+Events.reserved+8]
	add eax,[rbx+Events.reserved+12]
	add eax,[rbx+Events.reserved+16]
	cmp eax,[rbx+Events.reserved+4]
	je .accounted
	fail 3
.accounted:
	; 4: rank reads the shooting. A second survived is a hundredth. Eight
	; shots at nothing, all escaped, take six thousandths off, twice, to
	; nothing. Shots that all struck add thirty-four thousandths. A hurt takes
	; fifteen hundredths, down to nothing.
	cmp esi,14
	jne .rank_missed
	unless_near dword [rbx+Events.rank],rank_one,rank_slack,.rank_wrong
.rank_missed:
	cmp esi,29
	jne .rank_floor
	unless_near dword [rbx+Events.rank],rank_two,rank_slack,.rank_wrong
.rank_floor:
	cmp esi,44
	jne .rank_struck
	cmp dword [rbx+Events.rank],0
	jne .rank_wrong
.rank_struck:
	mov eax,[rbx+Events.reserved+24]
	cmp eax,[hurts_before]
	jb .rank			; a new run
	jne .rank_hurt
	cmp esi,299
	jne .rank
	movss xmm0,dword [rbx+Events.rank]
	subss xmm0,[rank_before]
	subss xmm0,[rank_rise]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[rank_slack]
	ja .rank_wrong
	mov [rise_checked],1
	jmp .rank
.rank_hurt:
	; A hurt in a frame that held no look: fifteen hundredths, or all there was.
	mov eax,esi
	xor edx,edx
	mov ecx,15
	div ecx
	cmp edx,14
	je .rank
	movss xmm0,[rank_before]
	subss xmm0,[rank_fall]
	xorps xmm1,xmm1
	maxss xmm0,xmm1
	subss xmm0,dword [rbx+Events.rank]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[rank_slack]
	ja .rank_wrong
	inc [falls_checked]
	jmp .rank
.rank_wrong:
	fail 4
.rank:
	; 5: a chain follows its head exactly. While the worm comes straight on,
	; its first segment is one spacing behind where the head stood a tick ago,
	; on the head's own line. Once all of it is out and turning, no two
	; neighbors are farther apart than the spacing, nor nearer than a turn that
	; tight can bring them. (Not in a frame the world stood still in: the
	; head "a tick ago" is then where it is.)
	mov eax,[rbx+Events.report+4]
	cmp eax,[last_stopped]
	jne .chain
	cmp esi,150
	jb .chain
	cmp esi,163
	ja .curled
	movss xmm0,dword [rbx+Events.reserved+56]
	subss xmm0,dword [rbx+Events.reserved+48]
	subss xmm0,[spacing]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	ja .chain_wrong
	movss xmm0,dword [rbx+Events.reserved+60]
	subss xmm0,dword [rbx+Events.reserved+52]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	ja .chain_wrong
.curled:
	cmp esi,200
	jb .chain
	cmp esi,245
	ja .chain
	cmp dword [rbx+Events.debug],9
	jne .chain_wrong
	movss xmm0,dword [rbx+Events.debug+4]
	ucomiss xmm0,[spacing_least]
	jb .chain_wrong
	movss xmm0,dword [rbx+Events.debug+8]
	ucomiss xmm0,[spacing_most]
	jbe .chain
.chain_wrong:
	fail 5
.chain:
	; 6: a body cannot make a body. The first turret's FIRE is a request in
	; one tick and a pellet in the next: none by frame 258, one in frame 259.
	at_frame 258,Events.reserved+44,0,.fire_wrong
	at_frame 259,Events.reserved+44,1,.fire_wrong
	at_frame 259,Events.reserved+32,1,.fire_wrong
	jmp .fire
.fire_wrong:
	fail 6
.fire:
	; 7: a hurt costs a life, one at a time and never two within the grace;
	; with none left the run is over, and stays over until Enter.
	mov eax,[rbx+Events.reserved+24]
	mov edx,eax
	sub edx,[hurts_before]
	jz .lives
	js .lives			; a new run
	cmp edx,1
	jne .lives_wrong
	inc [hurts_total]
	mov ecx,esi
	sub ecx,[hurt_frame]
	cmp ecx,30
	jb .lives_wrong
	mov [hurt_frame],esi
.lives:
	add eax,[rbx+Events.lives]
	cmp eax,3
	jne .lives_wrong
	cmp dword [rbx+Events.lives],0
	sete al
	cmp dword [rbx+Events.state],1
	sete dl
	cmp al,dl
	jne .lives_wrong
	at_frame RESTART_FRAME-1,Events.state,1,.lives_wrong
	at_frame RESTART_FRAME+2,Events.state,0,.lives_wrong
	at_frame RESTART_FRAME+2,Events.lives,3,.lives_wrong
	at_frame RESTART_FRAME+2,Events.score,0,.lives_wrong
	jmp .lived
.lives_wrong:
	fail 7
.lived:
	; 8: the level stops for what is anchored to it, and moves on. From frame
	; 290 to 335 its pace is nothing and it has not come a bit farther; by
	; frame 352 it is at full pace again.
	cmp esi,290
	jb .pace
	cmp esi,335
	ja .moved
	cmp dword [rbx+Events.reserved+36],0
	jne .pace_wrong
	mov eax,[rbx+Events.reserved+40]
	cmp eax,[scroll_before]
	jne .pace_wrong
.moved:
	cmp esi,352
	jne .pace
	unless_near dword [rbx+Events.reserved+36],full_pace,tolerance,.pace_wrong
	jmp .pace
.pace_wrong:
	fail 8
.pace:
	; 9: kill the head and the chain goes with it. In the second game the
	; worm's head is shot as it comes; five frames after the frame it dies in,
	; ten fewer are alive than the frame before.
	cmp esi,RESTART_FRAME+140
	jb .ripple
	cmp [head_died],0
	jne .rippling
	cmp dword [rbx+Events.debug],9
	jne .dying
	mov eax,[rbx+Events.reserved+28]
	mov [alive_before],eax
	mov [chain_seen],1
	jmp .ripple
.dying:
	cmp [chain_seen],0
	je .ripple
	mov [head_died],esi
	jmp .ripple
.rippling:
	mov eax,[head_died]
	add eax,5
	cmp esi,eax
	jne .ripple
	mov eax,[alive_before]
	sub eax,10
	cmp [rbx+Events.reserved+28],eax
	jle .ripple
	fail 9
.ripple:
	; 15: a bonus is taken by coming near it, once. The second game is given
	; one of each in front of the ship: each is in hand, and only one of it, a
	; few frames after it was set down.
	at_frame 418,Events.report+16,1,.bonus_wrong
	at_frame 429,Events.report+8,1,.bonus_wrong
	at_frame 441,Events.report+12,1,.bonus_wrong
	at_frame 454,Events.report+24,1,.bonus_wrong
	at_frame 471,Events.report+20,1,.bonus_wrong
	jmp .bonus
.bonus_wrong:
	fail 15
.bonus:
	; 16: the shield takes the next hurt. It is held from frame 418; a rammer
	; comes along the ship's row; by frame 505 the shield is spent on it, and
	; no life was.
	at_frame 418,Events.report+28,1,.shield_wrong
	at_frame 505,Events.report+32,1,.shield_wrong
	at_frame 505,Events.report+28,0,.shield_wrong
	at_frame 505,Events.lives,3,.shield_wrong
	jmp .shield
.shield_wrong:
	fail 16
.shield:
	; 17: RAPID halves the wait between shots and SPREAD makes each three.
	; Three frames of fire are four shots without either; they are eight with
	; RAPID, and twenty-four with both.
	mov eax,[rbx+Events.reserved+4]
	cmp esi,429
	je .mark
	cmp esi,441
	jne .rapid
.mark:
	mov [fired_mark],eax
.rapid:
	sub eax,[fired_mark]
	cmp esi,432
	jne .spread
	cmp eax,8
	jne .rate_wrong
.spread:
	cmp esi,444
	jne .rate
	cmp eax,24
	je .rate
.rate_wrong:
	fail 17
.rate:
	; 18: a nova strikes everything at once, and DOUBLE doubles what a kill is
	; worth. In the frame the nova is taken or the next, the drone set down
	; for it dies, and whatever swoopers were left; nothing that can be hit is
	; alive after; and the score has grown by exactly twice their worth at the
	; rank of the moment.
	mov eax,[rbx+Events.report+20]
	cmp [nova_frame],0
	jne .nova_after
	test eax,eax
	jz .nova
	mov [nova_frame],esi
	mov eax,[score_before]
	mov [nova_score],eax
	mov eax,[kills_before]
	mov [nova_kills],eax
	jmp .nova
.nova_after:
	mov eax,[nova_frame]
	inc eax
	cmp esi,eax
	jne .nova
	cmp dword [rbx+Events.reserved+28],0
	jne .nova_wrong
	mov ecx,[rbx+Events.reserved+20]
	sub ecx,[nova_kills]
	jle .nova_wrong
	dec ecx					; the swoopers among them
	movss xmm1,dword [rbx+Events.rank]
	addss xmm1,[rank_unit]
	movss xmm0,[worth_swooper]
	mulss xmm0,xmm1
	addss xmm0,[rank_round]
	cvttss2si eax,xmm0
	imul eax,ecx
	movss xmm0,[worth_drone]
	mulss xmm0,xmm1
	addss xmm0,[rank_round]
	cvttss2si edx,xmm0
	add eax,edx
	shl eax,1
	mov edx,[rbx+Events.score]
	sub edx,[nova_score]
	cmp eax,edx
	je .nova
.nova_wrong:
	fail 18
.nova:
	; 19: the companion is a surprise: there is none until the worm's head is
	; killed, and two frames after that there is.
	at_frame 500,Events.report+36,0,.mate_wrong
	mov eax,[head_died]
	test eax,eax
	jz .mate_place
	add eax,2
	cmp esi,eax
	jne .mate_place
	cmp dword [rbx+Events.report+36],1
	jne .mate_wrong
.mate_place:
	; 20: it is where you were. The ship has stood still since it came up 120
	; from where the run began, so 150 back along its path is the first point
	; it laid, 8 on from there; and the companion fired when the ship did.
	; Then the ship goes 160 to the right, and 150 back along its path is 10
	; to the right of where it turned.
	cmp esi,568
	jne .mate_followed
	unless_near dword [rbx+Events.report+40],mate_x_first,mate_slack,.mate_wrong
	unless_near dword [rbx+Events.report+44],mate_y_first,mate_slack,.mate_wrong
	cmp dword [rbx+Events.report+56],0
	je .mate_wrong
.mate_followed:
	cmp esi,579
	jne .mate_own
	unless_near dword [rbx+Events.report+40],mate_x_after,mate_slack,.mate_wrong
	unless_near dword [rbx+Events.report+44],mate_y_after,mate_slack,.mate_wrong
	mov eax,[rbx+Events.reserved+12]
	mov [struck_mark],eax
.mate_own:
	; 21: then it acts for itself. Its guard turns to a shot coming at it and
	; stops it; its gun turns to what is nearest and its shots strike, while
	; the player fires nothing.
	at_frame 582,Events.report+36,2,.mate_wrong
	at_frame 600,Events.report+64,1,.mate_wrong
	cmp esi,610
	jne .mate_aimed
	cmp dword [rbx+Events.report+60],0
	je .mate_wrong
	mov eax,[rbx+Events.reserved+12]
	cmp eax,[struck_mark]
	jne .mate_wrong
.mate_aimed:
	; 22: and then its gun takes your aim: it points from where it is to the crosshair.
	at_frame 614,Events.report+36,3,.mate_wrong
	cmp esi,630
	jne .mate
	movss xmm0,[aim_y]
	subss xmm0,dword [rbx+Events.report+44]
	movss [scratch],xmm0
	movss xmm0,[aim_x]
	subss xmm0,dword [rbx+Events.report+40]
	movss [scratch+4],xmm0
	fld dword [scratch]
	fld dword [scratch+4]
	fpatan
	fstp dword [scratch]
	unless_near dword [rbx+Events.report+48],scratch,centi,.mate_wrong
	jmp .mate
.mate_wrong:
	fail 19
.mate:
	; 20: the level waits for a boss. The dragon is the sixth squad of the
	; second game. Long after it has come, it and its twelve segments are all
	; there, nothing more has come, and the level stands; the script strikes
	; its head dead, and then the chain goes, the table begins again, and the
	; level moves.
	at_frame 900,Events.wave,6,.boss_wrong
	at_frame 940,Events.wave,6,.boss_wrong
	at_frame 940,Events.reserved+36,0,.boss_wrong
	at_frame 940,Events.debug,12,.boss_wrong
	at_frame 960,Events.debug,0,.boss_wrong
	cmp esi,995
	jne .boss
	cmp dword [rbx+Events.wave],7
	jb .boss_wrong
	unless_near dword [rbx+Events.reserved+36],full_pace,tolerance,.boss_wrong
	jmp .boss
.boss_wrong:
	fail 20
.boss:
	mov eax,[rbx+Events.score]
	mov [score_before],eax
	mov eax,[rbx+Events.reserved+20]
	mov [kills_before],eax
	; 13: the score the HUD shows chases the real one and never passes it.
	mov eax,[rbx+Events.report]
	cmp eax,[rbx+Events.score]
	jbe .shown
	fail 13
.shown:
	mov [last_shown],eax
	mov eax,[rbx+Events.report+4]
	mov [last_stopped],eax
	mov eax,[rbx+Events.report+72]
	mov [last_music_faults],eax
	cmp esi,STAGE_FRAME
	jb .staged
	fastcall check_stage,rbx,rsi
.staged:
	; The sum over the world at the end of each game: the proof runner holds
	; one run's to another's.
	iterate <when,name>, 399,sum_first, 999,sum_second, 1249,sum_third
		cmp esi,when
		jne .unsummed_#when
		mov eax,[rbx+Events.debug+12]
		mov [name],eax
	.unsummed_#when:
	end iterate
	iterate <name,offset>, hurts_before,Events.reserved+24, rank_before,Events.rank, scroll_before,Events.reserved+40, \
		last_counts,Events.report+80, stage_ship_y,Events.report+92
		mov eax,[rbx+offset]
		mov [name],eax
	end iterate
.done:
	inc [events_seen]
	ret
endp

; The third game's frames: RCX a frame's events, EDX which frame.
proc check_stage uses rbx rsi rdi,events,which
	mov rbx,rcx
	mov esi,edx
	; 24: charge is earned and spent. A new game has all of it. A pair of
	; missiles costs a quarter. A dash costs a fifth, takes the ship exactly
	; 320 the way it was going, and a shot it crosses on the way passes
	; through it: nothing is lost. A shot that passes close and does not
	; strike pays three hundredths, once. A kill pays six. With a quarter
	; left a launch is paid for; with less, a launch and a dash are each
	; refused, and nothing leaves and nothing moves.
	at_frame STAGE_FRAME+2,Events.state,0,.charge_wrong
	at_frame STAGE_FRAME+2,Events.lives,3,.charge_wrong
	iterate <when,amount,fired,dashes,slipped,grazes,empties>, 2,charge_all,0,0,0,0,0, 6,charge_launched,2,0,0,0,0, 14,charge_dashed,2,1,1,0,0, \
		36,charge_grazed,2,1,1,1,0, 204,charge_last,4,2,1,1,0, 210,charge_last,4,2,1,1,1, 216,charge_last,4,2,1,1,2
		cmp esi,STAGE_FRAME+when
		jne .not_#when
		unless_near dword [rbx+Events.report+76],amount,charge_slack,.charge_wrong
		cmp dword [rbx+Events.reserved+4],fired
		jne .charge_wrong
		mov eax,[rbx+Events.report+80]
		and eax,0FFFFFFh
		cmp eax,(dashes)+((slipped) shl 8)+((grazes) shl 16)
		jne .charge_wrong
		cmp byte [rbx+Events.report+85],empties
		jne .charge_wrong
	.not_#when:
	end iterate
	iterate <when,high>, 14,dash_up, 216,dash_down
		cmp esi,STAGE_FRAME+when
		jne .elsewhere_#when
		unless_near dword [rbx+Events.report+88],ship_column,stage_slack,.charge_wrong
		unless_near dword [rbx+Events.report+92],high,stage_slack,.charge_wrong
	.elsewhere_#when:
	end iterate
	at_frame STAGE_FRAME+14,Events.lives,3,.charge_wrong
	jmp .charged
.charge_wrong:
	fail 24
.charged:
	; 25: the hail-mary. A diver hurt to half fixes on the ship, and the fix
	; is where the ship is though the ship moves. It locks where the ship
	; then was, and stays there. A heavy shot comes for the lock: its mark is
	; the lock, and fades every frame it comes nearer; what loosed it goes the
	; other way. It bursts at the lock. The first time the ship has stayed,
	; and the burst costs it a life; the second it has dashed away, and it
	; costs nothing. The third diver is struck dead while it is still fixing,
	; and that stops nothing: its shot comes as it dies, for where the fix
	; was, and the ship, which killed it and stayed, loses a life to it.
	mov edi,[rbx+Events.report+96]
	mov eax,edi
	mov ecx,[stage_phase]
	cmp ecx,1
	je .fixing
	cmp ecx,2
	je .locked
	cmp ecx,3
	je .flying
	cmp ecx,4
	je .landed
	cmp al,MARK_FOCUS
	jne .staged_done
	mov [stage_phase],1
.fixing:
	cmp al,MARK_FOCUS
	jne .fixed
	unless_near dword [rbx+Events.report+100],rbx+Events.report+88,stage_slack,.stage_wrong
	unless_near dword [rbx+Events.report+104],rbx+Events.report+92,stage_slack,.stage_wrong
	mov eax,[rbx+Events.report+92]
	cmp eax,[stage_ship_y]
	je .staged_done
	mov [stage_followed],1
	jmp .staged_done
.fixed:
	test edi,256
	jnz .fixed_alive
	; Dead while it was fixing: that is the third's part, and nobody else's.
	; Its shot is owed all the same, for where its fix was: on the ship,
	; which has not moved.
	cmp [stage_round],2
	jne .stage_wrong
	mov eax,[rbx+Events.report+88]
	mov [lock_x],eax
	mov eax,[rbx+Events.report+92]
	mov [lock_y],eax
	mov [stage_phase],2
	jmp .locked
.fixed_alive:
	cmp al,MARK_LOCKED
	jne .stage_wrong
	cmp [stage_round],2
	je .stage_wrong
	mov eax,[rbx+Events.report+100]
	mov [lock_x],eax
	mov eax,[rbx+Events.report+104]
	mov [lock_y],eax
	unless_near dword [lock_x],rbx+Events.report+88,stage_slack,.stage_wrong
	unless_near dword [lock_y],rbx+Events.report+92,stage_slack,.stage_wrong
	mov [stage_phase],2
	jmp .staged_done
.locked:
	test edi,1024
	jnz .loosed
	; (The third is dead, and between a death and its shot there is a tick.)
	cmp [stage_round],2
	je .staged_done
	test edi,256
	jz .stage_wrong
	; (Between its mark going with the shot and the shot being made there is a tick.)
	test al,al
	jz .staged_done
	unless_near dword [rbx+Events.report+100],lock_x,stage_slack,.stage_wrong
	unless_near dword [rbx+Events.report+104],lock_y,stage_slack,.stage_wrong
	jmp .staged_done
.loosed:
	mov eax,[rbx+Events.report+108]
	mov [fire_x],eax
	mov eax,[rbx+Events.report+112]
	mov [fire_y],eax
	mov eax,[rbx+Events.reserved+24]
	mov [stage_hurts],eax
	mov [fade_before],2.0
	mov [stage_recoiled],0
	mov [stage_phase],3
.flying:
	test edi,1024
	jz .burst
	unless_near dword [rbx+Events.report+100],lock_x,stage_slack,.stage_wrong
	unless_near dword [rbx+Events.report+104],lock_y,stage_slack,.stage_wrong
	movss xmm0,dword [rbx+Events.report+124]
	ucomiss xmm0,[fade_before]
	jae .stage_wrong
	movss [fade_before],xmm0
	test edi,256
	jz .staged_done
	; How far it has gone since, along the way the shot went: never forward.
	movss xmm0,dword [rbx+Events.report+108]
	subss xmm0,[fire_x]
	movss xmm1,[lock_x]
	subss xmm1,[fire_x]
	mulss xmm0,xmm1
	movss xmm2,dword [rbx+Events.report+112]
	subss xmm2,[fire_y]
	movss xmm1,[lock_y]
	subss xmm1,[fire_y]
	mulss xmm2,xmm1
	addss xmm0,xmm2
	xorps xmm1,xmm1
	ucomiss xmm0,xmm1
	ja .stage_wrong
	jae .staged_done
	mov [stage_recoiled],1
	jmp .staged_done
.burst:
	movzx eax,byte [rbx+Events.report+83]
	mov ecx,[stage_round]
	inc ecx
	cmp eax,ecx
	jne .stage_wrong
	unless_near dword [rbx+Events.report+116],lock_x,stage_near,.stage_wrong
	unless_near dword [rbx+Events.report+120],lock_y,stage_near,.stage_wrong
	movss xmm0,[fade_before]
	ucomiss xmm0,[stage_little]
	ja .stage_wrong
	; What loosed it was seen to go the other way, if it lived to.
	cmp [stage_round],2
	je .burst_seen
	cmp [stage_recoiled],1
	jne .stage_wrong
.burst_seen:
	mov [stage_phase],4
	jmp .staged_done
.landed:
	; The first caught the ship, which had stayed. The second did not: the
	; ship had gone. The third caught it: killing was all the ship had done.
	mov ecx,[stage_round]
	lea rdx,[stage_caught]
	movzx eax,byte [rdx+rcx]
	cmp byte [rbx+Events.report+84],al
	jne .stage_wrong
	mov eax,[rbx+Events.reserved+24]
	sub eax,[stage_hurts]
	lea rdx,[stage_cost]
	movzx ecx,byte [rdx+rcx]
	cmp eax,ecx
	jne .stage_wrong
	inc [stage_round]
	mov [stage_phase],0
	jmp .staged_done
.stage_wrong:
	fail 25
.staged_done:
	; 27: nothing alive is written over. A worm's head is struck dead and
	; something else set down in its slot the tick after: the nine segments
	; die of it all the same. Then a flood: of four hundred hostile shots
	; 384 are made and sixteen refused; of four hundred drones as many are
	; made as there were places free, and the rest refused; with five places
	; emptied side by side a worm, which needs ten, is refused whole; and of
	; ten drones asked for then, five are made and five refused. Every drone
	; is still itself afterwards, and at the end it is all as it was.
	at_frame 1219,Events.reserved+60,10,.room_wrong
	cmp esi,1228
	jne .room_before
	cmp word [rbx+Events.reserved+60],0
	jne .room_wrong
	cmp dword [rbx+Events.reserved+48],0
	je .room_wrong
.room_before:
	cmp esi,1230
	jne .room_after
	mov eax,[rbx+Events.reserved+48]
	mov [room_occupied],eax
	mov eax,[rbx+Events.reserved+52]
	mov [room_refused],eax
.room_after:
	cmp esi,1236
	je .room_full
	cmp esi,1249
	jne .roomed
.room_full:
	cmp dword [rbx+Events.reserved+32],384
	jne .room_wrong
	cmp dword [rbx+Events.reserved+48],384
	jne .room_wrong
	; As many drones as there were places, numbered from one: their numbers sum to n(n+1)/2.
	mov ecx,384
	sub ecx,[room_occupied]
	movzx eax,word [rbx+Events.reserved+62]
	cmp eax,ecx
	jne .room_wrong
	lea eax,[ecx+1]
	imul eax,ecx
	shr eax,1
	cmp eax,[rbx+Events.reserved+56]
	jne .room_wrong
	; Sixteen shots more refused than before; and of hostiles, the drones
	; that did not fit, the worm, and the five too many.
	mov eax,[rbx+Events.reserved+52]
	sub eax,[room_refused]
	mov edx,406
	sub edx,ecx
	shl edx,16
	or edx,16 shl 8
	cmp eax,edx
	je .roomed
.room_wrong:
	fail 27
.roomed:
	ret
endp

; The music as the device rendered it, for the script to hold to the notes
; and to write out as something a player can open.
proc write_music uses rbx
	fastcall CreateFileW,<W,'build\myhits_game.music.bin'>,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .failed
	mov rbx,rax
	mov rdx,[bank_buffer.mapped]
	add rdx,BANK_SAMPLES*4
	fastcall WriteFile,rbx,rdx,TABLE_STEMS*MUSIC_SAMPLES*4,addr written,0
	test eax,eax
	jz .close_failed
	cmp [written],TABLE_STEMS*MUSIC_SAMPLES*4
	jne .close_failed
	fastcall CloseHandle,rbx
	ret
.close_failed:
	fastcall CloseHandle,rbx
.failed:
	mov [app_io_failed],1
	ret
endp

; A thousand frames by the script, then the totals no frame could show alone.
proc scripted_run uses rbx rsi
	fastcall write_music
	or dword [root+Root.flags],ROOT_SCRIPTED
	mov [script_ticks],GAME_TICKS
	mov ebx,SCRIPT_FRAMES
.frame:
	fastcall play_frame
	test eax,eax
	jz .broken
	dec ebx
	jnz .frame
	fastcall machine_drain
	test eax,eax
	jz .broken
	fastcall machine_write_measure
	mov esi,SCRIPT_FRAMES
	; 4 and 9, in part: the rises and falls of rank were seen, and the head did die.
	cmp [rise_checked],0
	je .unseen
	cmp [falls_checked],0
	je .unseen
	cmp [head_died],0
	jne .seen
.unseen:
	fail 10
	cmp [nova_frame],0
	jne .seen
	fail 10
.seen:
	; 13, in part: by the end the HUD has caught up, and there is a score to show.
	mov eax,[last_score]
	test eax,eax
	jz .hud_wrong
	cmp eax,[last_shown]
	je .hud
.hud_wrong:
	fail 13
.hud:
	; 14: a hurt is felt. Each stopped the world for four ticks, no more and
	; no fewer; and what the pad is told is what the events say: all of the
	; heavy motor is 65535, half of the light one 32768.
	mov eax,[hurts_total]
	shl eax,2
	cmp eax,[last_stopped]
	jne .felt_wrong
	movss xmm0,[felt_all]
	movss xmm1,[felt_half]
	fastcall pad_rumble
	cmp dword [pad_vibration],80000000h+0FFFFh
	je .felt
.felt_wrong:
	fail 14
.felt:
	xorps xmm0,xmm0
	xorps xmm1,xmm1
	fastcall pad_rumble
	; 22: the music. The device found every stem it rendered loud enough and
	; no louder than its gain. With nothing happening only the bass is wanted;
	; with everything, all three, each at its own level. And where there is a
	; device the stems are playing, and say where in the beat they are.
	cmp [last_music_faults],0
	jne .music_wrong
	xorps xmm0,xmm0
	fastcall audio_levels
	cmp dword [audio_wanted],0.5
	jne .music_wrong
	mov eax,dword [audio_wanted+4]
	or eax,dword [audio_wanted+8]
	jnz .music_wrong
	movss xmm0,[felt_all]
	fastcall audio_levels
	cmp dword [audio_wanted+4],0.55
	jne .music_wrong
	cmp dword [audio_wanted+8],0.5
	jne .music_wrong
	cmp [audio_ready],0
	je .music
	cmp [audio_playing],1
	jne .music_wrong
	fastcall audio_beat
	xorps xmm1,xmm1
	ucomiss xmm0,xmm1
	jb .music_wrong
	ucomiss xmm0,[felt_all]
	jb .music
.music_wrong:
	fail 22
.music:
	; 11: the sounds are the events: each sound a frame asked for went to a
	; voice once, none was refused, and every hurt was heard.
	mov eax,[sounds_asked]
	cmp [audio_plays],eax
	jne .sounds_wrong
	cmp [audio_failures],0
	jne .sounds_wrong
	mov eax,[hurts_total]
	cmp eax,3
	jb .sounds_wrong
	cmp [heard_hurts],eax
	je .sounds
.sounds_wrong:
	fail 11
.sounds:
	; 12: every frame's events were read; Root and Events were all the
	; traffic; and a frame of eight ticks is forty-one passes and two draws.
	cmp [events_seen],SCRIPT_FRAMES
	jne .commands
	cmp [traffic_down],SCRIPT_FRAMES*sizeof.Root
	jne .commands
	cmp [traffic_up],SCRIPT_FRAMES*sizeof.Events
	jne .commands
	cmp [startup_dispatches],STARTUP_DISPATCHES
	jne .commands
	cmp [dispatch_count],SCRIPT_FRAMES*(GAME_TICKS*TICK_DISPATCHES+1)
	jne .commands
	cmp [draw_count],SCRIPT_FRAMES*4
	je .manners
.commands:
	fail 12
.manners:
	; 25, in part: all three divers had their turn, the dead one too; the fix
	; was seen to follow the ship; and three shots burst, no more.
	cmp [stage_round],3
	jne .stage_short
	cmp [stage_phase],0
	jne .stage_short
	cmp [stage_followed],1
	jne .stage_short
	cmp byte [last_counts+3],3
	je .staged
.stage_short:
	fail 25
.staged:
	fastcall check_manners
	jmp .report
.broken:
	mov [app_io_failed],1
.report:
	cvtss2sd xmm0,[last_rank]
	mulsd xmm0,[thousand]
	cvtsd2si eax,xmm0
	mov [title_rank],eax
	fastcall wsprintfW,addr report_text,<W,'proof=game',13,10,'failure=%u',13,10,'failure_frame=%u',13,10,'frames=%u',13,10,'events=%u',13,10, \
		'ticks_a_frame=%u',13,10,'bodies=%u',13,10,'particles=%u',13,10,'kinds=%u',13,10,'moves=%u',13,10,'squads=%u',13,10,'world_bytes=%u',13,10, \
		'head_died_frame=%u',13,10,'nova_frame=%u',13,10,'rise_checked=%u',13,10,'falls_checked=%u',13,10,'hurts_heard=%u',13,10,'sounds_asked=%u',13,10,'plays=%u',13,10,'refused=%u',13,10,'device=%u',13,10, \
		'score=%u',13,10,'kills=%u',13,10,'rank_thousandths=%u',13,10,'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10,'startup_dispatches=%u',13,10,'dispatches=%u',13,10,'draws=%u',13,10, \
		'worst_latency=%u',13,10,'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10,'sums=%08X-%08X-%08X',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],GAME_TICKS,BODIES,PARTICLES,TABLE_KINDS,TABLE_MOVES,TABLE_WAVES,WORLD_BYTES, \
		[head_died],[nova_frame],[rise_checked],[falls_checked],[heard_hurts],[sounds_asked],[audio_plays],[audio_failures],[audio_ready],[last_score],[last_kills],[title_rank], \
		[traffic_down],[traffic_up],[startup_dispatches],[dispatch_count],[draw_count],[worst_latency],[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage], \
		[sum_first],[sum_second],[sum_third]
	fastcall machine_write_report,rax
	ret
endp

; 23: the window's manners, asked of the window itself by its own messages,
; with no one at it. P pauses: the next frame is paid no ticks and says it is
; paused. Paused, the window answers that its middle is a handle to move it
; by and its edges are edges to size it by; playing, or over the whole
; monitor, that all of it is the game's. F11 takes exactly the monitor and
; gives back exactly what it had. And through all of it the pointer is never
; taken: a scripted run has no one to take it from.
proc check_manners uses rbx rsi
	mov esi,SCRIPT_FRAMES
	and dword [root+Root.flags],not ROOT_SCRIPTED
	fastcall GetWindowRect,[window],addr manners_rect
	mov eax,[manners_rect.left]
	add eax,[manners_rect.right]
	sar eax,1
	mov edx,[manners_rect.top]
	add edx,[manners_rect.bottom]
	sar edx,1
	shl edx,16
	movzx eax,ax
	or eax,edx
	mov [manners_middle],rax
	mov eax,[manners_rect.left]
	add eax,2
	movzx eax,ax
	or eax,edx
	mov [manners_side],rax
	mov eax,[manners_rect.right]
	sub eax,2
	movzx eax,ax
	mov edx,[manners_rect.bottom]
	sub edx,2
	shl edx,16
	or eax,edx
	mov [manners_corner],rax
	; Playing: all of it is the game's.
	fastcall window_proc,[window],WM_NCHITTEST,0,[manners_middle]
	cmp eax,HTCLIENT
	jne .wrong
	fastcall window_proc,[window],WM_KEYDOWN,50h,0
	cmp [paused],1
	jne .wrong
	mov dword [root+Root.ticks],7
	fastcall machine_sample
	cmp dword [root+Root.ticks],0
	jne .wrong
	test dword [root+Root.flags],ROOT_PAUSED
	jz .wrong
	; Paused: a handle, and edges.
	iterate <point,part>, manners_middle,HTCAPTION, manners_side,HTLEFT, manners_corner,HTBOTTOMRIGHT
		fastcall window_proc,[window],WM_NCHITTEST,0,[point]
		cmp eax,part
		jne .wrong
	end iterate
	; The whole monitor, and nothing of it a handle.
	fastcall window_proc,[window],WM_KEYDOWN,VK_F11,0
	cmp [fullscreen],1
	jne .wrong
	fastcall GetWindowRect,[window],addr window_rect
	fastcall window_monitor
	iterate side, left,top,right,bottom
		mov eax,[window_rect.side]
		cmp eax,[monitor_info.rcMonitor.side]
		jne .wrong
	end iterate
	fastcall window_proc,[window],WM_NCHITTEST,0,[manners_middle]
	cmp eax,HTCLIENT
	jne .wrong
	; And back: where it was, as large as it was, and paused still.
	fastcall window_proc,[window],WM_KEYDOWN,VK_F11,0
	cmp [fullscreen],0
	jne .wrong
	fastcall GetWindowRect,[window],addr window_rect
	iterate side, left,top,right,bottom
		mov eax,[window_rect.side]
		cmp eax,[manners_rect.side]
		jne .wrong
	end iterate
	cmp [paused],1
	jne .wrong
	; P again: it plays, and says so.
	fastcall window_proc,[window],WM_KEYDOWN,50h,0
	cmp [paused],0
	jne .wrong
	fastcall machine_sample
	test dword [root+Root.flags],ROOT_PAUSED
	jnz .wrong
	; Leaving it for another program pauses it; coming back does not resume it.
	fastcall window_proc,[window],WM_ACTIVATEAPP,0,0
	cmp [paused],1
	jne .wrong
	fastcall window_proc,[window],WM_ACTIVATEAPP,1,0
	cmp [paused],1
	jne .wrong
	fastcall machine_pause,0
	cmp [confined],0
	je .remembers
.wrong:
	fail 23
.remembers:
	; 26: the window is remembered. Under a name of the check's own, so that
	; what a player left is not disturbed: with nothing remembered it is to
	; have the whole monitor; left as a window somewhere, it comes back there
	; as a window; left over the whole monitor, it comes back so, and to the
	; same place when that is given up.
	lea rax,[manners_value]
	mov [window_state_name],rax
	fastcall state_drop,[window_state_name]
	fastcall window_recall
	cmp eax,1
	jne .forgets
	fastcall SetWindowPos,[window],0,137,91,800,450,SWP_NOZORDER or SWP_NOACTIVATE
	fastcall window_remember
	fastcall SetWindowPos,[window],0,0,0,640,360,SWP_NOZORDER or SWP_NOACTIVATE
	fastcall window_recall
	test eax,eax
	jnz .forgets
	fastcall check_place
	test eax,eax
	jz .forgets
	fastcall machine_fullscreen
	fastcall window_remember
	fastcall machine_fullscreen
	fastcall SetWindowPos,[window],0,0,0,640,360,SWP_NOZORDER or SWP_NOACTIVATE
	fastcall window_recall
	cmp eax,1
	jne .forgets
	fastcall check_place
	test eax,eax
	jnz .done
.forgets:
	fail 26
.done:
	fastcall state_drop,[window_state_name]
	lea rax,[window_state_value]
	mov [window_state_name],rax
	or dword [root+Root.flags],ROOT_SCRIPTED
	ret
endp

; Whether the window is at 137, 91 and 800 by 450.
proc check_place
	fastcall GetWindowRect,[window],addr window_rect
	xor eax,eax
	iterate <side,value>, left,137, top,91, right,937, bottom,541
		cmp [window_rect.side],value
		jne .elsewhere
	end iterate
	mov eax,1
.elsewhere:
	ret
endp

proc mainCRTStartup
	fastcall read_options
	test rax,rax
	jz .failed
	fastcall command_option,<W,'--self-test'>
	mov [test_mode],eax
	fastcall machine_start
	test eax,eax
	jz .failed
	fastcall create_world
	test eax,eax
	jz .failed
	; The checks make no noise; and no device is not a failure.
	fastcall audio_start,[test_mode]
	mov rcx,[bank_buffer.mapped]
	add rcx,BANK_SAMPLES*4
	fastcall audio_music,rcx
	; A scripted run is always measured; a played one when it is asked to be.
	fastcall command_option,<W,'--measure'>
	or eax,[test_mode]
	jz .unmeasured
	fastcall machine_measure
.unmeasured:
	cmp [test_mode],0
	je .show
	fastcall snapshot_start
	fastcall scripted_run
	jmp .finish
.show:
	; As it was left; the first time, over the whole monitor; and either way
	; as the command line says, if it says.
	fastcall window_recall
	mov [start_whole],eax
	fastcall command_option,<W,'--windowed'>
	test eax,eax
	jz .as_asked
	mov [start_whole],0
.as_asked:
	fastcall command_option,<W,'--fullscreen'>
	test eax,eax
	jz .as_left
	mov [start_whole],1
.as_left:
	cmp [start_whole],0
	je .placed
	fastcall machine_fullscreen
.placed:
	fastcall ShowWindow,[window],SW_SHOWNORMAL
	fastcall UpdateWindow,[window]
	; Shown behind another program, or as an icon, it waits to be come to.
	fastcall GetForegroundWindow
	cmp rax,[window]
	je .begin
	fastcall machine_pause,1
.begin:
	fastcall QueryPerformanceCounter,addr clock_last
.messages:
	fastcall PeekMessageW,addr message,0,0,0,PM_REMOVE
	test eax,eax
	jz .idle
	cmp [message.message],WM_QUIT
	je .finish
	fastcall TranslateMessage,addr message
	fastcall DispatchMessageW,addr message
	jmp .messages
.idle:
	; Draw only while there is someone to draw for: not minimized, and either
	; playing in front or showing something other than the last frame. A
	; paused window draws the one frame that says so, and then waits.
	cmp [minimized],0
	jne .wait
	cmp [stale],0
	jne .draw
	cmp [paused],0
	jne .wait
	fastcall GetForegroundWindow
	cmp rax,[window]
	jne .wait
.draw:
	fastcall play_frame
	test eax,eax
	jz .failed
	mov [stale],0
	jmp .messages
.wait:
	fastcall WaitMessage
	fastcall QueryPerformanceCounter,addr clock_last
	jmp .messages
.failed:
	mov [app_io_failed],1
.finish:
	cmp [test_mode],0
	jne .measured
	cmp [device],0
	je .measured
	; What a played run cost, if it was measured.
	fastcall machine_drain
	fastcall machine_write_measure
.measured:
	fastcall free_options
	fastcall machine_stop
	fastcall machine_report_exit
	fastcall ExitProcess,rax
	int3
endp

section '.data$game' data readable writeable align 16
absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
thousand dq 1000.0
tolerance dd 0.05
rank_slack dd 0.00002
rank_one dd 0.01
rank_two dd 0.004
rank_rise dd 0.034
rank_fall dd 0.15
spacing dd 112.0
spacing_least dd 104.0			; what the worm's tightest turn can bring two neighbors to
spacing_most dd 112.6
rank_unit dd 1.0
rank_round dd 0.5
worth_swooper dd 200.0
worth_drone dd 150.0
mate_x_first dd 300.0
mate_y_first dd 532.0
mate_x_after dd 310.0
mate_y_after dd 420.0
mate_slack dd 1.5
aim_x dd 1500.0
aim_y dd 300.0
centi dd 0.01
scratch dd 0,0
felt_all dd 1.0
felt_half dd 0.5
full_pace dd 240.0
manners_rect RECT
manners_middle dq 0
manners_side dq 0
manners_corner dq 0
manners_value GLOBWSTR 'window.check',0
charge_all dd 1.0
charge_launched dd 0.75
charge_dashed dd 0.55
charge_grazed dd 0.58
charge_last dd 0.19
charge_slack dd 0.0005
ship_column dd 300.0
dash_up dd 220.0
dash_down dd 700.0
stage_slack dd 0.05
stage_near dd 1.0
stage_little dd 0.1
fade_before dd 2.0
; By which diver: how many bursts have caught the ship once its own has, and what its own cost in lives.
stage_caught db 1,1,2,0
stage_cost db 1,0,1,0
world_buffer GpuBuffer
header_buffer GpuBuffer
home_buffer GpuBuffer
bank_buffer GpuBuffer
iterate name, settle,begin,direct,update,collide,resolve,drift,report,render,scene,particle,veil,backdrop
	name#_pipeline dq 0
end iterate
iterate name, events_seen,proof_failure,proof_failure_frame,startup_dispatches,last_latency,worst_latency,title_rank,sounds_asked,heard_hurts, \
	last_score,last_lives,last_wave,last_state,last_rank,last_fired,last_struck,last_kills,last_hurts,last_alive, \
	hurts_before,rank_before,scroll_before,hurt_frame,hurts_total,rise_checked,falls_checked,chain_seen,head_died,alive_before,last_shown,last_stopped, \
	fired_mark,nova_frame,nova_score,nova_kills,score_before,kills_before,struck_mark,last_music_faults, \
	start_whole,last_counts,stage_ship_y,stage_phase,stage_round,stage_followed,stage_hurts,stage_recoiled,room_occupied,room_refused, \
	sum_first,sum_second,sum_third, \
	lock_x,lock_y,fire_x,fire_y
	name dd 0
end iterate

; The game's tables, as the device reads them.
section '.rdata$game_tables' data readable align 16
table_moves:
	game_tables
table_kinds:
	kinds_table
table_styles:
	game_styles
table_sounds:
	game_sounds
table_waves:
	game_waves
table_stems:
	game_music
TABLE_BYTES := $ - table_moves
HOME_BYTES := (sizeof.GameWorld + TABLE_BYTES + 3) and not 3	; the header and the tables, in whole words
assert TABLE_BYTES = TABLE_MOVES * sizeof.Move + TABLE_KINDS * sizeof.Kind + TABLE_STYLES * sizeof.Style + TABLE_SOUNDS * sizeof.Recipe + TABLE_WAVES * sizeof.Wave + TABLE_STEMS * sizeof.Stem
BANK_TOTAL := BANK_SAMPLES + TABLE_STEMS * MUSIC_SAMPLES	; the sounds, then the stems

section '.rdata$game_spirv' data readable align 4
iterate <name,module>, develop_code,develop, chart_code,chart, census_code,census, settle_code,settle, begin_code,begin, direct_code,direct, update_code,update, \
	collide_code,collide, resolve_code,resolve, drift_code,drift, report_code,report, render_code,render, scene_vertex_code,scene_vertex, \
	scene_fragment_code,scene_fragment, particle_vertex_code,particle_vertex, particle_fragment_code,particle_fragment, veil_vertex_code,veil_vertex, veil_fragment_code,veil_fragment, backdrop_vertex_code,backdrop_vertex, backdrop_fragment_code,backdrop_fragment
	align 4
	name file 'build\myhits_game_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
