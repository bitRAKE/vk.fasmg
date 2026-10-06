; Exercise callback routing directly, with independent caller-owned handles.
; Expected I/O failures must report to the debugger and still return VK_FALSE.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include '..\..\examples\debug\sink.inc'
include '..\..\examples\strings.inc'

public mainCRTStartup
extrn debug_initialize:qword
extrn debug_shutdown:qword
extrn debug_callback:qword
extrn debug_io_failed:dword
extrn CreateFileW:qword
extrn OutputDebugStringW:qword
extrn ExitProcess:qword

section '.text$probe' code readable executable align 16
proc check_record sink,message,expected
	mov [sink],rcx
	mov [callback_data.pMessage],rdx
	mov [expected],r8
	fastcall debug_callback,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT, \
		VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT,addr callback_data,[sink]
	test eax,eax
	jnz .failed
	mov eax,[debug_io_failed]
	cmp rax,[expected]
	jne .failed
	mov [debug_io_failed],0
	xor eax,eax
	ret
.failed:
	mov eax,1
	ret
endp

proc mainCRTStartup uses rbx rsi
	mov ebx,1
	fastcall debug_initialize,addr first_sink,<W,'build\debug_sink_a.log'>
	test eax,eax
	jnz .finish
	fastcall debug_initialize,addr second_sink,<W,'build\debug_sink_b.log'>
	test eax,eax
	jnz .finish
	fastcall check_record,addr first_sink,'probe.first: first handle',0
	test eax,eax
	jnz .finish
	fastcall check_record,addr second_sink,'probe.second: second handle',0
	test eax,eax
	jnz .finish
	; Retarget the first descriptor without changing any logger state.
	mov rsi,[first_sink.handle]
	mov rax,[second_sink.handle]
	mov [first_sink.handle],rax
	fastcall check_record,addr first_sink,'probe.retargeted: second handle',0
	mov [first_sink.handle],rsi
	test eax,eax
	jnz .finish
	; A valid handle selects WriteFile even when kind is DEBUG_DEBUGGER.
	mov [first_sink.kind],DEBUG_DEBUGGER
	fastcall check_record,addr first_sink,'probe.handle: handle selects WriteFile',0
	mov [first_sink.kind],DEBUG_FILE
	test eax,eax
	jnz .finish
	mov [first_sink.handle],-1
	fastcall check_record,addr first_sink,'probe.invalid: invalid sentinel',1
	mov [first_sink.handle],rsi
	test eax,eax
	jnz .finish
	mov [first_sink.handle],0
	fastcall check_record,addr first_sink,'probe.null: invalid handle',1
	mov [first_sink.handle],rsi
	test eax,eax
	jnz .finish
	fastcall check_record,addr debugger_sink,'probe.debugger: UTF-8 café λ',0
	test eax,eax
	jnz .finish
	fastcall OutputDebugStringW,<W,'probe.wide: inline UTF-16 café λ',13,10>
	; Reopen the first file read-only to make WriteFile fail deterministically.
	fastcall debug_shutdown,addr first_sink
	fastcall CreateFileW,<W,'build\debug_sink_a.log'>,80000000h,1,0,3,80h,0
	cmp rax,-1
	je .finish
	mov [first_sink.handle],rax
	fastcall check_record,addr first_sink,'probe.write: read-only handle',1
	test eax,eax
	jnz .finish
	xor ebx,ebx
.finish:
	fastcall debug_shutdown,addr first_sink
	fastcall debug_shutdown,addr second_sink
	cmp [debug_io_failed],0
	je .exit
	mov ebx,1
.exit:
	fastcall ExitProcess,rbx
	int3
endp

section '.data$probe' data readable writeable align 8
first_label GLOBSTR 'first',0
second_label GLOBSTR 'second',0
debugger_label GLOBSTR 'probe',0
first_sink DebugSink kind: DEBUG_FILE, handle: -1, label: first_label
second_sink DebugSink kind: DEBUG_FILE, handle: -1, label: second_label
debugger_sink DebugSink kind: DEBUG_DEBUGGER, handle: -1, label: debugger_label
callback_data VkDebugUtilsMessengerCallbackDataEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CALLBACK_DATA_EXT
