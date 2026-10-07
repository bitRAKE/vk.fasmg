; myhits: a horizontal shooter whose world lives on the GPU. The CPU reads the
; controls, sends 72 bytes a frame, reads 512 back, and plays the sounds they
; ask for. Everything else is in myhits.slang and the tables.
;
;	build\myhits.exe		play: arrows or WASD or a pad move, Space or the
;					left button fires, Shift or the right button
;					launches a pair of missiles at the crosshair,
;					Enter begins again when a run is over
;	build\myhits.exe --self-test	a scripted run of two games, every claim checked
;
; What the scripted run holds the game to is in proofs\README.md, under 07.
MACHINE_NAME equ 'myhits'
MACHINE_TAG equ 'game'
include 'machine.inc'
include 'pictures.inc'
include 'tables.inc'
include 'audio.inc'

; These are myhits.slang's.
BODIES := 1024
SHOTS := 256
PELLETS := 384
HOSTILES := 384
PARTICLES := 16384
TRAILS := 32
REQUESTS := 256
INSTANCES := 160 + BODIES + 4
GAME_BYTES := 192
POOL_BYTES := 8 + STYLE_LIMIT * 4
WORLD_BYTES := GAME_BYTES + POOL_BYTES + 2 * BODIES * BODY_BYTES + BODIES * 4 + TRAILS * TRAIL_POINTS * 8 + REQUESTS * REQUEST_BYTES + PARTICLES * PARTICLE_BYTES
TICK_DISPATCHES := 5			; the director, the bodies, the shots, the struck, the particles
STARTUP_DISPATCHES := PICTURES_PASSES + 2
GAME_TICKS := 8				; a scripted frame of the game runs this many: it has far to go
SCRIPT_FRAMES := 580
RESTART_FRAME := 400			; the script presses Enter here; the first game is over by then
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
	u32 capacity
	u32 particle_capacity
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
	require_ok fastcall create_device_buffer,addr world_buffer,WORLD_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1
	; The CPU writes the header and the tables once, into host-visible memory.
	require_ok fastcall create_buffer,addr header_buffer,sizeof.GameWorld+TABLE_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1
	; And the device writes the sounds once where the CPU, and so the voices, can read them.
	require_ok fastcall create_buffer,addr bank_buffer,BANK_SAMPLES*4,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1
	mov rdi,[header_buffer.mapped]
	require_ok fastcall pictures_create,rdi
	mov rax,[header_buffer.address]
	add rax,sizeof.GameWorld
	iterate <table,count,size>, moves,TABLE_MOVES,sizeof.Move, kinds,TABLE_KINDS,sizeof.Kind, styles,TABLE_STYLES,sizeof.Style, sounds,TABLE_SOUNDS,sizeof.Recipe, waves,TABLE_WAVES,sizeof.Wave
		mov [rdi+GameWorld.tables+Tables.table],rax
		add rax,(count)*(size)
	end iterate
	mov dword [rdi+GameWorld.tables+Tables.move_count],TABLE_MOVES
	mov dword [rdi+GameWorld.tables+Tables.kind_count],TABLE_KINDS
	mov dword [rdi+GameWorld.tables+Tables.style_count],TABLE_STYLES
	mov dword [rdi+GameWorld.tables+Tables.sound_count],TABLE_SOUNDS
	mov dword [rdi+GameWorld.tables+Tables.wave_count],TABLE_WAVES
	mov dword [rdi+GameWorld.tables+Tables.pad],0
	mov rax,[world_buffer.address]
	iterate <pool,bytes>, game,GAME_BYTES, pool,POOL_BYTES, bodies,2*BODIES*BODY_BYTES, damage,BODIES*4, trails,TRAILS*TRAIL_POINTS*8, queue,REQUESTS*REQUEST_BYTES, particles,PARTICLES*PARTICLE_BYTES
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
	iterate name, begin,direct,update,collide,resolve,drift,report,render
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	require_ok fastcall machine_graphics,addr scene_vertex_code,scene_vertex_code.size,addr scene_fragment_code,scene_fragment_code.size,BLEND_PREMULTIPLIED,addr scene_pipeline
	require_ok fastcall machine_graphics,addr particle_vertex_code,particle_vertex_code.size,addr particle_fragment_code,particle_fragment_code.size,BLEND_PREMULTIPLIED,addr particle_pipeline
	require_ok fastcall pictures_develop
	require_ok fastcall machine_serial_open
	fastcall machine_dispatch,[begin_pipeline],1
	; The sounds, too: nothing of them is uploaded but their recipes.
	fastcall machine_dispatch,[render_pipeline],(BANK_SAMPLES+63)/64
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
	iterate name, begin,direct,update,collide,resolve,drift,report,render,scene,particle
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	fastcall pictures_release
	fastcall destroy_buffer,addr bank_buffer
	fastcall destroy_buffer,addr header_buffer
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
	; row, and fire at its head as it comes.
	mov dword [root+Root.move],0
	mov dword [root+Root.move+4],0
	mov dword [root+Root.held],0
	mov dword [root+Root.pressed],0
	mov eax,[root+Root.frame]
	iterate <from,to,way>, 0,10,-1.0, 250,255,1.0, 401,403,-1.0
		cmp eax,from
		jb .still_#from
		cmp eax,to
		ja .still_#from
		mov dword [root+Root.move+4],way
	.still_#from:
	end iterate
	iterate <from,to>, 11,16, 290,294, 543,566
		cmp eax,from
		jb .quiet_#from
		cmp eax,to
		ja .quiet_#from
		mov dword [root+Root.held],BUTTON_FIRE
	.quiet_#from:
	end iterate
	cmp eax,RESTART_FRAME
	jne .sample
	mov dword [root+Root.pressed],BUTTON_START
.sample:
	fastcall machine_sample
	fastcall machine_open
	cmp eax,1
	jne .skipped
	mov ebx,[root+Root.ticks]
.tick:
	test ebx,ebx
	jz .ticked
	fastcall machine_dispatch,[direct_pipeline],1
	fastcall machine_settle
	fastcall machine_dispatch,[update_pipeline],BODIES/64
	fastcall machine_settle
	fastcall machine_dispatch,[collide_pipeline],(SHOTS+PELLETS)/64
	fastcall machine_settle
	fastcall machine_dispatch,[resolve_pipeline],HOSTILES/32
	fastcall machine_settle
	fastcall machine_dispatch,[drift_pipeline],PARTICLES/64
	fastcall machine_settle
	dec ebx
	jmp .tick
.ticked:
	fastcall machine_dispatch,[report_pipeline],1
	fastcall machine_canvas
	fastcall machine_draw,[scene_pipeline],6,INSTANCES
	fastcall machine_draw,[particle_pipeline],6,PARTICLES
	fastcall machine_close
	ret
.skipped:
	; 2: no image this turn, which is not a failure.
	shr eax,1
.stopped:
	ret
endp

; A finished frame's events: its sounds to the voices, its numbers to the
; title, and in a scripted run every one of them held to the rules.
proc consume_events uses rbx rsi rdi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	fastcall audio_events,rbx,addr table_sounds,[bank_buffer.mapped]
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
	; tight can bring them.
	cmp esi,150
	jb .chain
	cmp esi,165
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
	iterate <name,offset>, hurts_before,Events.reserved+24, rank_before,Events.rank, scroll_before,Events.reserved+40
		mov eax,[rbx+offset]
		mov [name],eax
	end iterate
.done:
	inc [events_seen]
	ret
endp

; 580 frames by the script, then the totals no frame could show alone.
proc scripted_run uses rbx rsi
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
.seen:
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
	cmp [draw_count],SCRIPT_FRAMES*2
	je .report
.commands:
	fail 12
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
		'head_died_frame=%u',13,10,'rise_checked=%u',13,10,'falls_checked=%u',13,10,'hurts_heard=%u',13,10,'sounds_asked=%u',13,10,'plays=%u',13,10,'refused=%u',13,10,'device=%u',13,10, \
		'score=%u',13,10,'kills=%u',13,10,'rank_thousandths=%u',13,10,'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10,'startup_dispatches=%u',13,10,'dispatches=%u',13,10,'draws=%u',13,10, \
		'worst_latency=%u',13,10,'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],GAME_TICKS,BODIES,PARTICLES,TABLE_KINDS,TABLE_MOVES,TABLE_WAVES,WORLD_BYTES, \
		[head_died],[rise_checked],[falls_checked],[heard_hurts],[sounds_asked],[audio_plays],[audio_failures],[audio_ready],[last_score],[last_kills],[title_rank], \
		[traffic_down],[traffic_up],[startup_dispatches],[dispatch_count],[draw_count],[worst_latency],[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage]
	fastcall machine_write_report,rax
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
	cmp [test_mode],0
	je .show
	fastcall scripted_run
	jmp .finish
.show:
	fastcall resize_window,1280,720
	fastcall ShowWindow,[window],SW_SHOWNORMAL
	fastcall UpdateWindow,[window]
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
	; in front or showing something other than the last frame.
	cmp [minimized],0
	jne .wait
	cmp [stale],0
	jne .draw
	fastcall GetForegroundWindow
	cmp rax,[window]
	jne .wait
.draw:
	fastcall play_frame
	test eax,eax
	jz .failed
	mov [stale],0
	test dword [root+Root.frame],15
	jnz .messages
	cvtss2sd xmm0,[last_rank]
	mulsd xmm0,[hundred]
	cvtsd2si eax,xmm0
	mov [title_rank],eax
	lea rax,[title_play]
	cmp [last_state],0
	je .title
	lea rax,[title_over]
.title:
	mov [title_format],rax
	fastcall wsprintfW,addr title_text,[title_format],[last_score],[last_lives],[title_rank],[last_wave],[last_fired],[last_struck],[last_kills]
	fastcall SetWindowTextW,[window],addr title_text
	jmp .messages
.wait:
	fastcall WaitMessage
	fastcall QueryPerformanceCounter,addr clock_last
	jmp .messages
.failed:
	mov [app_io_failed],1
.finish:
	fastcall free_options
	fastcall machine_stop
	fastcall machine_report_exit
	fastcall ExitProcess,rax
	int3
endp

section '.data$game' data readable writeable align 16
absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
thousand dq 1000.0
hundred dq 100.0
tolerance dd 0.05
rank_slack dd 0.00002
rank_one dd 0.01
rank_two dd 0.004
rank_rise dd 0.034
rank_fall dd 0.15
spacing dd 112.0
spacing_least dd 104.0			; what the worm's tightest turn can bring two neighbors to
spacing_most dd 112.6
full_pace dd 240.0
title_play GLOBWSTR 'myhits | score %u | lives %u | rank %u%% | squad %u | %u fired, %u struck, %u killed | arrows or WASD move, Space fires, Shift launches, Esc quits',0
title_over GLOBWSTR 'myhits | score %u | lives %u | rank %u%% | squad %u | %u fired, %u struck, %u killed | this run is over: Enter begins another',0
title_format dq 0
world_buffer GpuBuffer
header_buffer GpuBuffer
bank_buffer GpuBuffer
iterate name, begin,direct,update,collide,resolve,drift,report,render,scene,particle
	name#_pipeline dq 0
end iterate
iterate name, events_seen,proof_failure,proof_failure_frame,startup_dispatches,last_latency,worst_latency,title_rank,sounds_asked,heard_hurts, \
	last_score,last_lives,last_wave,last_state,last_rank,last_fired,last_struck,last_kills,last_hurts,last_alive, \
	hurts_before,rank_before,scroll_before,hurt_frame,hurts_total,rise_checked,falls_checked,chain_seen,head_died,alive_before
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
TABLE_BYTES := $ - table_moves
assert TABLE_BYTES = TABLE_MOVES * sizeof.Move + TABLE_KINDS * sizeof.Kind + TABLE_STYLES * sizeof.Style + TABLE_SOUNDS * sizeof.Recipe + TABLE_WAVES * sizeof.Wave

section '.rdata$game_spirv' data readable align 4
iterate <name,module>, develop_code,develop, chart_code,chart, census_code,census, begin_code,begin, direct_code,direct, update_code,update, \
	collide_code,collide, resolve_code,resolve, drift_code,drift, report_code,report, render_code,render, scene_vertex_code,scene_vertex, \
	scene_fragment_code,scene_fragment, particle_vertex_code,particle_vertex, particle_fragment_code,particle_fragment
	align 4
	name file 'build\myhits_game_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
