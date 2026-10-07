; The device, under the contract: Vulkan 1.3 or later on a discrete adapter,
; with dynamic rendering, synchronization2, shader code given inline to the
; pipeline, timeline semaphores, buffer device addresses and scalar block
; layout. All of it is required, so nothing is negotiated: an adapter fits or
; it is passed over, and what the first discrete one lacked is kept for the
; message.
;
;	device_start	Vulkan loaded, an instance, the window's surface, the
;			adapter, the device and its one queue; nonzero when all stand
;	device_stop	all of it gone, in the order it must go
;
; The window exists first (`window`, `module`). present.inc supplies the
; surface. Functions bind themselves the first time each is called
; (vk\loader\static.inc); only vkGetInstanceProcAddr is found by hand, so
; that a machine without Vulkan is a failure this can report.
extrn LoadLibraryW:qword
extrn FreeLibrary:qword
extrn GetProcAddress:qword
extrn OutputDebugStringA:qword
public own_gipa as '__imp_vkGetInstanceProcAddr'

; The contract, as bits: what a program's report calls caps and required.
CAP_RENDER := 1				; dynamic rendering
CAP_SYNC := 2				; synchronization2
CAP_INLINE := 8				; shader code given inline to the pipeline
CAP_TIMELINE := 16			; timeline semaphores
CAP_ADDRESS := 64			; buffer device addresses: every resource is a pointer
CAP_SCALAR := 128			; scalar block layout: the layout shared.inc promises
CAP_REQUIRED := CAP_RENDER or CAP_SYNC or CAP_INLINE or CAP_TIMELINE or CAP_ADDRESS or CAP_SCALAR
DEVICE_EXTENSIONS := 512		; as many of an adapter's as are read

section '.text$device' code readable executable align 16

; What the loader and the layers say goes to the debugger, each on a line,
; its name first where it has one. What the validation layers object to is
; remembered for the line a program ends on.
proc debug_callback uses rbx,severity,types,data,user
	mov rbx,r8
	test edx,VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT
	jz .say
	test ecx,VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
	jz .say
	mov [debug_validation_failed],1
.say:
	cmp [rbx+VkDebugUtilsMessengerCallbackDataEXT.pMessageIdName],0
	je .message
	fastcall OutputDebugStringA,[rbx+VkDebugUtilsMessengerCallbackDataEXT.pMessageIdName]
	fastcall OutputDebugStringA,addr debug_between
.message:
	cmp [rbx+VkDebugUtilsMessengerCallbackDataEXT.pMessage],0
	je .end
	fastcall OutputDebugStringA,[rbx+VkDebugUtilsMessengerCallbackDataEXT.pMessage]
.end:
	fastcall OutputDebugStringA,addr debug_end
	xor eax,eax
	ret
endp

; Is `name` among the `count` extensions listed at `entries`?
proc extension_present uses rbx rsi rdi,name,count,entries
	mov rdi,rcx
	mov ebx,edx
	mov rsi,r8
.entry:
	test ebx,ebx
	jz .absent
	xor ecx,ecx
.byte:
	mov al,[rdi+rcx]
	cmp al,[rsi+rcx]
	jne .next
	test al,al
	jz .found
	inc ecx
	jmp .byte
.next:
	add rsi,sizeof.VkExtensionProperties
	dec ebx
	jmp .entry
.found:
	mov eax,1
	ret
.absent:
	xor eax,eax
	ret
endp

proc device_start uses rbx rsi rdi
	fastcall LoadLibraryW,<W,'vulkan-1.dll'>
	test rax,rax
	jz .failed
	mov [vulkan_module],rax
	fastcall GetProcAddress,rax,'vkGetInstanceProcAddr'
	test rax,rax
	jz .failed
	mov [own_gipa],rax
	fastcall [own_gipa],0,'vkEnumerateInstanceVersion'
	test rax,rax
	jz .failed
	fastcall rax,addr loader_api
	test eax,eax
	jnz .result
	mov eax,[loader_api]
	cmp eax,VK_API_VERSION_1_3
	jb .failed
	cmp eax,VK_API_VERSION_1_4
	jbe .version
	mov eax,VK_API_VERSION_1_4
.version:
	mov [application_info.apiVersion],eax
	; A surface for the window is needed; a messenger is taken if there is one.
	mov [extension_count],DEVICE_EXTENSIONS
	vkEnumerateInstanceExtensionProperties 0,addr extension_count,addr extensions
	test eax,eax
	js .result
	xor ebx,ebx
	iterate <name,tag,needed>, 'VK_KHR_surface',surface,1, 'VK_KHR_win32_surface',win32,1, 'VK_EXT_debug_utils',debug,0
		fastcall extension_present,name,[extension_count],addr extensions
		test eax,eax
		if needed
			jz .failed
		else
			jz .without_#tag
			lea rax,[messenger_info]
			mov [instance_info.pNext],rax
		end if
		.name_#tag GLOBSTR name,0
		lea rax,[.name_#tag]
		lea rdx,[instance_names]
		mov [rdx+rbx*8],rax
		inc ebx
	.without_#tag:
	end iterate
	mov [instance_info.enabledExtensionCount],ebx
	vkCreateInstance addr instance_info,0,addr instance
	test eax,eax
	jnz .result
	cmp [instance_info.pNext],0
	je .surface
	vkCreateDebugUtilsMessengerEXT [instance],addr messenger_info,0,addr messenger
	test eax,eax
	jnz .result
.surface:
	fastcall present_surface
	test eax,eax
	jz .failed
	mov [adapter_count],16
	vkEnumeratePhysicalDevices [instance],addr adapter_count,addr adapters
	test eax,eax
	js .result
	xor ebx,ebx
.adapter:
	cmp ebx,[adapter_count]
	jae .failed
	lea rax,[adapters]
	mov rax,[rax+rbx*8]
	mov [physical_device],rax
	fastcall device_fits
	test eax,eax
	jnz .fits
	inc ebx
	jmp .adapter
.fits:
	vkCreateDevice [physical_device],addr device_info,0,addr device
	test eax,eax
	jnz .result
	vkGetDeviceQueue [device],[queue_info.queueFamilyIndex],0,addr queue
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

; Will the adapter in hand do? It must be discrete, speak 1.3, have a queue
; that draws, computes and presents to the window, a surface format in sRGB,
; and every feature of the contract. If so the device's description is left
; ready to make it from.
proc device_fits uses rbx rsi rdi
	vkGetPhysicalDeviceProperties2 [physical_device],addr properties2
	cmp [properties2.properties.deviceType],VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
	jne .no
	mov eax,[properties2.properties.apiVersion]
	cmp eax,VK_API_VERSION_1_3
	jb .no
	cmp eax,[application_info.apiVersion]
	jbe .speaks
	mov eax,[application_info.apiVersion]
.speaks:
	mov [device_api],eax
	mov [queue_count],32
	vkGetPhysicalDeviceQueueFamilyProperties [physical_device],addr queue_count,addr queues
	xor ebx,ebx
	lea rsi,[queues]
.queue:
	cmp ebx,[queue_count]
	jae .no
	cmp [rsi+VkQueueFamilyProperties.queueCount],0
	je .next_queue
	mov eax,[rsi+VkQueueFamilyProperties.queueFlags]
	and eax,VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT
	cmp eax,VK_QUEUE_GRAPHICS_BIT or VK_QUEUE_COMPUTE_BIT
	jne .next_queue
	vkGetPhysicalDeviceSurfaceSupportKHR [physical_device],rbx,[surface],addr present_supported
	test eax,eax
	jnz .next_queue
	cmp [present_supported],VK_TRUE
	je .queued
.next_queue:
	inc ebx
	add rsi,sizeof.VkQueueFamilyProperties
	jmp .queue
.queued:
	mov [queue_info.queueFamilyIndex],ebx
	mov [extension_count],DEVICE_EXTENSIONS
	vkEnumerateDeviceExtensionProperties [physical_device],0,addr extension_count,addr extensions
	test eax,eax
	js .no
	fastcall extension_present,'VK_KHR_swapchain',[extension_count],addr extensions
	test eax,eax
	jz .no
	mov [device_info.enabledExtensionCount],1
	; Shader code inline is the core's from 1.4, and an extension's before.
	mov esi,CAP_REQUIRED
	cmp [device_api],VK_API_VERSION_1_4
	jae .features
	mov [device_info.enabledExtensionCount],2
	fastcall extension_present,'VK_KHR_maintenance5',[extension_count],addr extensions
	test eax,eax
	jnz .features
	mov esi,CAP_REQUIRED and not CAP_INLINE
.features:
	vkGetPhysicalDeviceFeatures2 [physical_device],addr features2
	xor edx,edx
	iterate <feature,member,cap>, render_feature,dynamicRendering,CAP_RENDER, sync_feature,synchronization2,CAP_SYNC, inline_feature,maintenance5,CAP_INLINE, \
		timeline_feature,timelineSemaphore,CAP_TIMELINE, address_feature,bufferDeviceAddress,CAP_ADDRESS, scalar_feature,scalarBlockLayout,CAP_SCALAR
		cmp [feature.member],VK_TRUE
		jne .not_#cap
		or edx,cap
	.not_#cap:
	end iterate
	; (An adapter without the extension leaves its answer as the last one's.)
	and edx,esi
	mov [active_caps],edx
	not edx
	and edx,CAP_REQUIRED
	mov [missing_caps],edx
	jnz .no
	; Asked for: these and nothing else.
	lea rdi,[features2.features]
	mov ecx,sizeof.VkPhysicalDeviceFeatures/4
	xor eax,eax
	rep stosd
	mov [address_feature.bufferDeviceAddressCaptureReplay],0
	mov [address_feature.bufferDeviceAddressMultiDevice],0
	vkGetPhysicalDeviceMemoryProperties2 [physical_device],addr memory_properties2
	fastcall present_format
	test eax,eax
	jz .no
	mov eax,1
	ret
.no:
	xor eax,eax
	ret
endp

proc device_stop
	cmp [device],0
	je .instance
	vkDestroyDevice [device],0
	mov [device],0
.instance:
	cmp [instance],0
	je .module
	cmp [surface],0
	je .messenger
	vkDestroySurfaceKHR [instance],[surface],0
	mov [surface],0
.messenger:
	cmp [messenger],0
	je .destroy
	vkDestroyDebugUtilsMessengerEXT [instance],[messenger],0
	mov [messenger],0
.destroy:
	vkDestroyInstance [instance],0
	mov [instance],0
.module:
	cmp [vulkan_module],0
	je .done
	fastcall FreeLibrary,[vulkan_module]
	mov [vulkan_module],0
.done:
	ret
endp

section '.data$device' data readable writeable align 16
own_gipa dq 0
vulkan_module dq 0
instance dq 0
device dq 0
queue dq 0
physical_device dq 0
messenger dq 0
loader_api dd 0
device_api dd 0
active_caps dd 0
missing_caps dd CAP_REQUIRED		; until an adapter says otherwise
extension_count dd 0
adapter_count dd 0
queue_count dd 0
present_supported dd 0
debug_validation_failed dd 0
debug_io_failed dd 0			; nothing here writes anywhere that can fail; the line a program ends on keeps its place
queue_priority dd 1.0
debug_between db ': ',0
debug_end db 13,10,0
	align 8
instance_names rq 4
device_names dq swapchain_name,maintenance_name
swapchain_name GLOBSTR 'VK_KHR_swapchain',0
maintenance_name GLOBSTR 'VK_KHR_maintenance5',0
application_name GLOBSTR MACHINE_NAME,0
messenger_info VkDebugUtilsMessengerCreateInfoEXT sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT, \
	messageType: VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT or VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT, \
	pfnUserCallback: debug_callback
application_info VkApplicationInfo sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,pApplicationName: application_name
instance_info VkInstanceCreateInfo sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,pApplicationInfo: application_info,ppEnabledExtensionNames: instance_names
queue_info VkDeviceQueueCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,queueCount: 1,pQueuePriorities: queue_priority
device_info VkDeviceCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,pNext: features2,queueCreateInfoCount: 1,pQueueCreateInfos: queue_info,ppEnabledExtensionNames: device_names
properties2 VkPhysicalDeviceProperties2 sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2
memory_properties2 VkPhysicalDeviceMemoryProperties2 sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2
; The contract's features, in one chain: asked about, and then asked for.
features2 VkPhysicalDeviceFeatures2 sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,pNext: render_feature
render_feature VkPhysicalDeviceDynamicRenderingFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,pNext: sync_feature
sync_feature VkPhysicalDeviceSynchronization2Features sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES,pNext: inline_feature
inline_feature VkPhysicalDeviceMaintenance5Features sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_5_FEATURES,pNext: timeline_feature
timeline_feature VkPhysicalDeviceTimelineSemaphoreFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES,pNext: address_feature
address_feature VkPhysicalDeviceBufferDeviceAddressFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES,pNext: scalar_feature
scalar_feature VkPhysicalDeviceScalarBlockLayoutFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SCALAR_BLOCK_LAYOUT_FEATURES

section '.bss$device' readable writeable align 16
adapters rq 16
queues rb 32 * sizeof.VkQueueFamilyProperties
extensions rb DEVICE_EXTENSIONS * sizeof.VkExtensionProperties
