; Proof 02, the spine: the whole CPU-GPU boundary of the plan, end to end, on
; a device. 1024 motes drift; the controls move one of them.
;
;	build\myhits_spine.exe			watch it; arrows or WASD move the white mote
;	build\myhits_spine.exe --self-test	120 scripted frames, every claim checked
;
; What each check settles is in ..\README.md.
MACHINE_NAME equ 'myhits proof 02: spine'
MACHINE_TAG equ 'spine'
include '..\..\machine.inc'

MOTES := 1024
SCRIPT_FRAMES := 120
SCRIPT_LEG := 30			; frames moving right, then as many moving down
public mainCRTStartup

; The world's header, which the CPU writes once: World in spine.slang.
boundary SpineWorld
	ptr motes,Mote
	ptr texels,uint
	ptr state,State
	u32 count
	u32 pad
end boundary
STATE_BYTES := 16
MOTE_BYTES := 24
WORLD_BYTES := STATE_BYTES + MOTES * MOTE_BYTES + 1024 * 4

section '.text$spine' code readable executable align 16

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

proc create_world uses rdi
	mov [failure_stage],3
	; Only shaders touch the world: device-local memory, reached by address.
	require_ok fastcall create_device_buffer,addr world_buffer,WORLD_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1
	; The CPU writes the header once, straight into host-visible memory.
	require_ok fastcall create_buffer,addr header_buffer,sizeof.SpineWorld,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1
	mov rdi,[header_buffer.mapped]
	mov rax,[world_buffer.address]
	mov [rdi+SpineWorld.state],rax
	lea rdx,[rax+STATE_BYTES]
	mov [rdi+SpineWorld.motes],rdx
	lea rdx,[rax+STATE_BYTES+MOTES*MOTE_BYTES]
	mov [rdi+SpineWorld.texels],rdx
	mov dword [rdi+SpineWorld.count],MOTES
	mov dword [rdi+SpineWorld.pad],0
	require_ok fastcall flush_buffer,addr header_buffer
	mov rax,[header_buffer.address]
	mov [root+Root.world],rax
	iterate name, seed,direct,advance
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	require_ok fastcall machine_graphics,addr vertex_spirv,vertex_spirv.size,addr fragment_spirv,fragment_spirv.size,BLEND_OPAQUE,addr mote_pipeline
	; The device fills the world. Nothing is uploaded.
	require_ok fastcall machine_serial_open
	fastcall machine_dispatch,[seed_pipeline],16
	require_ok fastcall machine_serial_close
	mov [dispatch_count],0
	mov [failure_stage],0
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc release_world
	iterate name, seed,direct,advance,mote
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	fastcall destroy_buffer,addr header_buffer
	fastcall destroy_buffer,addr world_buffer
	ret
endp

; One frame: the last one's events in, Root down, two compute passes, one draw.
proc play_frame
	fastcall machine_await
	test eax,eax
	jz .stopped
	test dword [root+Root.flags],ROOT_SCRIPTED
	jz .sample
	; The script: right for a leg, down for a leg, then still.
	mov dword [root+Root.move],0
	mov dword [root+Root.move+4],0
	mov eax,[root+Root.frame]
	cmp eax,SCRIPT_LEG
	jae .down
	mov dword [root+Root.move],1.0
	jmp .sample
.down:
	cmp eax,2*SCRIPT_LEG
	jae .sample
	mov dword [root+Root.move+4],1.0
.sample:
	fastcall machine_sample
	fastcall machine_open
	cmp eax,1
	jne .skipped
	fastcall machine_dispatch,[direct_pipeline],1
	fastcall machine_settle
	fastcall machine_dispatch,[advance_pipeline],MOTES/64
	fastcall machine_canvas
	fastcall machine_draw,[mote_pipeline],6,MOTES
	fastcall machine_close
	ret
.skipped:
	; 2: no image this turn, which is not a failure.
	shr eax,1
.stopped:
	ret
endp

; A finished frame's events. Interactive runs show them; scripted runs hold
; every one to what the script and the shaders make inevitable.
proc consume_events uses rbx rsi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	mov eax,[rbx+Events.score]
	mov [last_shaded],eax
	mov eax,[rbx+Events.sound+Trigger.count]
	mov [last_near],eax
	mov eax,[root+Root.frame]
	sub eax,esi
	mov [last_latency],eax
	cmp eax,[worst_latency]
	jbe .counted
	mov [worst_latency],eax
.counted:
	cmp [test_mode],0
	je .done
	; 1: events arrive once each, in frame order.
	cmp esi,[events_seen]
	je .order
	fail 1
.order:
	; 2: every mote's atomic add reached host-visible memory, none lost.
	cmp dword [rbx+Events.debug],MOTES
	je .host
	fail 2
.host:
	; 3: every atomic add of every earlier frame is in device-local memory.
	imul eax,esi,MOTES
	cmp [rbx+Events.debug+4],eax
	je .device
	fail 3
.device:
	; 4: the controls of frame N moved the player in frame N.
	lea eax,[rsi+1]
	mov edx,SCRIPT_LEG
	cmp eax,edx
	cmova eax,edx
	imul eax,10
	add eax,480
	cvtsi2ss xmm0,eax
	subss xmm0,dword [rbx+Events.debug+8]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	ja .moved_wrong
	lea eax,[rsi+1-SCRIPT_LEG]
	xor ecx,ecx
	test eax,eax
	cmovs eax,ecx
	cmp eax,edx
	cmova eax,edx
	imul eax,10
	add eax,540
	cvtsi2ss xmm0,eax
	subss xmm0,dword [rbx+Events.debug+12]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	jbe .moved
.moved_wrong:
	fail 4
.moved:
	; 5: the pulled draw shaded discs: more than nothing, less than its squares.
	mov eax,[rbx+Events.score]
	cmp eax,SHADED_FLOOR
	jb .shaded_wrong
	cmp eax,SHADED_CEILING
	jbe .shaded
.shaded_wrong:
	fail 5
.shaded:
	; 6: in hand when the very next frame begins, never later.
	cmp [last_latency],1
	je .latency
	fail 6
.latency:
	; 7: a trigger's pan is a sum of offsets no wider than the playfield.
	mov eax,[rbx+Events.sound+Trigger.pan]
	cdq
	xor eax,edx
	sub eax,edx
	imul edx,[rbx+Events.sound+Trigger.count],PLAYFIELD_WIDTH/2
	cmp eax,edx
	jbe .done
	fail 7
.done:
	inc [events_seen]
	ret
endp

; 120 frames by the script, then the totals no frame could show alone.
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
	; 8: every frame's events were read. 9, 10: and that was all the traffic.
	cmp [events_seen],SCRIPT_FRAMES
	je .all
	fail 8
.all:
	cmp [traffic_down],SCRIPT_FRAMES*sizeof.Root
	je .down
	fail 9
.down:
	cmp [traffic_up],SCRIPT_FRAMES*sizeof.Events
	je .up
	fail 10
.up:
	; 11: two dispatches and one draw a frame, and nothing else.
	cmp [dispatch_count],2*SCRIPT_FRAMES
	jne .commands
	cmp [draw_count],SCRIPT_FRAMES
	je .shape
.commands:
	fail 11
.shape:
	; 12: a window of another shape keeps the playfield's, inside bars.
	mov ebx,[last_shaded]
	fastcall resize_window,1200,500
	fastcall play_frame
	test eax,eax
	jz .broken
	fastcall machine_drain
	test eax,eax
	jz .broken
	mov esi,SCRIPT_FRAMES
	cvtss2si eax,dword [root+Root.view]
	cmp eax,888
	jne .shape_wrong
	cvtss2si eax,dword [root+Root.view+4]
	cmp eax,500
	jne .shape_wrong
	; Smaller on screen, so fewer pixels: still a disc's share of each square.
	mov eax,[last_shaded]
	cmp eax,ebx
	jae .shape_wrong
	cmp eax,MOTES * 219 * 50 / 100
	jae .report
.shape_wrong:
	fail 12
	jmp .report
.broken:
	mov [app_io_failed],1
.report:
	fastcall wsprintfW,addr report_text,<W,'proof=spine',13,10,'failure=%u',13,10,'failure_frame=%u',13,10,'frames=%u',13,10,'events=%u',13,10,'motes=%u',13,10,'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10,'root_bytes=%u',13,10,'events_bytes=%u',13,10,'dispatches=%u',13,10,'draws=%u',13,10,'worst_latency=%u',13,10,'shaded=%u',13,10,'near=%u',13,10,'view_width=%u',13,10,'view_height=%u',13,10,'caps=%u',13,10,'required=%u',13,10,'api=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],MOTES,[traffic_down],[traffic_up],sizeof.Root,sizeof.Events,[dispatch_count],[draw_count],[worst_latency],[last_shaded],[last_near],[playfield_rect.extent.width],[playfield_rect.extent.height],[active_caps],CAP_REQUIRED,[device_api],[gpu_error],[failure_stage]
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
	fastcall scripted_run
	jmp .finish
.show:
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
	fastcall wsprintfW,addr title_text,<W,'myhits proof 02: spine | frame %u | events read %u frame(s) later | %u motes near | %u pixels drawn | arrows or WASD move, Esc quits'>, \
		[root+Root.frame],[last_latency],[last_near],[last_shaded]
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

; At 960 x 540 a mote's square is 16 pixels and its disc about 0.69 of that:
; roughly 180,000 pixels in all. A draw that pulled no texels would shade
; every square; one that pulled garbage, about none.
SHADED_FLOOR := MOTES * 256 * 50 / 100
SHADED_CEILING := MOTES * 256 * 85 / 100

section '.data$spine' data readable writeable align 16
absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
tolerance dd 0.05
world_buffer GpuBuffer
header_buffer GpuBuffer
seed_pipeline dq 0
direct_pipeline dq 0
advance_pipeline dq 0
mote_pipeline dq 0
events_seen dd 0
proof_failure dd 0
proof_failure_frame dd 0
last_shaded dd 0
last_near dd 0
last_latency dd 0
worst_latency dd 0

section '.rdata$spine_spirv' data readable align 4
iterate <name,module>, seed_code,seed, direct_code,direct, advance_code,advance, vertex_spirv,mote_vertex, fragment_spirv,mote_fragment
	align 4
	name file 'build\myhits_spine_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
