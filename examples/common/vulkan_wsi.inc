; Work/command retirement uses timelines when available; present retirement
; uses optional KHR/EXT maintenance fences. Older drivers retain frame fences
; and per-image presentation semaphores.
WSI_FRAME_COUNT = 2
WSI_FRAME_LIMIT = 8
WSI_IMAGE_LIMIT = 8
WSI_RETIRED_LIMIT = 16

struct WsiFrame
	pool dq 0
	command dq 0
	acquired dq 0
	fence dq 0
	retirement dq 0
ends
struct WsiImage
	handle dq 0
	view dq 0
	rendered dq 0
	presented dq 0
	pending dd 0
	rb 4
ends
struct RetiredSwapchain
	handle dq 0
	retirement dq 0
	image_count dd 0
	rb 4
	images rb WSI_IMAGE_LIMIT*sizeof.WsiImage
ends

section '.text$wsi' code readable executable align 16
proc wsi_instance_extensions
	; Preserve the optional debug-utils extension installed by the context.
	mov [wsi_instance_names],0
	cmp [instance_info.enabledExtensionCount],0
	je .surface
	lea rax,[debug_name]
	mov [wsi_instance_names],rax
.surface:
	iterate <name,tag>,'VK_KHR_surface',surface,'VK_KHR_win32_surface',win32
		fastcall extension_present,name,[instance_extension_count],addr instance_extensions
		test eax,eax
		jz .failed
		.pooled#tag GLOBSTR name,0
		mov eax,[instance_info.enabledExtensionCount]
		lea rdx,[wsi_instance_names]
		lea rcx,[.pooled#tag]
		mov [rdx+rax*8],rcx
		inc [instance_info.enabledExtensionCount]
	end iterate
	mov [wsi_surface_maintenance],0
	cmp [no_present_fences],0
	jne .names
	fastcall extension_present,'VK_KHR_get_surface_capabilities2',[instance_extension_count],addr instance_extensions
	test eax,eax
	jz .names
	lea rcx,[wsi_caps2_name]
	fastcall wsi_append_instance,rcx
	iterate <name,bit,tag>,'VK_KHR_surface_maintenance1',1,khr,'VK_EXT_surface_maintenance1',2,ext
		fastcall extension_present,name,[instance_extension_count],addr instance_extensions
		test eax,eax
		jz .skip#tag
		.surface_name#tag GLOBSTR name,0
		fastcall wsi_append_instance,addr .surface_name#tag
		or [wsi_surface_maintenance],bit
	.skip#tag:
	end iterate
.names:
	lea rax,[wsi_instance_names]
	mov [instance_info.ppEnabledExtensionNames],rax
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc wsi_append_instance name
	mov eax,[instance_info.enabledExtensionCount]
	lea rdx,[wsi_instance_names]
	mov [rdx+rax*8],rcx
	inc [instance_info.enabledExtensionCount]
	ret
endp

proc wsi_create_surface
	mov rax,[module]
	mov [wsi_surface_info.hinstance],rax
	mov rax,[window]
	mov [wsi_surface_info.hwnd],rax
	vkCreateWin32SurfaceKHR [instance],addr wsi_surface_info,0,addr surface
	mov [wsi_error],eax
	test eax,eax
	setz al
	movzx eax,al
	ret
endp

proc wsi_pick_present_queue uses rbx,graphics_family
	mov ebx,ecx
	vkGetPhysicalDeviceSurfaceSupportKHR [physical_device],rbx,[surface],addr wsi_supported
	test eax,eax
	jnz .failed
	cmp [wsi_supported],VK_TRUE
	je .found
	xor ebx,ebx
.queue:
	cmp ebx,[queue_count]
	jae .failed
	vkGetPhysicalDeviceSurfaceSupportKHR [physical_device],rbx,[surface],addr wsi_supported
	test eax,eax
	jnz .failed
	cmp [wsi_supported],VK_TRUE
	je .found
	inc ebx
	jmp .queue
.found:
	mov [present_queue_info.queueFamilyIndex],ebx
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc wsi_prepare_device
	fastcall extension_present,'VK_KHR_swapchain',[device_extension_count],addr device_extensions
	test eax,eax
	jz .done
	lea rax,[wsi_swapchain_name]
	mov [enabled_extensions],rax
	mov [device_info.enabledExtensionCount],1
	mov [device_info.queueCreateInfoCount],1
	mov eax,[queue_info.queueFamilyIndex]
	cmp eax,[present_queue_info.queueFamilyIndex]
	je .ready
	mov [device_info.queueCreateInfoCount],2
.ready:
	mov eax,1
.done:
	ret
endp

proc wsi_query_features
	mov [wsi_maintenance_route],0
	cmp [no_present_fences],0
	jne .done
	test [wsi_surface_maintenance],1
	jz .ext
	fastcall extension_present,'VK_KHR_swapchain_maintenance1',[device_extension_count],addr device_extensions
	test eax,eax
	jz .ext
	mov [wsi_maintenance_route],1
	jmp .feature
.ext:
	test [wsi_surface_maintenance],2
	jz .done
	fastcall extension_present,'VK_EXT_swapchain_maintenance1',[device_extension_count],addr device_extensions
	test eax,eax
	jz .done
	mov [wsi_maintenance_route],2
.feature:
	fastcall chain_feature,addr wsi_maintenance_feature
.done:
	ret
endp

proc wsi_enable_features
	cmp [wsi_maintenance_route],0
	je .done
	cmp [wsi_maintenance_feature.swapchainMaintenance1],VK_TRUE
	jne .done
	fastcall chain_feature,addr wsi_maintenance_feature
	lea rcx,[wsi_maintenance_khr_name]
	cmp [wsi_maintenance_route],1
	je .extension
	lea rcx,[wsi_maintenance_ext_name]
.extension:
	mov eax,[device_info.enabledExtensionCount]
	lea rdx,[enabled_extensions]
	mov [rdx+rax*8],rcx
	inc [device_info.enabledExtensionCount]
	mov [wsi_present_fences],1
.done:
	ret
endp

; Prefer the requested encoding and BGRA, accepting RGBA or UNORM if necessary.
proc wsi_choose_format uses rbx rsi rdi,preferred
	mov ebx,ecx
	mov [wsi_format_count],64
	vkGetPhysicalDeviceSurfaceFormatsKHR [physical_device],[surface],addr wsi_format_count,addr wsi_formats
	test eax,eax
	jnz .failed
	cmp [wsi_format_count],0
	je .failed
	cmp [wsi_format_count],1
	jne .search
	cmp [wsi_formats+VkSurfaceFormatKHR.format],VK_FORMAT_UNDEFINED
	jne .search
	mov [wsi_format],ebx
	mov eax,dword [wsi_formats+VkSurfaceFormatKHR.colorSpace]
	mov [wsi_colorspace],eax
	jmp .ready
.search:
	; Four passes: exact request, other channel order, then linear formats.
	xor edi,edi
.pass:
	mov edx,ebx
	test edi,1
	jz .encoding
	cmp edx,VK_FORMAT_B8G8R8A8_SRGB
	jne .rgba_unorm
	mov edx,VK_FORMAT_R8G8B8A8_SRGB
	jmp .encoding
.rgba_unorm:
	mov edx,VK_FORMAT_R8G8B8A8_UNORM
.encoding:
	cmp edi,2
	jb .entries
	mov edx,VK_FORMAT_B8G8R8A8_UNORM
	test edi,1
	jz .entries
	mov edx,VK_FORMAT_R8G8B8A8_UNORM
.entries:
	xor ecx,ecx
	lea rsi,[wsi_formats]
.entry:
	cmp ecx,[wsi_format_count]
	jae .next_pass
	cmp [rsi+VkSurfaceFormatKHR.format],edx
	jne .next
	cmp [rsi+VkSurfaceFormatKHR.colorSpace],VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
	jne .next
	mov [wsi_format],edx
	mov [wsi_colorspace],VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
	jmp .ready
.next:
	inc ecx
	add rsi,sizeof.VkSurfaceFormatKHR
	jmp .entry
.next_pass:
	inc edi
	cmp edi,4
	jb .pass
.failed:
	xor eax,eax
	ret
.ready:
	mov eax,1
	ret
endp

proc wsi_create_frames uses rbx rsi
	fastcall arena_take,WSI_RETIRED_LIMIT*sizeof.RetiredSwapchain
	mov [wsi_retired],rax
	test rax,rax
	jz .failed
	test [active_caps],CAP_TIMELINE
	jz .contexts
	mov rax,[timeline_semaphore]
	mov [wsi_work_signal.semaphore],rax
	mov [wsi_work_handle],rax
	mov rax,[retirement_semaphore]
	mov [wsi_retire_signal.semaphore],rax
	mov [wsi_retire_handle],rax
	mov [wsi_submit2.signalSemaphoreInfoCount],2
	mov [wsi_submit1.signalSemaphoreCount],2
	lea rax,[wsi_work_timeline]
	mov [wsi_submit1.pNext],rax
.contexts:
	xor ebx,ebx
	lea rsi,[wsi_frames]
.frame:
	fastcall wsi_create_context,rsi
	test eax,eax
	jnz .failed
	inc [wsi_frame_count]
	add rsi,sizeof.WsiFrame
	inc ebx
	cmp ebx,WSI_FRAME_COUNT
	jb .frame
	mov eax,1
	ret
.failed:
	mov [wsi_error],eax
	xor eax,eax
	ret
endp

proc wsi_create_context uses rbx,context
	mov rbx,rcx
	mov eax,[queue_info.queueFamilyIndex]
	mov [wsi_pool_info.queueFamilyIndex],eax
	vkCreateCommandPool [device],addr wsi_pool_info,0,addr rbx+WsiFrame.pool
	test eax,eax
	jnz .done
	mov rax,[rbx+WsiFrame.pool]
	mov [wsi_command_allocate.commandPool],rax
	vkAllocateCommandBuffers [device],addr wsi_command_allocate,addr rbx+WsiFrame.command
	test eax,eax
	jnz .done
	vkCreateSemaphore [device],addr wsi_semaphore_info,0,addr rbx+WsiFrame.acquired
	test eax,eax
	jnz .done
	test [active_caps],CAP_TIMELINE
	jnz .done
	vkCreateFence [device],addr wsi_fence_info,0,addr rbx+WsiFrame.fence
.done:
	ret
endp

proc wsi_destroy_frames uses rbx rsi
	xor ebx,ebx
	lea rsi,[wsi_frames]
.frame:
	iterate <field,function>,acquired,vkDestroySemaphore,fence,vkDestroyFence,pool,vkDestroyCommandPool
		cmp [rsi+WsiFrame.field],0
		je .skip#field
		function [device],[rsi+WsiFrame.field],0
		mov [rsi+WsiFrame.field],0
	.skip#field:
	end iterate
	add rsi,sizeof.WsiFrame
	inc ebx
	cmp ebx,WSI_FRAME_LIMIT
	jb .frame
	ret
endp

proc wsi_destroy_swapchain_now uses rbx rsi
	xor ebx,ebx
	lea rsi,[wsi_images]
.image:
	cmp ebx,[wsi_image_count]
	jae .swapchain
	iterate <field,function>,view,vkDestroyImageView,rendered,vkDestroySemaphore,presented,vkDestroyFence
		cmp [rsi+WsiImage.field],0
		je .skip#field
		function [device],[rsi+WsiImage.field],0
		mov [rsi+WsiImage.field],0
	.skip#field:
	end iterate
	mov [rsi+WsiImage.handle],0
	mov [rsi+WsiImage.pending],0
	add rsi,sizeof.WsiImage
	inc ebx
	jmp .image
.swapchain:
	cmp [swapchain],0
	je .done
	vkDestroySwapchainKHR [device],[swapchain],0
	mov [swapchain],0
.done:
	mov [wsi_image_count],0
	mov [wsi_dirty],1
	ret
endp

proc wsi_create_swapchain uses rbx rsi
	vkGetPhysicalDeviceSurfaceCapabilitiesKHR [physical_device],[surface],addr wsi_caps
	test eax,eax
	jnz .failed
	test [wsi_caps.supportedUsageFlags],VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT
	jz .failed
	mov eax,[wsi_caps.minImageCount]
	cmp eax,WSI_FRAME_COUNT
	jae .maximum
	mov eax,WSI_FRAME_COUNT
.maximum:
	cmp [wsi_caps.maxImageCount],0
	je .count
	cmp eax,[wsi_caps.maxImageCount]
	jbe .count
	mov eax,[wsi_caps.maxImageCount]
.count:
	cmp eax,WSI_IMAGE_LIMIT
	ja .failed
	mov [wsi_swapchain_info.minImageCount],eax
	mov eax,[wsi_caps.currentExtent.width]
	cmp eax,-1
	jne .fixed
	mov eax,[frame_width]
	cmp eax,[wsi_caps.minImageExtent.width]
	jae .max_width
	mov eax,[wsi_caps.minImageExtent.width]
.max_width:
	cmp eax,[wsi_caps.maxImageExtent.width]
	jbe .width
	mov eax,[wsi_caps.maxImageExtent.width]
.width:
	mov [wsi_swapchain_info.imageExtent.width],eax
	mov eax,[frame_height]
	cmp eax,[wsi_caps.minImageExtent.height]
	jae .max_height
	mov eax,[wsi_caps.minImageExtent.height]
.max_height:
	cmp eax,[wsi_caps.maxImageExtent.height]
	jbe .height
	mov eax,[wsi_caps.maxImageExtent.height]
.height:
	mov [wsi_swapchain_info.imageExtent.height],eax
	jmp .format
.fixed:
	mov [wsi_swapchain_info.imageExtent.width],eax
	mov eax,[wsi_caps.currentExtent.height]
	mov [wsi_swapchain_info.imageExtent.height],eax
.format:
	mov rax,[surface]
	mov [wsi_swapchain_info.surface],rax
	mov eax,[wsi_format]
	mov [wsi_swapchain_info.imageFormat],eax
	mov [wsi_view_info.format],eax
	mov eax,[wsi_colorspace]
	mov [wsi_swapchain_info.imageColorSpace],eax
	mov eax,[wsi_caps.currentTransform]
	mov [wsi_swapchain_info.preTransform],eax
	; The least significant supported alpha flag favors opaque presentation.
	mov eax,[wsi_caps.supportedCompositeAlpha]
	mov edx,eax
	neg edx
	and eax,edx
	mov [wsi_swapchain_info.compositeAlpha],eax
	mov [wsi_swapchain_info.imageSharingMode],VK_SHARING_MODE_EXCLUSIVE
	mov [wsi_swapchain_info.queueFamilyIndexCount],0
	mov eax,[queue_info.queueFamilyIndex]
	mov [wsi_queue_families],eax
	cmp eax,[present_queue_info.queueFamilyIndex]
	je .create
	mov eax,[present_queue_info.queueFamilyIndex]
	mov [wsi_queue_families+4],eax
	mov [wsi_swapchain_info.imageSharingMode],VK_SHARING_MODE_CONCURRENT
	mov [wsi_swapchain_info.queueFamilyIndexCount],2
.create:
	vkCreateSwapchainKHR [device],addr wsi_swapchain_info,0,addr swapchain
	test eax,eax
	jnz .failed
	mov [wsi_replacement_hold],0
	mov [wsi_swapchain_info.oldSwapchain],0
	mov [wsi_image_count],WSI_IMAGE_LIMIT
	vkGetSwapchainImagesKHR [device],[swapchain],addr wsi_image_count,addr wsi_raw_images
	test eax,eax
	jnz .failed
	xor ebx,ebx
	lea rsi,[wsi_images]
.image:
	cmp ebx,[wsi_image_count]
	jae .ready
	lea rax,[wsi_raw_images]
	mov rax,[rax+rbx*8]
	mov [rsi+WsiImage.handle],rax
	mov [wsi_view_info.image],rax
	vkCreateImageView [device],addr wsi_view_info,0,addr rsi+WsiImage.view
	test eax,eax
	jnz .failed
	vkCreateSemaphore [device],addr wsi_semaphore_info,0,addr rsi+WsiImage.rendered
	test eax,eax
	jnz .failed
	cmp [wsi_present_fences],0
	je .next_image
	vkCreateFence [device],addr fence_info,0,addr rsi+WsiImage.presented
	test eax,eax
	jnz .failed
.next_image:
	add rsi,sizeof.WsiImage
	inc ebx
	jmp .image
.ready:
	mov [wsi_dirty],0
	fastcall wsi_collect_swapchains
	mov eax,1
	ret
.failed:
	mov [wsi_error],eax
	xor eax,eax
	ret
endp

; Returns 1 with an acquired image, 2 for resize/retry, 0 for a GPU failure.
proc wsi_begin_frame uses rbx
	fastcall poll_retirement
	test eax,eax
	jnz .failed
	fastcall wsi_collect_swapchains
	test eax,eax
	jnz .failed
	mov eax,[wsi_frame_slot]
	imul eax,sizeof.WsiFrame
	lea rbx,[wsi_frames]
	add rbx,rax
	mov rax,[rbx+WsiFrame.retirement]
	cmp rax,[completed_retirement]
	jbe .context_ready
	cmp [wsi_frame_count],WSI_FRAME_LIMIT
	jae .wait_context
	mov eax,[wsi_frame_count]
	mov [wsi_frame_slot],eax
	imul eax,sizeof.WsiFrame
	lea rbx,[wsi_frames]
	add rbx,rax
	fastcall wsi_create_context,rbx
	test eax,eax
	jnz .failed
	inc [wsi_frame_count]
	jmp .context_ready
.wait_context:
	fastcall wait_retirement,rax
	test eax,eax
	jnz .failed
.context_ready:
	mov [wsi_current_frame],rbx
	vkAcquireNextImageKHR [device],[swapchain],5000000000,[rbx+WsiFrame.acquired],0,addr wsi_image_index
	cmp eax,VK_ERROR_OUT_OF_DATE_KHR
	je .resize
	cmp eax,VK_SUBOPTIMAL_KHR
	jne .acquired
	mov [wsi_dirty],1
	xor eax,eax
.acquired:
	test eax,eax
	jnz .failed
	mov eax,[wsi_image_index]
	imul eax,sizeof.WsiImage
	lea rdx,[wsi_images]
	add rax,rdx
	mov [wsi_current_image],rax
	cmp [rax+WsiImage.pending],0
	je .commands
	vkWaitForFences [device],1,addr rax+WsiImage.presented,VK_TRUE,5000000000
	test eax,eax
	jnz .failed
	mov rax,[wsi_current_image]
	mov [rax+WsiImage.pending],0
.commands:
	mov rax,[rbx+WsiFrame.command]
	mov [command_buffer],rax
	fastcall begin_commands
	test eax,eax
	jnz .failed
	mov eax,1
	ret
.resize:
	mov [wsi_dirty],1
	mov eax,2
	ret
.failed:
	mov [wsi_error],eax
	xor eax,eax
	ret
endp

proc wsi_submit_frame uses rbx
	mov rbx,[wsi_current_frame]
	vkEndCommandBuffer [command_buffer]
	test eax,eax
	jnz .failed
	test [active_caps],CAP_TIMELINE
	jnz .signals
	vkResetFences [device],1,addr rbx+WsiFrame.fence
	test eax,eax
	jnz .failed
.signals:
	fastcall reserve_submission
	mov rax,[rbx+WsiFrame.acquired]
	mov [wsi_acquired_handle],rax
	mov [wsi_wait_info.semaphore],rax
	mov rax,[wsi_current_image]
	mov rax,[rax+WsiImage.rendered]
	mov [wsi_rendered_handle],rax
	mov [wsi_signal_info.semaphore],rax
	mov rax,[completion_value]
	mov [wsi_work_signal.value],rax
	mov [wsi_signal_values+8],rax
	mov rax,[retirement_value]
	mov [wsi_retire_signal.value],rax
	mov rax,[command_buffer]
	mov [wsi_command_submit.commandBuffer],rax
	test [active_caps],CAP_SYNC
	jz .submit1
	mov edx,1
	test [active_caps],CAP_TIMELINE
	jz .submit2_count
	mov edx,2
.submit2_count:
	; Count is the second argument, so earlier queue setup cannot overwrite it.
	vkQueueSubmit2 [queue],rdx,addr wsi_submit2,[rbx+WsiFrame.fence]
	jmp .submitted
.submit1:
	mov edx,1
	test [active_caps],CAP_TIMELINE
	jz .submit1_count
	mov edx,2
.submit1_count:
	vkQueueSubmit [queue],rdx,addr wsi_submit1,[rbx+WsiFrame.fence]
.submitted:
	test eax,eax
	jnz .cancel
	mov rax,[retirement_value]
	mov [rbx+WsiFrame.retirement],rax
	cmp [wsi_present_fences],0
	je .present
	mov rax,[wsi_current_image]
	mov rdx,[rax+WsiImage.presented]
	mov [wsi_present_fence_handle],rdx
	vkResetFences [device],1,addr wsi_present_fence_handle
	test eax,eax
	jnz .failed
	mov rax,[wsi_current_image]
	mov [rax+WsiImage.pending],1
	lea rax,[wsi_present_fence_info]
	mov [wsi_present_info.pNext],rax
.present:
	vkQueuePresentKHR [present_queue],addr wsi_present_info
	cmp eax,VK_ERROR_OUT_OF_DATE_KHR
	je .resize
	cmp eax,VK_SUBOPTIMAL_KHR
	je .resize
	test eax,eax
	jnz .failed
	jmp .ready
.resize:
	mov [wsi_dirty],1
.ready:
	inc [wsi_present_count]
	inc [wsi_frame_slot]
	mov eax,[wsi_frame_count]
	cmp [wsi_frame_slot],eax
	jb .done
	mov [wsi_frame_slot],0
.done:
	mov eax,1
	ret
.failed:
	mov [wsi_error],eax
	xor eax,eax
	ret
.cancel:
	mov [wsi_error],eax
	fastcall cancel_submission
	xor eax,eax
	ret
endp

section '.data$wsi' data readable writeable align 8
surface dq 0
swapchain dq 0
present_queue dq 0
wsi_current_frame dq 0
wsi_current_image dq 0
wsi_acquired_handle dq 0
wsi_rendered_handle dq 0
wsi_work_handle dq 0
wsi_retire_handle dq 0
wsi_present_fence_handle dq 0
wsi_signal_values dq 0,0
wsi_binary_value dq 0
wsi_frame_slot dd 0
wsi_frame_count dd 0
wsi_image_index dd 0
wsi_image_count dd 0
wsi_format_count dd 0
wsi_format dd VK_FORMAT_B8G8R8A8_SRGB
wsi_colorspace dd VK_COLOR_SPACE_SRGB_NONLINEAR_KHR
wsi_dirty dd 1
wsi_supported dd 0
wsi_error dd 0
wsi_present_count dd 0
wsi_queue_families rd 2
wsi_instance_names rq 6
wsi_raw_images rq WSI_IMAGE_LIMIT
wsi_formats rb 64 * sizeof.VkSurfaceFormatKHR
wsi_frames: rb WSI_FRAME_LIMIT * sizeof.WsiFrame
wsi_images: rb WSI_IMAGE_LIMIT * sizeof.WsiImage
wsi_caps VkSurfaceCapabilitiesKHR
wsi_swapchain_name GLOBSTR 'VK_KHR_swapchain',0
wsi_caps2_name GLOBSTR 'VK_KHR_get_surface_capabilities2',0
wsi_maintenance_khr_name GLOBSTR 'VK_KHR_swapchain_maintenance1',0
wsi_maintenance_ext_name GLOBSTR 'VK_EXT_swapchain_maintenance1',0
no_present_fences dd 0
wsi_surface_maintenance dd 0
wsi_maintenance_route dd 0
wsi_present_fences dd 0
wsi_maintenance_feature VkPhysicalDeviceSwapchainMaintenance1FeaturesKHR sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SWAPCHAIN_MAINTENANCE_1_FEATURES_KHR
wsi_surface_info VkWin32SurfaceCreateInfoKHR sType: VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR
wsi_pool_info VkCommandPoolCreateInfo sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
wsi_command_allocate VkCommandBufferAllocateInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,commandBufferCount: 1
wsi_semaphore_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
wsi_fence_info VkFenceCreateInfo sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,flags: VK_FENCE_CREATE_SIGNALED_BIT
wsi_view_info VkImageViewCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,viewType: VK_IMAGE_VIEW_TYPE_2D,subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
wsi_swapchain_info VkSwapchainCreateInfoKHR sType: VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,imageArrayLayers: 1,imageUsage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,pQueueFamilyIndices: wsi_queue_families,presentMode: VK_PRESENT_MODE_FIFO_KHR,clipped: VK_TRUE
wsi_wait_stage dd VK_PIPELINE_STAGE_ALL_COMMANDS_BIT
wsi_wait_info VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
wsi_signal_info VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
wsi_work_signal VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
wsi_retire_signal VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
wsi_command_submit VkCommandBufferSubmitInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO
wsi_submit2 VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,waitSemaphoreInfoCount: 1,pWaitSemaphoreInfos: wsi_wait_info,commandBufferInfoCount: 1,pCommandBufferInfos: wsi_command_submit,signalSemaphoreInfoCount: 1,pSignalSemaphoreInfos: wsi_signal_info
	VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,signalSemaphoreInfoCount: 1,pSignalSemaphoreInfos: wsi_retire_signal
wsi_submit1 VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,waitSemaphoreCount: 1,pWaitSemaphores: wsi_acquired_handle,pWaitDstStageMask: wsi_wait_stage,commandBufferCount: 1,pCommandBuffers: command_buffer,signalSemaphoreCount: 1,pSignalSemaphores: wsi_rendered_handle
	VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,pNext: wsi_retire_timeline,signalSemaphoreCount: 1,pSignalSemaphores: wsi_retire_handle
wsi_work_timeline VkTimelineSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,waitSemaphoreValueCount: 1,pWaitSemaphoreValues: wsi_binary_value,signalSemaphoreValueCount: 2,pSignalSemaphoreValues: wsi_signal_values
wsi_retire_timeline VkTimelineSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,signalSemaphoreValueCount: 1,pSignalSemaphoreValues: retirement_value
wsi_present_info VkPresentInfoKHR sType: VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,waitSemaphoreCount: 1,pWaitSemaphores: wsi_rendered_handle,swapchainCount: 1,pSwapchains: swapchain,pImageIndices: wsi_image_index
wsi_present_fence_info VkSwapchainPresentFenceInfoKHR sType: VK_STRUCTURE_TYPE_SWAPCHAIN_PRESENT_FENCE_INFO_KHR,swapchainCount: 1,pFences: wsi_present_fence_handle
include 'vulkan_wsi_retirement.inc'
