; Shared device negotiation under the build contract of vulkan_routes.inc.
; Optional application hooks add scene-specific features.
; Extension routes below use a 1.2 floor for dynamic rendering/copy2, avoiding
; the extra dependency closure needed on 1.1. Older devices keep the full app.

extrn LoadLibraryW:qword
extrn FreeLibrary:qword
extrn GetProcAddress:qword
extrn debug_callback:qword
extrn debug_validation_failed:dword
extrn debug_io_failed:dword

; Satisfy the static loader's sole import with an explicitly loaded DLL. A
; missing runtime is then a failure the application reports, where an import
; would have kept Windows from starting the process.
public own_gipa as '__imp_vkGetInstanceProcAddr'

section '.text$caps' code readable executable align 16
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

; Append a feature struct to the query/create chain, preserving its lifetime.
proc chain_feature feature
	mov rax,[features2.pNext]
	mov [rcx+VkBaseOutStructure.pNext],rax
	mov [features2.pNext],rcx
	ret
endp

proc probe_gpu uses rbx rsi rdi
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
	jz .failed                       ; Negotiation starts at Vulkan 1.1.
	fastcall rax,addr loader_api
	test eax,eax
	jnz .failed
	cmp [loader_api],VK_API_VERSION_1_1
	jb .failed
	mov eax,[loader_api]
	cmp eax,VK_API_VERSION_1_4
	jbe .api
	mov eax,VK_API_VERSION_1_4
.api:
	cmp eax,[api_ceiling]
	jbe .requested_api
	mov eax,[api_ceiling]
.requested_api:
	mov [application_info.apiVersion],eax
	mov [instance_extension_count],256
	vkEnumerateInstanceExtensionProperties 0,addr instance_extension_count,addr instance_extensions
	test eax,eax
	jnz .failed
	fastcall extension_present,'VK_EXT_debug_utils',[instance_extension_count],addr instance_extensions
	test eax,eax
	jz .instance
	mov [instance_info.enabledExtensionCount],1
	lea rax,[debug_extension]
	mov [instance_info.ppEnabledExtensionNames],rax
	lea rax,[bootstrap_info]
	mov [instance_info.pNext],rax
.instance:
	if definite GPU_WSI
		fastcall wsi_instance_extensions
		test eax,eax
		jz .failed
	end if
	vkCreateInstance addr instance_info,0,addr instance
	test eax,eax
	jnz .failed
	cmp [instance_info.pNext],0
	je .adapters
	vkCreateDebugUtilsMessengerEXT [instance],addr bootstrap_info,0,addr messenger
	test eax,eax
	jnz .failed
.adapters:
	if definite GPU_WSI
		fastcall wsi_create_surface
		test eax,eax
		jz .failed
	end if
	mov [adapter_count],16
	vkEnumeratePhysicalDevices [instance],addr adapter_count,addr adapters
	test eax,eax
	jnz .failed
	cmp [adapter_count],0
	je .failed
	; Choose a graphics queue, trying every enumerated physical device.
	xor ebx,ebx
.adapter:
	cmp ebx,[adapter_count]
	jae .failed
	lea rax,[adapters]
	mov rax,[rax+rbx*8]
	mov [physical_device],rax
	if CAP_MASK and 31
		vkGetPhysicalDeviceProperties2 [physical_device],addr properties2
	else
		vkGetPhysicalDeviceProperties [physical_device],addr properties2.properties
	end if
	if definite GPU_HARDWARE_ONLY
		cmp [properties2.properties.deviceType],VK_PHYSICAL_DEVICE_TYPE_CPU
		je .next_adapter
	end if
	if definite GPU_DISCRETE_ONLY
		cmp [properties2.properties.deviceType],VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU
		jne .next_adapter
	end if
	mov eax,[properties2.properties.apiVersion]
	cmp eax,VK_API_VERSION_1_1
	jb .next_adapter
	cmp eax,[application_info.apiVersion]
	jbe .effective
	mov eax,[application_info.apiVersion]
.effective:
	mov [device_api],eax
	mov [queue_count],32
	vkGetPhysicalDeviceQueueFamilyProperties [physical_device],addr queue_count,addr queues
	xor edi,edi
	lea rsi,[queues]
.queue:
	cmp edi,[queue_count]
	jae .next_adapter
	cmp [rsi+VkQueueFamilyProperties.queueCount],0
	je .next_queue
	test [rsi+VkQueueFamilyProperties.queueFlags],VK_QUEUE_GRAPHICS_BIT
	jz .next_queue
	if definite GPU_REQUIRE_COMPUTE
		test [rsi+VkQueueFamilyProperties.queueFlags],VK_QUEUE_COMPUTE_BIT
		jz .next_queue
	end if
	if definite GPU_WSI
		fastcall wsi_pick_present_queue,rdi
		test eax,eax
		jz .next_queue
	end if
	jmp .selected
.next_queue:
	inc edi
	add rsi,sizeof.VkQueueFamilyProperties
	jmp .queue
.next_adapter:
	inc ebx
	jmp .adapter
.selected:
	if definite GPU_EXTRA_FORMATS
		fastcall choose_formats
		test eax,eax
		jz .next_adapter
	end if
	mov [queue_info.queueFamilyIndex],edi
	mov [pool_info.queueFamilyIndex],edi
	if CAP_MASK and 31
		vkGetPhysicalDeviceMemoryProperties2 [physical_device],addr memory_properties2
	else
		vkGetPhysicalDeviceMemoryProperties [physical_device],addr memory_properties2.memoryProperties
	end if
	; B8G8R8A8 bytes match the top-down bitmap an export writes.
	vkGetPhysicalDeviceFormatProperties [physical_device],VK_FORMAT_B8G8R8A8_UNORM,addr format_properties
	mov eax,[format_properties.optimalTilingFeatures]
	and eax,VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or VK_FORMAT_FEATURE_TRANSFER_SRC_BIT
	cmp eax,VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or VK_FORMAT_FEATURE_TRANSFER_SRC_BIT
	jne .failed
	vkGetPhysicalDeviceImageFormatProperties [physical_device],VK_FORMAT_B8G8R8A8_UNORM,VK_IMAGE_TYPE_2D, \
		VK_IMAGE_TILING_OPTIMAL,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT,0,addr image_properties
	test eax,eax
	jnz .failed
	mov eax,TILE_CEILING
	cmp eax,[properties2.properties.limits.maxImageDimension2D]
	jbe .width_limit
	mov eax,[properties2.properties.limits.maxImageDimension2D]
.width_limit:
	cmp eax,[image_properties.maxExtent.width]
	jbe .height_limit
	mov eax,[image_properties.maxExtent.width]
.height_limit:
	cmp eax,[image_properties.maxExtent.height]
	jbe .tile
	mov eax,[image_properties.maxExtent.height]
.tile:
	test eax,eax
	jz .failed
	mov [tile_size],eax
	mov [device_extension_count],256
	vkEnumerateDeviceExtensionProperties [physical_device],0,addr device_extension_count,addr device_extensions
	test eax,eax
	jnz .failed
	if definite GPU_WSI
		fastcall wsi_prepare_device
		test eax,eax
		jz .next_adapter
	end if
	; A contract that can select none of the five routes has none to walk.
	if CAP_MASK and 31
	; One route descriptor per optional operation; feature-bearing routes link
	; their individual structs, never aggregate and individual aliases together.
	xor ebx,ebx
	lea rsi,[routes]
.route:
	cmp ebx,5
	jae .query
	xor ecx,ecx
	bts ecx,ebx
	test [requested_caps],ecx
	jz .next_route
	mov eax,[device_api]
	cmp [force_khr],0
	jne .extension
	cmp eax,[rsi+Route.coreVersion]
	jae .core
.extension:
	cmp eax,[rsi+Route.extensionFloor]
	jb .next_route
	fastcall extension_present,[rsi+Route.name],[device_extension_count],addr device_extensions
	test eax,eax
	jz .next_route
	xor ecx,ecx
	bts ecx,ebx
	or [extension_routes],ecx
.core:
	xor ecx,ecx
	bts ecx,ebx
	or [candidate_caps],ecx
	mov rcx,[rsi+Route.feature]
	test rcx,rcx
	jz .next_route
	fastcall chain_feature,rcx
.next_route:
	inc ebx
	add rsi,sizeof.Route
	jmp .route
	end if
.query:
	if definite GPU_WSI
		fastcall wsi_query_features
	end if
	if definite GPU_EXTRA_FEATURES
		fastcall query_extra_features
	end if
	if CAP_MASK and 31
		vkGetPhysicalDeviceFeatures2 [physical_device],addr features2
	else
		vkGetPhysicalDeviceFeatures [physical_device],addr features2.features
	end if
	if definite GPU_REMEMBER_CORE_FEATURES
		fastcall remember_extra_features
	end if
	mov eax,[features2.features.shaderFloat64]
	mov [float64_supported],eax
	; Clear queried bits, then enable only the selected core 1.0 feature.
	lea rdi,[features2.features]
	mov ecx,sizeof.VkPhysicalDeviceFeatures / 4
	xor eax,eax
	rep stosd
	test [requested_caps],CAP_FLOAT64
	jz .no_float64
	cmp [float64_supported],VK_TRUE
	jne .no_float64
	or [active_caps],CAP_FLOAT64
	mov [features2.features.shaderFloat64],VK_TRUE
.no_float64:
	mov [features2.pNext],0
	if CAP_MASK and 31
	xor ebx,ebx
	lea rsi,[routes]
.enable:
	cmp ebx,5
	jae .device
	xor ecx,ecx
	bts ecx,ebx
	test [candidate_caps],ecx
	jz .next_enable
	mov rdi,[rsi+Route.feature]
	test rdi,rdi
	jz .enabled
	cmp dword [rdi+16],VK_TRUE
	jne .next_enable
	fastcall chain_feature,rdi
.enabled:
	xor ecx,ecx
	bts ecx,ebx
	or [active_caps],ecx
	test [extension_routes],ecx
	jz .next_enable
	mov eax,[device_info.enabledExtensionCount]
	lea rdx,[enabled_extensions]
	mov rcx,[rsi+Route.name]
	mov [rdx+rax*8],rcx
	inc [device_info.enabledExtensionCount]
.next_enable:
	inc ebx
	add rsi,sizeof.Route
	jmp .enable
	end if
.device:
	if definite GPU_WSI
		fastcall wsi_enable_features
	end if
	if definite GPU_EXTRA_FEATURES
		fastcall enable_extra_features
	end if
	mov eax,[active_caps]
	and [extension_routes],eax
	if CAP_REQUIRED
		; What the build cannot do without is settled before a device exists.
		not eax
		and eax,CAP_REQUIRED
		mov [missing_caps],eax
		jnz .failed
	end if
	if CAP_MASK and 31
		lea rax,[features2]
		mov [device_info.pNext],rax
	else
		lea rax,[features2.features]
		mov [device_info.pEnabledFeatures],rax
	end if
	vkCreateDevice [physical_device],addr device_info,0,addr device
	test eax,eax
	jnz .failed
	vkGetDeviceQueue [device],[queue_info.queueFamilyIndex],0,addr queue
	if definite GPU_WSI
		vkGetDeviceQueue [device],[present_queue_info.queueFamilyIndex],0,addr present_queue
	end if
	; Resolve selected promoted commands explicitly, including KHR names on
	; extension routes. All pointers remain private to this one device.
	iterate <bit,function,coreName,khrName>, \
		CAP_RENDER,vkCmdBeginRendering,'vkCmdBeginRendering','vkCmdBeginRenderingKHR', \
		CAP_RENDER,vkCmdEndRendering,'vkCmdEndRendering','vkCmdEndRenderingKHR', \
		CAP_SYNC,vkCmdPipelineBarrier2,'vkCmdPipelineBarrier2','vkCmdPipelineBarrier2KHR', \
		CAP_SYNC,vkQueueSubmit2,'vkQueueSubmit2','vkQueueSubmit2KHR', \
		CAP_COPY,vkCmdCopyImageToBuffer2,'vkCmdCopyImageToBuffer2','vkCmdCopyImageToBuffer2KHR', \
		CAP_TIMELINE,vkWaitSemaphores,'vkWaitSemaphores','vkWaitSemaphoresKHR', \
		CAP_TIMELINE,vkGetSemaphoreCounterValue,'vkGetSemaphoreCounterValue','vkGetSemaphoreCounterValueKHR', \
		CAP_TIMELINE,vkSignalSemaphore,'vkSignalSemaphore','vkSignalSemaphoreKHR'
			route bit,.skip#function
				.command_name#function GLOBSTR coreName,0
				.alias_name#function GLOBSTR khrName,0
				lea rdx,[.command_name#function]
				test [extension_routes],bit
				jz .resolve#function
				lea rdx,[.alias_name#function]
			.resolve#function:
				vkGetDeviceProcAddr [device],rdx
				test rax,rax
				jz .failed
				mov [function],rax
			end route
		.skip#function:
	end iterate
	if definite GPU_EXTRA_FEATURES
		fastcall resolve_extra_commands
		test eax,eax
		jz .failed
	end if
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

struct Route
	coreVersion dd ?
	extensionFloor dd ?
	name dq ?
	feature dq ?
ends

section '.data$caps' data readable writeable align 16
own_gipa dq 0
vulkan_module dq 0
instance dq 0
device dq 0
queue dq 0
physical_device dq 0
messenger dq 0
loader_api dd VK_API_VERSION_1_0
device_api dd 0
active_caps dd 0
float64_supported dd 0
requested_caps dd CAP_MASK
missing_caps dd 0                   ; required by the build, unavailable here
force_khr dd 0
api_ceiling dd VK_API_VERSION_1_4
candidate_caps dd 0
extension_routes dd 0
tile_size dd TILE_CEILING
instance_extension_count dd 0
device_extension_count dd 0
adapter_count dd 0
queue_count dd 0
queue_priority dd 1.0
debug_name GLOBSTR 'VK_EXT_debug_utils',0
debug_extension dq debug_name
if definite GPU_APP_NAME
app_name GLOBSTR GPU_APP_NAME,0
debug_label GLOBSTR GPU_APP_NAME,0
else
app_name GLOBSTR 'Vulkan example',0
debug_label GLOBSTR 'Vulkan example',0
end if
bootstrap_sink DebugSink kind: DEBUG_DEBUGGER,handle: -1,label: debug_label
bootstrap_info VkDebugUtilsMessengerCreateInfoEXT \
	sType: VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT, \
	messageSeverity: DEBUG_INFO,messageType: DEBUG_ALL_TYPES, \
	pfnUserCallback: debug_callback,pUserData: bootstrap_sink
application_info VkApplicationInfo sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,pApplicationName: app_name
instance_info VkInstanceCreateInfo sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,pApplicationInfo: application_info
queue_info VkDeviceQueueCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,queueCount: 1,pQueuePriorities: queue_priority
if definite GPU_WSI
present_queue_info VkDeviceQueueCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,queueCount: 1,pQueuePriorities: queue_priority
end if
device_info VkDeviceCreateInfo sType: VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,queueCreateInfoCount: 1,pQueueCreateInfos: queue_info,ppEnabledExtensionNames: enabled_extensions
properties2 VkPhysicalDeviceProperties2 sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2
memory_properties2 VkPhysicalDeviceMemoryProperties2 sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2
features2 VkPhysicalDeviceFeatures2 sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2
format_properties VkFormatProperties
image_properties VkImageFormatProperties
if CAP_MASK and 31
render_feature VkPhysicalDeviceDynamicRenderingFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES
sync_feature VkPhysicalDeviceSynchronization2Features sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES
inline_feature VkPhysicalDeviceMaintenance5Features sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_5_FEATURES
timeline_feature VkPhysicalDeviceTimelineSemaphoreFeatures sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES
render_name GLOBSTR 'VK_KHR_dynamic_rendering',0
sync_name GLOBSTR 'VK_KHR_synchronization2',0
copy_name GLOBSTR 'VK_KHR_copy_commands2',0
inline_name GLOBSTR 'VK_KHR_maintenance5',0
timeline_name GLOBSTR 'VK_KHR_timeline_semaphore',0
routes:
render_route Route coreVersion: VK_API_VERSION_1_3,extensionFloor: VK_API_VERSION_1_2,name: render_name,feature: render_feature
sync_route Route coreVersion: VK_API_VERSION_1_3,extensionFloor: VK_API_VERSION_1_2,name: sync_name,feature: sync_feature
copy_route Route coreVersion: VK_API_VERSION_1_3,extensionFloor: VK_API_VERSION_1_2,name: copy_name
inline_route Route coreVersion: VK_API_VERSION_1_4,extensionFloor: VK_API_VERSION_1_3,name: inline_name,feature: inline_feature
timeline_route Route coreVersion: VK_API_VERSION_1_2,extensionFloor: VK_API_VERSION_1_1,name: timeline_name,feature: timeline_feature
end if

; Enumeration results need no place in the file.
section '.bss$caps' readable writeable align 16
enabled_extensions rq 16
adapters rq 16
queues rb 32 * sizeof.VkQueueFamilyProperties
instance_extensions rb 256 * sizeof.VkExtensionProperties
device_extensions rb 256 * sizeof.VkExtensionProperties
