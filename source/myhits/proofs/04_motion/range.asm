; Proof 04, motion: every easing curve on the wall, and a range where bodies
; run the programs of tables.inc at a fixed tick: shots, the missile, three
; hostiles, and the level itself slowing to a stop for what is anchored to it.
;
;	build\myhits_motion.exe			watch it; Space or the left button fires,
;						Shift or the right button launches a pair
;	build\myhits_motion.exe --self-test	200 scripted frames, every claim checked
;
; What each check settles is in ..\README.md.
MACHINE_NAME equ 'myhits proof 04: motion'
MACHINE_TAG equ 'motion'
MACHINE_SNAPSHOT := 1
include '..\..\machine.inc'
include '..\..\pictures.inc'
include '..\..\tables.inc'

; These four are range.slang's.
CAPACITY := 256
TRACE := 128
SAMPLES := 65
INSTANCES := 160 + CAPACITY + TRACE + 2 * EASE_CURVES + 4
SCRIPT_FRAMES := 200
FRAME_DISPATCHES := SCRIPT_TICKS * 2 + 1	; the director and the bodies each tick, then the report
STARTUP_DISPATCHES := PICTURES_PASSES + 1
public mainCRTStartup

; The world's header, which the CPU writes once: World in range.slang.
boundary RangeWorld
	block pictures,Pictures
	block tables,Tables
	ptr bodies,Body
	ptr game,Game
	ptr trace,float2
	ptr curves,float
	u32 capacity
	u32 pad
end boundary
GAME_BYTES := 96
WORLD_BYTES := GAME_BYTES + 2 * CAPACITY * BODY_BYTES + TRACE * 8
CURVES_BYTES := EASE_CURVES * SAMPLES * 4

section '.text$range' code readable executable align 16

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
; Leave to `target` unless the float at `place` is within `slack` of the one at `value`.
macro unless_near place*,value*,slack*,target*
	movss xmm0,place
	subss xmm0,[value]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[slack]
	ja target
end macro

proc create_world uses rsi rdi
	mov [failure_stage],3
	; Only shaders touch the world: device-local memory, reached by address.
	require_ok fastcall create_buffer_domain,addr world_buffer,WORLD_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1,BUFFER_DEVICE
	; The CPU writes the header and the tables once, into host-visible memory.
	require_ok fastcall create_buffer_domain,addr header_buffer,sizeof.RangeWorld+TABLE_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1,BUFFER_UPLOAD
	; And the device writes the curves once where the CPU can read them.
	require_ok fastcall create_buffer_domain,addr curves_buffer,CURVES_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1,BUFFER_READBACK
	mov rdi,[header_buffer.mapped]
	require_ok fastcall pictures_create,rdi
	mov rax,[header_buffer.address]
	add rax,sizeof.RangeWorld
	mov [rdi+RangeWorld.tables+Tables.moves],rax
	add rax,TABLE_MOVES*sizeof.Move
	mov [rdi+RangeWorld.tables+Tables.kinds],rax
	mov dword [rdi+RangeWorld.tables+Tables.move_count],TABLE_MOVES
	mov dword [rdi+RangeWorld.tables+Tables.kind_count],TABLE_KINDS
	mov rax,[world_buffer.address]
	mov [rdi+RangeWorld.game],rax
	add rax,GAME_BYTES
	mov [rdi+RangeWorld.bodies],rax
	add rax,2*CAPACITY*BODY_BYTES
	mov [rdi+RangeWorld.trace],rax
	mov rax,[curves_buffer.address]
	mov [rdi+RangeWorld.curves],rax
	mov dword [rdi+RangeWorld.capacity],CAPACITY
	mov dword [rdi+RangeWorld.pad],0
	add rdi,sizeof.RangeWorld
	lea rsi,[table_moves]
	mov ecx,TABLE_BYTES
	rep movsb
	require_ok fastcall flush_buffer,addr header_buffer
	mov rax,[header_buffer.address]
	mov [root+Root.world],rax
	iterate name, examine,direct,update,report
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	require_ok fastcall machine_graphics,addr scene_vertex_code,scene_vertex_code.size,addr scene_fragment_code,scene_fragment_code.size,BLEND_PREMULTIPLIED,addr scene_pipeline
	require_ok fastcall machine_graphics,addr plot_vertex_code,plot_vertex_code.size,addr plot_fragment_code,plot_fragment_code.size,BLEND_PREMULTIPLIED,addr plot_pipeline
	require_ok fastcall pictures_develop
	require_ok fastcall machine_serial_open
	fastcall machine_dispatch,[examine_pipeline],(EASE_CURVES*SAMPLES+63)/64
	require_ok fastcall machine_serial_close
	require_ok fastcall invalidate_buffer,addr curves_buffer
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
	iterate name, examine,direct,update,report,scene,plot
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	fastcall pictures_release
	fastcall destroy_buffer,addr curves_buffer
	fastcall destroy_buffer,addr header_buffer
	fastcall destroy_buffer,addr world_buffer
	ret
endp

; The device's curves, as it sampled them, for the script to hold to its own.
proc write_curves uses rbx
	fastcall CreateFileW,<W,'build\myhits_motion.curves.bin'>,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .failed
	mov rbx,rax
	fastcall WriteFile,rbx,[curves_buffer.mapped],CURVES_BYTES,addr written,0
	test eax,eax
	jz .close_failed
	cmp [written],CURVES_BYTES
	jne .close_failed
	fastcall CloseHandle,rbx
	ret
.close_failed:
	fastcall CloseHandle,rbx
.failed:
	mov [app_io_failed],1
	ret
endp

; One frame: the last one's events in, Root down, then as many ticks as real
; time has earned (a director and every body, each), the report, two draws.
proc play_frame uses rbx
	fastcall machine_await
	test eax,eax
	jz .stopped
	test dword [root+Root.flags],ROOT_SCRIPTED
	jz .sample
	; The script: right for ten frames; a pair of missiles at frame 20; fire
	; held from 60 to 99; the crosshair where the missiles are to go.
	mov dword [root+Root.move],0
	mov dword [root+Root.move+4],0
	mov dword [root+Root.held],0
	mov dword [root+Root.pressed],0
	mov eax,[aim_x]
	mov dword [root+Root.aim],eax
	mov eax,[aim_y]
	mov dword [root+Root.aim+4],eax
	mov eax,[root+Root.frame]
	cmp eax,10
	jae .launch
	mov dword [root+Root.move],1.0
.launch:
	cmp eax,20
	jne .fire
	mov dword [root+Root.held],BUTTON_SECOND
	mov dword [root+Root.pressed],BUTTON_SECOND
.fire:
	cmp eax,60
	jb .sample
	cmp eax,99
	ja .sample
	mov dword [root+Root.held],BUTTON_FIRE
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
	dec ebx
	jmp .tick
.ticked:
	fastcall machine_dispatch,[report_pipeline],1
	fastcall machine_canvas
	fastcall draw_world
	; The scripted run leaves pictures of itself: the missiles turned to the crosshair, shots in flight, the level stopped.
	iterate when, 45,62,100
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
	fastcall machine_draw,[plot_pipeline],6,EASE_CURVES
	fastcall machine_draw,[scene_pipeline],6,INSTANCES
	ret
endp

; A finished frame's events. Interactive runs show them; scripted runs hold
; every one to what the tables, the script and the shaders make inevitable.
proc consume_events uses rbx rsi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	iterate <name,offset>, last_ticks,Events.reserved, last_fired,Events.reserved+4, last_escaped,Events.reserved+8, last_flying,Events.reserved+12, \
		last_pace,Events.reserved+16, last_scroll,Events.reserved+20
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
	; 2: the device examined its own curves and found nothing: each is 0 at 0
	; and 1 at 1 exactly, an OUT is its IN turned about, an INOUT passes through
	; the middle, none but bounce goes back, and only back and elastic pass outside.
	mov eax,[rbx+Events.debug]
	or eax,[rbx+Events.debug+4]
	or eax,[rbx+Events.debug+8]
	or eax,[rbx+Events.debug+12]
	jz .curves
	fail 2
.curves:
	; 3: a scripted frame is two ticks, and the device has counted every one.
	lea eax,[rsi*2+2]
	cmp [rbx+Events.reserved],eax
	je .ticks
	fail 3
.ticks:
	; 4: the controls of frame N moved the ship in frame N, through both ticks.
	lea eax,[rsi+1]
	mov edx,10
	cmp eax,edx
	cmova eax,edx
	imul eax,10
	add eax,760
	cvtsi2ss xmm0,eax
	subss xmm0,dword [rbx+Events.reserved+32]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	ja .ship_wrong
	unless_near dword [rbx+Events.reserved+36],f_540,tolerance,.ship_wrong
	jmp .ship
.ship_wrong:
	fail 4
.ship:
	; 5: the missile's first move, 42 ticks of OUT_CUBIC, ends exactly at its
	; offset from where it was launched: nothing accumulated on the way.
	cmp esi,40
	jne .offset
	cmp dword [rbx+Events.reserved+40],KIND_MISSILE
	jne .offset_wrong
	cmp dword [rbx+Events.reserved+60],1
	jne .offset_wrong
	unless_near dword [rbx+Events.reserved+44],f_930,fine,.offset_wrong
	unless_near dword [rbx+Events.reserved+48],f_480,fine,.offset_wrong
	jmp .offset
.offset_wrong:
	fail 5
.offset:
	; 13: its twin goes twice as quick. Its offset is 21 ticks and not 42: it
	; is still in it at frame 29, and at frame 30 it is done, exactly at its
	; own offset, which is the first one's mirrored.
	at_frame 29,Events.report,0,.tempo_wrong
	cmp esi,30
	jne .tempo
	cmp dword [rbx+Events.report],1
	jne .tempo_wrong
	unless_near dword [rbx+Events.report+4],f_930,fine,.tempo_wrong
	unless_near dword [rbx+Events.report+8],f_600,fine,.tempo_wrong
	jmp .tempo
.tempo_wrong:
	fail 13
.tempo:
	; 6: its second, 18 ticks of INOUT_SINE, leaves it facing the crosshair.
	cmp esi,49
	jne .faced
	cmp dword [rbx+Events.reserved+60],2
	jne .face_wrong
	mov eax,[rbx+Events.reserved+44]
	mov [faced_x],eax
	mov eax,[rbx+Events.reserved+48]
	mov [faced_y],eax
	mov eax,[rbx+Events.reserved+52]
	mov [faced_angle],eax
	movss xmm0,[aim_y]
	subss xmm0,[faced_y]
	movss [scratch],xmm0
	movss xmm0,[aim_x]
	subss xmm0,[faced_x]
	movss [scratch+4],xmm0
	fld dword [scratch]
	fld dword [scratch+4]
	fpatan
	fstp dword [scratch]
	unless_near [faced_angle],scratch,milli,.face_wrong
	jmp .faced
.face_wrong:
	fail 6
.faced:
	; 7: its third, 60 ticks of IN_EXPO, brings it to speed on the line to the
	; crosshair, and there the program ends and it coasts.
	cmp esi,79
	jne .thrust
	cmp dword [rbx+Events.reserved+60],3
	jne .thrust_wrong
	unless_near dword [rbx+Events.reserved+56],f_2400,fine,.thrust_wrong
	unless_near dword [rbx+Events.reserved+52],faced_angle,milli,.thrust_wrong
	movss xmm0,dword [rbx+Events.reserved+44]
	subss xmm0,[faced_x]
	ucomiss xmm0,[f_100]
	jbe .thrust_wrong
	movss xmm1,dword [rbx+Events.reserved+48]
	subss xmm1,[faced_y]
	movss xmm2,[aim_x]
	subss xmm2,[faced_x]
	movss xmm3,[aim_y]
	subss xmm3,[faced_y]
	mulss xmm0,xmm3
	mulss xmm1,xmm2
	subss xmm0,xmm1
	andps xmm0,xword [absolute]
	ucomiss xmm0,[f_300]		; half a unit off a line some 600 long
	jbe .thrust
.thrust_wrong:
	fail 7
.thrust:
	; 8: the level's pace is eased too, and what rides the level rides it
	; exactly: the anchor and the scroll always sum to where the anchor began;
	; for the forty frames the level stands, the scroll does not change at all;
	; and the anchor has stopped where the eased pace puts it.
	cmp dword [rbx+Events.reserved+28],0
	je .rode
	movss xmm0,dword [rbx+Events.reserved+24]
	addss xmm0,dword [rbx+Events.reserved+20]
	subss xmm0,[f_1760]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	ja .pace_wrong
.rode:
	cmp esi,80
	jb .moving
	cmp esi,119
	ja .moving
	mov eax,[rbx+Events.reserved+20]
	cmp eax,[scroll_before]
	jne .pace_wrong
	cmp dword [rbx+Events.reserved+16],0
	jne .pace_wrong
	cmp esi,100
	jne .moving
	unless_near dword [rbx+Events.reserved+24],f_1501,tolerance,.pace_wrong
	jmp .moving
.pace_wrong:
	fail 8
.moving:
	mov eax,[rbx+Events.reserved+20]
	mov [scroll_before],eax
	; 10, in part: the draw pulls as many sprites as the shaders lay out.
	cmp dword [rbx+Events.score],INSTANCES
	je .done
	fail 10
.done:
	inc [events_seen]
	ret
endp

; 11: a press comes from its message, not from where the key is when the
; frame looks. One shorter than a frame is still pressed, and held, for that
; frame; the keyboard repeating a key is not a press; the pad's presses are
; the edges of what it holds.
proc press_check
	mov dword [root+Root.held],0
	fastcall window_proc,[window],WM_KEYDOWN,VK_SPACE,0
	fastcall merge_presses,0
	cmp dword [root+Root.pressed],BUTTON_FIRE
	jne .wrong
	cmp dword [root+Root.held],BUTTON_FIRE
	jne .wrong
	mov dword [root+Root.held],0
	fastcall merge_presses,0
	cmp dword [root+Root.pressed],0
	jne .wrong
	fastcall window_proc,[window],WM_KEYDOWN,VK_SPACE,40000000h
	fastcall window_proc,[window],WM_RBUTTONDOWN,0,0
	fastcall merge_presses,BUTTON_START
	cmp dword [root+Root.pressed],BUTTON_SECOND or BUTTON_START
	jne .wrong
	mov dword [root+Root.held],0
	fastcall merge_presses,BUTTON_START
	cmp dword [root+Root.pressed],0
	jne .wrong
	fastcall merge_presses,0
	ret
.wrong:
	fail 11
	ret
endp

; 12: real time is paid out in whole ticks, and a stall is not chased. A
; second behind earns the limit and no more, and leaves nothing owed; the
; frame after it, sampled at once, earns none.
proc pace_check
	and dword [root+Root.flags],not ROOT_SCRIPTED
	fastcall QueryPerformanceCounter,addr clock_last
	mov rax,[clock_frequency]
	sub [clock_last],rax
	fastcall machine_sample
	cmp dword [root+Root.ticks],TICKS_LIMIT
	jne .wrong
	cmp dword [root+Root.blend],0
	jne .wrong
	fastcall machine_sample
	cmp dword [root+Root.ticks],0
	jne .wrong
	or dword [root+Root.flags],ROOT_SCRIPTED
	ret
.wrong:
	or dword [root+Root.flags],ROOT_SCRIPTED
	fail 12
	ret
endp

; 200 frames by the script, then the totals no frame could show alone.
proc scripted_run uses rbx rsi
	fastcall write_curves
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
	; 9: accuracy is counted where it happens. Fourteen shots and two missiles
	; were fired; with nothing to hit, every one left the playfield and none is
	; still flying. And the level has come as far as its eased pace says.
	cmp [last_fired],16
	jne .count_wrong
	cmp [last_escaped],16
	jne .count_wrong
	cmp [last_flying],0
	jne .count_wrong
	unless_near [last_scroll],f_520,tolerance,.count_wrong
	jmp .count
.count_wrong:
	fail 9
.count:
	; 10: every frame's events were read; Root and Events were all the
	; traffic; and a frame of two ticks is five passes and two draws.
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
	je .presses
.commands:
	fail 10
.presses:
	fastcall press_check
	fastcall pace_check
	jmp .report
.broken:
	mov [app_io_failed],1
.report:
	cvtss2si eax,[last_scroll]
	mov [title_scroll],eax
	fastcall wsprintfW,addr report_text,<W,'proof=motion',13,10,'failure=%u',13,10,'failure_frame=%u',13,10,'frames=%u',13,10,'events=%u',13,10, \
		'tick_rate=%u',13,10,'ticks=%u',13,10,'curves=%u',13,10,'samples=%u',13,10,'kinds=%u',13,10,'moves=%u',13,10,'bodies=%u',13,10,'instances=%u',13,10, \
		'fired=%u',13,10,'escaped=%u',13,10,'flying=%u',13,10,'scroll=%u',13,10,'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10, \
		'startup_dispatches=%u',13,10,'dispatches=%u',13,10,'draws=%u',13,10,'worst_latency=%u',13,10,'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],TICK_RATE,[last_ticks],EASE_CURVES,SAMPLES,TABLE_KINDS,TABLE_MOVES,CAPACITY,INSTANCES, \
		[last_fired],[last_escaped],[last_flying],[title_scroll],[traffic_down],[traffic_up],[startup_dispatches],[dispatch_count],[draw_count],[worst_latency], \
		[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage]
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
	cvtss2si eax,[last_pace]
	mov [title_pace],eax
	fastcall wsprintfW,addr title_text,<W,'myhits proof 04: motion | %u ticks a second, %u this frame | the level moves at %u | %u fired, %u missed | Space or left button fires, Shift or right button launches, arrows or WASD move, Esc quits'>, \
		TICK_RATE,[root+Root.ticks],[title_pace],[last_fired],[last_escaped]
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

section '.data$range' data readable writeable align 16
absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
tolerance dd 0.05
fine dd 0.01
milli dd 0.001
aim_x dd 1500.0			; the script's crosshair
aim_y dd 300.0
f_100 dd 100.0
f_300 dd 300.0
f_480 dd 480.0			; 540 - 60: the missile's offset, up
f_520 dd 520.0			; the scroll after 400 ticks: 240 a second for 260 of them
f_540 dd 540.0
f_600 dd 600.0			; 540 + 60: the twin's offset, down
f_930 dd 930.0			; 760 + 100 + 30 + 40
f_1501 dd 1501.0		; 1760 less 129.5 ticks at 240 a second
f_1760 dd 1760.0
f_2400 dd 2400.0
scratch dd 0,0
faced_x dd 0
faced_y dd 0
faced_angle dd 0
world_buffer GpuBuffer
header_buffer GpuBuffer
curves_buffer GpuBuffer
iterate name, examine,direct,update,report,scene,plot
	name#_pipeline dq 0
end iterate
iterate name, events_seen,proof_failure,proof_failure_frame,startup_dispatches,last_latency,worst_latency,title_pace,title_scroll,scroll_before, \
	last_ticks,last_fired,last_escaped,last_flying,last_pace,last_scroll
	name dd 0
end iterate

; The game's tables, as the device reads them: the moves, then the kinds.
section '.rdata$range_tables' data readable align 16
table_moves:
	game_tables
table_kinds:
	kinds_table
TABLE_BYTES := $ - table_moves
assert TABLE_BYTES = TABLE_MOVES * sizeof.Move + TABLE_KINDS * sizeof.Kind

section '.rdata$range_spirv' data readable align 4
iterate <name,module>, develop_code,develop, chart_code,chart, census_code,census, examine_code,examine, direct_code,direct, update_code,update, report_code,report, \
	scene_vertex_code,scene_vertex, scene_fragment_code,scene_fragment, plot_vertex_code,plot_vertex, plot_fragment_code,plot_fragment
	align 4
	name file 'build\myhits_motion_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
