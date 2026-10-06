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
	fastcall debug_initialize,0
	test eax,eax
	jnz .finish
	fastcall console_write_line,creating_instance
	fastcall create_instance
	test eax,eax
	jnz .finish
	inc ebx
	vkCreateDebugUtilsMessengerEXT [instance],addr lifetime_info,0,addr messenger
	test eax,eax
	jnz .instance
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,instance_created,DEBUG_DEMO_ID+4
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,messenger_created,DEBUG_DEMO_ID+5
	inc ebx
	fastcall create_device
	test eax,eax
	jnz .messenger
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,device_created,DEBUG_DEMO_ID+6
	inc ebx
	vkCreateSemaphore [device],addr semaphore_info,0,addr semaphore
	test eax,eax
	jnz .device
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,semaphore_created,DEBUG_DEMO_ID+7
	; Destruction is logged while the object and persistent messenger are live.
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,semaphore_destroying,DEBUG_DEMO_ID+8
	vkDestroySemaphore [device],[semaphore],0
	mov [semaphore],0
	xor ebx,ebx
.device:
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,device_destroying,DEBUG_DEMO_ID+9
	fastcall destroy_device
	test eax,eax
	jz .messenger
	mov ebx,101
.messenger:
	fastcall submit_event,VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,messenger_destroying,DEBUG_DEMO_ID+10
	vkDestroyDebugUtilsMessengerEXT [instance],[messenger],0
	mov [messenger],0
.instance:
	fastcall console_write_line,destroying_instance
	fastcall destroy_instance             ; Only the chained bootstrap callback remains.
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
messenger dq 0
semaphore dq 0
lifetime_sink DebugSink kind: DEBUG_CONSOLE, label: lifetime_label
lifetime_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: DEBUG_INFO, messageType: DEBUG_ALL_TYPES, \
	pfnUserCallback: debug_callback, pUserData: lifetime_sink
semaphore_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO

section '.rdata$debug_example' data readable align 2
lifetime_label db 'lifecycle',0
creating_instance db '[debug] vkCreateInstance: chained callback active during the call',0
destroying_instance db '[debug] vkDestroyInstance: chained callback active during the call',0
instance_created db 'create instance: success',0
messenger_created db 'create messenger: success',0
device_created db 'create device: success',0
semaphore_created db 'create semaphore: success',0
semaphore_destroying db 'destroy semaphore: begin',0
device_destroying db 'destroy device: begin',0
messenger_destroying db 'destroy messenger: begin',0
success_text db '[debug] lifecycle: PASS',0
