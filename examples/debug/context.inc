; Small headless host, included in each example's single Vulkan-calling object.
; No window, surface, rendering features, device extensions, or C runtime.
include 'sink.inc'

extrn ExitProcess:qword
extrn console_initialize:qword
extrn console_write_line:qword
extrn debug_initialize:qword
extrn debug_shutdown:qword
extrn debug_callback:qword
extrn debug_io_failed:dword
extrn debug_validation_failed:dword

section '.text$debug_context' code readable executable align 16

proc create_instance
	vkCreateInstance addr instance_info, 0, addr instance
	ret
endp

proc create_device uses rbx rsi
	mov [adapter_count],16
	vkEnumeratePhysicalDevices [instance], addr adapter_count, addr adapters
	test eax,eax
	js .done
	cmp [adapter_count],0
	je .unavailable
	mov [family_count],32
	vkGetPhysicalDeviceQueueFamilyProperties [adapters], addr family_count, addr families
	xor ebx,ebx
	lea rsi,[families]
.find:
	cmp ebx,[family_count]
	jae .unavailable
	cmp [rsi + VkQueueFamilyProperties.queueCount],0
	je .next
	test [rsi + VkQueueFamilyProperties.queueFlags],VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT or VK_QUEUE_TRANSFER_BIT
	jnz .found
.next:
	inc ebx
	add rsi,sizeof.VkQueueFamilyProperties
	jmp .find
.found:
	mov [family_index],ebx
	mov [queue_info.queueFamilyIndex],ebx
	vkCreateDevice [adapters], addr device_info, 0, addr device
	test eax,eax
	jnz .done
	vkGetDeviceQueue [device], [family_index], 0, addr queue
	xor eax,eax
.done:
	ret
.unavailable:
	mov eax,VK_ERROR_INITIALIZATION_FAILED
	ret
endp

; Send a GENERAL application event through the actual Vulkan message stream.
; Event metadata can be supplied explicitly by the object/label example.
proc submit_event severity,message,id
	mov [severity],rcx
	mov [event_data.pMessage],rdx
	mov [event_data.messageIdNumber],r8d
	vkSubmitDebugUtilsMessageEXT [instance], [severity], VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT, addr event_data
	ret
endp

proc destroy_device uses rbx
	xor ebx,ebx
	cmp [device],0
	je .done
	vkDeviceWaitIdle [device]
	mov ebx,eax
	vkDestroyDevice [device],0
	mov [device],0
.done:
	mov eax,ebx
	ret
endp

proc destroy_instance
	cmp [instance],0
	je .done
	; bootstrap_info remains alive until this call and its callbacks return.
	vkDestroyInstance [instance],0
	mov [instance],0
.done:
	ret
endp

section '.data$debug_context' data readable writeable align 16

instance dq 0
device dq 0
queue dq 0
adapter_count dd 0
family_count dd 0
family_index dd 0
queue_priority dd 1.0
adapters rq 16
families rb 32 * sizeof.VkQueueFamilyProperties

bootstrap_sink DebugSink kind: DEBUG_CONSOLE, label: bootstrap_label
bootstrap_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: DEBUG_INFO, messageType: DEBUG_ALL_TYPES, \
	pfnUserCallback: debug_callback, pUserData: bootstrap_sink

application_info VkApplicationInfo \
	sType: VK_STRUCTURE_TYPE_APPLICATION_INFO, \
	pApplicationName: application_name, apiVersion: VK_API_VERSION_1_1
instance_info VkInstanceCreateInfo \
	sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, pNext: bootstrap_info, \
	pApplicationInfo: application_info, \
	enabledExtensionCount: 1, ppEnabledExtensionNames: instance_extensions
queue_info VkDeviceQueueCreateInfo \
	sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, \
	queueCount: 1, pQueuePriorities: queue_priority
device_info VkDeviceCreateInfo \
	sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, \
	queueCreateInfoCount: 1, pQueueCreateInfos: queue_info
event_data VkDebugUtilsMessengerCallbackDataEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CALLBACK_DATA_EXT, \
	pMessageIdName: event_id

instance_extensions dq debug_utils_extension
debug_utils_extension db VK_EXT_DEBUG_UTILS_EXTENSION_NAME,0
application_name db 'vk.fasmg debug examples',0
bootstrap_label db 'bootstrap',0
event_id db 'vk.fasmg.debug',0
