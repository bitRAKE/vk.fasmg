; The machine under the game and under each proof: a window, the modern
; contract, memory the shaders reach through pointers, pipelines whose whole
; interface is the root block, and the frame that carries Root down and
; Events back.
;
; The including source defines MACHINE_NAME and MACHINE_TAG, includes this,
; and supplies two procedures:
;
;	consume_events	RCX = a finished frame's Events; called oldest first
;	release_world	destroy its pipelines and buffers; the device is idle
;
; Every frame it calls, in order: machine_await, machine_sample, machine_open,
; its compute passes with machine_dispatch and machine_settle between them,
; machine_canvas, its draws with machine_draw, machine_close.
;
; machine_sample pays real time out in ticks, TICK_RATE a second: a program
; that simulates runs its passes Root.ticks times in the frame, which may be
; none, and draws its world Root.blend of the way between the last two.
include 'newcoff.inc'
struc? TCHAR args:?&
	. du args
end struc
macro TCHAR args:?&
	du args
end macro
sizeof.TCHAR = 2
include 'equates/kernel64.inc'
include 'equates/user64.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/khr/surface.inc'
include 'vk/khr/win32_surface.inc'
include 'vk/khr/swapchain.inc'
include 'vk/khr/swapchain_maintenance1.inc'
include 'vk/loader/static.inc'
include '..\..\examples\debug\sink.inc'
include '..\..\examples\strings.inc'
include '..\..\examples\common\command_options.inc'

; The contract: modern only. Dynamic rendering (1), synchronization2 (2),
; inline shader code (8) and timeline semaphores (16) are required, with the
; two features below; nothing they replace is assembled.
CAP_ADDRESS := 64			; bufferDeviceAddress: every resource is a pointer
CAP_SCALAR := 128			; scalarBlockLayout: the layout shared.inc promises
CAP_MASK = 1 or 2 or 8 or 16 or 64 or 128
CAP_REQUIRED = CAP_MASK
TILE_CEILING = 16384
include '..\..\examples\common\vulkan_routes.inc'
include 'shared.inc'

MACHINE_STAGES := VK_SHADER_STAGE_COMPUTE_BIT or VK_SHADER_STAGE_VERTEX_BIT or VK_SHADER_STAGE_FRAGMENT_BIT
BLEND_OPAQUE := 0
BLEND_ALPHA := 1
BLEND_ADDITIVE := 2
BLEND_PREMULTIPLIED := 3		; the pictures': one blend covers and adds alike
TICKS_LIMIT := 8			; the most one frame runs; past that, lost time stays lost
SCRIPT_TICKS := 2			; a scripted frame is a sixtieth of a second
QS_ALLINPUT := 4FFh

iterate function,GetModuleHandleW,GetCommandLineW,OutputDebugStringW,ExitProcess,CreateFileW,WriteFile,CloseHandle,VirtualAlloc,VirtualFree, \
	RegisterClassExW,CreateWindowExW,DefWindowProcW,DestroyWindow,ShowWindow,UpdateWindow,PeekMessageW,TranslateMessage,DispatchMessageW, \
	WaitMessage,PostQuitMessage,BeginPaint,EndPaint,GetClientRect,LoadCursorW,MessageBoxW,SetWindowPos,AdjustWindowRectEx, \
	SetWindowTextW,wsprintfW,QueryPerformanceCounter,QueryPerformanceFrequency,GetAsyncKeyState,GetCursorPos,ScreenToClient,GetForegroundWindow, \
	XInputGetState
	extrn function:qword
end iterate
; For the startup arena behind the shared allocators.
iterate function,GetLargePageMinimum,GetLastError,SetLastError,OpenProcessToken,LookupPrivilegeValueW,AdjustTokenPrivileges
	extrn function:qword
end iterate

GPU_APP_NAME equ MACHINE_NAME
GPU_EXTRA_FEATURES := 1
GPU_EXTRA_FORMATS := 1
GPU_HARDWARE_ONLY := 1
GPU_WSI := 1
include '..\..\examples\common\cpu_arena.inc'
include '..\..\examples\common\vulkan_wsi.inc'
include '..\..\examples\common\vulkan_context.inc'
include '..\..\examples\common\vulkan_memory.inc'
include '..\..\examples\common\vulkan_commands.inc'
include '..\..\examples\common\vulkan_barriers.inc'
include 'input.inc'

; A VkResult in EAX: on failure record it and leave.
macro require_vk line&
	line
	test eax,eax
	jnz .result
end macro
; A Boolean in EAX.
macro require_ok line&
	line
	test eax,eax
	jz .failed
end macro

section '.text$machine' code readable executable align 16

; Hooks of the shared context: the two features the contract adds.
proc query_extra_features
	cmp [device_api],VK_API_VERSION_1_2
	jb .done
	fastcall chain_feature,addr address_feature
	fastcall chain_feature,addr scalar_feature
.done:
	ret
endp

proc enable_extra_features
	cmp [device_api],VK_API_VERSION_1_2
	jb .done
	cmp [address_feature.bufferDeviceAddress],VK_TRUE
	jne .scalar
	mov [address_feature.bufferDeviceAddressCaptureReplay],0
	mov [address_feature.bufferDeviceAddressMultiDevice],0
	fastcall chain_feature,addr address_feature
	or [active_caps],CAP_ADDRESS
.scalar:
	cmp [scalar_feature.scalarBlockLayout],VK_TRUE
	jne .done
	fastcall chain_feature,addr scalar_feature
	or [active_caps],CAP_SCALAR
.done:
	ret
endp

proc resolve_extra_commands
	mov eax,1
	ret
endp

; Colors are blended in linear light, so the surface is sRGB.
proc choose_formats
	require_ok fastcall wsi_choose_format,VK_FORMAT_B8G8R8A8_SRGB
	mov eax,[wsi_format]
	mov [target_format],eax
	mov eax,1
.failed:
	ret
endp

proc resize_client
	fastcall GetClientRect,[window],addr client_rect
	mov eax,[client_rect.right]
	mov edx,[client_rect.bottom]
	test eax,eax
	jz .done
	test edx,edx
	jz .done
	cmp eax,[frame_width]
	jne .changed
	cmp edx,[frame_height]
	je .done
.changed:
	mov [frame_width],eax
	mov [frame_height],edx
	mov [wsi_dirty],1
.done:
	ret
endp

proc window_proc hwnd,message,wparam,lparam
	mov [hwnd],rcx
	mov [message],rdx
	mov [wparam],r8
	mov [lparam],r9
	iterate <code,target>, WM_PAINT,.paint,WM_SIZE,.size,WM_KEYDOWN,.key,WM_LBUTTONDOWN,.left,WM_RBUTTONDOWN,.right,WM_GETMINMAXINFO,.minimum,WM_CLOSE,.close,WM_DESTROY,.close
		cmp edx,code
		je target
	end iterate
.default:
	fastcall DefWindowProcW,[hwnd],[message],[wparam],[lparam]
	ret
.paint:
	fastcall BeginPaint,[hwnd],addr paint
	fastcall EndPaint,[hwnd],addr paint
	jmp .handled
.size:
	mov [minimized],0
	cmp r8d,SIZE_MINIMIZED
	jne .client_size
	mov [minimized],1
	jmp .handled
.client_size:
	cmp [window],0
	je .handled
	fastcall resize_client
	mov [stale],1
	jmp .handled
; A press is taken from its message, so one shorter than a frame is not lost.
.key:
	cmp r8d,VK_ESCAPE
	je .close
	bt r9,30			; the keyboard repeating a key already down
	jc .default
	iterate <key,bit>, VK_SPACE,BUTTON_FIRE, VK_SHIFT,BUTTON_SECOND, VK_RETURN,BUTTON_START
		cmp r8d,key
		jne .not_#key
		or [pressed_pending],bit
	.not_#key:
	end iterate
	jmp .default
.left:
	or [pressed_pending],BUTTON_FIRE
	jmp .default
.right:
	or [pressed_pending],BUTTON_SECOND
	jmp .default
.close:
	fastcall PostQuitMessage,0
	jmp .handled
.minimum:
	mov [r9+MINMAXINFO.ptMinTrackSize.x],320
	mov [r9+MINMAXINFO.ptMinTrackSize.y],200
.handled:
	xor eax,eax
	ret
endp

; Give the client area, and so the swapchain, exactly this size.
proc resize_window width,height
	mov [window_rect.left],0
	mov [window_rect.top],0
	mov [window_rect.right],ecx
	mov [window_rect.bottom],edx
	fastcall AdjustWindowRectEx,addr window_rect,WS_OVERLAPPEDWINDOW,0,0
	mov r8d,[window_rect.right]
	sub r8d,[window_rect.left]
	mov r9d,[window_rect.bottom]
	sub r9d,[window_rect.top]
	mov [window_rect.right],r8d
	mov [window_rect.bottom],r9d
	fastcall SetWindowPos,[window],0,0,0,[window_rect.right],[window_rect.bottom],SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE
	ret
endp

proc create_window
	fastcall GetModuleHandleW,0
	mov [module],rax
	mov [window_class.hInstance],rax
	fastcall LoadCursorW,0,IDC_ARROW
	mov [window_class.hCursor],rax
	fastcall RegisterClassExW,addr window_class
	test eax,eax
	jz .failed
	fastcall CreateWindowExW,0,addr class_name,addr window_name,WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,976,579,0,0,[module],0
	test rax,rax
	jz .failed
	mov [window],rax
	fastcall resize_window,960,540
	fastcall resize_client
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

; Window, device under the contract, allocators, the one pipeline layout and
; the ring of event slots. Returns nonzero when all of it stands.
proc machine_start
	mov [failure_stage],1
	fastcall QueryPerformanceFrequency,addr clock_frequency
	mov [large_pages_requested],0
	require_ok fastcall create_cpu_arena
	require_ok fastcall create_window
	require_ok fastcall probe_gpu
	mov [failure_stage],2
	require_ok fastcall create_memory_pools
	require_vk fastcall create_commands
	mov rax,[command_buffer]
	mov [serial_command_buffer],rax
	require_ok fastcall wsi_create_frames
	require_vk vkCreatePipelineLayout [device],addr layout_info,0,addr machine_layout
	mov rax,[machine_layout]
	mov [compute_info.layout],rax
	mov [graphics_info.layout],rax
	; The CPU reads these, so the memory is host-visible and cached.
	require_ok fastcall create_buffer,addr events_buffer,EVENT_SLOTS*sizeof.Events,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT or VK_BUFFER_USAGE_TRANSFER_DST_BIT,1
	mov [failure_stage],0
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

; A compute pipeline from SPIR-V. The code is chained to the stage: no module.
proc machine_compute code,bytes,pipeline
	mov [shader_code.pCode],rcx
	mov [shader_code.codeSize],rdx
	mov [pipeline],r8
	vkCreateComputePipelines [device],0,1,addr compute_info,0,[pipeline]
	test eax,eax
	jnz .result
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; A graphics pipeline that takes no vertex input: its shaders pull what they
; draw through the root block. `blend` is one of BLEND_*.
proc machine_graphics vertex,vertex_bytes,fragment,fragment_bytes,blend,pipeline
	mov [vertex_code.pCode],rcx
	mov [vertex_code.codeSize],rdx
	mov [fragment_code.pCode],r8
	mov [fragment_code.codeSize],r9
	mov [blend_attachment.blendEnable],VK_FALSE
	mov eax,dword [blend]
	test eax,eax
	jz .create
	mov [blend_attachment.blendEnable],VK_TRUE
	mov [blend_attachment.srcColorBlendFactor],VK_BLEND_FACTOR_SRC_ALPHA
	mov [blend_attachment.srcAlphaBlendFactor],VK_BLEND_FACTOR_ONE
	mov [blend_attachment.dstAlphaBlendFactor],VK_BLEND_FACTOR_ONE
	mov [blend_attachment.dstColorBlendFactor],VK_BLEND_FACTOR_ONE
	cmp eax,BLEND_ADDITIVE
	je .create
	mov [blend_attachment.dstColorBlendFactor],VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	mov [blend_attachment.dstAlphaBlendFactor],VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	cmp eax,BLEND_PREMULTIPLIED
	jne .create
	mov [blend_attachment.srcColorBlendFactor],VK_BLEND_FACTOR_ONE
.create:
	vkCreateGraphicsPipelines [device],0,1,addr graphics_info,0,[pipeline]
	test eax,eax
	jnz .result
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; Work outside a frame, for what is set up once: between these two, record
; with machine_bind and machine_dispatch. Returns when the device has done it.
proc machine_serial_open
	mov rax,[serial_command_buffer]
	mov [command_buffer],rax
	require_vk fastcall begin_commands
	vkCmdPushConstants [command_buffer],[machine_layout],MACHINE_STAGES,0,sizeof.Root,addr root
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc machine_serial_close
	require_vk fastcall submit_commands
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; One compute pass over `groups` workgroups.
proc machine_dispatch uses rbx,pipeline,groups
	mov ebx,edx
	mov [pipeline],rcx
	vkCmdBindPipeline [command_buffer],VK_PIPELINE_BIND_POINT_COMPUTE,[pipeline]
	vkCmdDispatch [command_buffer],rbx,1,1
	inc [dispatch_count]
	ret
endp

; What the last pass wrote, the next may read: compute to compute.
proc machine_settle
	fastcall memory_barrier,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_ACCESS_SHADER_WRITE_BIT, \
		VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_ACCESS_SHADER_READ_BIT or VK_ACCESS_SHADER_WRITE_BIT
	ret
endp

; `vertices` for each of `instances`, all of it pulled by the shaders.
proc machine_draw uses rbx rsi,pipeline,vertices,instances
	mov ebx,edx
	mov esi,r8d
	mov [pipeline],rcx
	vkCmdBindPipeline [command_buffer],VK_PIPELINE_BIND_POINT_GRAPHICS,[pipeline]
	vkCmdDraw [command_buffer],rbx,rsi,0,0
	inc [draw_count]
	ret
endp

; A frame begins when the device has finished the one before. Presentation
; lets a program queue frames ahead, and a queued frame's commands, its
; simulation among them, wait for a swapchain image: its events would come
; back frames late and its controls would be stale by as much. Waiting here
; instead keeps both at one frame, and reads the controls as late as can be.
proc machine_await
	require_vk fastcall wait_retirement,[last_retirement]
	require_ok fastcall machine_events
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

; Hand each finished frame's Events to the program, oldest first, without
; waiting; except that a slot about to be reused is waited for.
proc machine_events uses rbx
	fastcall poll_retirement
	test eax,eax
	jnz .result
.next:
	mov ebx,[events_read]
	cmp ebx,[root+Root.frame]
	jae .done
	mov eax,ebx
	and eax,EVENT_SLOTS-1
	lea rdx,[events_retirement]
	mov rcx,[rdx+rax*8]
	cmp rcx,[completed_retirement]
	jbe .consume
	mov eax,[root+Root.frame]
	sub eax,ebx
	cmp eax,EVENT_SLOTS
	jb .done
	fastcall wait_retirement,rcx
	test eax,eax
	jnz .result
.consume:
	require_ok fastcall invalidate_buffer,addr events_buffer
	mov eax,ebx
	and eax,EVENT_SLOTS-1
	imul eax,sizeof.Events
	add rax,[events_buffer.mapped]
	fastcall consume_events,rax
	add [traffic_up],sizeof.Events
	inc [events_read]
	jmp .next
.done:
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

; The clock and the controls into Root, read now: the frame recorded next
; shows them. Real time is paid out in whole ticks; what is left over is where
; the picture stands between the last two. Keys, then the mouse, then a pad
; over both. A scripted run supplies its own controls and steps evenly.
proc machine_sample uses rbx
	test dword [root+Root.flags],ROOT_SCRIPTED
	jnz .scripted
	fastcall QueryPerformanceCounter,addr clock_now
	mov rax,[clock_now]
	mov rdx,rax
	sub rax,[clock_last]
	mov [clock_last],rdx
	cvtsi2sd xmm0,rax
	cvtsi2sd xmm1,qword [clock_frequency]
	divsd xmm0,xmm1
	cmp dword [root+Root.frame],0
	jne .owed
	xorps xmm0,xmm0
.owed:
	cvtsd2ss xmm1,xmm0
	minss xmm1,[longest_step]
	movss [frame_seconds],xmm1
	addsd xmm0,[tick_debt]
	movsd xmm1,[tick_rate]
	mulsd xmm1,xmm0
	cvttsd2si eax,xmm1
	cmp eax,TICKS_LIMIT
	jbe .pay
	; Too far behind to catch up, after a stall or a breakpoint: run the limit
	; and forgive the rest.
	mov eax,TICKS_LIMIT
	cvtsi2sd xmm0,eax
	divsd xmm0,[tick_rate]
.pay:
	mov [root+Root.ticks],eax
	add [ticks_run],rax
	cvtsi2sd xmm2,eax
	divsd xmm2,[tick_rate]
	subsd xmm0,xmm2
	movsd [tick_debt],xmm0
	mulsd xmm0,[tick_rate]
	cvtsd2ss xmm1,xmm0
	movss [root+Root.blend],xmm1
	; The picture shows the tick before last, and this much of the way on.
	cvtsi2sd xmm2,[ticks_run]
	subsd xmm2,[whole_tick]
	addsd xmm2,xmm0
	xorps xmm3,xmm3
	maxsd xmm2,xmm3
	divsd xmm2,[tick_rate]
	cvtsd2ss xmm1,xmm2
	movss [root+Root.time],xmm1
	; Keys and buttons only while the window has the keyboard.
	mov dword [root+Root.move],0
	mov dword [root+Root.move+4],0
	mov dword [root+Root.held],0
	xor ebx,ebx
	fastcall GetForegroundWindow
	cmp rax,[window]
	jne .edges
	iterate <key,offset,value>, VK_LEFT,0,-1.0, 41h,0,-1.0, VK_RIGHT,0,1.0, 44h,0,1.0, VK_UP,4,-1.0, 57h,4,-1.0, VK_DOWN,4,1.0, 53h,4,1.0
		fastcall GetAsyncKeyState,key
		test ax,ax
		jns .up_#key
		mov dword [root+Root.move+offset],value
	.up_#key:
	end iterate
	iterate <key,bit>, VK_SPACE,BUTTON_FIRE, VK_LBUTTON,BUTTON_FIRE, VK_SHIFT,BUTTON_SECOND, VK_RBUTTON,BUTTON_SECOND, VK_RETURN,BUTTON_START
		fastcall GetAsyncKeyState,key
		test ax,ax
		jns .off_#key
		or dword [root+Root.held],bit
	.off_#key:
	end iterate
	; The crosshair follows the mouse, in playfield units, when the mouse moves;
	; between times the pad's right stick may carry it.
	fastcall GetCursorPos,addr cursor
	mov rax,qword [cursor]
	cmp rax,[cursor_last]
	je .pad
	mov [cursor_last],rax
	fastcall ScreenToClient,[window],addr cursor
	iterate <coordinate,origin,extent,span,offset>, cursor.x,viewport.x,viewport.width,PLAYFIELD_WIDTH,0, cursor.y,viewport.y,viewport.height,PLAYFIELD_HEIGHT,4
		cvtsi2ss xmm0,dword [coordinate]
		subss xmm0,[origin]
		divss xmm0,[extent]
		mulss xmm0,[playfield_#span]
		movss [root+Root.aim+offset],xmm0
	end iterate
.pad:
	; What the pad adds to the buttons is the pad's; its presses are its edges.
	mov ebx,[root+Root.held]
	fastcall pad_sample
	not ebx
	and ebx,[root+Root.held]
.edges:
	fastcall merge_presses,rbx
	ret
.scripted:
	mov dword [root+Root.ticks],SCRIPT_TICKS
	mov dword [root+Root.blend],1.0
	add [ticks_run],SCRIPT_TICKS
	cvtsi2sd xmm0,[ticks_run]
	divsd xmm0,[tick_rate]
	cvtsd2ss xmm1,xmm0
	movss [root+Root.time],xmm1
	ret
endp

; Root.pressed for this frame: what the window's messages saw go down since
; the last one, and what the pad (ECX, its buttons now) newly holds. A press
; shorter than a frame still holds for that frame.
proc merge_presses pad_held
	mov eax,[pressed_pending]
	mov [pressed_pending],0
	or [root+Root.held],eax
	mov edx,[pad_before]
	mov [pad_before],ecx
	not edx
	and edx,ecx
	or eax,edx
	mov [root+Root.pressed],eax
	ret
endp

; Open a frame: a swapchain image in, this frame's event slot chosen, Root
; pushed. Returns 1 to record, 2 to skip this turn, 0 on failure. The program
; has filled Root; nothing else goes down.
proc machine_open uses rbx rsi
	xor esi,esi
	mov [failure_stage],5
	cmp [wsi_dirty],0
	jne .resize
	mov eax,[frame_width]
	cmp eax,[target_width]
	jne .resize
	mov eax,[frame_height]
	cmp eax,[target_height]
	je .acquire
.resize:
	require_vk fastcall wsi_wait_work
	fastcall wsi_destroy_swapchain
	mov [target_width],0
	require_ok fastcall wsi_create_swapchain
	mov eax,[wsi_swapchain_info.imageExtent.width]
	mov [frame_width],eax
	mov [target_width],eax
	mov [rendering_info.renderArea.extent.width],eax
	mov eax,[wsi_swapchain_info.imageExtent.height]
	mov [frame_height],eax
	mov [target_height],eax
	mov [rendering_info.renderArea.extent.height],eax
	fastcall fit_playfield
.acquire:
	fastcall wsi_begin_frame
	cmp eax,2
	je .retry
	test eax,eax
	jz .wsi_failed
	mov [failure_stage],6
	mov rbx,[wsi_current_image]
	mov rax,[rbx+WsiImage.handle]
	mov [draw_image],rax
	mov rax,[rbx+WsiImage.view]
	mov [render_color.imageView],rax
	mov eax,[root+Root.frame]
	and eax,EVENT_SLOTS-1
	imul eax,sizeof.Events
	add rax,[events_buffer.address]
	mov [root+Root.events],rax
	; Earlier frames wrote what this one reads.
	fastcall memory_barrier,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT or VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_ACCESS_SHADER_WRITE_BIT, \
		VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_ACCESS_SHADER_READ_BIT or VK_ACCESS_SHADER_WRITE_BIT
	vkCmdPushConstants [command_buffer],[machine_layout],MACHINE_STAGES,0,sizeof.Root,addr root
	add [traffic_down],sizeof.Root
	mov eax,1
	ret
.retry:
	inc esi
	cmp esi,2
	jb .resize
	mov eax,2
	ret
.wsi_failed:
	mov eax,[wsi_error]
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

; The largest 16:9 rectangle in the window is the playfield; the rest is bars.
proc fit_playfield
	mov eax,[frame_width]
	imul eax,PLAYFIELD_HEIGHT
	mov edx,[frame_height]
	imul edx,PLAYFIELD_WIDTH
	cmp eax,edx
	ja .pillars
	; Width decides: height = width * 9 / 16.
	mov ecx,[frame_width]
	imul eax,ecx,9
	shr eax,4
	mov r8d,eax
	jmp .place
.pillars:
	; Height decides: width = height * 16 / 9.
	mov r8d,[frame_height]
	mov eax,r8d
	shl eax,4
	xor edx,edx
	mov ecx,9
	div ecx
	mov ecx,eax
.place:
	mov [playfield_rect.extent.width],ecx
	mov [playfield_rect.extent.height],r8d
	mov eax,[frame_width]
	sub eax,ecx
	shr eax,1
	mov [playfield_rect.offset.x],eax
	cvtsi2ss xmm0,eax
	movss [viewport.x],xmm0
	mov eax,[frame_height]
	sub eax,r8d
	shr eax,1
	mov [playfield_rect.offset.y],eax
	cvtsi2ss xmm0,eax
	movss [viewport.y],xmm0
	cvtsi2ss xmm0,ecx
	movss [viewport.width],xmm0
	movss [root+Root.view],xmm0
	cvtsi2ss xmm0,r8d
	movss [viewport.height],xmm0
	movss [root+Root.view+4],xmm0
	ret
endp

; From the compute passes to the picture: the swapchain image, cleared, with
; the playfield as viewport.
proc machine_canvas
	fastcall memory_barrier,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_ACCESS_SHADER_WRITE_BIT, \
		VK_PIPELINE_STAGE_VERTEX_SHADER_BIT or VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,VK_ACCESS_SHADER_READ_BIT or VK_ACCESS_SHADER_WRITE_BIT
	fastcall transition_image,[draw_image],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
	vkCmdBeginRendering [command_buffer],addr rendering_info
	vkCmdSetViewport [command_buffer],0,1,addr viewport
	vkCmdSetScissor [command_buffer],0,1,addr playfield_rect
	ret
endp

; Close the frame: present it, and remember when its events may be read.
proc machine_close
	vkCmdEndRendering [command_buffer]
	fastcall transition_image,[draw_image],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,0
	fastcall wsi_submit_frame
	test eax,eax
	jz .failed
	mov eax,[root+Root.frame]
	and eax,EVENT_SLOTS-1
	lea rdx,[events_retirement]
	mov rcx,[retirement_value]
	mov [rdx+rax*8],rcx
	mov [last_retirement],rcx
	inc dword [root+Root.frame]
	mov [failure_stage],0
	mov eax,1
	ret
.failed:
	mov eax,[wsi_error]
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; Everything submitted is finished and its events handed over.
proc machine_drain
	require_vk fastcall wsi_wait_work
	require_ok fastcall machine_events
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

proc machine_stop
	cmp [device],0
	je .instance
	mov [wsi_shutdown],1
	mov [wsi_replacement_hold],0
	fastcall wsi_drain
	fastcall release_world
	fastcall wsi_destroy_swapchain
	fastcall destroy_buffer,addr events_buffer
	cmp [machine_layout],0
	je .pools
	vkDestroyPipelineLayout [device],[machine_layout],0
	mov [machine_layout],0
.pools:
	fastcall collect_gpu_deletes
	fastcall destroy_memory_pools
	fastcall wsi_destroy_frames
	fastcall destroy_commands
	vkDestroyDevice [device],0
	mov [device],0
.instance:
	cmp [instance],0
	je .module
	cmp [surface],0
	je .messenger
	vkDestroySurfaceKHR [instance],[surface],0
	mov [surface],0
.messenger:
	cmp [messenger],0
	je .destroy_instance
	vkDestroyDebugUtilsMessengerEXT [instance],[messenger],0
	mov [messenger],0
.destroy_instance:
	vkDestroyInstance [instance],0
	mov [instance],0
.module:
	cmp [vulkan_module],0
	je .window
	fastcall FreeLibrary,[vulkan_module]
	mov [vulkan_module],0
.window:
	cmp [window],0
	je .arena
	fastcall DestroyWindow,[window]
	mov [window],0
.arena:
	fastcall destroy_cpu_arena
	ret
endp

; The failure every program reports the same way, then the exit line the
; checks look for. Returns the process exit code.
proc machine_report_exit
	cmp [app_io_failed],0
	je .line
	cmp [failure_stage],0
	je .line
	fastcall wsprintfW,addr title_text,<W,'[myhits] Vulkan initialization or rendering failed (stage=%u, VkResult=%d, missing=%u). This build requires Vulkan 1.3 with maintenance5, or 1.4: 1 dynamic rendering, 2 synchronization2, 8 inline shader code, 16 timeline semaphores, 64 buffer device addresses, 128 scalar block layout.',13,10>,[failure_stage],[gpu_error],[missing_caps]
	fastcall OutputDebugStringW,addr title_text
	cmp [test_mode],0
	jne .line
	fastcall MessageBoxW,0,addr title_text,addr window_name,MB_ICONERROR
.line:
	fastcall wsprintfW,addr title_text,<W,'[myhits] exit: app_io=%u validation=%u debug_io=%u',13,10>,[app_io_failed],[debug_validation_failed],[debug_io_failed]
	fastcall OutputDebugStringW,addr title_text
	mov eax,[app_io_failed]
	or eax,[debug_validation_failed]
	or eax,[debug_io_failed]
	ret
endp

; Write report_text, UTF-16, to build\myhits_<tag>.report.txt.
proc machine_write_report uses rbx rsi,characters
	lea esi,[ecx*2]
	fastcall CreateFileW,<W,'build\myhits_' bappend MACHINE_TAG bappend '.report.txt'>,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .failed
	mov rbx,rax
	fastcall WriteFile,rbx,addr report_text,rsi,addr written,0
	test eax,eax
	jz .close_failed
	cmp [written],esi
	jne .close_failed
	fastcall CloseHandle,rbx
	test eax,eax
	jz .failed
	ret
.close_failed:
	fastcall CloseHandle,rbx
.failed:
	mov [app_io_failed],1
	ret
endp

section '.data$machine' data readable writeable align 16
root:
	rb 128
window dq 0
module dq 0
machine_layout dq 0
draw_image dq 0
serial_command_buffer dq 0
clock_frequency dq 1
clock_last dq 0
clock_now dq 0
ticks_run dq 0
tick_debt dq 0.0			; seconds of real time not yet paid out in ticks
tick_rate dq 1.0*TICK_RATE
whole_tick dq 1.0
traffic_down dq 0			; bytes the CPU sent after startup
traffic_up dq 0				; bytes the CPU read back
events_retirement rq EVENT_SLOTS
last_retirement dq 0
events_buffer GpuBuffer
events_read dd 0
dispatch_count dd 0
draw_count dd 0
frame_width dd 960
frame_height dd 540
target_width dd 0
target_height dd 0
target_format dd VK_FORMAT_B8G8R8A8_SRGB
minimized dd 0
stale dd 1				; the window shows something other than the last frame
test_mode dd 0
gpu_error dd 0
failure_stage dd 1
app_io_failed dd 0
written dd 0
longest_step dd 0.05
frame_seconds dd 0.0			; real time since the last frame, for what follows the hand
pressed_pending dd 0			; BUTTON_ bits the window's messages saw go down
pad_before dd 0
playfield_PLAYFIELD_WIDTH dd 1920.0
playfield_PLAYFIELD_HEIGHT dd 1080.0
cursor POINT
cursor_last dq -1
class_name GLOBWSTR 'VkFasmgMyhits',0
window_name GLOBWSTR MACHINE_NAME,0
window_class WNDCLASSEX cbSize: sizeof.WNDCLASSEX,lpfnWndProc: window_proc,lpszClassName: class_name
client_rect RECT
window_rect RECT
paint PAINTSTRUCT
message MSG
address_feature VkPhysicalDeviceBufferDeviceAddressFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES
scalar_feature VkPhysicalDeviceScalarBlockLayoutFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES
; One layout for every pipeline: the root block and nothing else.
push_range VkPushConstantRange stageFlags: MACHINE_STAGES,size: sizeof.Root
layout_info VkPipelineLayoutCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,pushConstantRangeCount: 1,pPushConstantRanges: push_range
entry_name GLOBSTR 'main',0
shader_code VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
compute_info VkComputePipelineCreateInfo sType: VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,basePipelineIndex: -1, \
	stage: <sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,pNext: shader_code,stage: VK_SHADER_STAGE_COMPUTE_BIT,pName: entry_name>
vertex_code VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
fragment_code VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
shader_stages:
	VkPipelineShaderStageCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,pNext: vertex_code,stage: VK_SHADER_STAGE_VERTEX_BIT,pName: entry_name
	VkPipelineShaderStageCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,pNext: fragment_code,stage: VK_SHADER_STAGE_FRAGMENT_BIT,pName: entry_name
vertex_input VkPipelineVertexInputStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
input_assembly VkPipelineInputAssemblyStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
viewport_state VkPipelineViewportStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,viewportCount: 1,scissorCount: 1
raster_state VkPipelineRasterizationStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,polygonMode: VK_POLYGON_MODE_FILL,cullMode: VK_CULL_MODE_NONE,lineWidth: 1.0
multisample_state VkPipelineMultisampleStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,rasterizationSamples: VK_SAMPLE_COUNT_1_BIT
blend_attachment VkPipelineColorBlendAttachmentState colorWriteMask: 15
blend_state VkPipelineColorBlendStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,attachmentCount: 1,pAttachments: blend_attachment
dynamic_states dd VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR
dynamic_state VkPipelineDynamicStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,dynamicStateCount: 2,pDynamicStates: dynamic_states
pipeline_rendering VkPipelineRenderingCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,colorAttachmentCount: 1,pColorAttachmentFormats: target_format
graphics_info VkGraphicsPipelineCreateInfo sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,pNext: pipeline_rendering,stageCount: 2,pStages: shader_stages, \
	pVertexInputState: vertex_input,pInputAssemblyState: input_assembly,pViewportState: viewport_state,pRasterizationState: raster_state, \
	pMultisampleState: multisample_state,pColorBlendState: blend_state,pDynamicState: dynamic_state,basePipelineIndex: -1
viewport VkViewport minDepth: 0.0,maxDepth: 1.0
playfield_rect VkRect2D
render_color VkRenderingAttachmentInfo sType: VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,imageLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,loadOp: VK_ATTACHMENT_LOAD_OP_CLEAR,storeOp: VK_ATTACHMENT_STORE_OP_STORE
rendering_info VkRenderingInfo sType: VK_STRUCTURE_TYPE_RENDERING_INFO,layerCount: 1,colorAttachmentCount: 1,pColorAttachments: render_color

section '.bss$machine' readable writeable align 8
title_text rw 1024
report_text rw 2048
