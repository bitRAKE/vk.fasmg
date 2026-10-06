section '.text$cube_target' code readable executable align 16
proc supported_image uses rbx rsi,format,usage,features
	mov ebx,ecx
	mov esi,edx
	mov [required_format_features],r8d
	vkGetPhysicalDeviceFormatProperties [physical_device],rbx,addr cube_format_properties
	mov eax,[cube_format_properties.optimalTilingFeatures]
	and eax,[required_format_features]
	cmp eax,[required_format_features]
	jne .failed
	vkGetPhysicalDeviceImageFormatProperties [physical_device],rbx,VK_IMAGE_TYPE_2D,VK_IMAGE_TILING_OPTIMAL,rsi,0,addr cube_image_properties
	test eax,eax
	jnz .failed
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc choose_formats
	mov [target_format],VK_FORMAT_B8G8R8A8_SRGB
	mov [texture_format],VK_FORMAT_R8G8B8A8_SRGB
	mov [material_flags],0
	cmp [linear_formats],0
	jne .linear_target
	fastcall supported_image,VK_FORMAT_B8G8R8A8_SRGB,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT,VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or VK_FORMAT_FEATURE_TRANSFER_SRC_BIT
	test eax,eax
	jnz .texture
.linear_target:
	fastcall supported_image,VK_FORMAT_B8G8R8A8_UNORM,VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT,VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or VK_FORMAT_FEATURE_TRANSFER_SRC_BIT
	test eax,eax
	jz .failed
	mov [target_format],VK_FORMAT_B8G8R8A8_UNORM
	or [material_flags],MATERIAL_TARGET_ENCODE
.texture:
	fastcall wsi_choose_format,[target_format]
	test eax,eax
	jz .failed
	mov eax,[wsi_format]
	mov [target_format],eax
	and [material_flags],not MATERIAL_TARGET_ENCODE
	cmp eax,VK_FORMAT_B8G8R8A8_SRGB
	je .surface_format
	cmp eax,VK_FORMAT_R8G8B8A8_SRGB
	je .surface_format
	or [material_flags],MATERIAL_TARGET_ENCODE
.surface_format:
	fastcall supported_image,[target_format],VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT,VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or VK_FORMAT_FEATURE_TRANSFER_SRC_BIT
	test eax,eax
	jz .failed
	cmp [linear_formats],0
	jne .linear_texture
	fastcall supported_image,VK_FORMAT_R8G8B8A8_SRGB,VK_IMAGE_USAGE_SAMPLED_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT,VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT or VK_FORMAT_FEATURE_TRANSFER_DST_BIT
	test eax,eax
	jnz .depth
.linear_texture:
	fastcall supported_image,VK_FORMAT_R8G8B8A8_UNORM,VK_IMAGE_USAGE_SAMPLED_BIT or VK_IMAGE_USAGE_TRANSFER_DST_BIT,VK_FORMAT_FEATURE_SAMPLED_IMAGE_BIT or VK_FORMAT_FEATURE_TRANSFER_DST_BIT
	test eax,eax
	jz .failed
	mov [texture_format],VK_FORMAT_R8G8B8A8_UNORM
	or [material_flags],MATERIAL_TEXTURE_DECODE
.depth:
	cmp [force_d16],0
	jne .d16
	fastcall supported_image,VK_FORMAT_D32_SFLOAT,VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT
	test eax,eax
	jz .d16
	mov [depth_format],VK_FORMAT_D32_SFLOAT
	jmp .ready
.d16:
	fastcall supported_image,VK_FORMAT_D16_UNORM,VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT
	test eax,eax
	jz .d24
	mov [depth_format],VK_FORMAT_D16_UNORM
	jmp .ready
.d24:
	fastcall supported_image,VK_FORMAT_D24_UNORM_S8_UINT,VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT
	test eax,eax
	jz .failed
	mov [depth_format],VK_FORMAT_D24_UNORM_S8_UINT
.ready:
	mov [depth_aspect],VK_IMAGE_ASPECT_DEPTH_BIT
	cmp [depth_format],VK_FORMAT_D24_UNORM_S8_UINT
	jne .clear
	or [depth_aspect],VK_IMAGE_ASPECT_STENCIL_BIT
.clear:
	mov [clear_values],0.2
	mov [clear_values+4],0.2
	mov [clear_values+8],0.2
	test [material_flags],MATERIAL_TARGET_ENCODE
	je .clear_copy
	mov [clear_values],0.484529204481707
	mov [clear_values+4],0.484529204481707
	mov [clear_values+8],0.484529204481707
.clear_copy:
	lea rax,[clear_values]
	movups xmm0,[rax]
	movups [render_color.clearValue],xmm0
	movups xmm0,[rax+16]
	movups [render_depth.clearValue],xmm0
	mov eax,[target_format]
	mov [color_image_info.format],eax
	mov [color_view_info.format],eax
	mov [color_attachment.format],eax
	mov [pipeline_rendering.depthAttachmentFormat],VK_FORMAT_D32_SFLOAT
	mov eax,[depth_format]
	mov [depth_image_info.format],eax
	mov [depth_view_info.format],eax
	mov [depth_attachment.format],eax
	mov [pipeline_rendering.depthAttachmentFormat],eax
	mov eax,[texture_format]
	mov [texture_image_info.format],eax
	mov [texture_view_info.format],eax
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc destroy_target uses rbx rsi
	fastcall destroy_capture_target
	xor ebx,ebx
	lea rsi,[framebuffers]
.framebuffer:
	cmp qword [rsi],0
	je .next
	vkDestroyFramebuffer [device],[rsi],0
	mov qword [rsi],0
.next:
	add rsi,8
	inc ebx
	cmp ebx,WSI_IMAGE_LIMIT
	jb .framebuffer
	fastcall destroy_image,addr depth_image
	fastcall wsi_destroy_swapchain
	mov [target_width],0
	mov [target_height],0
	ret
endp

proc create_target uses rbx rsi rdi
	require_vk fastcall wsi_wait_work
	fastcall destroy_target
	fastcall wsi_create_swapchain
	test eax,eax
	jz .failed
	mov eax,[wsi_swapchain_info.imageExtent.width]
	mov [frame_width],eax
	mov eax,[wsi_swapchain_info.imageExtent.height]
	mov [frame_height],eax
	mov eax,[frame_width]
	cmp eax,[tile_size]
	ja .failed
	mov [color_image_info.extent.width],eax
	mov [depth_image_info.extent.width],eax
	mov [framebuffer_info.width],eax
	mov [scissor.extent.width],eax
	mov [rendering_info.renderArea.extent.width],eax
	mov [renderpass_begin.renderArea.extent.width],eax
	mov [readback_region.imageExtent.width],eax
	cvtsi2ss xmm0,eax
	movss [viewport.width],xmm0
	mov eax,[frame_height]
	cmp eax,[tile_size]
	ja .failed
	mov [color_image_info.extent.height],eax
	mov [depth_image_info.extent.height],eax
	mov [framebuffer_info.height],eax
	mov [scissor.extent.height],eax
	mov [rendering_info.renderArea.extent.height],eax
	mov [renderpass_begin.renderArea.extent.height],eax
	mov [readback_region.imageExtent.height],eax
	cvtsi2ss xmm0,eax
	movss [viewport.height],xmm0
	fastcall create_image,addr depth_image,addr depth_image_info,addr depth_view_info
	test eax,eax
	jz .failed
	mov rax,[depth_image.view]
	mov [framebuffer_views+8],rax
	mov [render_depth.imageView],rax
	test [active_caps],CAP_RENDER
	jnz .ready
	xor ebx,ebx
	lea rsi,[wsi_images]
	lea rdi,[framebuffers]
.framebuffer:
	cmp ebx,[wsi_image_count]
	jae .ready
	mov rax,[rsi+WsiImage.view]
	mov [framebuffer_views],rax
	require_vk vkCreateFramebuffer [device],addr framebuffer_info,0,rdi
	inc ebx
	add rsi,sizeof.WsiImage
	add rdi,8
	jmp .framebuffer
.ready:
	mov eax,[frame_width]
	mov [target_width],eax
	mov eax,[frame_height]
	mov [target_height],eax
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

section '.data$cube_target' data readable writeable align 8
target_width dd 0
target_height dd 0
target_format dd VK_FORMAT_B8G8R8A8_SRGB
texture_format dd VK_FORMAT_R8G8B8A8_SRGB
depth_format dd VK_FORMAT_D32_SFLOAT
depth_aspect dd VK_IMAGE_ASPECT_DEPTH_BIT
MATERIAL_TEXTURE_DECODE = 1
MATERIAL_TARGET_ENCODE = 2
material_flags dd 0
required_format_features dd 0
depth_image GpuImage
readback_buffer GpuBuffer
framebuffers rq WSI_IMAGE_LIMIT
framebuffer_views rq 2
cube_format_properties VkFormatProperties
cube_image_properties VkImageFormatProperties
color_image_info VkImageCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,imageType: VK_IMAGE_TYPE_2D,extent: <depth: 1>,mipLevels: 1,arrayLayers: 1,samples: VK_SAMPLE_COUNT_1_BIT,tiling: VK_IMAGE_TILING_OPTIMAL,usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT
depth_image_info VkImageCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,imageType: VK_IMAGE_TYPE_2D,extent: <depth: 1>,mipLevels: 1,arrayLayers: 1,samples: VK_SAMPLE_COUNT_1_BIT,tiling: VK_IMAGE_TILING_OPTIMAL,usage: VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
color_view_info VkImageViewCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,viewType: VK_IMAGE_VIEW_TYPE_2D,subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
depth_view_info VkImageViewCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,viewType: VK_IMAGE_VIEW_TYPE_2D,subresourceRange: <aspectMask: VK_IMAGE_ASPECT_DEPTH_BIT,levelCount: 1,layerCount: 1>
readback_region VkBufferImageCopy imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageExtent: <depth: 1>
readback_invalidate VkMappedMemoryRange sType: VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,size: VK_WHOLE_SIZE
