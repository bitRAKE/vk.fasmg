; GPU-only port of NoGraphicsAPI's spinning textured cube.
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
include 'equates/gdi64.inc'
include 'equates/comdlg64.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/ext/descriptor_heap.inc'
include 'vk/khr/shader_untyped_pointers.inc'
include 'vk/khr/device_address_commands.inc'
include 'vk/khr/surface.inc'
include 'vk/khr/win32_surface.inc'
include 'vk/khr/swapchain.inc'
include 'vk/khr/swapchain_maintenance1.inc'
include 'vk/loader/static.inc'
include '..\debug\sink.inc'
include '..\strings.inc'
include '..\common\command_options.inc'

CAP_MASK = 479
TILE_CEILING = 16384
include '..\common\vulkan_routes.inc'
public mainCRTStartup
iterate function,GetModuleHandleW,GetCommandLineW,OutputDebugStringW,ExitProcess,CreateFileW,WriteFile,CloseHandle,VirtualAlloc,VirtualFree, \
	RegisterClassExW,CreateWindowExW,DefWindowProcW,DestroyWindow,ShowWindow,UpdateWindow,GetMessageW,TranslateMessage,DispatchMessageW, \
	PostQuitMessage,BeginPaint,EndPaint,GetClientRect,LoadCursorW,SendMessageW,MessageBoxW,SetWindowPos,AdjustWindowRectEx, \
	SetWindowTextW,SetTimer,KillTimer,PeekMessageW,WaitMessage,QueryPerformanceCounter,QueryPerformanceFrequency,GetSaveFileNameW,wsprintfW,MultiByteToWideChar
	extrn function:qword
end iterate

iterate function,GetLargePageMinimum,GetLastError,SetLastError,OpenProcessToken,LookupPrivilegeValueW,AdjustTokenPrivileges
	extrn function:qword
end iterate
include '..\common\cpu_arena.inc'
include 'features.inc'
GPU_WSI := 1
include '..\common\vulkan_wsi.inc'
include '..\common\vulkan_context.inc'
include 'scene.inc'
include 'gpu.inc'
include 'present_test.inc'
include 'memory_test.inc'

section '.text$cube_window' code readable executable align 16
include '..\common\bitmap.inc'

proc write_report uses rbx rsi
	fastcall wsi_drain
	test eax,eax
	jz .report
	mov [gpu_error],eax
	mov [app_io_failed],1
.report:
	fastcall wsprintfW,addr report_text,<W,'caps=%u',13,10,'extensions=%u',13,10,'api=%u',13,10,'depth=%u',13,10,'texture=%u',13,10,'target=%u',13,10,'frames=%u',13,10,'width=%u',13,10,'height=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10,'paused=%u',13,10,'presents=%u',13,10,'readbacks=%u',13,10,'material_flags=%u',13,10,'root_bytes=%u',13,10,'large_pages_requested=%u',13,10,'large_pages=%u',13,10,'large_pages_error=%u',13,10,'cpu_arena_bytes=%I64u',13,10,'memory_allocations=%u',13,10,'memory_reuses=%u',13,10,'memory_reserved=%I64u',13,10,'retirement=%I64u',13,10,'retired=%I64u',13,10,'present_fences=%u',13,10,'command_contexts=%u',13,10,'swapchains_retired=%u',13,10,'swapchains_reclaimed=%u',13,10,'swapchains_pending=%u',13,10,'deletes_pending=%u',13,10>,[active_caps],[extension_routes],[device_api],[depth_format],[texture_format],[target_format],[frame_count],[frame_width],[frame_height],[gpu_error],[failure_stage],[paused],[wsi_present_count],[capture_count],[material_flags],ROOT_BYTES,[large_pages_requested],[large_pages_active],[large_pages_error],[cpu_arena_bytes],[memory_allocations],[memory_reuses],[memory_reserved_bytes],[retirement_value],[completed_retirement],[wsi_present_fences],[wsi_frame_count],[wsi_swapchains_retired],[wsi_swapchains_reclaimed],[wsi_retired_count],[gpu_delete_count]
	lea esi,[eax*2]
	fastcall CreateFileW,<W,'build\noAPI_cube.report.txt'>,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
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

proc export_dialog
	fastcall GetSaveFileNameW,addr save_dialog
	test eax,eax
	jz .done
	fastcall capture_frame
	test eax,eax
	jz .failed
	fastcall save_bitmap,addr save_path,[pixels],[frame_width],[frame_height]
	test eax,eax
	jnz .done
.failed:
	fastcall MessageBoxW,[window],<W,'Could not write the bitmap.'>,<W,'NoGraphicsAPI cube'>,MB_ICONERROR
.done:
	ret
endp

proc update_title
	lea r8,[bindings_name]
	test [active_caps],CAP_ADDRESS
	jz .route
	lea r8,[pointer_name]
	test [active_caps],CAP_HEAP
	jz .route
	lea r8,[heap_name]
.route:
	fastcall wsprintfW,addr title_text,<W,'NoGraphicsAPI cube | %s | caps=%u | Space: pause  Arrows: turn  R: reset  S: save'>,r8,[active_caps]
	fastcall SetWindowTextW,[window],addr title_text
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
	jne .allocate
	cmp edx,[frame_height]
	jne .allocate
	jmp .done
.allocate:
	mov [frame_width],eax
	mov [frame_height],edx
	mov [wsi_dirty],1
.done:
	mov eax,1
	ret
endp

proc redraw
	fastcall render_frame
	test eax,eax
	jz .failed
	ret
.failed:
	mov [app_io_failed],1
	fastcall PostQuitMessage,1
	ret
endp

proc window_proc hwnd,message,wparam,lparam
	mov [hwnd],rcx
	mov [message],rdx
	mov [wparam],r8
	mov [lparam],r9
	cmp edx,WM_PAINT
	je .paint
	cmp edx,WM_SIZE
	je .size
	cmp edx,WM_TIMER
	je .timer
	cmp edx,WM_ENTERSIZEMOVE
	je .enter_move
	cmp edx,WM_EXITSIZEMOVE
	je .exit_move
	cmp edx,WM_KEYDOWN
	je .key
	cmp edx,WM_CLOSE
	je .close
	cmp edx,WM_GETMINMAXINFO
	je .minimum
	cmp edx,WM_DESTROY
	je .destroy
.default:
	fastcall DefWindowProcW,[hwnd],[message],[wparam],[lparam]
	ret
.paint:
	fastcall BeginPaint,[hwnd],addr paint
	fastcall EndPaint,[hwnd],addr paint
	jmp .handled
.enter_move:
	fastcall SetTimer,[hwnd],1,16,0
	jmp .handled
.exit_move:
	fastcall KillTimer,[hwnd],1
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
	test eax,eax
	jz .size_failed
	cmp [ready],0
	je .handled
	fastcall redraw
	jmp .handled
.size_failed:
	mov [app_io_failed],1
	fastcall PostQuitMessage,1
	jmp .handled
.timer:
	cmp [minimized],0
	jne .handled
	cmp [paused],0
	jne .handled
	movss xmm0,[angle]
	addss xmm0,[spin_step]
	ucomiss xmm0,[full_turn]
	jb .angle
	subss xmm0,[full_turn]
.angle:
	movss [angle],xmm0
	fastcall redraw
	jmp .handled
.key:
	cmp r8d,27
	je .close
	cmp r8d,32
	je .pause
	cmp r8d,'S'
	je .save
	cmp r8d,'R'
	je .reset
	cmp r8d,37
	je .left
	cmp r8d,39
	jne .default
	movss xmm0,[angle]
	addss xmm0,[spin_step]
	jmp .key_angle
.left:
	movss xmm0,[angle]
	subss xmm0,[spin_step]
.key_angle:
	movss [angle],xmm0
	fastcall redraw
	jmp .handled
.reset:
	mov [angle],0.0
	fastcall redraw
	jmp .handled
.pause:
	xor [paused],1
	jmp .handled
.save:
	fastcall export_dialog
	jmp .handled
.close:
	fastcall PostQuitMessage,0
	jmp .handled
.minimum:
	mov [r9+MINMAXINFO.ptMinTrackSize.x],200
	mov [r9+MINMAXINFO.ptMinTrackSize.y],200
	jmp .handled
.destroy:
	fastcall KillTimer,[hwnd],1
	fastcall PostQuitMessage,0
.handled:
	xor eax,eax
	ret
endp

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
	fastcall CreateWindowExW,0,addr class_name,<W,'NoGraphicsAPI cube'>,WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,516,539,0,0,[module],0
	test rax,rax
	jz .failed
	mov [window],rax
	mov [save_dialog.hwndOwner],rax
	fastcall resize_window,500,500
	fastcall resize_client
	test eax,eax
	jz .failed
	fastcall update_title
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc self_test uses rbx
	fastcall capture_frame
	test eax,eax
	jz .failed
	fastcall save_bitmap,<W,'build\noAPI_cube.bmp'>,[pixels],[frame_width],[frame_height]
	; Use actual timer and key messages, with deterministic frame count and angles.
	mov ebx,10
.spin:
	fastcall SendMessageW,[window],WM_TIMER,1,0
	dec ebx
	jnz .spin
	fastcall capture_frame
	test eax,eax
	jz .failed
	fastcall save_bitmap,<W,'build\noAPI_cube.rotated.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_KEYDOWN,32,0
	fastcall SendMessageW,[window],WM_TIMER,1,0
	fastcall capture_frame
	test eax,eax
	jz .failed
	fastcall save_bitmap,<W,'build\noAPI_cube.paused.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_KEYDOWN,37,0
	fastcall capture_frame
	test eax,eax
	jz .failed
	fastcall save_bitmap,<W,'build\noAPI_cube.turned.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_KEYDOWN,52h,0
	fastcall capture_frame
	test eax,eax
	jz .failed
	fastcall save_bitmap,<W,'build\noAPI_cube.reset.bmp'>,[pixels],[frame_width],[frame_height]
	iterate <width,height,tag>,800,480,'wide',480,320,'short',320,640,'narrow'
		fastcall resize_window,width,height
		fastcall capture_frame
	test eax,eax
	jz .failed
	fastcall save_bitmap,<W,'build\noAPI_cube.' bappend tag bappend '.bmp'>,[pixels],[frame_width],[frame_height]
	end iterate
	fastcall resize_window,500,500
	fastcall write_report
	ret
.failed:
	mov [app_io_failed],1
	ret
endp

proc mainCRTStartup uses rbx
	fastcall read_options
	test rax,rax
	jz .failed
	fastcall command_option,<W,'--self-test'>
	test rax,rax
	setnz al
	movzx eax,al
	mov [test_mode],eax
	fastcall command_option,<W,'--present-test'>
	test eax,eax
	jz .options
	mov [test_mode],2
.options:
	fastcall command_option,<W,'--allocator-test'>
	test eax,eax
	jz .masks
	mov [test_mode],3
.masks:
	iterate <option_text,flag,tag>,'--no-heap',CAP_HEAP,heap,'--no-address',CAP_ADDRESS or CAP_HEAP or CAP_COMMAND_ADDRESS,address,'--no-address-commands',CAP_COMMAND_ADDRESS,commands, \
		'--no-rendering',CAP_RENDER,rendering,'--no-sync2',CAP_SYNC,sync2,'--no-copy2',CAP_COPY,copy2,'--no-inline',CAP_INLINE,inline,'--no-timeline',CAP_TIMELINE,timeline
		.option#tag GLOBWSTR option_text,0
		fastcall command_option,addr .option#tag
		test rax,rax
		jz .keep#tag
		and [requested_caps],not flag
	.keep#tag:
	end iterate
	iterate <option_text,variable,value,tag>,'--compatibility',requested_caps,0,compatibility,'--api-1.2',api_ceiling,VK_API_VERSION_1_2,api12,'--api-1.1',api_ceiling,VK_API_VERSION_1_1,api11, \
		'--force-khr',force_khr,1,khr,'--linear-formats',linear_formats,1,linear,'--depth16',force_d16,1,depth16, \
		'--no-large-pages',large_pages_requested,0,pages,'--large-pages',large_pages_requested,1,large_pages, \
		'--no-present-fences',no_present_fences,1,present_fences,'--compatibility',no_present_fences,1,compat_present, \
		'--dedicated-memory',force_dedicated,1,dedicated,'--small-pools',image_pool_bytes,4*1024*1024,small_pools, \
		'--noncoherent',force_noncoherent,1,noncoherent
		.option#tag GLOBWSTR option_text,0
		fastcall command_option,addr .option#tag
		test rax,rax
		jz .keep#tag
		mov [variable],value
	.keep#tag:
	end iterate
	iterate <option_text,variable,minimum,tag>,'--cpu-heap-mib=',cpu_arena_configured_bytes,2,cpu_heap,'--buffer-pool-mib=',buffer_pool_bytes,1,buffer_pool,'--image-pool-mib=',image_pool_bytes,1,image_pool
		fastcall command_option_uint,<W,option_text>
		test eax,eax
		jz .default#tag
		cmp eax,-1
		je .bad_configuration
		cmp edx,minimum
		jb .bad_configuration
		cmp edx,1024
		ja .bad_configuration
		shl edx,20
		mov [variable],edx
	.default#tag:
	end iterate
	fastcall create_cpu_arena
	test eax,eax
	jz .failed
	fastcall wsprintfW,addr title_text,<W,'[cube memory] startup arena=%I64u large_pages=%u fallback_error=%u',13,10>,[cpu_arena_bytes],[large_pages_active],[large_pages_error]
	fastcall OutputDebugStringW,addr title_text
	fastcall create_window
	test eax,eax
	jz .failed
	fastcall probe_gpu
	test eax,eax
	jz .failed
	fastcall create_gpu_resources
	test eax,eax
	jz .failed
	fastcall update_title
	fastcall render_frame
	test eax,eax
	jz .failed
	mov [ready],1
	cmp [test_mode],0
	je .show
	cmp [test_mode],2
	je .present_test
	cmp [test_mode],3
	je .memory_test
	fastcall self_test
	jmp .finish
.present_test:
	fastcall present_test
	jmp .finish
.memory_test:
	fastcall memory_test
	jmp .finish
.show:
	fastcall ShowWindow,[window],SW_SHOWNORMAL
	fastcall UpdateWindow,[window]
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
	cmp [paused],0
	jne .wait
	cmp [minimized],0
	jne .wait
	fastcall SendMessageW,[window],WM_TIMER,1,0
	jmp .messages
.wait:
	fastcall WaitMessage
	jmp .messages
.failed:
	mov [app_io_failed],1
	fastcall wsprintfW,addr title_text,<W,'[cube] GPU initialization/rendering failed (stage=%u, VkResult=%d). Vulkan 1.1, Win32 presentation, a graphics queue, color/texture formats, and a depth format are required.',13,10>,[failure_stage],[gpu_error]
	fastcall OutputDebugStringW,addr title_text
	cmp [test_mode],0
	jne .finish
	fastcall MessageBoxW,[window],addr title_text,<W,'NoGraphicsAPI cube — GPU unavailable'>,MB_ICONERROR
	jmp .finish
.bad_configuration:
	mov [app_io_failed],1
	fastcall OutputDebugStringW,<W,'[cube] invalid startup heap configuration: use --cpu-heap-mib=2..1024 and --buffer-pool-mib/--image-pool-mib=1..1024.',13,10>
.finish:
	mov [ready],0
	fastcall free_options
	fastcall destroy_gpu
	cmp [window],0
	je .pixels
	fastcall DestroyWindow,[window]
	mov [window],0
.pixels:
	cmp [pixels],0
	je .exit
	fastcall VirtualFree,[pixels],0,MEM_RELEASE
.exit:
	fastcall destroy_cpu_arena
	fastcall wsprintfW,addr title_text,<W,'[cube] exit: app_io=%u validation=%u debug_io=%u',13,10>,[app_io_failed],[debug_validation_failed],[debug_io_failed]
	fastcall OutputDebugStringW,addr title_text
	mov eax,[app_io_failed]
	or eax,[debug_validation_failed]
	or eax,[debug_io_failed]
	fastcall ExitProcess,rax
	int3
endp

section '.data$cube_window' data readable writeable align 8
window dq 0
module dq 0
pixels dq 0
frame_width dd 500
frame_height dd 500
ready dd 0
paused dd 0
minimized dd 0
test_mode dd 0
linear_formats dd 0
force_d16 dd 0
app_io_failed dd 0
save_byte_count dd 0
written dd 0
class_name GLOBWSTR 'VkFasmgNoAPICube',0
bindings_name GLOBWSTR 'vertex bindings / descriptor sets',0
pointer_name GLOBWSTR 'GPU pointers / descriptor sets',0
heap_name GLOBWSTR 'GPU pointers / descriptor heaps',0
window_class WNDCLASSEX cbSize: sizeof.WNDCLASSEX,lpfnWndProc: window_proc,lpszClassName: class_name
client_rect RECT
window_rect RECT
paint PAINTSTRUCT
message MSG
bitmap_file_header:
	db 'BM'
.length dd 0
	dw 0,0
	dd 54
.info BITMAPINFOHEADER biSize: sizeof.BITMAPINFOHEADER,biPlanes: 1,biBitCount: 32,biCompression: BI_RGB
filter_text GLOBWSTR 'Bitmap image (*.bmp)',0,'*.bmp',0,0
extension_text GLOBWSTR 'bmp',0
save_dialog OPENFILENAME lStructSize: sizeof.OPENFILENAME,lpstrFilter: filter_text,lpstrFile: save_path,nMaxFile: 512,Flags: OFN_OVERWRITEPROMPT or OFN_PATHMUSTEXIST or OFN_NOCHANGEDIR,lpstrDefExt: extension_text
section '.bss$cube_window' readable writeable align 8
save_path rw 512
title_text rw 1024
report_text rw 1024
