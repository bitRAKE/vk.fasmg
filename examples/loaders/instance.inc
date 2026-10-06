; Instance half of the loader examples.  The source is the same under every
; loader: what differs is the includes ahead of it.  Creates an instance,
; calls a function of each kind a loader has to bind, runs the device half and
; tears down.  The process exits with 0, or with the number of the step that
; failed.

extrn ExitProcess:qword
extrn console_initialize:qword
extrn console_write_string:qword
extrn console_write_line:qword

section '.text$t' code readable executable align 16

proc mainCRTStartup uses rbx
	fastcall console_initialize
	fastcall console_write_string,report_prefix
	fastcall console_write_line,binding_text

	mov ebx,1
	vkCreateInstance addr instance_info, 0, addr instance
	test eax,eax
	jnz .exit

	; A function that needs no instance, first called once there is one.
	inc ebx
	vkEnumerateInstanceVersion addr api_version
	test eax,eax
	jnz .destroy_instance

	; A function of an extension vulkan-1.dll exports.  A null surface is a
	; valid thing to destroy.
	vkDestroySurfaceKHR [instance], 0, 0

if definite VK_EXT_DEBUG_UTILS_SPEC_VERSION
	; Functions of an extension vulkan-1.dll does not export: only an
	; object that included its file, ahead of a loader able to bind them,
	; has these three.
	inc ebx
	vkCreateDebugUtilsMessengerEXT [instance], addr messenger_info, 0, addr messenger
	test eax,eax
	jnz .destroy_instance
	vkSubmitDebugUtilsMessageEXT [instance], VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT, \
		VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT, addr message
	vkDestroyDebugUtilsMessengerEXT [instance], [messenger], 0
else
	fastcall console_write_line,no_debug_utils_text
end if

	fastcall run_device
	mov ebx,eax
	test eax,eax
	jnz .destroy_instance
	fastcall console_write_line,device_text
.destroy_instance:
	vkDestroyInstance [instance], 0
.exit:
	fastcall ExitProcess,rbx
	int3
endp

if definite VK_EXT_DEBUG_UTILS_SPEC_VERSION

; PFN_vkDebugUtilsMessengerCallbackEXT: prints what was submitted.
proc report_message severity,types,callback_data,user_data
	mov [callback_data],r8
	fastcall console_write_string,report_prefix
	mov rax,[callback_data]
	fastcall console_write_line,[rax + VkDebugUtilsMessengerCallbackDataEXT.pMessage]
	xor eax,eax
	ret
endp

end if

section '.data$t' data readable writeable align 16

instance dq 0
device dq 0
messenger dq 0
api_version dd 0

align 8
instance_extensions:
	dq surface_extension
if definite VK_EXT_DEBUG_UTILS_SPEC_VERSION
	dq debug_utils_extension
end if
instance_extensions.count = ($ - instance_extensions) / 8

application_info VkApplicationInfo \
	sType: VK_STRUCTURE_TYPE_APPLICATION_INFO, \
	apiVersion: VK_API_VERSION_1_1

instance_info VkInstanceCreateInfo \
	sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, \
	pApplicationInfo: application_info, \
	enabledExtensionCount: instance_extensions.count, \
	ppEnabledExtensionNames: instance_extensions

if definite VK_EXT_DEBUG_UTILS_SPEC_VERSION

messenger_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT, \
	messageType: VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT, \
	pfnUserCallback: report_message

message VkDebugUtilsMessengerCallbackDataEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CALLBACK_DATA_EXT, \
	pMessage: message_text

debug_utils_extension db VK_EXT_DEBUG_UTILS_EXTENSION_NAME,0
message_text db 'a debug_utils messenger received this through three lazily bound functions',0

end if

surface_extension db VK_KHR_SURFACE_EXTENSION_NAME,0
report_prefix db '[loaders] ',0
no_debug_utils_text db '[loaders] debug_utils is not included: the import table has no slot for it',0
device_text db '[loaders] instance and device created, device idle, both destroyed',0
