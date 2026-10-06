; Offscreen Vulkan renderer; Win32 presents/exports the same BGRA image.
; Fallbacks implement this serial workload, not a general sync2/timeline API.
macro require_vk line&
	line
	test eax,eax
	jnz .failed
end macro

section '.text$gpu' code readable executable align 16
proc memory_index uses rbx rsi,bits,required
	mov ebx,ecx
	lea rsi,[memory_properties2.memoryProperties.memoryTypes]
	xor eax,eax
.type:
	cmp eax,[memory_properties2.memoryProperties.memoryTypeCount]
	jae .failed
	bt ebx,eax
	jnc .next
	mov ecx,[rsi+VkMemoryType.propertyFlags]
	and ecx,edx
	cmp ecx,edx
	je .done
.next:
	inc eax
	add rsi,sizeof.VkMemoryType
	jmp .type
.failed:
	mov eax,-1
.done:
	ret
endp

proc create_gpu_resources uses rbx
	require_vk vkCreateCommandPool [device],addr pool_info,0,addr command_pool
	mov rax,[command_pool]
	mov [command_allocate.commandPool],rax
	require_vk vkAllocateCommandBuffers [device],addr command_allocate,addr command_buffer
	mov eax,[tile_size]
	mov [image_info.extent.width],eax
	mov [image_info.extent.height],eax
	mov [framebuffer_info.width],eax
	mov [framebuffer_info.height],eax
	require_vk vkCreateImage [device],addr image_info,0,addr render_image
	vkGetImageMemoryRequirements [device],[render_image],addr requirements
	fastcall memory_index,[requirements.memoryTypeBits],VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
	cmp eax,-1
	jne .image_type
	fastcall memory_index,[requirements.memoryTypeBits],0
.image_type:
	cmp eax,-1
	je .failed
	mov [allocation_info.memoryTypeIndex],eax
	mov rax,[requirements.size]
	mov [allocation_info.allocationSize],rax
	require_vk vkAllocateMemory [device],addr allocation_info,0,addr image_memory
	require_vk vkBindImageMemory [device],[render_image],[image_memory],0
	mov rax,[render_image]
	mov [image_view_info.image],rax
	mov [barrier2.image],rax
	mov [barrier1.image],rax
	mov [copy2_info.srcImage],rax
	require_vk vkCreateImageView [device],addr image_view_info,0,addr image_view
	mov rax,[image_view]
	mov [render_attachment.imageView],rax
	mov eax,[tile_size]
	imul eax,eax
	shl rax,2
	mov [buffer_info.size],rax
	require_vk vkCreateBuffer [device],addr buffer_info,0,addr staging_buffer
	mov rax,[staging_buffer]
	mov [copy2_info.dstBuffer],rax
	vkGetBufferMemoryRequirements [device],[staging_buffer],addr requirements
	fastcall memory_index,[requirements.memoryTypeBits],VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
	cmp eax,-1
	je .failed
	mov [allocation_info.memoryTypeIndex],eax
	imul eax,sizeof.VkMemoryType
	lea rcx,[memory_properties2.memoryProperties.memoryTypes]
	mov eax,[rcx+rax+VkMemoryType.propertyFlags]
	and eax,VK_MEMORY_PROPERTY_HOST_COHERENT_BIT
	mov [staging_coherent],eax
	mov rax,[requirements.size]
	mov [allocation_info.allocationSize],rax
	require_vk vkAllocateMemory [device],addr allocation_info,0,addr staging_memory
	require_vk vkBindBufferMemory [device],[staging_buffer],[staging_memory],0
	require_vk vkMapMemory [device],[staging_memory],0,VK_WHOLE_SIZE,0,addr mapped_pixels
	mov rax,[staging_memory]
	mov [invalidate_info.memory],rax
	test [active_caps],CAP_RENDER
	jnz .layout
	require_vk vkCreateRenderPass [device],addr renderpass_info,0,addr render_pass
	mov rax,[render_pass]
	mov [framebuffer_info.renderPass],rax
	mov [pipeline_info.renderPass],rax
	mov [renderpass_begin.renderPass],rax
	require_vk vkCreateFramebuffer [device],addr framebuffer_info,0,addr framebuffer
	mov rax,[framebuffer]
	mov [renderpass_begin.framebuffer],rax
.layout:
	require_vk vkCreatePipelineLayout [device],addr layout_info,0,addr pipeline_layout
	mov rax,[pipeline_layout]
	mov [pipeline_info.layout],rax
	test [active_caps],CAP_INLINE
	jz .modules
	lea rax,[vertex_module_info]
	mov [vertex_stage.pNext],rax
	lea rax,[fragment_module_info]
	mov [fragment_stage.pNext],rax
	jmp .pipeline
.modules:
	require_vk vkCreateShaderModule [device],addr vertex_module_info,0,addr vertex_module
	mov rax,[vertex_module]
	mov [vertex_stage.module],rax
	require_vk vkCreateShaderModule [device],addr fragment_module_info,0,addr fragment_module
	mov rax,[fragment_module]
	mov [fragment_stage.module],rax
.pipeline:
	test [active_caps],CAP_RENDER
	jz .create_pipeline
	lea rax,[pipeline_rendering]
	mov [pipeline_info.pNext],rax
.create_pipeline:
	require_vk vkCreateGraphicsPipelines [device],0,1,addr pipeline_info,0,addr pipeline
	test [active_caps],CAP_FLOAT64
	jz .modules_done
	test [active_caps],CAP_INLINE
	jz .double_module
	lea rax,[fragment64_module_info]
	mov [fragment_stage.pNext],rax
	jmp .double_pipeline
.double_module:
	vkDestroyShaderModule [device],[fragment_module],0
	mov [fragment_module],0
	require_vk vkCreateShaderModule [device],addr fragment64_module_info,0,addr fragment_module
	mov rax,[fragment_module]
	mov [fragment_stage.module],rax
.double_pipeline:
	require_vk vkCreateGraphicsPipelines [device],0,1,addr pipeline_info,0,addr pipeline64
.modules_done:
	; Inline code and explicit modules have identical pipeline semantics.
	cmp [vertex_module],0
	je .completion
	vkDestroyShaderModule [device],[vertex_module],0
	mov [vertex_module],0
	vkDestroyShaderModule [device],[fragment_module],0
	mov [fragment_module],0
.completion:
	test [active_caps],CAP_TIMELINE
	jz .fence
	require_vk vkCreateSemaphore [device],addr semaphore_info,0,addr timeline_semaphore
	mov rax,[timeline_semaphore]
	mov [signal_info.semaphore],rax
	mov [submit1.signalSemaphoreCount],1
	lea rax,[timeline_submit]
	mov [submit1.pNext],rax
	mov [submit2.signalSemaphoreInfoCount],1
	jmp .ready
.fence:
	require_vk vkCreateFence [device],addr fence_info,0,addr completion_fence
.ready:
	mov rax,[command_buffer]
	mov [command_submit.commandBuffer],rax
	mov eax,1
	ret
.failed:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; The only transitions used by this renderer: discard -> color, color -> copy.
; Modern high COPY maps to legacy TRANSFER, and source NONE maps to TOP_OF_PIPE.
proc image_barrier phase
	test ecx,ecx
	jnz .copy
	mov [barrier2.srcStageMask],VK_PIPELINE_STAGE_2_NONE
	mov [barrier2.srcAccessMask],0
	mov [barrier2.dstStageMask],VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT
	mov [barrier2.dstAccessMask],VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT
	mov [barrier2.oldLayout],VK_IMAGE_LAYOUT_UNDEFINED
	mov [barrier2.newLayout],VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
	mov [barrier1.srcAccessMask],0
	mov [barrier1.dstAccessMask],VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
	mov [barrier1.oldLayout],VK_IMAGE_LAYOUT_UNDEFINED
	mov [barrier1.newLayout],VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
	mov [legacy_src_stage],VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT
	mov [legacy_dst_stage],VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
	jmp .emit
.copy:
	mov [barrier2.srcStageMask],VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT
	mov [barrier2.srcAccessMask],VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT
	mov rax,VK_PIPELINE_STAGE_2_COPY_BIT
	mov [barrier2.dstStageMask],rax
	mov [barrier2.dstAccessMask],VK_ACCESS_2_TRANSFER_READ_BIT
	mov [barrier2.oldLayout],VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
	mov [barrier2.newLayout],VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
	mov [barrier1.srcAccessMask],VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
	mov [barrier1.dstAccessMask],VK_ACCESS_TRANSFER_READ_BIT
	mov [barrier1.oldLayout],VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
	mov [barrier1.newLayout],VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL
	mov [legacy_src_stage],VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
	mov [legacy_dst_stage],VK_PIPELINE_STAGE_TRANSFER_BIT
.emit:
	test [active_caps],CAP_SYNC
	jz .legacy
	vkCmdPipelineBarrier2 [command_buffer],addr dependency_info
	ret
.legacy:
	vkCmdPipelineBarrier [command_buffer],[legacy_src_stage],[legacy_dst_stage],0,0,0,0,0,1,addr barrier1
	ret
endp

proc render_gpu uses rbx rsi rdi
	lea rax,[push_data+16]
	mov [push_origin],rax
	mov rax,[pipeline]
	mov [draw_pipeline],rax
	cmp [gpu_precision],2
	je .double
	cvtsd2ss xmm0,[center_x]
	movss [push_data],xmm0
	cvtsd2ss xmm0,[center_y]
	movss [push_data+4],xmm0
	cvtsd2ss xmm0,[view_scale]
	movss [push_data+8],xmm0
	mov eax,[palette]
	mov [push_data+12],eax
	cvtsi2ss xmm0,dword [frame_width]
	movss [push_data+24],xmm0
	cvtsi2ss xmm0,dword [frame_height]
	movss [push_data+28],xmm0
	jmp .start
.double:
	lea rax,[push_data+32]
	mov [push_origin],rax
	mov rax,[pipeline64]
	mov [draw_pipeline],rax
	mov rax,[center_x]
	mov [push_data],rax
	mov rax,[center_y]
	mov [push_data+8],rax
	mov rax,[view_scale]
	mov [push_data+16],rax
	mov eax,[palette]
	mov [push_data+24],eax
	cvtsi2ss xmm0,dword [frame_width]
	movss [push_data+40],xmm0
	cvtsi2ss xmm0,dword [frame_height]
	movss [push_data+44],xmm0
.start:
	mov [tile_x],0
	mov [tile_y],0
	mov [tile_count],0
.tile:
	mov eax,[frame_width]
	sub eax,[tile_x]
	cmp eax,[tile_size]
	jbe .width
	mov eax,[tile_size]
.width:
	mov [tile_width],eax
	mov [scissor.extent.width],eax
	mov [rendering_info.renderArea.extent.width],eax
	mov [renderpass_begin.renderArea.extent.width],eax
	mov [copy1_region.imageExtent.width],eax
	mov [copy2_region.imageExtent.width],eax
	cvtsi2ss xmm0,eax
	movss [viewport.width],xmm0
	mov eax,[frame_height]
	sub eax,[tile_y]
	cmp eax,[tile_size]
	jbe .height
	mov eax,[tile_size]
.height:
	mov [tile_height],eax
	mov [scissor.extent.height],eax
	mov [rendering_info.renderArea.extent.height],eax
	mov [renderpass_begin.renderArea.extent.height],eax
	mov [copy1_region.imageExtent.height],eax
	mov [copy2_region.imageExtent.height],eax
	cvtsi2ss xmm0,eax
	movss [viewport.height],xmm0
	cvtsi2ss xmm0,dword [tile_x]
	mov rdx,[push_origin]
	movss [rdx],xmm0
	cvtsi2ss xmm0,dword [tile_y]
	movss [rdx+4],xmm0
	require_vk vkResetCommandBuffer [command_buffer],0
	require_vk vkBeginCommandBuffer [command_buffer],addr command_begin
	fastcall image_barrier,0
	test [active_caps],CAP_RENDER
	jz .renderpass
	vkCmdBeginRendering [command_buffer],addr rendering_info
	jmp .draw
.renderpass:
	vkCmdBeginRenderPass [command_buffer],addr renderpass_begin,VK_SUBPASS_CONTENTS_INLINE
.draw:
	vkCmdBindPipeline [command_buffer],VK_PIPELINE_BIND_POINT_GRAPHICS,[draw_pipeline]
	vkCmdSetViewport [command_buffer],0,1,addr viewport
	vkCmdSetScissor [command_buffer],0,1,addr scissor
	vkCmdPushConstants [command_buffer],[pipeline_layout],VK_SHADER_STAGE_FRAGMENT_BIT,0,48,addr push_data
	vkCmdDraw [command_buffer],3,1,0,0
	test [active_caps],CAP_RENDER
	jz .end_renderpass
	vkCmdEndRendering [command_buffer]
	jmp .copy
.end_renderpass:
	vkCmdEndRenderPass [command_buffer]
.copy:
	fastcall image_barrier,1
	test [active_caps],CAP_COPY
	jz .copy1
	vkCmdCopyImageToBuffer2 [command_buffer],addr copy2_info
	jmp .host
.copy1:
	vkCmdCopyImageToBuffer [command_buffer],[render_image],VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,[staging_buffer],1,addr copy1_region
.host:
	test [active_caps],CAP_SYNC
	jz .host1
	vkCmdPipelineBarrier2 [command_buffer],addr host_dependency
	jmp .end
.host1:
	vkCmdPipelineBarrier [command_buffer],VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_HOST_BIT,0,1,addr host_barrier1,0,0,0,0
.end:
	require_vk vkEndCommandBuffer [command_buffer]
	test [active_caps],CAP_TIMELINE
	jz .reset_fence
	inc [completion_value]
	mov rax,[completion_value]
	mov [signal_info.value],rax
	jmp .submit
.reset_fence:
	require_vk vkResetFences [device],1,addr completion_fence
.submit:
	test [active_caps],CAP_SYNC
	jz .submit1
	require_vk vkQueueSubmit2 [queue],1,addr submit2,[completion_fence]
	jmp .wait
.submit1:
	require_vk vkQueueSubmit [queue],1,addr submit1,[completion_fence]
.wait:
	test [active_caps],CAP_TIMELINE
	jz .wait_fence
	require_vk vkWaitSemaphores [device],addr timeline_wait,5000000000
	jmp .read
.wait_fence:
	require_vk vkWaitForFences [device],1,addr completion_fence,VK_TRUE,5000000000
.read:
	cmp [staging_coherent],0
	jne .rows
	require_vk vkInvalidateMappedMemoryRanges [device],1,addr invalidate_info
.rows:
	mov eax,[tile_y]
	imul eax,[frame_width]
	add eax,[tile_x]
	mov rdi,[pixels]
	lea rdi,[rdi+rax*4]
	mov rsi,[mapped_pixels]
	mov ebx,[tile_height]
.row:
	mov ecx,[tile_width]
	rep movsd
	mov eax,[frame_width]
	sub eax,[tile_width]
	lea rdi,[rdi+rax*4]
	dec ebx
	jnz .row
	inc [tile_count]
	mov eax,[tile_size]
	add [tile_x],eax
	mov ecx,[frame_width]
	cmp [tile_x],ecx
	jb .tile
	mov [tile_x],0
	add [tile_y],eax
	mov ecx,[frame_height]
	cmp [tile_y],ecx
	jb .tile
	mov eax,1
	ret
.failed:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc destroy_gpu
	cmp [device],0
	je .instance
	vkDeviceWaitIdle [device]
	cmp [mapped_pixels],0
	je .objects
	vkUnmapMemory [device],[staging_memory]
	mov [mapped_pixels],0
.objects:
	iterate <handle,function>, \
		pipeline,vkDestroyPipeline,pipeline64,vkDestroyPipeline,pipeline_layout,vkDestroyPipelineLayout, \
		vertex_module,vkDestroyShaderModule,fragment_module,vkDestroyShaderModule, \
		framebuffer,vkDestroyFramebuffer,render_pass,vkDestroyRenderPass, \
		image_view,vkDestroyImageView,render_image,vkDestroyImage,staging_buffer,vkDestroyBuffer, \
		image_memory,vkFreeMemory,staging_memory,vkFreeMemory, \
		timeline_semaphore,vkDestroySemaphore,completion_fence,vkDestroyFence,command_pool,vkDestroyCommandPool
		cmp [handle],0
		je .skip#handle
		function [device],[handle],0
		mov [handle],0
	.skip#handle:
	end iterate
	vkDestroyDevice [device],0
	mov [device],0
.instance:
	cmp [instance],0
	je .module
	cmp [messenger],0
	je .destroy_instance
	vkDestroyDebugUtilsMessengerEXT [instance],[messenger],0
	mov [messenger],0
.destroy_instance:
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

section '.data$gpu' data readable writeable align 16
command_pool dq 0
command_buffer dq 0
render_image dq 0
image_memory dq 0
image_view dq 0
staging_buffer dq 0
staging_memory dq 0
mapped_pixels dq 0
render_pass dq 0
framebuffer dq 0
pipeline_layout dq 0
pipeline dq 0
pipeline64 dq 0
draw_pipeline dq 0
push_origin dq 0
gpu_precision dd 1
vertex_module dq 0
fragment_module dq 0
timeline_semaphore dq 0
completion_fence dq 0
completion_value dq 0
gpu_error dd 0
staging_coherent dd 0
tile_x dd 0
tile_y dd 0
tile_width dd 0
tile_height dd 0
tile_count dd 0
legacy_src_stage dd 0
legacy_dst_stage dd 0
align 8
push_data:
	rb 48
pool_info VkCommandPoolCreateInfo sType: VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,flags: VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
command_allocate VkCommandBufferAllocateInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,level: VK_COMMAND_BUFFER_LEVEL_PRIMARY,commandBufferCount: 1
command_begin VkCommandBufferBeginInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,flags: VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT
image_info VkImageCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,imageType: VK_IMAGE_TYPE_2D,format: VK_FORMAT_B8G8R8A8_UNORM, \
	extent: <depth: 1>,mipLevels: 1,arrayLayers: 1,samples: VK_SAMPLE_COUNT_1_BIT,tiling: VK_IMAGE_TILING_OPTIMAL,usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT
image_view_info VkImageViewCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,viewType: VK_IMAGE_VIEW_TYPE_2D,format: VK_FORMAT_B8G8R8A8_UNORM, \
	subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
requirements VkMemoryRequirements
allocation_info VkMemoryAllocateInfo sType: VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
buffer_info VkBufferCreateInfo sType: VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,usage: VK_BUFFER_USAGE_TRANSFER_DST_BIT
invalidate_info VkMappedMemoryRange sType: VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE,size: VK_WHOLE_SIZE
attachment VkAttachmentDescription format: VK_FORMAT_B8G8R8A8_UNORM,samples: VK_SAMPLE_COUNT_1_BIT,loadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,storeOp: VK_ATTACHMENT_STORE_OP_STORE, \
	stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,initialLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
attachment_ref VkAttachmentReference attachment: 0,layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
subpass VkSubpassDescription pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,colorAttachmentCount: 1,pColorAttachments: attachment_ref
renderpass_info VkRenderPassCreateInfo sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,attachmentCount: 1,pAttachments: attachment,subpassCount: 1,pSubpasses: subpass
framebuffer_info VkFramebufferCreateInfo sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,attachmentCount: 1,pAttachments: image_view,layers: 1
push_range VkPushConstantRange stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT,size: 48
layout_info VkPipelineLayoutCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,pushConstantRangeCount: 1,pPushConstantRanges: push_range
vertex_module_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: vertex_code.size,pCode: vertex_code
fragment_module_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: fragment_code.size,pCode: fragment_code
fragment64_module_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: fragment64_code.size,pCode: fragment64_code
entry_name GLOBSTR 'main',0
shader_stages:
vertex_stage VkPipelineShaderStageCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,stage: VK_SHADER_STAGE_VERTEX_BIT,pName: entry_name
fragment_stage VkPipelineShaderStageCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,stage: VK_SHADER_STAGE_FRAGMENT_BIT,pName: entry_name
vertex_input VkPipelineVertexInputStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
input_assembly VkPipelineInputAssemblyStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,topology: VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
viewport_state VkPipelineViewportStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,viewportCount: 1,scissorCount: 1
raster_state VkPipelineRasterizationStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,polygonMode: VK_POLYGON_MODE_FILL,cullMode: VK_CULL_MODE_NONE,lineWidth: 1.0
multisample_state VkPipelineMultisampleStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,rasterizationSamples: VK_SAMPLE_COUNT_1_BIT
blend_attachment VkPipelineColorBlendAttachmentState colorWriteMask: 15
blend_state VkPipelineColorBlendStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,attachmentCount: 1,pAttachments: blend_attachment
dynamic_states dd VK_DYNAMIC_STATE_VIEWPORT,VK_DYNAMIC_STATE_SCISSOR
dynamic_state VkPipelineDynamicStateCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,dynamicStateCount: 2,pDynamicStates: dynamic_states
color_format dd VK_FORMAT_B8G8R8A8_UNORM
pipeline_rendering VkPipelineRenderingCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,colorAttachmentCount: 1,pColorAttachmentFormats: color_format
pipeline_info VkGraphicsPipelineCreateInfo sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,stageCount: 2,pStages: shader_stages, \
	pVertexInputState: vertex_input,pInputAssemblyState: input_assembly,pViewportState: viewport_state,pRasterizationState: raster_state, \
	pMultisampleState: multisample_state,pColorBlendState: blend_state,pDynamicState: dynamic_state,basePipelineIndex: -1
semaphore_type VkSemaphoreTypeCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_TYPE_CREATE_INFO,semaphoreType: VK_SEMAPHORE_TYPE_TIMELINE
semaphore_info VkSemaphoreCreateInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,pNext: semaphore_type
fence_info VkFenceCreateInfo sType: VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
signal_info VkSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO,stageMask: VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT
command_submit VkCommandBufferSubmitInfo sType: VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO
submit2 VkSubmitInfo2 sType: VK_STRUCTURE_TYPE_SUBMIT_INFO_2,commandBufferInfoCount: 1,pCommandBufferInfos: command_submit,pSignalSemaphoreInfos: signal_info
timeline_submit VkTimelineSemaphoreSubmitInfo sType: VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,signalSemaphoreValueCount: 1,pSignalSemaphoreValues: completion_value
submit1 VkSubmitInfo sType: VK_STRUCTURE_TYPE_SUBMIT_INFO,commandBufferCount: 1,pCommandBuffers: command_buffer,pSignalSemaphores: timeline_semaphore
timeline_wait VkSemaphoreWaitInfo sType: VK_STRUCTURE_TYPE_SEMAPHORE_WAIT_INFO,semaphoreCount: 1,pSemaphores: timeline_semaphore,pValues: completion_value
viewport VkViewport minDepth: 0.0,maxDepth: 1.0
scissor VkRect2D
render_attachment VkRenderingAttachmentInfo sType: VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,imageLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,loadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,storeOp: VK_ATTACHMENT_STORE_OP_STORE
rendering_info VkRenderingInfo sType: VK_STRUCTURE_TYPE_RENDERING_INFO,layerCount: 1,colorAttachmentCount: 1,pColorAttachments: render_attachment
renderpass_begin VkRenderPassBeginInfo sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
barrier2 VkImageMemoryBarrier2 sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED, \
	subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
barrier1 VkImageMemoryBarrier sType: VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,srcQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED,dstQueueFamilyIndex: VK_QUEUE_FAMILY_IGNORED, \
	subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
dependency_info VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,imageMemoryBarrierCount: 1,pImageMemoryBarriers: barrier2
copy1_region VkBufferImageCopy imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageExtent: <depth: 1>
copy2_region VkBufferImageCopy2 sType: VK_STRUCTURE_TYPE_BUFFER_IMAGE_COPY_2,imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageExtent: <depth: 1>
copy2_info VkCopyImageToBufferInfo2 sType: VK_STRUCTURE_TYPE_COPY_IMAGE_TO_BUFFER_INFO_2,srcImageLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,regionCount: 1,pRegions: copy2_region
host_barrier2 VkMemoryBarrier2 sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER_2,srcStageMask: VK_PIPELINE_STAGE_2_COPY_BIT,srcAccessMask: VK_ACCESS_2_TRANSFER_WRITE_BIT,dstStageMask: VK_PIPELINE_STAGE_2_HOST_BIT,dstAccessMask: VK_ACCESS_2_HOST_READ_BIT
host_barrier1 VkMemoryBarrier sType: VK_STRUCTURE_TYPE_MEMORY_BARRIER,srcAccessMask: VK_ACCESS_TRANSFER_WRITE_BIT,dstAccessMask: VK_ACCESS_HOST_READ_BIT
host_dependency VkDependencyInfo sType: VK_STRUCTURE_TYPE_DEPENDENCY_INFO,memoryBarrierCount: 1,pMemoryBarriers: host_barrier2

section '.rdata$spirv' data readable align 4
vertex_code file 'build\legacy_fullscreen.spv'
vertex_code.size = $ - vertex_code
align 4
fragment_code file 'build\legacy_fractal.spv'
fragment_code.size = $ - fragment_code
align 4
fragment64_code file 'build\legacy_fractal64.spv'
fragment64_code.size = $ - fragment64_code
