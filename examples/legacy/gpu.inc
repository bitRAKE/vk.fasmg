; Pipelines and presentation. A frame is drawn into the acquired swapchain
; image and presented from there; nothing in this file reads an image back.
; Each modern operation sits in a `route` block and what it replaces in an
; `alternate` block, so the build's contract decides which of them exist.

; A VkResult in EAX: on failure record it and leave.
macro require_vk line&
	line
	test eax,eax
	jnz .result
end macro
; A Boolean in EAX.
macro require_ok line&
	line
	test eax,eax
	jz .failed
end macro

include '..\common\vulkan_memory.inc'
include '..\common\vulkan_commands.inc'
include '..\common\vulkan_barriers.inc'

section '.text$gpu' code readable executable align 16

; Called while adapters are considered. A UNORM surface keeps the palette's
; bytes as the shader writes them, on screen and in an export alike.
proc choose_formats
	require_ok fastcall wsi_choose_format,VK_FORMAT_B8G8R8A8_UNORM
	vkGetPhysicalDeviceFormatProperties [physical_device],[wsi_format],addr target_properties
	mov eax,[target_properties.optimalTilingFeatures]
	and eax,VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or VK_FORMAT_FEATURE_TRANSFER_SRC_BIT
	cmp eax,VK_FORMAT_FEATURE_COLOR_ATTACHMENT_BIT or VK_FORMAT_FEATURE_TRANSFER_SRC_BIT
	jne .failed
	mov eax,[wsi_format]
	mov [target_format],eax
	mov [tile_image_info.format],eax
	mov [tile_view_info.format],eax
	alternate CAP_RENDER
		mov [color_attachment.format],eax
	end alternate
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc create_gpu_resources
	mov [failure_stage],2
	require_ok fastcall create_memory_pools
	require_vk fastcall create_commands
	mov rax,[command_buffer]
	mov [export_command_buffer],rax
	require_ok fastcall wsi_create_frames
	mov [failure_stage],3
	require_ok fastcall create_pipelines
	mov [failure_stage],0
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

proc create_pipelines
	alternate CAP_RENDER,.layout
		require_vk vkCreateRenderPass [device],addr renderpass_info,0,addr render_pass
		mov rax,[render_pass]
		mov [framebuffer_info.renderPass],rax
		mov [pipeline_info.renderPass],rax
		mov [renderpass_begin.renderPass],rax
	end alternate
.layout:
	require_vk vkCreatePipelineLayout [device],addr layout_info,0,addr pipeline_layout
	mov rax,[pipeline_layout]
	mov [pipeline_info.layout],rax
	route CAP_RENDER,.vertex
		lea rax,[pipeline_rendering]
		mov [pipeline_info.pNext],rax
	end route
.vertex:
	route CAP_INLINE,.vertex_module
		lea rax,[vertex_code_info]
		mov [vertex_stage.pNext],rax
		jmp .fragments
	end route
	alternate CAP_INLINE
	.vertex_module:
		require_vk vkCreateShaderModule [device],addr vertex_code_info,0,addr vertex_module
		mov rax,[vertex_module]
		mov [vertex_stage.module],rax
	end alternate
.fragments:
	require_ok fastcall create_pipeline,addr fragment_code_info,addr pipeline
	; Deep zoom: doubles where the device enabled them, float pairs where not.
	lea rcx,[pairs_code_info]
	mov rax,[pairs_minimum_scale]
	test [active_caps],CAP_FLOAT64
	jz .deep
	lea rcx,[fragment64_code_info]
	mov rax,[double_minimum_scale]
.deep:
	mov [minimum_scale],rax
	require_ok fastcall create_pipeline,rcx,addr deep_pipeline
	alternate CAP_INLINE,.ready
		vkDestroyShaderModule [device],[vertex_module],0
		mov [vertex_module],0
	end alternate
.ready:
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

; One pipeline per fragment shader. Code chained to the stage and code in a
; module make the same pipeline; the module is not needed once it exists.
proc create_pipeline uses rbx rsi,code,handle
	mov rbx,rcx
	mov rsi,rdx
	route CAP_INLINE,.module
		mov [fragment_stage.pNext],rbx
		jmp .create
	end route
	alternate CAP_INLINE
	.module:
		require_vk vkCreateShaderModule [device],rbx,0,addr fragment_module
		mov rax,[fragment_module]
		mov [fragment_stage.module],rax
	end alternate
.create:
	require_vk vkCreateGraphicsPipelines [device],0,1,addr pipeline_info,0,rsi
	alternate CAP_INLINE,.ready
		vkDestroyShaderModule [device],[fragment_module],0
		mov [fragment_module],0
	end alternate
.ready:
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc destroy_target uses rbx rsi
	fastcall destroy_export_target
	alternate CAP_RENDER
		lea rsi,[framebuffers]
		mov ebx,WSI_IMAGE_LIMIT
	.framebuffer:
		cmp qword [rsi],0
		je .next
		vkDestroyFramebuffer [device],[rsi],0
		mov qword [rsi],0
	.next:
		add rsi,8
		dec ebx
		jnz .framebuffer
	end alternate
	fastcall wsi_destroy_swapchain
	mov [target_width],0
	mov [target_height],0
	ret
endp

; A swapchain for the client area as it is now. The render-pass alternate
; needs a framebuffer for each of its images; dynamic rendering needs nothing.
proc create_target uses rbx rsi rdi
	require_vk fastcall wsi_wait_work
	fastcall destroy_target
	require_ok fastcall wsi_create_swapchain
	mov eax,[wsi_swapchain_info.imageExtent.width]
	mov [frame_width],eax
	mov edx,[wsi_swapchain_info.imageExtent.height]
	mov [frame_height],edx
	alternate CAP_RENDER,.ready
		mov [framebuffer_info.width],eax
		mov [framebuffer_info.height],edx
		xor ebx,ebx
		lea rsi,[wsi_images]
		lea rdi,[framebuffers]
	.framebuffer:
		cmp ebx,[wsi_image_count]
		jae .ready
		mov rax,[rsi+WsiImage.view]
		mov [framebuffer_view],rax
		require_vk vkCreateFramebuffer [device],addr framebuffer_info,0,rdi
		inc ebx
		add rsi,sizeof.WsiImage
		add rdi,8
		jmp .framebuffer
	end alternate
.ready:
	mov eax,[frame_width]
	mov [target_width],eax
	mov eax,[frame_height]
	mov [target_height],eax
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

; Record the view into draw_image, which the caller also made the rendering
; attachment or the framebuffer: `width` by `height` pixels whose top-left one
; is (origin_x, origin_y) of the whole picture. The fragment shader covers
; every pixel, so the previous contents are discarded.
proc record_view uses rbx rsi,width,height,origin_x,origin_y
	mov ebx,ecx
	mov esi,edx
	fastcall write_view,r8,r9
	mov [scissor.extent.width],ebx
	mov [scissor.extent.height],esi
	cvtsi2ss xmm0,ebx
	movss [viewport.width],xmm0
	cvtsi2ss xmm0,esi
	movss [viewport.height],xmm0
	fastcall transition_image,[draw_image],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
	route CAP_RENDER,.renderpass
		mov [rendering_info.renderArea.extent.width],ebx
		mov [rendering_info.renderArea.extent.height],esi
		vkCmdBeginRendering [command_buffer],addr rendering_info
		jmp .draw
	end route
	alternate CAP_RENDER
	.renderpass:
		mov [renderpass_begin.renderArea.extent.width],ebx
		mov [renderpass_begin.renderArea.extent.height],esi
		vkCmdBeginRenderPass [command_buffer],addr renderpass_begin,VK_SUBPASS_CONTENTS_INLINE
	end alternate
.draw:
	vkCmdBindPipeline [command_buffer],VK_PIPELINE_BIND_POINT_GRAPHICS,[draw_pipeline]
	vkCmdSetViewport [command_buffer],0,1,addr viewport
	vkCmdSetScissor [command_buffer],0,1,addr scissor
	vkCmdPushConstants [command_buffer],[pipeline_layout],VK_SHADER_STAGE_FRAGMENT_BIT,0,PUSH_BYTES,addr push_data
	vkCmdDraw [command_buffer],3,1,0,0
	route CAP_RENDER,.end_renderpass
		vkCmdEndRendering [command_buffer]
		ret
	end route
	alternate CAP_RENDER
	.end_renderpass:
		vkCmdEndRenderPass [command_buffer]
		ret
	end alternate
endp

proc render_frame uses rbx rsi
	xor esi,esi
	mov [failure_stage],5
	cmp [wsi_dirty],0
	jne .resize
	mov eax,[frame_width]
	cmp eax,[target_width]
	jne .resize
	mov eax,[frame_height]
	cmp eax,[target_height]
	je .acquire
.resize:
	require_ok fastcall create_target
.acquire:
	fastcall wsi_begin_frame
	cmp eax,2
	je .retry
	test eax,eax
	jz .wsi_failed
	mov [failure_stage],6
	mov rbx,[wsi_current_image]
	mov rax,[rbx+WsiImage.handle]
	mov [draw_image],rax
	route CAP_RENDER
		mov rax,[rbx+WsiImage.view]
		mov [render_color.imageView],rax
	end route
	alternate CAP_RENDER
		mov eax,[wsi_image_index]
		lea rdx,[framebuffers]
		mov rax,[rdx+rax*8]
		mov [renderpass_begin.framebuffer],rax
	end alternate
	fastcall record_view,[frame_width],[frame_height],0,0
	fastcall transition_image,[draw_image],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,0
	fastcall wsi_submit_frame
	test eax,eax
	jz .wsi_failed
	inc [frame_count]
	jmp .ready
.retry:
	; Recreate once in this call, so a restored window recovers too.
	inc esi
	cmp esi,2
	jb .resize
.ready:
	mov [failure_stage],0
	mov eax,1
	ret
.wsi_failed:
	mov eax,[wsi_error]
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

proc destroy_gpu
	cmp [device],0
	je .instance
	mov [wsi_shutdown],1
	mov [wsi_replacement_hold],0
	fastcall wsi_drain
	fastcall destroy_target
	iterate <handle,function>,pipeline,vkDestroyPipeline,deep_pipeline,vkDestroyPipeline,pipeline_layout,vkDestroyPipelineLayout
		cmp [handle],0
		je .skip#handle
		function [device],[handle],0
		mov [handle],0
	.skip#handle:
	end iterate
	alternate CAP_INLINE
		iterate handle,vertex_module,fragment_module
			cmp [handle],0
			je .skip#handle
			vkDestroyShaderModule [device],[handle],0
			mov [handle],0
		.skip#handle:
		end iterate
	end alternate
	alternate CAP_RENDER
		cmp [render_pass],0
		je .pools
		vkDestroyRenderPass [device],[render_pass],0
		mov [render_pass],0
	end alternate
.pools:
	fastcall collect_gpu_deletes
	fastcall destroy_memory_pools
	fastcall wsi_destroy_frames
	fastcall destroy_commands
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

section '.data$gpu' data readable writeable align 8
pipeline_layout dq 0
pipeline dq 0
deep_pipeline dq 0
draw_image dq 0
export_command_buffer dq 0
target_width dd 0
target_height dd 0
target_format dd VK_FORMAT_B8G8R8A8_UNORM
frame_count dd 0
gpu_error dd 0
failure_stage dd 1
target_properties VkFormatProperties
push_range VkPushConstantRange stageFlags: VK_SHADER_STAGE_FRAGMENT_BIT,size: PUSH_BYTES
layout_info VkPipelineLayoutCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,pushConstantRangeCount: 1,pPushConstantRanges: push_range
; Shader code: chained to a stage on the inline route, made a module otherwise.
vertex_code_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: vertex_code.size,pCode: vertex_code
fragment_code_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: fragment_code.size,pCode: fragment_code
fragment64_code_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: fragment64_code.size,pCode: fragment64_code
pairs_code_info VkShaderModuleCreateInfo sType: VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,codeSize: pairs_code.size,pCode: pairs_code
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
pipeline_info VkGraphicsPipelineCreateInfo sType: VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,stageCount: 2,pStages: shader_stages, \
	pVertexInputState: vertex_input,pInputAssemblyState: input_assembly,pViewportState: viewport_state,pRasterizationState: raster_state, \
	pMultisampleState: multisample_state,pColorBlendState: blend_state,pDynamicState: dynamic_state,basePipelineIndex: -1
viewport VkViewport minDepth: 0.0,maxDepth: 1.0
scissor VkRect2D
route CAP_RENDER
	pipeline_rendering VkPipelineRenderingCreateInfo sType: VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,colorAttachmentCount: 1,pColorAttachmentFormats: target_format
	render_color VkRenderingAttachmentInfo sType: VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,imageLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,loadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,storeOp: VK_ATTACHMENT_STORE_OP_STORE
	rendering_info VkRenderingInfo sType: VK_STRUCTURE_TYPE_RENDERING_INFO,layerCount: 1,colorAttachmentCount: 1,pColorAttachments: render_color
end route
alternate CAP_RENDER
	; One render pass serves every target; a framebuffer names each of them.
	render_pass dq 0
	framebuffer_view dq 0
	framebuffers rq WSI_IMAGE_LIMIT
	color_attachment VkAttachmentDescription samples: VK_SAMPLE_COUNT_1_BIT,loadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,storeOp: VK_ATTACHMENT_STORE_OP_STORE, \
		stencilLoadOp: VK_ATTACHMENT_LOAD_OP_DONT_CARE,stencilStoreOp: VK_ATTACHMENT_STORE_OP_DONT_CARE,initialLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
	color_reference VkAttachmentReference attachment: 0,layout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
	subpass VkSubpassDescription pipelineBindPoint: VK_PIPELINE_BIND_POINT_GRAPHICS,colorAttachmentCount: 1,pColorAttachments: color_reference
	renderpass_info VkRenderPassCreateInfo sType: VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,attachmentCount: 1,pAttachments: color_attachment,subpassCount: 1,pSubpasses: subpass
	framebuffer_info VkFramebufferCreateInfo sType: VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,attachmentCount: 1,pAttachments: framebuffer_view,layers: 1
	renderpass_begin VkRenderPassBeginInfo sType: VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
end alternate
alternate CAP_INLINE
	vertex_module dq 0
	fragment_module dq 0
end alternate

section '.rdata$spirv' data readable align 4
vertex_code file 'build\legacy_fullscreen.spv'
vertex_code.size = $ - vertex_code
align 4
fragment_code file 'build\legacy_fractal.spv'
fragment_code.size = $ - fragment_code
align 4
fragment64_code file 'build\legacy_fractal64.spv'
fragment64_code.size = $ - fragment64_code
align 4
pairs_code file 'build\legacy_fractal32x2.spv'
pairs_code.size = $ - pairs_code
