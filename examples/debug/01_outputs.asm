; Three real messengers: console warnings+, debugger info+, file every severity.
include 'newcoff.inc'
include 'vk/core.inc'
include 'vk/ext/debug_utils.inc'
include 'vk/loader/static.inc'
include 'context.inc'

public mainCRTStartup

section '.text$debug_example' code readable executable align 16
proc mainCRTStartup uses rbx
	fastcall console_initialize
	mov ebx,1
	fastcall debug_initialize,log_filename
	test eax,eax
	jnz .finish
	; Keep loader/validation bootstrap warnings, but not INFO on stdout.
	mov [bootstrap_info.messageSeverity],DEBUG_WARNINGS
	fastcall create_instance
	test eax,eax
	jnz .finish
	inc ebx
	vkCreateDebugUtilsMessengerEXT [instance],addr console_info,0,addr console_messenger
	test eax,eax
	jnz .instance
	inc ebx
	vkCreateDebugUtilsMessengerEXT [instance],addr debugger_info,0,addr debugger_messenger
	test eax,eax
	jnz .console
	inc ebx
	vkCreateDebugUtilsMessengerEXT [instance],addr file_info,0,addr file_messenger
	test eax,eax
	jnz .debugger

	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,verbose_message,DEBUG_DEMO_ID
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,info_message,DEBUG_DEMO_ID+1
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT,warning_message,DEBUG_DEMO_ID+2
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,error_message,DEBUG_DEMO_ID+3

	mov ebx,5
	cmp [console_sink.demoMask],1100b
	jne .file
	cmp [debugger_sink.demoMask],1110b
	jne .file
	cmp [file_sink.demoMask],1111b
	jne .file
	xor ebx,ebx
.file:
	vkDestroyDebugUtilsMessengerEXT [instance],[file_messenger],0
.debugger:
	vkDestroyDebugUtilsMessengerEXT [instance],[debugger_messenger],0
.console:
	vkDestroyDebugUtilsMessengerEXT [instance],[console_messenger],0
.instance:
	fastcall destroy_instance
.finish:
	fastcall debug_shutdown
	cmp [debug_io_failed],0
	jne .logging_failed
	cmp [debug_validation_failed],0
	jne .logging_failed
	test ebx,ebx
	jnz .exit
	fastcall console_write_line,success_text
	jmp .exit
.logging_failed:
	mov ebx,100
.exit:
	fastcall ExitProcess,rbx
	int3
endp

section '.data$debug_example' data readable writeable align 8
console_messenger dq 0
debugger_messenger dq 0
file_messenger dq 0
console_sink DebugSink kind: DEBUG_CONSOLE, label: levels_label
debugger_sink DebugSink kind: DEBUG_DEBUGGER, label: levels_label
file_sink DebugSink kind: DEBUG_FILE, label: levels_label
console_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: DEBUG_WARNINGS, messageType: DEBUG_ALL_TYPES, \
	pfnUserCallback: debug_callback, pUserData: console_sink
debugger_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: DEBUG_INFO, messageType: DEBUG_ALL_TYPES, \
	pfnUserCallback: debug_callback, pUserData: debugger_sink
file_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: DEBUG_ALL_SEVERITIES, messageType: DEBUG_ALL_TYPES, \
	pfnUserCallback: debug_callback, pUserData: file_sink

section '.rdata$debug_example' data readable align 2
levels_label db 'levels',0
log_filename db 'build\debug_outputs.log',0
verbose_message db 'demo.verbose: detail for the file sink',0
; UTF-8 bytes for "cafe with acute accent" and Greek lambda; the debugger
; receives the corresponding UTF-16 string, while the file keeps UTF-8.
info_message db 'demo.info: debugger and file; UTF-8 caf',0C3h,0A9h,' ',0CEh,0BBh,0
warning_message db 'demo.warning: all three sinks',0
error_message db 'demo.error: synthetic GENERAL event, not a Vulkan validation failure',0
success_text db '[debug] outputs: PASS (console=0xC debugger=0xE file=0xF)',0
