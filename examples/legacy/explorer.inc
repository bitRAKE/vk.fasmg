; Three builds share this complete Win32 GUI, camera, palette, and BMP exporter.
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
include 'vk/loader/static.inc'
include '..\debug\sink.inc'
include '..\strings.inc'

FRAME_WIDTH := 512
FRAME_HEIGHT := 384
FRAME_BYTES := FRAME_WIDTH * FRAME_HEIGHT * 4
CANVAS_TOP := 168
DIB_RGB_COLORS := 0
public mainCRTStartup

iterate function,GetModuleHandleW,GetCommandLineW,GetTickCount64,GetLastError,OutputDebugStringW,ExitProcess,CreateFileW,WriteFile,CloseHandle, \
	RegisterClassExW,CreateWindowExW,DefWindowProcW,DestroyWindow,ShowWindow,UpdateWindow,GetMessageW,TranslateMessage,DispatchMessageW, \
	PostQuitMessage,BeginPaint,EndPaint,GetClientRect,InvalidateRect,LoadCursorW,SendMessageW,MessageBoxW,SetFocus,MoveWindow,SetWindowPos,GetDC,ReleaseDC, \
	CreateSolidBrush,DeleteObject,SelectObject,SetTextColor,SetBkMode,DrawTextW,FillRect,StretchDIBits, \
	CreateFontW,CreateCompatibleDC,DeleteDC,CreateDIBSection,SetViewportOrgEx,GetSaveFileNameW,StrStrIW,wsprintfW,VirtualAlloc,VirtualFree
	extrn function:qword
end iterate

include 'capabilities.inc'
include 'gpu.inc'
include 'cpu.inc'

section '.text$gui' code readable executable align 16
proc save_bitmap uses rbx rsi rdi,filename,source,width,height
	mov [source],rdx
	mov [bitmap_file_header.info.biWidth],r8d
	neg r9d
	mov [bitmap_file_header.info.biHeight],r9d
	neg r9d
	imul r8d,r9d
	shl r8d,2
	mov [save_byte_count],r8d
	mov [bitmap_file_header.info.biSizeImage],r8d
	add r8d,54
	mov [bitmap_file_header.length],r8d
	fastcall CreateFileW,rcx,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .failed
	mov rbx,rax
	fastcall WriteFile,rbx,addr bitmap_file_header,54,addr written,0
	test eax,eax
	jz .close_failed
	cmp [written],54
	jne .close_failed
	mov rsi,[source]
	mov edi,[save_byte_count]
.write:
	test edi,edi
	jz .success
	fastcall WriteFile,rbx,rsi,rdi,addr written,0
	test eax,eax
	jz .close_failed
	mov eax,[written]
	test eax,eax
	jz .close_failed
	add rsi,rax
	sub edi,eax
	jmp .write
.success:
	fastcall CloseHandle,rbx
	test eax,eax
	jz .failed
	mov eax,1
	ret
.close_failed:
	fastcall CloseHandle,rbx
.failed:
	mov [app_io_failed],1
	xor eax,eax
	ret
endp

proc export_dialog
	fastcall GetSaveFileNameW,addr save_dialog
	test eax,eax
	jz .done
	fastcall save_bitmap,addr save_path,[pixels],[frame_width],[frame_height]
	test eax,eax
	jnz .done
	fastcall MessageBoxW,[window],<W,'Could not write the bitmap.'>,<W,'Vulkan Atlas'>,MB_ICONERROR
.done:
	ret
endp

; Shared by toolbar clicks, keyboard input, and the scripted GUI regression.
proc apply_action action
	cmp ecx,100
	je .zoom_in
	cmp ecx,101
	je .zoom_out
	cmp ecx,102
	je .reset
	cmp ecx,103
	je .palette
	cmp ecx,104
	je .export
	cmp ecx,105
	je .backend
	cmp ecx,106
	je .deep
	movsd xmm0,[view_scale]
	mulsd xmm0,[pan_fraction]
	cmp ecx,107
	je .left
	cmp ecx,108
	je .right
	cmp ecx,109
	je .up
	cmp ecx,110
	je .down
	xor eax,eax
	ret
.zoom_in:
	movsd xmm0,[view_scale]
	divsd xmm0,[two_double]
	maxsd xmm0,[minimum_scale]
	jmp .scale
.zoom_out:
	movsd xmm0,[view_scale]
	mulsd xmm0,[two_double]
	minsd xmm0,[maximum_scale]
.scale:
	movsd [view_scale],xmm0
	jmp .changed
.left:
	movsd xmm1,[center_x]
	subsd xmm1,xmm0
	movsd [center_x],xmm1
	jmp .changed
.right:
	addsd xmm0,[center_x]
	movsd [center_x],xmm0
	jmp .changed
.up:
	movsd xmm1,[center_y]
	subsd xmm1,xmm0
	movsd [center_y],xmm1
	jmp .changed
.down:
	addsd xmm0,[center_y]
	movsd [center_y],xmm0
	jmp .changed
.reset:
	mov rax,[default_x]
	mov [center_x],rax
	mov [center_y],0
	mov rax,[default_scale]
	mov [view_scale],rax
	mov [palette],0
	jmp .changed
.palette:
	inc [palette]
	and [palette],7
	jmp .changed
.backend:
	xor [software_override],1
	jmp .changed
.deep:
	mov rax,[deep_x]
	mov [center_x],rax
	mov rax,[deep_y]
	mov [center_y],rax
	mov rax,[deep_scale]
	mov [view_scale],rax
.changed:
	mov eax,1
	ret
.export:
	fastcall export_dialog
	xor eax,eax
	ret
endp

proc update_status uses rbx rsi rdi
	lea rbx,[cpu_status]
	cmp [last_backend],0
	je .status
	lea rbx,[gpu_status]
	cmp [last_backend],2
	jne .status
	lea rbx,[gpu64_status]
.status:
	fastcall wsprintfW,addr status_text,<W,'%s   |   %u × %u   |   %u ms   |   palette %u'>,rbx,[frame_width],[frame_height],[render_ms],[palette]
	lea rbx,[renderpass_text]
	lea rsi,[sync1_text]
	lea rdi,[copy1_text]
	test [active_caps],CAP_RENDER
	jz .sync
	lea rbx,[rendering_text]
.sync:
	test [active_caps],CAP_SYNC
	jz .copy
	lea rsi,[sync2_text]
.copy:
	test [active_caps],CAP_COPY
	jz .format
	lea rdi,[copy2_text]
.format:
	lea rax,[modules_text]
	test [active_caps],CAP_INLINE
	jz .modules
	lea rax,[inline_text]
.modules:
	mov [shader_status],rax
	lea rax,[fence_text]
	test [active_caps],CAP_TIMELINE
	jz .completion
	lea rax,[timeline_text]
.completion:
	mov [completion_status],rax
	fastcall wsprintfW,addr route_text,<W,'%s  /  %s  /  %s  /  %s  /  %s'>,rbx,rsi,rdi,[shader_status],[completion_status]
	cmp [last_backend],0
	jne .done
	fastcall wsprintfW,addr route_text,<W,'Software renderer   /   same camera, palette and full-size BMP export'>
.done:
	ret
endp

; Derive every rectangle from the client, wrap toolbar controls, and replace
; only the host image on resize. The reusable GPU tile resources stay bounded.
proc update_layout uses rbx rsi rdi r12 r13
	fastcall GetClientRect,[window],addr client_rect
	cmp [client_rect.right],0
	jle .unchanged
	cmp [client_rect.bottom],0
	jle .unchanged
	mov eax,[client_rect.right]
	sub eax,16
	mov [title_rect.right],eax
	mov [subtitle_rect.right],eax
	mov [status_rect.right],eax
	mov [route_rect.right],eax
	mov [footer_rect.right],eax
	mov [footer_rect.top],0
	mov [footer_rect.bottom],0
	fastcall GetDC,[window]
	test rax,rax
	jz .failed
	mov rbx,rax
	fastcall SelectObject,rbx,[body_font]
	mov rdi,rax
	fastcall DrawTextW,rbx,addr footer_text,-1,addr footer_rect,DT_WORDBREAK or DT_CALCRECT
	mov esi,eax
	fastcall SelectObject,rbx,rdi
	fastcall ReleaseDC,[window],rbx
	mov eax,[client_rect.right]
	sub eax,16
	mov [footer_rect.right],eax
	mov eax,[client_rect.bottom]
	sub eax,12
	mov [footer_rect.bottom],eax
	sub eax,esi
	mov [footer_rect.top],eax
	lea rsi,[buttons]
	xor ebx,ebx
	mov r12d,16
	mov r13d,88
.button:
	mov eax,[rsi+Button.width]
	add eax,r12d
	cmp eax,[footer_rect.right]
	jbe .place
	cmp r12d,16
	je .place
	mov r12d,16
	add r13d,42
.place:
	mov [rsi+Button.x],r12d
	mov [rsi+Button.y],r13d
	lea rcx,[button_handles]
	mov rcx,[rcx+rbx*8]
	fastcall MoveWindow,rcx,r12,r13,[rsi+Button.width],34,1
	add r12d,[rsi+Button.width]
	add r12d,8
	add rsi,sizeof.Button
	inc ebx
	cmp ebx,7
	jb .button
	lea eax,[r13d+38]
	mov [status_rect.top],eax
	add eax,20
	mov [status_rect.bottom],eax
	inc eax
	mov [route_rect.top],eax
	add eax,20
	mov [route_rect.bottom],eax
	inc eax
	mov [canvas_top],eax
	mov ecx,[footer_rect.top]
	sub ecx,12
	sub ecx,eax
	cmp ecx,1
	jge .height
	mov ecx,1
.height:
	mov [canvas_height],ecx
	mov eax,[client_rect.right]
	mov [canvas_width],eax
	mov [canvas_left],0
	cmp [pixels],0
	je .allocate
	cmp eax,[frame_width]
	jne .allocate
	cmp ecx,[frame_height]
	je .unchanged
.allocate:
	imul rax,rcx
	lea rdx,[rax*4]
	fastcall VirtualAlloc,0,rdx,MEM_RESERVE or MEM_COMMIT,PAGE_READWRITE
	test rax,rax
	jz .failed
	mov rsi,rax
	cmp [pixels],0
	je .dimensions
	fastcall VirtualFree,[pixels],0,MEM_RELEASE
.dimensions:
	mov [pixels],rsi
	mov eax,[canvas_width]
	mov [frame_width],eax
	mov [dib_info.biWidth],eax
	cvtsi2sd xmm0,eax
	movsd [frame_width_double],xmm0
	mulsd xmm0,[half_double]
	movsd [frame_half_width],xmm0
	mov eax,[canvas_height]
	mov [frame_height],eax
	neg eax
	mov [dib_info.biHeight],eax
	neg eax
	cvtsi2sd xmm0,eax
	movsd [frame_height_double],xmm0
	mulsd xmm0,[half_double]
	movsd [frame_half_height],xmm0
	mov eax,1
	ret
.failed:
	mov [app_io_failed],1
.unchanged:
	xor eax,eax
	ret
endp

proc paint_canvas uses rbx rsi rdi,dc
	mov rbx,rcx
	fastcall FillRect,rbx,addr client_rect,[background_brush]
	fastcall SetBkMode,rbx,TRANSPARENT
	fastcall SetTextColor,rbx,0F4F0E8h
	fastcall SelectObject,rbx,[title_font]
	fastcall DrawTextW,rbx,<W,'VULKAN ATLAS'>,-1,addr title_rect,DT_SINGLELINE or DT_END_ELLIPSIS
	fastcall SelectObject,rbx,[body_font]
	fastcall SetTextColor,rbx,0BEB3A1h
	fastcall DrawTextW,rbx,addr subtitle_text,-1,addr subtitle_rect,DT_SINGLELINE or DT_END_ELLIPSIS
	fastcall update_status
	fastcall DrawTextW,rbx,addr status_text,-1,addr status_rect,DT_SINGLELINE or DT_END_ELLIPSIS
	fastcall SetTextColor,rbx,089A388h
	fastcall DrawTextW,rbx,addr route_text,-1,addr route_rect,DT_SINGLELINE or DT_END_ELLIPSIS
	; The image dimensions match the entire render rectangle: no bars or stretch.
	fastcall StretchDIBits,rbx,0,[canvas_top],[canvas_width],[canvas_height], \
		0,0,[frame_width],[frame_height],[pixels],addr dib_info,DIB_RGB_COLORS,SRCCOPY
	fastcall DrawTextW,rbx,addr footer_text,-1,addr footer_rect,DT_WORDBREAK
	ret
endp

proc recenter position
	movsx eax,cx
	sar ecx,16
	cmp ecx,[canvas_top]
	jl .done
	sub eax,[canvas_left]
	js .done
	cmp eax,[canvas_width]
	jae .done
	sub ecx,[canvas_top]
	cmp ecx,[canvas_height]
	jae .done
	cvtsi2sd xmm0,eax
	cvtsi2sd xmm1,dword [canvas_width]
	divsd xmm0,xmm1
	mulsd xmm0,[frame_width_double]
	subsd xmm0,[frame_half_width]
	cvtsi2sd xmm1,ecx
	cvtsi2sd xmm2,dword [canvas_height]
	divsd xmm1,xmm2
	mulsd xmm1,[frame_height_double]
	subsd xmm1,[frame_half_height]
	movsd xmm2,[view_scale]
	divsd xmm2,[frame_height_double]
	mulsd xmm0,xmm2
	mulsd xmm1,xmm2
	addsd xmm0,[center_x]
	addsd xmm1,[center_y]
	movsd [center_x],xmm0
	movsd [center_y],xmm1
.done:
	ret
endp

proc window_proc hwnd,message,wparam,lparam
	mov [hwnd],rcx
	mov [message],rdx
	mov [wparam],r8
	mov [lparam],r9
	cmp edx,WM_DESTROY
	je .destroy
	cmp edx,WM_PAINT
	je .paint
	cmp edx,WM_PRINTCLIENT
	je .print
	cmp edx,WM_SIZE
	je .size
	cmp edx,WM_GETMINMAXINFO
	je .minimum
	cmp edx,WM_ERASEBKGND
	je .erased
	cmp edx,WM_COMMAND
	je .command
	cmp edx,WM_KEYDOWN
	je .key
	cmp edx,WM_MOUSEWHEEL
	je .wheel
	cmp edx,WM_LBUTTONDOWN
	je .recenter
	fastcall DefWindowProcW,rcx,rdx,r8,r9
	ret
.key:
	mov ecx,r8d
	iterate <key,action_id>,52h,102,50h,103,53h,104,43h,105,44h,106,VK_LEFT,107,VK_RIGHT,108,VK_UP,109,VK_DOWN,110,VK_ADD,100,0BBh,100,VK_SUBTRACT,101,0BDh,101
		cmp ecx,key
		je .key#key
	end iterate
	jmp .handled
	iterate <key,action_id>,52h,102,50h,103,53h,104,43h,105,44h,106,VK_LEFT,107,VK_RIGHT,108,VK_UP,109,VK_DOWN,110,VK_ADD,100,0BBh,100,VK_SUBTRACT,101,0BDh,101
	.key#key:
		mov ecx,action_id
		jmp .action
	end iterate
.wheel:
	sar r8d,16
	mov ecx,100
	test r8w,r8w
	jg .action
	mov ecx,101
	jmp .action
.command:
	; Keep keyboard shortcuts on the canvas after a toolbar button is clicked.
	fastcall SetFocus,[hwnd]
	mov rcx,[wparam]
	and ecx,0FFFFh
.action:
	fastcall apply_action,rcx
	test eax,eax
	jz .handled
	jmp .render
.recenter:
	fastcall recenter,r9
.render:
	fastcall render_frame
	jmp .invalidate
.size:
	cmp [window],0
	je .handled
	cmp [wparam],SIZE_MINIMIZED
	je .handled
	fastcall update_layout
	test eax,eax
	jnz .render
.invalidate:
	fastcall InvalidateRect,[hwnd],0,0
	jmp .handled
.paint:
	fastcall BeginPaint,[hwnd],addr paint
	fastcall paint_canvas,rax
	fastcall EndPaint,[hwnd],addr paint
	jmp .handled
.print:
	fastcall paint_canvas,r8
	jmp .handled
.destroy:
	fastcall PostQuitMessage,0
.handled:
	xor eax,eax
	ret
.erased:
	mov eax,1
	ret
.minimum:
	mov dword [r9+MINMAXINFO.ptMinTrackSize+POINT.x],420
	mov dword [r9+MINMAXINFO.ptMinTrackSize+POINT.y],420
	jmp .handled
endp

proc create_gui uses rbx rsi
	fastcall GetModuleHandleW,0
	mov [app_module],rax
	mov [window_class.hInstance],rax
	fastcall LoadCursorW,0,IDC_ARROW
	mov [window_class.hCursor],rax
	fastcall RegisterClassExW,addr window_class
	test eax,eax
	jz .failed
	fastcall CreateSolidBrush,001A0F0Ah
	mov [background_brush],rax
	fastcall CreateFontW,-28,0,0,0,FW_BOLD,0,0,0,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,<W,'Segoe UI'>
	mov [title_font],rax
	fastcall CreateFontW,-16,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,0,0,CLEARTYPE_QUALITY,0,<W,'Segoe UI'>
	mov [body_font],rax
	fastcall CreateWindowExW,0,addr class_name,<W,'Vulkan Atlas — Mandelbrot explorer'>,WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN, \
		CW_USEDEFAULT,CW_USEDEFAULT,1000,760,0,0,[app_module],0
	test rax,rax
	jz .failed
	mov [window],rax
	mov [save_dialog.hwndOwner],rax
	mov ebx,100
	lea rsi,[buttons]
.button:
	fastcall CreateWindowExW,0,<W,'BUTTON'>,[rsi+Button.text],WS_CHILD or WS_VISIBLE or WS_TABSTOP, \
		[rsi+Button.x],88,[rsi+Button.width],34,[window],rbx,[app_module],0
	test rax,rax
	jz .failed
	lea rcx,[button_handles]
	mov edx,ebx
	sub edx,100
	mov [rcx+rdx*8],rax
	fastcall SendMessageW,rax,WM_SETFONT,[body_font],1
	inc ebx
	add rsi,sizeof.Button
	cmp ebx,107
	jb .button
	fastcall update_layout
	cmp [pixels],0
	je .failed
	mov eax,1
	ret
.failed:
	fastcall GetLastError
	fastcall wsprintfW,addr status_text,<W,'[legacy] create_gui failed: %u',13,10>,rax
	fastcall OutputDebugStringW,addr status_text
	xor eax,eax
	ret
endp

proc save_gui_snapshot uses rbx rsi rdi,filename
	mov [filename],rcx
	fastcall GetClientRect,[window],addr client_rect
	mov eax,[client_rect.right]
	mov [snapshot_info.biWidth],eax
	mov eax,[client_rect.bottom]
	neg eax
	mov [snapshot_info.biHeight],eax
	fastcall CreateCompatibleDC,0
	test rax,rax
	jz .failed
	mov rbx,rax
	fastcall CreateDIBSection,rbx,addr snapshot_info,DIB_RGB_COLORS,addr snapshot_pixels,0,0
	test rax,rax
	jz .dc_failed
	mov rsi,rax
	fastcall SelectObject,rbx,rsi
	mov rdi,rax
	; Print in client coordinates. WM_PRINT's automatic child placement includes
	; the top-level nonclient origin on some themes, so place each child explicitly.
	fastcall SendMessageW,[window],WM_PRINTCLIENT,rbx,PRF_CLIENT
	mov [snapshot_old_bitmap],rdi
	xor edi,edi
.button:
	mov eax,edi
	imul eax,sizeof.Button
	lea rcx,[buttons]
	mov edx,[rcx+rax+Button.x]
	mov r8d,[rcx+rax+Button.y]
	fastcall SetViewportOrgEx,rbx,rdx,r8,0
	lea rcx,[button_handles]
	mov rcx,[rcx+rdi*8]
	fastcall SendMessageW,rcx,WM_PRINT,rbx,PRF_CLIENT or PRF_ERASEBKGND
	inc edi
	cmp edi,7
	jb .button
	fastcall SetViewportOrgEx,rbx,0,0,0
	fastcall save_bitmap,[filename],[snapshot_pixels],[client_rect.right],[client_rect.bottom]
	fastcall SelectObject,rbx,[snapshot_old_bitmap]
	fastcall DeleteObject,rsi
	fastcall DeleteDC,rbx
	ret
.dc_failed:
	fastcall DeleteDC,rbx
.failed:
	mov [app_io_failed],1
	ret
endp

; Save the shared report buffer as UTF-16 without a BOM.
proc save_report uses rbx,filename
	fastcall CreateFileW,rcx,GENERIC_WRITE,FILE_SHARE_READ,0,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0
	cmp rax,-1
	je .failed
	mov rbx,rax
	lea rcx,[report_text]
	xor edx,edx
.length:
	cmp word [rcx+rdx*2],0
	je .write
	inc edx
	jmp .length
.write:
	shl edx,1
	mov r8d,edx
	mov [save_byte_count],r8d
	fastcall WriteFile,rbx,addr report_text,r8,addr written,0
	test eax,eax
	jz .close_failed
	mov eax,[save_byte_count]
	cmp [written],eax
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

proc save_layout_report uses rbx,filename
	mov rbx,rcx
	fastcall wsprintfW,addr report_text,<W,'width=%u',13,10,'height=%u',13,10,'canvas_top=%u',13,10,'footer_top=%u',13,10,'footer_bottom=%u',13,10,'client_height=%u',13,10>, \
		[frame_width],[frame_height],[canvas_top],[footer_rect.top],[footer_rect.bottom],[client_rect.bottom]
	fastcall save_report,rbx
	ret
endp

proc self_test
	fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_COMMAND,100,0
	fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.zoom.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_COMMAND,108,0
	fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.pan.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_COMMAND,103,0
	fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.changed.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_COMMAND,102,0
	fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.reset.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_COMMAND,106,0
	mov eax,[last_backend]
	mov [deep_backend],eax
	fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.deep.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall save_gui_snapshot,<W,'build\legacy_' bappend PROFILE_TAG bappend '.deep.gui.bmp'>
	fastcall SendMessageW,[window],WM_COMMAND,105,0
	fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.deep.cpu.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_COMMAND,105,0
	fastcall SendMessageW,[window],WM_COMMAND,102,0
	fastcall SendMessageW,[window],WM_COMMAND,105,0
	mov eax,[last_backend]
	mov [cpu_backend],eax
	fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.cpu.bmp'>,[pixels],[frame_width],[frame_height]
	fastcall SendMessageW,[window],WM_COMMAND,105,0
	fastcall save_gui_snapshot,<W,'build\legacy_' bappend PROFILE_TAG bappend '.gui.bmp'>
	fastcall save_layout_report,<W,'build\legacy_' bappend PROFILE_TAG bappend '.layout.txt'>
	iterate <size_tag,width,height>, 'wide',1400,900,'short',1000,420,'narrow',440,650
		fastcall SetWindowPos,[window],0,0,0,width,height,SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE
		fastcall save_bitmap,<W,'build\legacy_' bappend PROFILE_TAG bappend '.' bappend size_tag bappend '.bmp'>,[pixels],[frame_width],[frame_height]
		fastcall save_gui_snapshot,<W,'build\legacy_' bappend PROFILE_TAG bappend '.' bappend size_tag bappend '.gui.bmp'>
		fastcall save_layout_report,<W,'build\legacy_' bappend PROFILE_TAG bappend '.' bappend size_tag bappend '.layout.txt'>
	end iterate
	fastcall SetWindowPos,[window],0,0,0,1000,760,SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE
	fastcall wsprintfW,addr report_text,<W,'profile=%s',13,10,'backend=%u',13,10,'caps=%u',13,10,'extensions=%u',13,10,'tile=%u',13,10,'tiles=%u',13,10,'deep_backend=%u',13,10,'cpu_backend=%u',13,10,'frames=%u',13,10,'gpu_error=%d',13,10,'api=%u',13,10,'width=%u',13,10,'height=%u',13,10,'float64_supported=%u',13,10>, \
		addr profile_name,[last_backend],[active_caps],[extension_routes],[tile_size],[tile_count],[deep_backend],[cpu_backend],[frame_count],[gpu_error],[device_api],[frame_width],[frame_height],[float64_supported]
	fastcall save_report,<W,'build\legacy_' bappend PROFILE_TAG bappend '.report.txt'>
	ret
endp

proc mainCRTStartup uses rbx
	fastcall GetCommandLineW
	mov rbx,rax
	fastcall StrStrIW,rbx,<W,'--self-test'>
	test rax,rax
	setnz al
	movzx eax,al
	mov [test_mode],eax
	fastcall StrStrIW,rbx,<W,'--force-khr'>
	test rax,rax
	setnz al
	movzx eax,al
	mov [force_khr],eax
	fastcall StrStrIW,rbx,<W,'--api-1.2'>
	test rax,rax
	jz .mask
	mov [api_ceiling],VK_API_VERSION_1_2
.mask:
	iterate <option,flag>, '--no-rendering',CAP_RENDER,'--no-sync2',CAP_SYNC,'--no-copy2',CAP_COPY,'--no-inline',CAP_INLINE,'--no-timeline',CAP_TIMELINE,'--no-float64',CAP_FLOAT64
		.local_name#flag GLOBWSTR option,0
		fastcall StrStrIW,rbx,addr .local_name#flag
		test rax,rax
		jz .keep#flag
		and [requested_caps],not flag
	.keep#flag:
	end iterate
	fastcall probe_gpu
	test eax,eax
	jz .cpu
	fastcall create_gpu_resources
	test eax,eax
	jz .cpu
	mov [gpu_ready],1
	jmp .gui
.cpu:
	fastcall destroy_gpu
.gui:
	fastcall create_gui
	test eax,eax
	jz .failed
	fastcall render_frame
	cmp [test_mode],0
	je .show
	fastcall self_test
	fastcall DestroyWindow,[window]
	jmp .finish
.show:
	fastcall ShowWindow,[window],SW_SHOWNORMAL
	fastcall UpdateWindow,[window]
.message:
	fastcall GetMessageW,addr message,0,0,0
	test eax,eax
	jle .finish
	fastcall TranslateMessage,addr message
	fastcall DispatchMessageW,addr message
	jmp .message
.failed:
	mov [app_io_failed],1
.finish:
	fastcall destroy_gpu
	cmp [pixels],0
	je .fonts
	fastcall VirtualFree,[pixels],0,MEM_RELEASE
.fonts:
	fastcall DeleteObject,[background_brush]
	fastcall DeleteObject,[title_font]
	fastcall DeleteObject,[body_font]
	fastcall wsprintfW,addr status_text,<W,'[legacy] exit: app_io=%u validation=%u debug_io=%u',13,10>,[app_io_failed],[debug_validation_failed],[debug_io_failed]
	fastcall OutputDebugStringW,addr status_text
	mov eax,[app_io_failed]
	or eax,[debug_validation_failed]
	or eax,[debug_io_failed]
	fastcall ExitProcess,rax
	int3
endp

struct Button
	text dq ?
	x dd ?
	width dd ?
	y dd 88
ends

section '.data$gui' data readable writeable align 16
window dq 0
app_module dq 0
background_brush dq 0
title_font dq 0
body_font dq 0
snapshot_pixels dq 0
snapshot_old_bitmap dq 0
button_handles rq 7
shader_status dq 0
completion_status dq 0
canvas_left dd 16
canvas_top dd CANVAS_TOP
canvas_width dd 512
canvas_height dd 384
frame_width dd FRAME_WIDTH
frame_height dd FRAME_HEIGHT
pixels dq 0
frame_width_double dq FRAME_WIDTH*1.0
frame_height_double dq FRAME_HEIGHT*1.0
frame_half_width dq FRAME_WIDTH*0.5
frame_half_height dq FRAME_HEIGHT*0.5
app_io_failed dd 0
test_mode dd 0
deep_backend dd 0
cpu_backend dd 0
save_byte_count dd 0
written dd 0
class_name GLOBWSTR 'VkFasmgLegacyExplorer',0
profile_name GLOBWSTR PROFILE_NAME,0
subtitle_text GLOBWSTR 'MANDELBROT EXPLORER   /   ' bappend PROFILE_NAME bappend ' profile   /   full-resolution export',0
cpu_status GLOBWSTR 'CPU double precision — all controls available',0
gpu_status GLOBWSTR 'Vulkan GPU float32',0
gpu64_status GLOBWSTR 'Vulkan GPU float64',0
footer_text GLOBWSTR 'Wheel / +/-: zoom    Arrows: pan    P: palette    R: reset    D: deep zoom    S: export',0
renderpass_text GLOBWSTR 'Render-pass cache',0
rendering_text GLOBWSTR 'Dynamic rendering',0
sync1_text GLOBWSTR 'Sync1 / submit1',0
sync2_text GLOBWSTR 'Sync2 / submit2',0
copy1_text GLOBWSTR 'Copy1',0
copy2_text GLOBWSTR 'Copy2',0
modules_text GLOBWSTR 'Shader modules',0
inline_text GLOBWSTR 'Inline SPIR-V',0
fence_text GLOBWSTR 'Fence',0
timeline_text GLOBWSTR 'Timeline',0
window_class WNDCLASSEX cbSize: sizeof.WNDCLASSEX,lpfnWndProc: window_proc,lpszClassName: class_name
client_rect RECT
title_rect RECT left: 16,top: 14,right: 800,bottom: 48
subtitle_rect RECT left: 18,top: 50,right: 970,bottom: 74
status_rect RECT left: 18,top: 126,right: 980,bottom: 146
route_rect RECT left: 18,top: 147,right: 980,bottom: 167
footer_rect RECT left: 16,top: 690,right: 980,bottom: 730
paint PAINTSTRUCT
message MSG
dib_info BITMAPINFOHEADER biSize: sizeof.BITMAPINFOHEADER,biWidth: FRAME_WIDTH,biHeight: -FRAME_HEIGHT,biPlanes: 1,biBitCount: 32,biCompression: BI_RGB
snapshot_info BITMAPINFOHEADER biSize: sizeof.BITMAPINFOHEADER,biPlanes: 1,biBitCount: 32,biCompression: BI_RGB
bitmap_file_header:
	db 'BM'
.length dd 54+FRAME_BYTES
	dw 0,0
	dd 54
.info BITMAPINFOHEADER biSize: sizeof.BITMAPINFOHEADER,biWidth: FRAME_WIDTH,biHeight: -FRAME_HEIGHT,biPlanes: 1,biBitCount: 32,biCompression: BI_RGB
filter_text GLOBWSTR 'Bitmap image (*.bmp)',0,'*.bmp',0,0
extension_text GLOBWSTR 'bmp',0
save_dialog OPENFILENAME lStructSize: sizeof.OPENFILENAME,lpstrFilter: filter_text,lpstrFile: save_path,nMaxFile: 512, \
	Flags: OFN_OVERWRITEPROMPT or OFN_PATHMUSTEXIST or OFN_NOCHANGEDIR,lpstrDefExt: extension_text
buttons:
plus_text GLOBWSTR '+ Zoom',0
plus_button Button text: plus_text,x: 16,width: 90
minus_text GLOBWSTR '- Zoom',0
minus_button Button text: minus_text,x: 114,width: 90
reset_text GLOBWSTR 'Reset',0
reset_button Button text: reset_text,x: 212,width: 90
palette_text GLOBWSTR 'Palette',0
palette_button Button text: palette_text,x: 310,width: 90
export_text GLOBWSTR 'Export BMP',0
export_button Button text: export_text,x: 408,width: 112
backend_text GLOBWSTR 'CPU / GPU',0
backend_button Button text: backend_text,x: 528,width: 112
deep_text GLOBWSTR 'Deep zoom',0
deep_button Button text: deep_text,x: 648,width: 112

section '.bss$gui' readable writeable align 16
save_path rw 512
status_text rw 512
route_text rw 256
report_text rw 1024
