; Vulkan Atlas: a Mandelbrot explorer whose every frame is Vulkan's.
; A source states its build contract (CAP_MASK, CAP_REQUIRED, TILE_CEILING)
; and includes this; see ..\common\vulkan_routes.inc for what a contract does.
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
include 'vk/khr/surface.inc'
include 'vk/khr/win32_surface.inc'
include 'vk/khr/swapchain.inc'
include 'vk/khr/swapchain_maintenance1.inc'
include 'vk/loader/static.inc'
include '..\debug\sink.inc'
include '..\strings.inc'
include '..\common\command_options.inc'
include '..\common\vulkan_routes.inc'

public mainCRTStartup
QS_ALLINPUT := 4FFh
iterate function,GetModuleHandleW,GetCommandLineW,OutputDebugStringW,ExitProcess,CreateFileW,WriteFile,CloseHandle,VirtualAlloc,VirtualFree, \
	RegisterClassExW,CreateWindowExW,DefWindowProcW,DestroyWindow,ShowWindow,UpdateWindow,PeekMessageW,TranslateMessage,DispatchMessageW, \
	WaitMessage,MsgWaitForMultipleObjects,PostQuitMessage,BeginPaint,EndPaint,GetClientRect,LoadCursorW,SendMessageW,MessageBoxW, \
	SetWindowPos,AdjustWindowRectEx,SetWindowTextW,SetTimer,KillTimer,GetSaveFileNameW,wsprintfW,lstrcmpW,lstrcpyW, \
	QueryPerformanceCounter,QueryPerformanceFrequency
	extrn function:qword
end iterate
; For the startup arena behind the shared allocators.
iterate function,GetLargePageMinimum,GetLastError,SetLastError,OpenProcessToken,LookupPrivilegeValueW,AdjustTokenPrivileges
	extrn function:qword
end iterate

GPU_APP_NAME equ 'Vulkan Atlas'
GPU_EXTRA_FORMATS := 1
GPU_WSI := 1
include '..\common\cpu_arena.inc'
include '..\common\vulkan_wsi.inc'
include '..\common\vulkan_context.inc'
include 'view.inc'
include 'tour.inc'
include 'gpu.inc'
include 'export.inc'

; RAX = the name of whichever of a route and its alternate is in use.
macro route_name bit*,selected*,declined*
	local selected_text,declined_text
	alternate bit
		declined_text GLOBWSTR declined,0
		lea rax,[declined_text]
	end alternate
	route bit,.named_#bit
		selected_text GLOBWSTR selected,0
		lea rax,[selected_text]
	end route
.named_#bit:
end macro

section '.text$window' code readable executable align 16
include '..\common\bitmap.inc'

; The title is the status line: contract, the five operations, the picture's
; arithmetic, size, palette and iterations, and where a tour is. It is set
; only when it reads differently, which during a tour is seldom.
proc update_title uses rbx rsi rdi r12 r13 r14 r15
	route_name CAP_RENDER,'dynamic rendering','render pass'
	mov rbx,rax
	route_name CAP_SYNC,'sync2','sync1'
	mov rsi,rax
	route_name CAP_COPY,'copy2','copy1'
	mov rdi,rax
	route_name CAP_INLINE,'inline SPIR-V','shader modules'
	mov r12,rax
	route_name CAP_TIMELINE,'timeline','fence'
	mov r13,rax
	lea r14,[float32_name]
	cmp [precision],PRECISION_FLOAT32
	je .format
	lea r14,[float64_name]
	cmp [precision],PRECISION_FLOAT64
	je .format
	lea r14,[pairs_name]
.format:
	fastcall wsprintfW,addr title_text,<W,'Vulkan Atlas | %s | %s / %s / %s / %s / %s | %s | %u × %u | palette %u | %u iterations'>, \
		addr contract_name,rbx,rsi,rdi,r12,r13,r14,[frame_width],[frame_height],[palette],[iterations]
	cmp [tour_state],TOUR_IDLE
	je .show
	lea r15,[title_text]
	lea r15,[r15+rax*2]
	lea rbx,[tour_stops]
	cmp [tour_state],TOUR_DWELL
	je .at
	mov eax,[tour_next]
	imul eax,sizeof.TourStop
	fastcall wsprintfW,r15,<W,' | tour: to %s'>,[rbx+rax+TourStop.title]
	jmp .show
.at:
	mov eax,[tour_at]
	imul eax,sizeof.TourStop
	fastcall wsprintfW,r15,<W,' | tour: at %s'>,[rbx+rax+TourStop.title]
.show:
	fastcall lstrcmpW,addr title_text,addr shown_title
	test eax,eax
	jz .done
	fastcall lstrcpyW,addr shown_title,addr title_text
	fastcall SetWindowTextW,[window],addr shown_title
.done:
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

proc redraw
	cmp [minimized],0
	jne .done
	fastcall render_frame
	test eax,eax
	jz .failed
	fastcall update_title
.done:
	ret
.failed:
	mov [app_io_failed],1
	fastcall PostQuitMessage,1
	ret
endp

proc export_dialog
	fastcall GetSaveFileNameW,addr save_dialog
	test eax,eax
	jz .done
	fastcall export_view
	test eax,eax
	jz .failed
	fastcall save_bitmap,addr save_path,[pixels],[frame_width],[frame_height]
	test eax,eax
	jnz .done
.failed:
	fastcall MessageBoxW,[window],<W,'Could not write the bitmap.'>,<W,'Vulkan Atlas'>,MB_ICONERROR
.done:
	ret
endp

proc window_proc hwnd,message,wparam,lparam
	mov [hwnd],rcx
	mov [message],rdx
	mov [wparam],r8
	mov [lparam],r9
	iterate <code,target>, WM_PAINT,.paint,WM_SIZE,.size,WM_KEYDOWN,.key,WM_MOUSEWHEEL,.wheel,WM_LBUTTONDOWN,.zoom_in,WM_RBUTTONDOWN,.zoom_out, \
		WM_TIMER,.timer,WM_ENTERSIZEMOVE,.enter_move,WM_EXITSIZEMOVE,.exit_move,WM_GETMINMAXINFO,.minimum,WM_CLOSE,.close,WM_DESTROY,.close
		cmp edx,code
		je target
	end iterate
.default:
	fastcall DefWindowProcW,[hwnd],[message],[wparam],[lparam]
	ret
.paint:
	; The swapchain owns the client area; there is nothing for GDI to draw.
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
	cmp [ready],0
	je .handled
	fastcall resize_client
	jmp .redraw
.timer:
	; The tour's frames while Windows runs a move or size loop of its own.
	fastcall tour_frame
	jmp .handled
.enter_move:
	fastcall SetTimer,[hwnd],1,15,0
	jmp .handled
.exit_move:
	fastcall KillTimer,[hwnd],1
	jmp .handled
.wheel:
	sar r8d,16
	fastcall change_iterations,r8
	jmp .redraw
.zoom_in:
	fastcall zoom_at,r9,0
	jmp .taken
.zoom_out:
	fastcall zoom_at,r9,1
	jmp .taken
.key:
	cmp r8d,VK_ESCAPE
	je .escape
	cmp r8d,KEY_EXPORT
	je .save
	cmp r8d,KEY_TOUR
	je .tour
	fastcall apply_key,r8
	test eax,eax
	jz .default
	cmp eax,VIEW_MOVED
	jne .redraw
.taken:
	; Moving the view by hand takes it from the tour.
	mov [tour_state],TOUR_IDLE
.redraw:
	fastcall redraw
	jmp .handled
.tour:
	fastcall tour_go
	fastcall update_title
	jmp .handled
.escape:
	; Esc ends a tour where it is; with none under way it closes the window.
	cmp [tour_state],TOUR_IDLE
	je .close
	mov [tour_state],TOUR_IDLE
	fastcall update_title
	jmp .handled
.save:
	fastcall export_dialog
	jmp .handled
.minimum:
	mov [r9+MINMAXINFO.ptMinTrackSize.x],200
	mov [r9+MINMAXINFO.ptMinTrackSize.y],200
	jmp .handled
.close:
	fastcall PostQuitMessage,0
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
	fastcall CreateWindowExW,0,addr class_name,<W,'Vulkan Atlas'>,WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,816,599,0,0,[module],0
	test rax,rax
	jz .failed
	mov [window],rax
	mov [save_dialog.hwndOwner],rax
	fastcall resize_window,800,560
	fastcall resize_client
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc write_report uses rbx rsi
	fastcall wsi_drain
	test eax,eax
	jz .report
	mov [gpu_error],eax
	mov [app_io_failed],1
.report:
	fastcall wsprintfW,addr report_text,<W,'contract=%s',13,10,'caps=%u',13,10,'required=%u',13,10,'extensions=%u',13,10,'api=%u',13,10,'target=%u',13,10,'tile=%u',13,10,'tiles=%u',13,10,'precision=%u',13,10,'deep_precision=%u',13,10,'float64_supported=%u',13,10,'iterations=%u',13,10,'wheel_iterations=%u',13,10,'tour_state=%u',13,10,'tour_at=%u',13,10,'tour_next=%u',13,10,'tour_stops=%u',13,10,'idle_frames=%u',13,10,'frames=%u',13,10,'presents=%u',13,10,'exports=%u',13,10,'present_fences=%u',13,10,'width=%u',13,10,'height=%u',13,10,'gpu_error=%d',13,10,'failure_stage=%u',13,10>, \
		addr contract_name,[active_caps],CAP_REQUIRED,[extension_routes],[device_api],[target_format],[tile_size],[tile_count],[precision],[deep_precision],[float64_supported],[iterations],[wheel_iterations],[tour_state],[tour_at],[tour_next],TOUR_STOPS,[idle_frames],[frame_count],[wsi_present_count],[export_count],[wsi_present_fences],[frame_width],[frame_height],[gpu_error],[failure_stage]
	lea esi,[eax*2]
	fastcall CreateFileW,<W,'build\legacy_' bappend CONTRACT_TAG bappend '.report.txt'>,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
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

proc save_view filename
	mov [filename],rcx
	fastcall export_view
	test eax,eax
	jz .failed
	fastcall save_bitmap,[filename],[pixels],[frame_width],[frame_height]
	ret
.failed:
	mov [app_io_failed],1
	ret
endp

; One step of the scripted run: a real window message, then an export.
macro step tag,message,wparam,lparam
	match any, message
		fastcall SendMessageW,[window],message,wparam,lparam
	end match
	match any, tag
		fastcall save_view,<W,'build\legacy_' bappend CONTRACT_TAG bappend tag bappend '.bmp'>
	end match
end macro

; Timer messages until the tour is no longer travelling, each one frame.
; Returns zero if that takes implausibly many.
proc tour_to_arrival uses rbx
	mov ebx,20000
.frame:
	fastcall SendMessageW,[window],WM_TIMER,1,0
	cmp [tour_state],TOUR_TRAVEL
	jne .arrived
	dec ebx
	jnz .frame
	mov [app_io_failed],1
.arrived:
	mov eax,ebx
	ret
endp

proc self_test uses rbx
	step '.base'
	step '.zoom',WM_KEYDOWN,VK_ADD,0
	step '.pan',WM_KEYDOWN,VK_RIGHT,0
	step '.palette',WM_KEYDOWN,KEY_PALETTE,0
	step '.reset',WM_KEYDOWN,KEY_RESET,0
	step '.in',WM_LBUTTONDOWN,MK_LBUTTON,(140 shl 16) or 200
	step '.out',WM_RBUTTONDOWN,MK_RBUTTON,(140 shl 16) or 200
	step '.wheel',WM_MOUSEWHEEL,120*65536,0
	mov eax,[iterations]
	mov [wheel_iterations],eax
	step ,WM_KEYDOWN,KEY_RESET,0
	step '.deep',WM_KEYDOWN,KEY_DEEP,0
	mov eax,[precision]
	mov [deep_precision],eax
	step ,WM_KEYDOWN,KEY_RESET,0
	; The tour: under way, stopped by Esc, taken up again, arrived.
	step ,WM_KEYDOWN,KEY_TOUR,0
	mov ebx,25
.underway:
	fastcall SendMessageW,[window],WM_TIMER,1,0
	dec ebx
	jnz .underway
	step ,WM_KEYDOWN,VK_ESCAPE,0
	mov ebx,[frame_count]
	iterate count, 1,2,3,4,5
		fastcall SendMessageW,[window],WM_TIMER,1,0
	end iterate
	sub ebx,[frame_count]
	neg ebx
	mov [idle_frames],ebx
	step '.tour'
	step ,WM_KEYDOWN,KEY_TOUR,0
	fastcall tour_to_arrival
	step '.arrival'
	step ,WM_KEYDOWN,KEY_RESET,0
	iterate <tag,width,height>, '.wide',1200,500,'.short',640,320,'.narrow',360,640
		fastcall resize_window,width,height
		step tag
	end iterate
	fastcall resize_window,800,560
	fastcall write_report
	ret
endp

; The whole tour, exporting the view at each stop.
proc tour_test uses rbx
	xor ebx,ebx
.leg:
	fastcall SendMessageW,[window],WM_KEYDOWN,KEY_TOUR,0
	fastcall tour_to_arrival
	fastcall wsprintfW,addr save_path,<W,'build\legacy_' bappend CONTRACT_TAG bappend '.stop%u.bmp'>,rbx
	fastcall save_view,addr save_path
	inc ebx
	cmp ebx,TOUR_STOPS
	jb .leg
	fastcall write_report
	ret
endp

proc mainCRTStartup
	fastcall read_options
	test rax,rax
	jz .failed
	fastcall command_option,<W,'--self-test'>
	mov [test_mode],eax
	fastcall command_option,<W,'--tour-test'>
	test eax,eax
	jz .switches
	mov [test_mode],2
.switches:
	; A switch can only take a route away; none forces a feature on.
	iterate <option_text,flag>,'--no-rendering',CAP_RENDER,'--no-sync2',CAP_SYNC,'--no-copy2',CAP_COPY,'--no-inline',CAP_INLINE, \
		'--no-timeline',CAP_TIMELINE,'--no-float64',CAP_FLOAT64
		fastcall command_option,<W,option_text>
		test eax,eax
		jz .keep#flag
		and [requested_caps],not flag
	.keep#flag:
	end iterate
	iterate <option_text,variable,value,tag>,'--api-1.2',api_ceiling,VK_API_VERSION_1_2,api12,'--api-1.1',api_ceiling,VK_API_VERSION_1_1,api11, \
		'--force-khr',force_khr,1,khr,'--no-present-fences',no_present_fences,1,fences
		fastcall command_option,<W,option_text>
		test eax,eax
		jz .unset_#tag
		mov [variable],value
	.unset_#tag:
	end iterate
	fastcall command_option_uint,<W,'--tile-limit='>
	test eax,eax
	jz .startup
	cmp eax,-1
	je .bad_option
	cmp edx,16
	jb .bad_option
	mov [tile_limit],edx
.startup:
	if ~ CAP_MASK and 31
		; Present fences are enabled through a feature chain, which the
		; original physical-device queries of this contract do not have.
		mov [no_present_fences],1
	end if
	fastcall QueryPerformanceFrequency,addr tour_frequency
	mov [large_pages_requested],0
	fastcall create_cpu_arena
	test eax,eax
	jz .failed
	fastcall create_window
	test eax,eax
	jz .failed
	fastcall probe_gpu
	test eax,eax
	jz .failed
	mov eax,[tile_limit]
	cmp eax,[tile_size]
	jae .resources
	mov [tile_size],eax
.resources:
	fastcall create_gpu_resources
	test eax,eax
	jz .failed
	fastcall select_precision
	fastcall render_frame
	test eax,eax
	jz .failed
	fastcall update_title
	mov [ready],1
	cmp [test_mode],0
	je .show
	cmp [test_mode],2
	je .tour_test
	fastcall self_test
	jmp .finish
.tour_test:
	fastcall tour_test
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
	; Nothing moves but a tour. Presentation paces its frames; between
	; them, at a stop or behind another window, wait for a message or a moment.
	cmp [tour_state],TOUR_IDLE
	je .wait
	cmp [minimized],0
	jne .wait
	fastcall tour_frame
	test eax,eax
	jnz .messages
	fastcall MsgWaitForMultipleObjects,0,0,0,15,QS_ALLINPUT
	jmp .messages
.wait:
	fastcall WaitMessage
	jmp .messages
.failed:
	mov [app_io_failed],1
	fastcall wsprintfW,addr title_text,<W,'[legacy] Vulkan initialization or rendering failed (stage=%u, VkResult=%d, missing=%u). Vulkan 1.1, Win32 presentation and a UNORM surface format are required. Missing names what this build cannot do without: 1 dynamic rendering, 2 synchronization2, 4 copy commands2, 8 inline shader code, 16 timeline semaphores, 32 shaderFloat64.',13,10>,[failure_stage],[gpu_error],[missing_caps]
	fastcall OutputDebugStringW,addr title_text
	cmp [test_mode],0
	jne .finish
	fastcall MessageBoxW,[window],addr title_text,<W,'Vulkan Atlas — Vulkan unavailable'>,MB_ICONERROR
	jmp .finish
.bad_option:
	mov [app_io_failed],1
	fastcall OutputDebugStringW,<W,'[legacy] invalid option: use --tile-limit=16 or more.',13,10>
.finish:
	mov [ready],0
	fastcall free_options
	fastcall destroy_gpu
	cmp [window],0
	je .arena
	fastcall DestroyWindow,[window]
	mov [window],0
.arena:
	fastcall destroy_cpu_arena
	fastcall wsprintfW,addr title_text,<W,'[legacy] exit: app_io=%u validation=%u debug_io=%u',13,10>,[app_io_failed],[debug_validation_failed],[debug_io_failed]
	fastcall OutputDebugStringW,addr title_text
	mov eax,[app_io_failed]
	or eax,[debug_validation_failed]
	or eax,[debug_io_failed]
	fastcall ExitProcess,rax
	int3
endp

section '.data$window' data readable writeable align 8
window dq 0
module dq 0
frame_width dd 800
frame_height dd 560
tile_limit dd -1
ready dd 0
minimized dd 0
test_mode dd 0
deep_precision dd 0
wheel_iterations dd 0
idle_frames dd 0
app_io_failed dd 0
save_byte_count dd 0
written dd 0
class_name GLOBWSTR 'VkFasmgLegacyExplorer',0
contract_name GLOBWSTR CONTRACT_NAME,0
float32_name GLOBWSTR 'float32',0
float64_name GLOBWSTR 'float64',0
pairs_name GLOBWSTR 'float32 pairs',0
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
save_dialog OPENFILENAME lStructSize: sizeof.OPENFILENAME,lpstrFilter: filter_text,lpstrFile: save_path,nMaxFile: 512, \
	Flags: OFN_OVERWRITEPROMPT or OFN_PATHMUSTEXIST or OFN_NOCHANGEDIR,lpstrDefExt: extension_text

section '.bss$window' readable writeable align 8
save_path rw 512
title_text rw 1024
shown_title rw 1024
report_text rw 1536
