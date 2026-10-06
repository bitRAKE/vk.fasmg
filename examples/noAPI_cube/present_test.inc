; Exercise multiple outstanding presentations without allocating capture memory.
section '.text$cube_present_test' code readable executable align 16
proc present_test uses rbx
	fastcall QueryPerformanceFrequency,addr present_frequency
	iterate <width,height>,500,500,1920,1080,3840,2160
		fastcall resize_window,width,height
		mov ebx,8
	.warm#width:
		fastcall SendMessageW,[window],WM_TIMER,1,0
		dec ebx
		jnz .warm#width
		mov eax,[memory_allocations]
		mov [present_allocations],eax
		fastcall QueryPerformanceCounter,addr present_started
		mov ebx,120
	.frame#width:
		fastcall SendMessageW,[window],WM_TIMER,1,0
		dec ebx
		jnz .frame#width
		require_vk fastcall wsi_wait_work
		mov eax,[memory_allocations]
		cmp eax,[present_allocations]
		jne .failed
		fastcall QueryPerformanceCounter,addr present_finished
		mov rax,[present_finished]
		sub rax,[present_started]
		mov [present_elapsed],rax
		fastcall wsprintfW,addr title_text,<W,'[cube present] width=%u height=%u frames=120 ticks=%u frequency=%u memory_allocations=0 contexts=%u',13,10>,[frame_width],[frame_height],[present_elapsed],[present_frequency],[wsi_frame_count]
		fastcall OutputDebugStringW,addr title_text
	end iterate
	; The window's modal move/resize loop continues to deliver timer messages.
	fastcall SendMessageW,[window],WM_ENTERSIZEMOVE,0,0
	fastcall SendMessageW,[window],WM_TIMER,1,0
	fastcall SendMessageW,[window],WM_EXITSIZEMOVE,0,0
	fastcall SendMessageW,[window],WM_KEYDOWN,32,0
	mov ebx,[frame_count]
	fastcall SendMessageW,[window],WM_TIMER,1,0
	cmp ebx,[frame_count]
	jne .failed
	fastcall SendMessageW,[window],WM_SIZE,SIZE_MINIMIZED,0
	fastcall SendMessageW,[window],WM_TIMER,1,0
	cmp ebx,[frame_count]
	jne .failed
	fastcall resize_window,500,500
	; A frame must not have touched CPU image or mapped readback storage.
	cmp [capture_count],0
	jne .failed
	cmp [pixels],0
	jne .failed
	cmp [readback_buffer.handle],0
	jne .failed
	require_vk fastcall wsi_drain
	fastcall write_report
	ret
.failed:
	mov [app_io_failed],1
	ret
endp

section '.data$cube_present_test' data readable writeable align 8
present_started dq 0
present_finished dq 0
present_elapsed dq 0
present_frequency dq 0
present_allocations dd 0
