; Proof 06, sound: the device renders the bank from the recipes of tables.inc,
; and a sound asked for in one frame's events is on a voice when the next
; frame begins.
;
;	build\myhits_sound.exe			a board of the sounds: Space or the left
;						button plays the shot, Shift or the right
;						button the launch, Enter the rest in turn,
;						each where the mouse is, left to right
;	build\myhits_sound.exe --self-test	100 scripted frames, every claim checked,
;						and not a sound made
;
; What each check settles is in ..\README.md.
MACHINE_NAME equ 'myhits proof 06: sound'
MACHINE_TAG equ 'sound'
MACHINE_SNAPSHOT := 1
include '..\..\..\common\machine.inc'
include '..\..\tables.inc'
include '..\..\..\common\audio.inc'

SCRIPT_FRAMES := 100
SCRIPT_PLAYS := 25			; 1 + 1 + 1 + 1 + 1, then twenty in a row
STATE_BYTES := 64
public mainCRTStartup

; The world's header, which the CPU writes once: World in board.slang.
boundary BoardWorld
	block tables,Tables
	ptr bank,float
	ptr state,State
end boundary

section '.text$board' code readable executable align 16

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

proc create_world uses rsi rdi
	mov [failure_stage],3
	require_ok fastcall create_buffer,addr state_buffer,STATE_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_DEVICE
	; The CPU writes the header and the recipes once, into host-visible memory.
	require_ok fastcall create_buffer,addr header_buffer,sizeof.BoardWorld+TABLE_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_UPLOAD
	; And the device writes the bank once where the CPU, and so the voices, can read it.
	require_ok fastcall create_buffer,addr bank_buffer,BANK_SAMPLES*4,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_READBACK
	mov rdi,[header_buffer.mapped]
	xor eax,eax
	mov ecx,sizeof.BoardWorld
	rep stosb
	mov rdi,[header_buffer.mapped]
	mov rax,[header_buffer.address]
	add rax,sizeof.BoardWorld
	mov [rdi+BoardWorld.tables+Tables.sounds],rax
	mov dword [rdi+BoardWorld.tables+Tables.sound_count],TABLE_SOUNDS
	mov rax,[bank_buffer.address]
	mov [rdi+BoardWorld.bank],rax
	mov rax,[state_buffer.address]
	mov [rdi+BoardWorld.state],rax
	add rdi,sizeof.BoardWorld
	lea rsi,[table_sounds]
	mov ecx,TABLE_BYTES
	rep movsb
	require_ok fastcall flush_buffer,addr header_buffer
	mov rax,[header_buffer.address]
	mov [root+Root.world],rax
	iterate name, render,examine,direct
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	require_ok fastcall machine_graphics,addr wave_vertex_code,wave_vertex_code.size,addr wave_fragment_code,wave_fragment_code.size,BLEND_PREMULTIPLIED,addr wave_pipeline
	; The device makes the bank. Nothing is uploaded but the recipes.
	require_ok fastcall machine_serial_open
	fastcall machine_dispatch,[render_pipeline],(BANK_SAMPLES+63)/64
	fastcall machine_settle
	fastcall machine_dispatch,[examine_pipeline],1
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
	iterate name, render,examine,direct,wave
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	fastcall destroy_buffer,addr bank_buffer
	fastcall destroy_buffer,addr header_buffer
	fastcall destroy_buffer,addr state_buffer
	ret
endp

; The device's bank, as it rendered it, for the script to hold to its own and
; to write out as something a player can open.
proc write_bank uses rbx
	fastcall CreateFileW,<W,'build\myhits_sound.bank.bin'>,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .failed
	mov rbx,rax
	fastcall WriteFile,rbx,[bank_buffer.mapped],BANK_SAMPLES*4,addr written,0
	test eax,eax
	jz .close_failed
	cmp [written],BANK_SAMPLES*4
	jne .close_failed
	fastcall CloseHandle,rbx
	ret
.close_failed:
	fastcall CloseHandle,rbx
.failed:
	mov [app_io_failed],1
	ret
endp

; One frame: the last one's events in (and its sounds out), Root down, one
; pass, one draw. When each frame read its controls is kept, to time a sound by.
proc play_frame
	fastcall machine_await
	test eax,eax
	jz .stopped
	fastcall machine_sample
	mov eax,[root+Root.frame]
	and eax,EVENT_SLOTS-1
	lea rdx,[frame_clock]
	lea rcx,[rdx+rax*8]
	fastcall QueryPerformanceCounter,rcx
	fastcall machine_open
	cmp eax,1
	jne .skipped
	fastcall machine_dispatch,[direct_pipeline],1
	fastcall machine_canvas
	fastcall draw_world
	; The scripted run leaves a picture of itself: the bank, with the hit just asked for.
	iterate when, 31
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
	fastcall machine_draw,[wave_pipeline],6,TABLE_SOUNDS
	ret
endp

; A finished frame's events: its sounds go to the voices now, which is when
; the next frame begins.
proc consume_events uses rbx rsi rdi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	mov edi,[audio_plays]
	fastcall audio_events,rbx,addr table_sounds,[bank_buffer.mapped]
	sub edi,[audio_plays]
	neg edi				; sounds this frame put on voices
	jz .latency
	; From the frame's controls being read to its sound being on a voice.
	fastcall QueryPerformanceCounter,addr clock_now
	mov ecx,esi
	and ecx,EVENT_SLOTS-1
	lea rdx,[frame_clock]
	mov rax,[clock_now]
	sub rax,[rdx+rcx*8]
	mov ecx,1000000
	mul rcx
	div [clock_frequency]
	mov [last_delay],eax
	cmp eax,[worst_delay]
	jbe .latency
	mov [worst_delay],eax
.latency:
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
	; 2: the device examined its own bank and found nothing: every sound
	; begins at silence, ends near it, is never louder than its gain, and does
	; get loud.
	mov eax,[rbx+Events.debug]
	or eax,[rbx+Events.debug+4]
	or eax,[rbx+Events.debug+8]
	or eax,[rbx+Events.debug+12]
	jz .bank
	fail 2
.bank:
	; 3: a frame's events ask for what its script says, and each sound asked
	; for went to a voice as the next frame began: one voice a sound, however
	; many times it was asked for.
	xor eax,eax
	iterate <when,which,times>, 10,SOUND_SHOT,1, 20,SOUND_LAUNCH,1, 30,SOUND_HIT,5, 40,SOUND_BURST,1, 50,SOUND_HURT,1
		cmp esi,when
		jne .not_#when
		cmp dword [rbx+Events.sound+which*sizeof.Trigger+Trigger.count],times
		jne .asked_wrong
		mov eax,1
	.not_#when:
	end iterate
	cmp esi,60
	jb .voices
	cmp esi,80
	jae .voices
	cmp dword [rbx+Events.sound+SOUND_SHOT*sizeof.Trigger+Trigger.count],1
	jne .asked_wrong
	mov eax,1
.voices:
	cmp edi,eax
	je .asked
.asked_wrong:
	fail 3
.asked:
	; 4: five hits in one frame, at 200, 400, 600, 800 and 1000, are one voice
	; at their mean, 600: five sixteenths of the way across, so 0.882 of it
	; goes left and 0.471 right; and at twice one hit's level, which is as
	; loud as many get.
	cmp esi,30
	jne .done
	cmp dword [rbx+Events.sound+SOUND_HIT*sizeof.Trigger+Trigger.pan],-1800
	jne .pan_wrong
	unless_near [audio_matrix],pan_left,milli,.pan_wrong
	unless_near [audio_matrix+4],pan_right,milli,.pan_wrong
	jmp .done
.pan_wrong:
	fail 4
.done:
	inc [events_seen]
	ret
endp

; 100 frames by the script, then the totals no frame could show alone.
proc scripted_run uses rbx rsi
	fastcall write_bank
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
	; 5: twenty-five sounds went to sixteen voices, round and round, and no
	; voice refused one.
	cmp [audio_plays],SCRIPT_PLAYS
	jne .ring_wrong
	cmp [audio_failures],0
	je .ring
.ring_wrong:
	fail 5
.ring:
	; 6: where there is a device, the engine took every sample it was given:
	; soon no voice has anything left to play.
	fastcall audio_latency
	mov [engine_latency],eax
	fastcall audio_idle
	mov [still_queued],eax
	test eax,eax
	jz .played
	fail 6
.played:
	; 7: every frame's events were read; Root and Events were all the traffic
	; of a frame; and a frame is one pass and one draw.
	cmp [events_seen],SCRIPT_FRAMES
	jne .commands
	cmp [traffic_down],SCRIPT_FRAMES*sizeof.Root
	jne .commands
	cmp [traffic_up],SCRIPT_FRAMES*sizeof.Events
	jne .commands
	cmp [startup_dispatches],2
	jne .commands
	cmp [dispatch_count],SCRIPT_FRAMES
	jne .commands
	cmp [draw_count],SCRIPT_FRAMES
	je .report
.commands:
	fail 7
	jmp .report
.broken:
	mov [app_io_failed],1
.report:
	fastcall wsprintfW,addr report_text,<W,'proof=sound',13,10,'failure=%u',13,10,'failure_frame=%u',13,10,'frames=%u',13,10,'events=%u',13,10, \
		'sounds=%u',13,10,'bank_samples=%u',13,10,'rate=%u',13,10,'device=%u',13,10,'voices=%u',13,10,'plays=%u',13,10,'refused=%u',13,10,'still_queued=%u',13,10, \
		'engine_latency_samples=%u',13,10,'worst_delay_microseconds=%u',13,10,'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10,'startup_dispatches=%u',13,10, \
		'dispatches=%u',13,10,'draws=%u',13,10,'worst_latency=%u',13,10,'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],TABLE_SOUNDS,BANK_SAMPLES,SOUND_RATE,[audio_ready],AUDIO_VOICES,[audio_plays],[audio_failures],[still_queued], \
		[engine_latency],[worst_delay],[traffic_down],[traffic_up],[startup_dispatches],[dispatch_count],[draw_count],[worst_latency],[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage]
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
	fastcall audio_latency
	mov [engine_latency],eax
	fastcall wsprintfW,addr title_text,<W,'myhits proof 06: sound | %u sounds in %u samples | a device: %u | %u played | the last was on its voice %u microseconds after its controls were read, and the engine adds %u samples | Space, Shift, Enter or the mouse buttons play, Esc quits'>, \
		TABLE_SOUNDS,BANK_SAMPLES,[audio_ready],[audio_plays],[last_delay],[engine_latency]
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

section '.data$board' data readable writeable align 16
absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
milli dd 0.001
pan_left dd 0.88192			; cos and sin of five sixteenths of a quarter turn,
pan_right dd 0.47140			; at twice a single sound's level of a half
state_buffer GpuBuffer
header_buffer GpuBuffer
bank_buffer GpuBuffer
frame_clock rq EVENT_SLOTS
iterate name, render,examine,direct,wave
	name#_pipeline dq 0
end iterate
iterate name, events_seen,proof_failure,proof_failure_frame,startup_dispatches,last_latency,worst_latency,last_delay,worst_delay,engine_latency,still_queued
	name dd 0
end iterate

; The recipes, as the device and the voices read them.
section '.rdata$board_tables' data readable align 16
table_sounds:
	game_sounds
TABLE_BYTES := $ - table_sounds
assert TABLE_BYTES = TABLE_SOUNDS * sizeof.Recipe

section '.rdata$board_spirv' data readable align 4
iterate <name,module>, render_code,render, examine_code,examine, direct_code,direct, wave_vertex_code,wave_vertex, wave_fragment_code,wave_fragment
	align 4
	name file 'build\myhits_sound_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
