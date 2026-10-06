; Proof 03, pictures: every frame art.txt lists is made on the device, masked
; there, and drawn from there with nothing bound. A gallery shows each frame
; over its mask; a chain turns under a light that does not; the ship answers
; the keys and the pad.
;
;	build\myhits_pictures.exe		watch it; arrows, WASD or a pad move the ship
;	build\myhits_pictures.exe --self-test	120 scripted frames, every claim checked
;
; What each check settles is in ..\README.md.
MACHINE_NAME equ 'myhits proof 03: pictures'
MACHINE_TAG equ 'pictures'
include '..\..\machine.inc'
include '..\..\pictures.inc'

SPRITES := 2 * ART_FRAMES + 25		; the gallery, the light, the chain, the ship and its two
SCRIPT_FRAMES := 120
SCRIPT_LEG := 30			; frames moving right, then as many moving down
public mainCRTStartup

; The world's header, which the CPU writes once: World in gallery.slang.
boundary GalleryWorld
	block pictures,Pictures
	ptr sprites,Sprite
	ptr state,State
	u32 count
	u32 pad
end boundary
STATE_BYTES := 8
SPRITE_BYTES := 24
WORLD_BYTES := STATE_BYTES + SPRITES * SPRITE_BYTES

section '.text$gallery' code readable executable align 16

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
; Leave to `target` unless the float at `place` is within the tolerance of `value`.
macro unless_near place*,value*,target*
	movss xmm0,place
	subss xmm0,[value]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	ja target
end macro

proc create_world uses rdi
	mov [failure_stage],3
	; Only shaders touch the world: device-local memory, reached by address.
	require_ok fastcall create_device_buffer,addr world_buffer,WORLD_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1
	; The CPU writes the header once, straight into host-visible memory.
	require_ok fastcall create_buffer,addr header_buffer,sizeof.GalleryWorld,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,1
	mov rdi,[header_buffer.mapped]
	require_ok fastcall pictures_create,rdi
	mov rax,[world_buffer.address]
	mov [rdi+GalleryWorld.state],rax
	add rax,STATE_BYTES
	mov [rdi+GalleryWorld.sprites],rax
	mov dword [rdi+GalleryWorld.count],SPRITES
	mov dword [rdi+GalleryWorld.pad],0
	require_ok fastcall flush_buffer,addr header_buffer
	mov rax,[header_buffer.address]
	mov [root+Root.world],rax
	require_ok fastcall machine_compute,addr direct_code,direct_code.size,addr direct_pipeline
	require_ok fastcall machine_graphics,addr vertex_spirv,vertex_spirv.size,addr fragment_spirv,fragment_spirv.size,BLEND_PREMULTIPLIED,addr sprite_pipeline
	; The device makes the pictures. What went up for it is the packer's block, once.
	require_ok fastcall pictures_develop
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
	iterate name, direct,sprite
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

; One frame: the last one's events in, Root down, one compute pass, one draw.
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
	fastcall machine_canvas
	fastcall machine_draw,[sprite_pipeline],6,SPRITES
	fastcall machine_close
	ret
.skipped:
	; 2: no image this turn, which is not a failure.
	shr eax,1
.stopped:
	ret
endp

; A finished frame's events. Interactive runs show them; scripted runs hold
; every one to what the packer, the script and the shaders make inevitable.
proc consume_events uses rbx rsi,events
	mov rbx,rcx
	mov esi,[rbx+Events.frame]
	iterate <name,offset>, last_shaded,Events.score, last_toward,Events.debug, last_away,Events.debug+4, last_fixed_toward,Events.debug+8, last_fixed_away,Events.debug+12, \
		last_baked_solid,Events.reserved+8, last_made_solid,Events.reserved+20, last_lopsided,Events.reserved+24, last_mask_pixels,Events.reserved+44, last_picture_pixels,Events.reserved+48
		mov eax,[rbx+offset]
		mov [name],eax
	end iterate
	iterate <total,name>, toward,last_toward, away,last_away, fixed_toward,last_fixed_toward, fixed_away,last_fixed_away
		mov eax,[name]
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
	; 2: every packed frame reached the device as the packer left it: the count
	; of its solid texels by the device's own mask, and the sum of its texels.
	cmp dword [rbx+Events.reserved],ART_BAKED_FRAMES
	jne .baked_wrong
	cmp dword [rbx+Events.reserved+4],0
	jne .baked_wrong
	cmp dword [rbx+Events.reserved+8],ART_BAKED_SOLID
	je .baked
.baked_wrong:
	fail 2
.baked:
	; 3: every other frame was made there, none empty, and each drawn one covers
	; what the packer's own reading of its strokes covers.
	cmp dword [rbx+Events.reserved+12],ART_FRAMES-ART_BAKED_FRAMES
	jne .made_wrong
	cmp dword [rbx+Events.reserved+16],0
	jne .made_wrong
	cmp dword [rbx+Events.reserved+20],0
	jne .made
.made_wrong:
	fail 3
.made:
	; 4: a frame said to be symmetric has a mask that is, bit for bit.
	cmp dword [rbx+Events.reserved+24],0
	je .symmetric
	fail 4
.symmetric:
	; 5: the masks are what is drawn. At half size a texel is a quarter of a
	; pixel, so the gallery's masks cover a quarter of all solid texels, and its
	; pictures, by their own filtered alpha, cover the same.
	mov eax,[last_baked_solid]
	add eax,[last_made_solid]
	shr eax,2
	mov ecx,eax
	shr ecx,4			; a sixteenth either way
	mov edx,[last_mask_pixels]
	sub edx,eax
	mov eax,edx
	neg eax
	cmovs eax,edx
	cmp eax,ecx
	ja .masks_wrong
	mov edx,[last_picture_pixels]
	sub edx,[last_mask_pixels]
	mov eax,edx
	neg eax
	cmovs eax,edx
	cmp eax,ecx
	jbe .masks
.masks_wrong:
	fail 5
.masks:
	; 6: the controls of frame N moved the ship in frame N.
	lea eax,[rsi+1]
	mov edx,SCRIPT_LEG
	cmp eax,edx
	cmova eax,edx
	imul eax,10
	add eax,300
	cvtsi2ss xmm0,eax
	subss xmm0,dword [rbx+Events.reserved+32]
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
	add eax,640
	cvtsi2ss xmm0,eax
	subss xmm0,dword [rbx+Events.reserved+36]
	andps xmm0,xword [absolute]
	ucomiss xmm0,[tolerance]
	jbe .moved
.moved_wrong:
	fail 6
.moved:
	; 7: the one pass set down every sprite the draw pulls, no more and no fewer.
	cmp dword [rbx+Events.reserved+40],SPRITES
	je .done
	fail 7
.done:
	inc [events_seen]
	ret
endp

; 11: the pad's mapping, on states no pad need be present to give.
proc pad_check uses rbx rdi
	lea rbx,[pad_probe]
	iterate <stick_x,stick_y,buttons,move_x,move_y,expected>, 4000,0,0,zero,zero,0, 32767,0,0,one,zero,0, 20308,0,0,half,zero,0, 0,32767,0,zero,minus_one,0, \
		0,-32768,PAD_A,zero,one,BUTTON_FIRE, 0,0,PAD_LEFT or PAD_X,minus_one,zero,BUTTON_SECOND
		mov rdi,rbx
		xor eax,eax
		mov ecx,16
		rep stosb
		mov word [rbx+PAD_LEFT_X],stick_x
		mov word [rbx+PAD_LEFT_Y],stick_y
		mov word [rbx+PAD_BUTTONS],buttons
		mov dword [root+Root.move],0
		mov dword [root+Root.move+4],0
		mov dword [root+Root.held],0
		fastcall pad_apply,rbx
		unless_near dword [root+Root.move],move_x,.wrong
		unless_near dword [root+Root.move+4],move_y,.wrong
		cmp dword [root+Root.held],expected
		jne .wrong
	end iterate
	mov dword [root+Root.move],0
	mov dword [root+Root.move+4],0
	mov dword [root+Root.held],0
	ret
.wrong:
	fail 11
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
	; 8: while the chain turned, the light did not. Of the fragments the light
	; brightened, nearly all lay on the lit side of their sprite; had the light
	; turned with the pictures, about half would have.
	mov eax,[toward]
	add eax,[away]
	jz .light_wrong
	imul eax,85
	imul edx,[toward],100
	cmp edx,eax
	jb .light_wrong
	mov eax,[fixed_toward]
	add eax,[fixed_away]
	jz .light_wrong
	imul eax,70
	imul edx,[fixed_toward],100
	cmp edx,eax
	jbe .light
.light_wrong:
	fail 8
.light:
	; 9: every frame's events were read, and Root and Events were all the traffic.
	cmp [events_seen],SCRIPT_FRAMES
	jne .traffic_wrong
	cmp [traffic_down],SCRIPT_FRAMES*sizeof.Root
	jne .traffic_wrong
	cmp [traffic_up],SCRIPT_FRAMES*sizeof.Events
	je .traffic
.traffic_wrong:
	fail 9
.traffic:
	; 10: three passes made the pictures; after that, one pass and one draw a frame.
	cmp [startup_dispatches],PICTURES_PASSES
	jne .commands
	cmp [dispatch_count],SCRIPT_FRAMES
	jne .commands
	cmp [draw_count],SCRIPT_FRAMES
	je .pad
.commands:
	fail 10
.pad:
	fastcall pad_check
	jmp .report
.broken:
	mov [app_io_failed],1
.report:
	fastcall wsprintfW,addr report_text,<W,'proof=pictures',13,10,'failure=%u',13,10,'failure_frame=%u',13,10,'frames=%u',13,10,'events=%u',13,10, \
		'art_frames=%u',13,10,'baked_frames=%u',13,10,'texels=%u',13,10,'mask_words=%u',13,10,'strokes=%u',13,10,'packed_bytes=%u',13,10,'device_bytes=%u',13,10, \
		'baked_solid=%u',13,10,'made_solid=%u',13,10,'lopsided=%u',13,10,'mask_pixels=%u',13,10,'picture_pixels=%u',13,10,'shaded=%u',13,10, \
		'toward=%u',13,10,'away=%u',13,10,'fixed_toward=%u',13,10,'fixed_away=%u',13,10,'sprites=%u',13,10,'bytes_down=%I64u',13,10,'bytes_up=%I64u',13,10, \
		'startup_dispatches=%u',13,10,'dispatches=%u',13,10,'draws=%u',13,10,'worst_latency=%u',13,10,'caps=%u',13,10,'required=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		[proof_failure],[proof_failure_frame],[root+Root.frame],[events_seen],ART_FRAMES,ART_BAKED_FRAMES,ART_TEXELS,ART_MASK_WORDS,ART_STROKES,PACKED_BYTES,PICTURES_BYTES, \
		[last_baked_solid],[last_made_solid],[last_lopsided],[last_mask_pixels],[last_picture_pixels],[last_shaded],[toward],[away],[fixed_toward],[fixed_away],SPRITES, \
		[traffic_down],[traffic_up],[startup_dispatches],[dispatch_count],[draw_count],[worst_latency],[active_caps],CAP_REQUIRED,[gpu_error],[failure_stage]
	fastcall machine_write_report,rax
	ret
endp

; A share of 100, for the title.
proc percent part,whole
	add edx,ecx
	jz .none
	imul eax,ecx,100
	mov ecx,edx
	xor edx,edx
	div ecx
	ret
.none:
	xor eax,eax
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
	fastcall percent,[last_toward],[last_away]
	mov [title_share],eax
	fastcall percent,[last_fixed_toward],[last_fixed_away]
	mov [title_fixed],eax
	fastcall wsprintfW,addr title_text,<W,'myhits proof 03: pictures | %u frames, %u solid texels | %u%% of the light falls on the lit side (%u%% had it turned with the pictures) | %u pixels drawn | arrows, WASD or pad move, Esc quits'>, \
		ART_FRAMES,[last_baked_solid],[title_share],[title_fixed],[last_shaded]
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

section '.data$gallery' data readable writeable align 16
absolute dd 7FFFFFFFh,7FFFFFFFh,7FFFFFFFh,7FFFFFFFh
tolerance dd 0.05
zero dd 0.0
half dd 0.5
one dd 1.0
minus_one dd -1.0
world_buffer GpuBuffer
header_buffer GpuBuffer
direct_pipeline dq 0
sprite_pipeline dq 0
events_seen dd 0
proof_failure dd 0
proof_failure_frame dd 0
startup_dispatches dd 0
last_latency dd 0
worst_latency dd 0
title_share dd 0
title_fixed dd 0
iterate name, last_shaded,last_toward,last_away,last_fixed_toward,last_fixed_away,last_baked_solid,last_made_solid,last_lopsided,last_mask_pixels,last_picture_pixels, \
	toward,away,fixed_toward,fixed_away
	name dd 0
end iterate
pad_probe:
	rb 16

section '.rdata$gallery_spirv' data readable align 4
iterate <name,module>, develop_code,develop, chart_code,chart, census_code,census, direct_code,direct, vertex_spirv,sprite_vertex, fragment_spirv,sprite_fragment
	align 4
	name file 'build\myhits_pictures_' bappend `module bappend '.spv'
	name.size = $ - name
end iterate
