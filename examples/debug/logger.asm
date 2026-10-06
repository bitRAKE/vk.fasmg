; Callback formatter and Win32 sinks. No Vulkan commands are called here.
; Callback-owned strings/arrays are consumed synchronously; nothing is retained.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include 'sink.inc'
include '..\strings.inc'

public debug_initialize
public debug_shutdown
public debug_callback
public debug_io_failed
public debug_validation_failed

extrn GetStdHandle:qword
extrn CreateFileW:qword
extrn WriteFile:qword
extrn CloseHandle:qword
extrn AcquireSRWLockExclusive:qword
extrn ReleaseSRWLockExclusive:qword
extrn MultiByteToWideChar:qword
extrn OutputDebugStringW:qword

LOG_CAPACITY := 4096

section '.text$debug_logger' code readable executable align 16

; Caller owns the descriptor and its handle. File names are UTF-16.
; Initialize before creating a messenger; close only after its last callback.
proc debug_initialize uses rbx,sink,filename
	mov rbx,rcx
	mov [filename],rdx
	mov [rbx + DebugSink.handle],-1
	cmp [rbx + DebugSink.kind],DEBUG_DEBUGGER
	je .success
	cmp [rbx + DebugSink.kind],DEBUG_FILE
	je .file
	fastcall GetStdHandle,-11
	jmp .check
.file:
	fastcall CreateFileW,[filename],40000000h,1,0,2,80h,0
.check:
	mov [rbx + DebugSink.handle],rax
	test rax,rax
	jz .failed
	cmp rax,-1
	je .failed
.success:
	xor eax,eax
	jmp .done
.failed:
	mov [debug_io_failed],1
	fastcall OutputDebugStringW,<W,'[debug] sink: could not open output handle',13,10>
	mov eax,1
.done:
	ret
endp

; Console handles are borrowed; only a file sink owns a closable handle.
proc debug_shutdown uses rbx,sink
	mov rbx,rcx
	cmp [rbx + DebugSink.kind],DEBUG_FILE
	jne .done
	cmp [rbx + DebugSink.handle],-1
	je .done
	fastcall CloseHandle,[rbx + DebugSink.handle]
	test eax,eax
	jnz .closed
	mov [debug_io_failed],1
	fastcall OutputDebugStringW,<W,'[debug] sink: CloseHandle failed',13,10>
.closed:
	mov [rbx + DebugSink.handle],-1
.done:
	ret
endp

; Helpers below run under the callback's lock; reserve CRLF and a NUL byte.
proc append_text uses rsi,text
	mov rsi,rcx
	test rsi,rsi
	jnz .loop
	lea rsi,[null_text]
.loop:
	mov eax,[line_length]
	cmp eax,LOG_CAPACITY-3
	jae .done
	mov dl,[rsi]
	test dl,dl
	jz .done
	lea rcx,[line_buffer]
	mov [rcx+rax],dl
	inc [line_length]
	inc rsi
	jmp .loop
.done:
	ret
endp

proc append_hex uses rbx rsi,value
	mov rbx,rcx
	fastcall append_text,'0x'
	mov esi,16
.loop:
	rol rbx,4
	mov eax,ebx
	and eax,15
	lea rcx,[hex_digits]
	mov dl,[rcx+rax]
	mov eax,[line_length]
	cmp eax,LOG_CAPACITY-3
	jae .done
	lea rcx,[line_buffer]
	mov [rcx+rax],dl
	inc [line_length]
	dec esi
	jnz .loop
.done:
	ret
endp

proc append_labels uses rbx rsi rdi,count,labels,prefix
	mov ebx,ecx
	mov rsi,rdx
	mov rdi,r8
	test rsi,rsi
	jz .done
.loop:
	test ebx,ebx
	jz .done
	fastcall append_text,rdi
	fastcall append_text,[rsi + VkDebugUtilsLabelEXT.pLabelName]
	add rsi,sizeof.VkDebugUtilsLabelEXT
	dec ebx
	jmp .loop
.done:
	ret
endp

proc write_record uses rbx rsi rdi,handle
	mov rbx,rcx
	xor esi,esi
.loop:
	mov edi,[line_length]
	sub edi,esi
	jz .done
	lea rdx,[line_buffer]
	add rdx,rsi
	fastcall WriteFile,rbx,rdx,rdi,addr bytes_written,0
	test eax,eax
	jz .failed
	mov eax,[bytes_written]
	test eax,eax
	jz .failed
	add esi,eax
	jmp .loop
.failed:
	mov eax,1
	ret
.done:
	xor eax,eax
	ret
endp

proc debug_callback uses rbx rsi rdi,severity,types,callback_data,user_data
	mov [severity],rcx
	mov [types],rdx
	mov [callback_data],r8
	mov [user_data],r9
	; SRWLOCK protects formatting, counters, and complete output records.
	fastcall AcquireSRWLockExclusive,addr log_lock
	mov rsi,[callback_data]
	mov rdi,[user_data]
	mov [line_length],0

	test [types],VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT
	jz .validation_checked
	test [severity],DEBUG_WARNINGS
	jz .validation_checked
	mov [debug_validation_failed],1
.validation_checked:
	mov eax,[rsi + VkDebugUtilsMessengerCallbackDataEXT.messageIdNumber]
	sub eax,DEBUG_DEMO_ID
	cmp eax,32
	jae .counted
	bts [rdi + DebugSink.demoMask],eax
.counted:
	fastcall append_text,'[debug]['
	mov eax,[rdi + DebugSink.kind]
	lea rcx,[console_text]
	cmp eax,DEBUG_DEBUGGER
	jne .not_debugger
	lea rcx,[debugger_text]
.not_debugger:
	cmp eax,DEBUG_FILE
	jne .kind_ready
	lea rcx,[file_text]
.kind_ready:
	fastcall append_text,rcx
	fastcall append_text,']['
	fastcall append_text,[rdi + DebugSink.label]
	fastcall append_text,']['
	lea rcx,[verbose_text]
	cmp [severity],VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT
	jne .not_info
	lea rcx,[info_text]
.not_info:
	cmp [severity],VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT
	jne .not_warning
	lea rcx,[warning_text]
.not_warning:
	cmp [severity],VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
	jne .severity_ready
	lea rcx,[error_text]
.severity_ready:
	fastcall append_text,rcx
	fastcall append_text,'] types='
	test [types],VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT
	jz .no_general
	fastcall append_text,'general '
.no_general:
	test [types],VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT
	jz .no_validation
	fastcall append_text,'validation '
.no_validation:
	test [types],VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT
	jz .no_performance
	fastcall append_text,'performance '
.no_performance:
	fastcall append_text,'id='
	fastcall append_text,[rsi + VkDebugUtilsMessengerCallbackDataEXT.pMessageIdName]
	fastcall append_text,' number='
	mov ecx,[rsi + VkDebugUtilsMessengerCallbackDataEXT.messageIdNumber]
	fastcall append_hex,rcx
	fastcall append_text,' message='
	fastcall append_text,[rsi + VkDebugUtilsMessengerCallbackDataEXT.pMessage]

	mov ebx,[rsi + VkDebugUtilsMessengerCallbackDataEXT.objectCount]
	mov rdi,[rsi + VkDebugUtilsMessengerCallbackDataEXT.pObjects]
	test rdi,rdi
	jz .objects_done
.objects:
	test ebx,ebx
	jz .objects_done
	fastcall append_text,<13,10,'  object type='>
	mov ecx,[rdi + VkDebugUtilsObjectNameInfoEXT.objectType]
	fastcall append_hex,rcx
	fastcall append_text,' handle='
	fastcall append_hex,[rdi + VkDebugUtilsObjectNameInfoEXT.objectHandle]
	fastcall append_text,' name='
	fastcall append_text,[rdi + VkDebugUtilsObjectNameInfoEXT.pObjectName]
	add rdi,sizeof.VkDebugUtilsObjectNameInfoEXT
	dec ebx
	jmp .objects
.objects_done:
	fastcall append_labels,[rsi + VkDebugUtilsMessengerCallbackDataEXT.queueLabelCount], \
		[rsi + VkDebugUtilsMessengerCallbackDataEXT.pQueueLabels],<13,10,'  queue-label='>
	fastcall append_labels,[rsi + VkDebugUtilsMessengerCallbackDataEXT.cmdBufLabelCount], \
		[rsi + VkDebugUtilsMessengerCallbackDataEXT.pCmdBufLabels],<13,10,'  command-label='>
	mov eax,[line_length]
	lea rcx,[line_buffer]
	mov word [rcx+rax],0A0Dh
	mov byte [rcx+rax+2],0
	add [line_length],2

	mov rdi,[user_data]
	mov rcx,[rdi + DebugSink.handle]
	cmp rcx,-1
	je .sentinel
	test rcx,rcx
	jz .invalid
	fastcall write_record,rcx
	test eax,eax
	jnz .write_failed
	jmp .done
.sentinel:
	cmp [rdi + DebugSink.kind],DEBUG_DEBUGGER
	je .debugger
.invalid:
	mov [debug_io_failed],1
	fastcall OutputDebugStringW,<W,'[debug] sink: invalid output handle',13,10>
	jmp .done
.write_failed:
	mov [debug_io_failed],1
	fastcall OutputDebugStringW,<W,'[debug] sink: WriteFile failed',13,10>
	jmp .done
.debugger:
	; Vulkan messages are UTF-8; convert before OutputDebugStringW.
	fastcall MultiByteToWideChar,65001,0,addr line_buffer,-1,addr wide_buffer,LOG_CAPACITY
	test eax,eax
	jz .failed
	fastcall OutputDebugStringW,addr wide_buffer
	jmp .done
.failed:
	mov [debug_io_failed],1
	fastcall OutputDebugStringW,<W,'[debug] sink: UTF-8 conversion failed',13,10>
.done:
	fastcall ReleaseSRWLockExclusive,addr log_lock
	xor eax,eax                         ; Always VK_FALSE; never abort a Vulkan call.
	ret
endp

section '.data$debug_logger' data readable writeable align 16
log_lock dq 0
line_length dd 0
bytes_written dd 0
debug_io_failed dd 0
debug_validation_failed dd 0

section '.bss$debug_logger' readable writeable align 16
line_buffer rb LOG_CAPACITY
wide_buffer rw LOG_CAPACITY

console_text GLOBSTR 'console',0
debugger_text GLOBSTR 'debugger',0
file_text GLOBSTR 'file',0
verbose_text GLOBSTR 'verbose',0
info_text GLOBSTR 'info',0
warning_text GLOBSTR 'warning',0
error_text GLOBSTR 'error',0
hex_digits GLOBSTR '0123456789ABCDEF'
null_text GLOBSTR '(none)',0
