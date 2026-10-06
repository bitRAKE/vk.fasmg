; Creation/destruction: pNext coverage plus explicit application lifecycle events.
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
	fastcall debug_initialize,addr bootstrap_sink,0
	test eax,eax
	jnz .finish
	mov rax,[bootstrap_sink.handle]
	mov [lifetime_sink.handle],rax
	fastcall console_write_line,'[debug] vkCreateInstance: chained callback active during the call'
	fastcall create_instance
	test eax,eax
	jnz .finish
	inc ebx
	vkCreateDebugUtilsMessengerEXT [instance],addr lifetime_info,0,addr messenger
	test eax,eax
	jnz .instance
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'create instance: success',DEBUG_DEMO_ID+4
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'create messenger: success',DEBUG_DEMO_ID+5
	inc ebx
	fastcall create_device
	test eax,eax
	jnz .messenger
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'create device: success',DEBUG_DEMO_ID+6
	inc ebx
	vkCreateSemaphore [device],addr semaphore_info,0,addr semaphore
	test eax,eax
	jnz .device
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'create semaphore: success',DEBUG_DEMO_ID+7
	; Destruction is logged while the object and persistent messenger are live.
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'destroy semaphore: begin',DEBUG_DEMO_ID+8
	vkDestroySemaphore [device],[semaphore],0
	mov [semaphore],0
	xor ebx,ebx
.device:
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'destroy device: begin',DEBUG_DEMO_ID+9
	fastcall destroy_device
	test eax,eax
	jz .messenger
	mov ebx,101
.messenger:
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,'destroy messenger: begin',DEBUG_DEMO_ID+10
	vkDestroyDebugUtilsMessengerEXT [instance],[messenger],0
	mov [messenger],0
.instance:
	fastcall console_write_line,'[debug] vkDestroyInstance: chained callback active during the call'
	fastcall destroy_instance             ; Only the chained bootstrap callback remains.
.finish:
	cmp [debug_io_failed],0
	jne .logging_failed
	cmp [debug_validation_failed],0
	jne .logging_failed
	test ebx,ebx
	jnz .exit
	fastcall console_write_line,'[debug] lifecycle: PASS'
	jmp .exit
.logging_failed:
	mov ebx,100
.exit:
	fastcall ExitProcess,rbx
	int3
endp

section '.data$debug_example' data readable writeable align 8
messenger dq 0
semaphore dq 0
lifetime_label GLOBSTR 'lifecycle',0
lifetime_sink DebugSink kind: DEBUG_CONSOLE, handle: -1, label: lifetime_label
lifetime_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: DEBUG_INFO, messageType: DEBUG_ALL_TYPES, \
	pfnUserCallback: debug_callback, pUserData: lifetime_sink
semaphore_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
