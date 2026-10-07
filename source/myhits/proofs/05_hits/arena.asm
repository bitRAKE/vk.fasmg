; Proof 05, hits: shots strike what they are drawn to strike, by its mask, at
; any speed; what is struck takes it, dies of it, and throws off particles and
; sounds; and what touches the ship hurts it, once.
;
;	build\myhits_hits.exe			watch it; Space or the left button fires,
;						Shift or the right button throws a lance,
;						Enter sets off more fireworks than are allowed
;	build\myhits_hits.exe --self-test	280 scripted frames, every claim checked
;
; What each check settles is in ..\README.md.
MACHINE_NAME equ 'myhits proof 05: hits'
MACHINE_TAG equ 'hits'
MACHINE_SNAPSHOT := 1
include '..\..\..\common\machine.inc'
include '..\..\..\common\pictures.inc'
include '..\..\tables.inc'

; These are arena.slang's.
CAPACITY := 256
HOSTILES := 96
PARTICLES := 16384
HIT_LOG := 64
INSTANCES := CAPACITY + 2
SPARKS := 6
DEBRIS := 48
BURST_CAP := 128
SCRIPT_FRAMES := 280
TICK_DISPATCHES := 5			; the director, the bodies, the shots, the struck, the particles
FRAME_DISPATCHES := SCRIPT_TICKS * TICK_DISPATCHES + 1
STARTUP_DISPATCHES := PICTURES_PASSES + 2
public mainCRTStartup

; The world's header, which the CPU writes once: World in arena.slang.
boundary ArenaWorld
	block pictures,Pictures
	block tables,Tables
	ptr bodies,Body
	ptr game,Game
	ptr damage,uint
	ptr particles,Particle
	ptr pool,ParticlePool
	ptr hit_log,float2
	u32 capacity
	u32 particle_capacity
end boundary
GAME_BYTES := 96
POOL_BYTES := 8 + STYLE_LIMIT * 4
WORLD_BYTES := GAME_BYTES + POOL_BYTES + 2 * CAPACITY * BODY_BYTES + CAPACITY * 4 + HIT_LOG * 8 + PARTICLES * PARTICLE_BYTES

section '.text$arena' code readable executable align 16

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
	; The CPU writes the header and the tables once, into host-visible memory.
	require_ok fastcall create_buffer,addr header_buffer,sizeof.ArenaWorld+TABLE_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_UPLOAD
	mov rdi,[header_buffer.mapped]
	require_ok fastcall pictures_create,rdi
	mov rax,[header_buffer.address]
	add rax,sizeof.ArenaWorld
	mov [rdi+ArenaWorld.tables+Tables.moves],rax
	add rax,TABLE_MOVES*sizeof.Move
	mov [rdi+ArenaWorld.tables+Tables.kinds],rax
	add rax,TABLE_KINDS*sizeof.Kind
	mov [rdi+ArenaWorld.tables+Tables.styles],rax
	mov dword [rdi+ArenaWorld.tables+Tables.move_count],TABLE_MOVES
	mov dword [rdi+ArenaWorld.tables+Tables.kind_count],TABLE_KINDS
	add rax,TABLE_STYLES*sizeof.Style
	mov [rdi+ArenaWorld.tables+Tables.sounds],rax
	mov dword [rdi+ArenaWorld.tables+Tables.style_count],TABLE_STYLES
	mov dword [rdi+ArenaWorld.tables+Tables.sound_count],TABLE_SOUNDS
	mov qword [rdi+ArenaWorld.tables+Tables.waves],0
	mov dword [rdi+ArenaWorld.tables+Tables.wave_count],0
	mov qword [rdi+ArenaWorld.tables+Tables.stems],0
	mov dword [rdi+ArenaWorld.tables+Tables.stem_count],0
	mov rax,[world_buffer.address]
	mov [rdi+ArenaWorld.game],rax
	add rax,GAME_BYTES
	mov [rdi+ArenaWorld.pool],rax
	add rax,POOL_BYTES
	mov [rdi+ArenaWorld.bodies],rax
	add rax,2*CAPACITY*BODY_BYTES
	mov [rdi+ArenaWorld.damage],rax
	add rax,CAPACITY*4
	mov [rdi+ArenaWorld.hit_log],rax
	add rax,HIT_LOG*8
	mov [rdi+ArenaWorld.particles],rax
	mov dword [rdi+ArenaWorld.capacity],CAPACITY
	mov dword [rdi+ArenaWorld.particle_capacity],PARTICLES
	add rdi,sizeof.ArenaWorld
	lea rsi,[table_moves]
	mov ecx,TABLE_BYTES
	rep movsb
	require_ok fastcall flush_buffer,addr header_buffer
	mov rax,[header_buffer.address]
	mov [root+Root.world],rax
	iterate name, begin,survey,direct,update,collide,resolve,drift,report
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	require_ok fastcall machine_graphics,addr scene_vertex_code,scene_vertex_code.size,addr scene_fragment_code,scene_fragment_code.size,BLEND_PREMULTIPLIED,addr scene_pipeline
	require_ok fastcall machine_graphics,addr particle_vertex_code,particle_vertex_code.size,addr particle_fragment_code,particle_fragment_code.size,BLEND_PREMULTIPLIED,addr particle_pipeline
	require_ok fastcall pictures_develop
	require_ok fastcall machine_serial_open
	fastcall machine_dispatch,[begin_pipeline],1
	fastcall machine_settle
	fastcall machine_dispatch,[survey_pipeline],ART_FRAMES
	require_ok fastcall machine_serial_close
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
	iterate name, begin,survey,direct,update,collide,resolve,drift,report,scene,particle
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	fastcall pictures_release
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
	; The script. Four shots at the ring; a lance at it; up 70 and four shots
	; past it; up 220 and four at the drone; then hands off while two rammers
	; come by; then the fireworks.
	mov dword [root+Root.move],0
	mov dword [root+Root.move+4],0
	mov dword [root+Root.held],0
	mov dword [root+Root.pressed],0
	mov eax,[root+Root.frame]
	iterate <from,to>, 45,51, 70,91
		cmp eax,from
		jb .still_#from
		cmp eax,to
		ja .still_#from
		mov dword [root+Root.move+4],-1.0
	.still_#from:
	end iterate
	iterate <from,to>, 10,21, 55,66, 95,106
		cmp eax,from
		jb .quiet_#from
		cmp eax,to
		ja .quiet_#from
		mov dword [root+Root.held],BUTTON_FIRE
	.quiet_#from:
	end iterate
	cmp eax,40
	jne .fireworks
	mov dword [root+Root.pressed],BUTTON_SECOND
.fireworks:
	cmp eax,225
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
	fastcall machine_dispatch,[update_pipeline],CAPACITY/64
	fastcall machine_settle
	fastcall machine_dispatch,[collide_pipeline],2
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
	fastcall draw_world
	; The scripted run leaves pictures of itself: shots at the ring, the drone bursting, the ship hurt, the fireworks.
	iterate when, 30,119,205,227
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

; Everything a frame draws.
proc draw_world
	fastcall machine_draw,[scene_pipeline],6,INSTANCES
	fastcall machine_draw,[particle_pipeline],6,PARTICLES
	ret
endp

; A finished frame's events. Interactive runs show them; scripted runs hold
; every one to what the tables, the script and the masks make inevitable.
proc consume_events uses rbx rsi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	iterate <name,offset>, last_fired,Events.reserved+4, last_escaped,Events.reserved+8, last_struck,Events.reserved+12, last_flying,Events.reserved+16, \
		last_kills,Events.reserved+20, last_hurts,Events.reserved+24, last_asked,Events.reserved+28, last_live,Events.reserved+32, last_score,Events.score
		mov eax,[rbx+offset]
		mov [name],eax
	end iterate
	; What the sounds would have been, added up.
	iterate <total,which>, heard_shots,SOUND_SHOT, heard_launches,SOUND_LAUNCH, heard_hits,SOUND_HIT, heard_bursts,SOUND_BURST, heard_hurts,SOUND_HURT
		mov eax,[rbx+Events.sound+which*sizeof.Trigger+Trigger.count]
		add [total],eax
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
	; 2: what is drawn is what is hit. Through each of four poses, every texel
	; set down as the draw sets it and brought back as a hit is comes back
	; solid exactly where its mask is, and the cut frames' solid texels number
	; what the packer counted in the PNGs.
	cmp dword [rbx+Events.wave],0
	jne .survey_wrong
	iterate pose, 0,4,8,12
		cmp dword [rbx+Events.debug+pose],ART_BAKED_SOLID
		jne .survey_wrong
	end iterate
	jmp .survey
.survey_wrong:
	fail 2
.survey:
	; 3: every shot is accounted for, in every frame: fired is struck, escaped and flying.
	mov eax,[rbx+Events.reserved+8]
	add eax,[rbx+Events.reserved+12]
	add eax,[rbx+Events.reserved+16]
	cmp eax,[rbx+Events.reserved+4]
	je .accounted
	fail 3
.accounted:
	; 4: a shot strikes the ring where the ring begins: its first solid texel
	; on the shot's row, which the sweep meets within a texel. The first five
	; hits are all there, on the row they were fired along.
	at_frame 37,Events.reserved+12,4,.wall_wrong
	cmp esi,46
	ja .wall
	cmp dword [rbx+Events.reserved+40],0
	je .wall
	movss xmm0,dword [rbx+Events.reserved+44]
	ucomiss xmm0,[wall_near]
	jb .wall_wrong
	ucomiss xmm0,[wall_far]
	ja .wall_wrong
	movss xmm0,dword [rbx+Events.reserved+48]
	subss xmm0,[f_540]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[fine]
	jbe .wall
.wall_wrong:
	fail 4
.wall:
	; 5: a lance covers 50 units a tick and the ring's wall is 12 thick: it is
	; never inside the wall at a tick, on either side. It strikes all the same.
	at_frame 39,Events.reserved+12,4,.lance_wrong
	at_frame 46,Events.reserved+12,5,.lance_wrong
	jmp .lance
.lance_wrong:
	fail 5
.lance:
	; 6: the corner of a picture is not the picture. Four shots pass through
	; the ring's square, clear of the ring, and strike nothing.
	at_frame 110,Events.reserved+12,5,.corner_wrong
	at_frame 110,Events.reserved+8,4,.corner_wrong
	jmp .corner
.corner_wrong:
	fail 6
.corner:
	; 7: the drone takes three hits and dies of the third, for its worth; the
	; fourth shot finds nothing there.
	at_frame 117,Events.reserved+20,0,.kill_wrong
	at_frame 121,Events.reserved+20,1,.kill_wrong
	at_frame 121,Events.reserved+12,8,.kill_wrong
	at_frame 121,Events.score,150,.kill_wrong
	at_frame 160,Events.reserved+8,5,.kill_wrong
	jmp .kill
.kill_wrong:
	fail 7
.kill:
	; 8: a rammer passing 110 above the ship is inside its circle and outside
	; its mask: nothing. One along its row hurts it, once, though it is inside
	; the ship for a dozen ticks; and that is felt.
	at_frame 198,Events.reserved+24,0,.hurt_wrong
	at_frame 220,Events.reserved+24,1,.hurt_wrong
	cmp dword [rbx+Events.reserved+24],0
	jne .felt
	cmp dword [rbx+Events.rumble_low],0
	jne .hurt_wrong
	jmp .hurt
.felt:
	cmp esi,215
	jne .hurt
	cmp dword [rbx+Events.rumble_low],0
	jne .hurt
.hurt_wrong:
	fail 8
.hurt:
	; 9, in part: asked for 500 in one tick, the style let in its cap.
	at_frame 226,Events.reserved+36,BURST_CAP,.cap_wrong
	at_frame 226,Events.reserved+28,8*SPARKS+DEBRIS+BURST_CAP,.cap_wrong
	jmp .done
.cap_wrong:
	fail 9
.done:
	inc [events_seen]
	ret
endp

; 280 frames by the script, then the totals no frame could show alone.
proc scripted_run uses rbx rsi
	or dword [root+Root.flags],ROOT_SCRIPTED
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
	; 9: six sparks a hit and 48 for the death, no more and no fewer, and every
	; one of them has lived its life and gone.
	cmp [last_asked],8*SPARKS+DEBRIS+BURST_CAP
	jne .particles_wrong
	cmp [last_live],0
	je .particles
.particles_wrong:
	fail 9
.particles:
	; 10: the sounds are the events. Over the run, as many shots, launches,
	; hits, deaths and hurts were asked for as happened.
	cmp [heard_shots],12
	jne .sounds_wrong
	cmp [heard_launches],1
	jne .sounds_wrong
	mov eax,[last_struck]
	cmp eax,8
	jne .sounds_wrong
	cmp [heard_hits],eax
	jne .sounds_wrong
	mov eax,[last_kills]
	cmp [heard_bursts],eax
	jne .sounds_wrong
	mov eax,[last_hurts]
	cmp [heard_hurts],eax
	jne .sounds_wrong
	cmp [last_fired],13
	jne .sounds_wrong
	cmp [last_escaped],5
	je .sounds
.sounds_wrong:
	fail 10
.sounds:
	; 11: every frame's events were read; Root and Events were all the
	; traffic; and a frame of two ticks is eleven passes and two draws.
	cmp [events_seen],SCRIPT_FRAMES
	jne .commands
	cmp [traffic_down],SCRIPT_FRAMES*sizeof.Root
	jne .commands
	cmp [traffic_up],SCRIPT_FRAMES*sizeof.Events
	jne .commands
	cmp [startup_dispatches],STARTUP_DISPATCHES
	jne .commands
	cmp [dispatch_count],SCRIPT_FRAMES*FRAME_DISPATCHES
	jne .commands
	cmp [draw_count],SCRIPT_FRAMES*2
	je .report
.commands:
	fail 11
	jmp .report
.broken:
	mov [app_io_failed],1
.report:
	fastcall wsprintfW,addr report_text,<W,'proof=hits',13,10,'failure=%u',13,10,'failure_frame=%u',13,10,'frames=%u',13,10,'events=%u',13,10, \
		'solid=%u',13,10,'fired=%u',13,10,'struck=%u',13,10,'escaped=%u',13,10,'flying=%u',13,10,'kills=%u',13,10,'score=%u',13,10,'hurts=%u',13,10, \
		'particles_asked=%u',13,10,'particles_live=%u',13,10,'particle_slots=%u',13,10,'heard_shots=%u',13,10,'heard_hits=%u',13,10,'heard_bursts=%u',13,10,'heard_hurts=%u',13,10, \
		'kinds=%u',13,10,'styles=%u',13,10,'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10,'startup_dispatches=%u',13,10,'dispatches=%u',13,10,'draws=%u',13,10, \
		'worst_latency=%u',13,10,'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],ART_BAKED_SOLID,[last_fired],[last_struck],[last_escaped],[last_flying],[last_kills],[last_score],[last_hurts], \
		[last_asked],[last_live],PARTICLES,[heard_shots],[heard_hits],[heard_bursts],[heard_hurts],TABLE_KINDS,TABLE_STYLES,[traffic_down],[traffic_up], \
		[startup_dispatches],[dispatch_count],[draw_count],[worst_latency],[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage]
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
	cmp [test_mode],0
	je .show
	fastcall snapshot_start
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
	test dword [root+Root.frame],31
	jnz .messages
	fastcall wsprintfW,addr title_text,<W,'myhits proof 05: hits | %u fired, %u struck, %u missed | score %u | hurt %u times | %u particles alive | Space or left button fires, Shift or right button throws a lance, Enter for fireworks, arrows or WASD move, Esc quits'>, \
		[last_fired],[last_struck],[last_escaped],[last_score],[last_hurts],[last_live]
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

section '.data$arena' data readable writeable align 16
absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
fine dd 0.01
f_540 dd 540.0
; The ring is 96 texels across at 1.5 and centered on 1400. Its outline's
; first solid texel on the middle row is the fourth: 1400 + (3 - 48) * 1.5.
wall_near dd 1332.4
wall_far dd 1334.1		; and the sweep meets it within a texel
world_buffer GpuBuffer
header_buffer GpuBuffer
iterate name, begin,survey,direct,update,collide,resolve,drift,report,scene,particle
	name#_pipeline dq 0
end iterate
iterate name, events_seen,proof_failure,proof_failure_frame,startup_dispatches,last_latency,worst_latency, \
	last_fired,last_escaped,last_struck,last_flying,last_kills,last_hurts,last_asked,last_live,last_score, \
	heard_shots,heard_launches,heard_hits,heard_bursts,heard_hurts
	name dd 0
end iterate

; The game's tables, as the device reads them: moves, kinds, styles, sounds.
section '.rdata$arena_tables' data readable align 16
table_moves:
	game_tables
table_kinds:
	kinds_table
table_styles:
	game_styles
table_sounds:
	game_sounds
TABLE_BYTES := $ - table_moves
assert TABLE_BYTES = TABLE_MOVES * sizeof.Move + TABLE_KINDS * sizeof.Kind + TABLE_STYLES * sizeof.Style + TABLE_SOUNDS * sizeof.Recipe

section '.rdata$arena_spirv' data readable align 4
iterate <name,module>, develop_code,develop, chart_code,chart, census_code,census, begin_code,begin, survey_code,survey, direct_code,direct, update_code,update, \
	collide_code,collide, resolve_code,resolve, drift_code,drift, report_code,report, scene_vertex_code,scene_vertex, scene_fragment_code,scene_fragment, \
	particle_vertex_code,particle_vertex, particle_fragment_code,particle_fragment
	align 4
	name file 'build\myhits_hits_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
