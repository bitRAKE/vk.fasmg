macro require_vk line&
	line
	test eax,eax
	jnz .failed
end macro

include '..\common\vulkan_memory.inc'
include '..\common\vulkan_commands.inc'
include '..\common\vulkan_barriers.inc'
include 'target.inc'
include 'material.inc'
include 'pipeline.inc'

section '.text$cube_gpu' code readable executable align 16
proc create_gpu_resources
	mov [failure_stage],2
	fastcall choose_formats
	test eax,eax
	jz .failed
	mov [failure_stage],3
	fastcall create_memory_pools
	test eax,eax
	jz .failed
	require_vk fastcall create_commands
	mov rax,[command_buffer]
	mov [capture_command_buffer],rax
	fastcall wsi_create_frames
	test eax,eax
	jz .failed
	fastcall create_material
	test eax,eax
	jz .failed
	mov [failure_stage],4
	fastcall create_pipeline
	test eax,eax
	jz .failed
	mov [failure_stage],0
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
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
	fastcall create_target
	test eax,eax
	jz .failed
.acquire:
	fastcall wsi_begin_frame
	cmp eax,2
	je .retry
	test eax,eax
	jz .failed
	mov [failure_stage],6
	mov rbx,[wsi_current_image]
	mov rax,[rbx+WsiImage.handle]
	mov [draw_color_image],rax
	mov rax,[rbx+WsiImage.view]
	mov [render_color.imageView],rax
	mov eax,[wsi_image_index]
	lea rdx,[framebuffers]
	mov rax,[rdx+rax*8]
	mov [renderpass_begin.framebuffer],rax
	fastcall record_scene
	fastcall transition_image,[draw_color_image],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,0
	fastcall wsi_submit_frame
	test eax,eax
	jz .failed
	inc [frame_count]
	jmp .ready
.retry:
	; Recreate once in this call so a paused window also recovers on restore.
	inc esi
	cmp esi,2
	jae .ready
	jmp .resize
.ready:
	mov [failure_stage],0
	mov eax,1
	ret
.failed:
	mov eax,[wsi_error]
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

; Shared by direct swapchain rendering and on-demand GPU image capture.
proc record_scene
	fastcall update_scene
	fastcall transition_image,[draw_color_image],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
	fastcall transition_image,[depth_image.handle],[depth_aspect],VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT or VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT,VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_READ_BIT or VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT
	test [active_caps],CAP_RENDER
	jz .renderpass
	vkCmdBeginRendering [command_buffer],addr rendering_info
	jmp .pipeline
.renderpass:
	vkCmdBeginRenderPass [command_buffer],addr renderpass_begin,VK_SUBPASS_CONTENTS_INLINE
.pipeline:
	vkCmdBindPipeline [command_buffer],VK_PIPELINE_BIND_POINT_GRAPHICS,[pipeline]
	vkCmdSetViewport [command_buffer],0,1,addr viewport
	vkCmdSetScissor [command_buffer],0,1,addr scissor
	test [active_caps],CAP_HEAP
	jz .sets
	vkCmdBindResourceHeapEXT [command_buffer],addr resource_bind
	vkCmdBindSamplerHeapEXT [command_buffer],addr sampler_bind
	vkCmdPushDataEXT [command_buffer],addr push_data_info
	jmp .vertices
.sets:
	vkCmdBindDescriptorSets [command_buffer],VK_PIPELINE_BIND_POINT_GRAPHICS,[pipeline_layout],0,1,addr descriptor_set,0,0
	vkCmdPushConstants [command_buffer],[pipeline_layout],VK_SHADER_STAGE_VERTEX_BIT or VK_SHADER_STAGE_FRAGMENT_BIT,0,ROOT_BYTES,addr cube_root
.vertices:
	test [active_caps],CAP_ADDRESS
	jnz .indices
	vkCmdBindVertexBuffers [command_buffer],0,1,addr data_buffer.handle,addr vertex_offset
.indices:
	test [active_caps],CAP_COMMAND_ADDRESS
	jz .index_buffer
	vkCmdBindIndexBuffer3KHR [command_buffer],addr address_index
	jmp .draw_indexed
.index_buffer:
	vkCmdBindIndexBuffer [command_buffer],[data_buffer.handle],CUBE_VERTEX_BYTES,VK_INDEX_TYPE_UINT16
.draw_indexed:
	vkCmdDrawIndexed [command_buffer],36,1,0,0,0
	test [active_caps],CAP_RENDER
	jz .end_pass
	vkCmdEndRendering [command_buffer]
	jmp .end_scene
.end_pass:
	vkCmdEndRenderPass [command_buffer]
.end_scene:
	ret
endp

include 'capture.inc'

section '.text$cube_gpu' code readable executable align 16
proc destroy_gpu
	cmp [device],0
	je .instance
	mov [wsi_shutdown],1
	mov [wsi_replacement_hold],0
	fastcall wsi_drain
	fastcall destroy_target
	iterate <handle,function>,pipeline,vkDestroyPipeline,pipeline_layout,vkDestroyPipelineLayout,vertex_module,vkDestroyShaderModule,fragment_module,vkDestroyShaderModule,render_pass,vkDestroyRenderPass
		cmp [handle],0
		je .skip#handle
		function [device],[handle],0
		mov [handle],0
	.skip#handle:
	end iterate
	fastcall destroy_material
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

section '.data$cube_gpu' data readable writeable align 8
draw_color_image dq 0
capture_command_buffer dq 0
capture_count dd 0
frame_count dd 0
gpu_error dd 0
failure_stage dd 1
push_data_info VkPushDataInfoEXT sType: VK_STRUCTURE_TYPE_PUSH_DATA_INFO_EXT,data: <address: cube_root,size: ROOT_BYTES>
readback2_region VkBufferImageCopy2 sType: VK_STRUCTURE_TYPE_BUFFER_IMAGE_COPY_2,imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageExtent: <depth: 1>
readback2 VkCopyImageToBufferInfo2 sType: VK_STRUCTURE_TYPE_COPY_IMAGE_TO_BUFFER_INFO_2,srcImageLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,regionCount: 1,pRegions: readback2_region
readback_address_region VkDeviceMemoryImageCopyKHR sType: VK_STRUCTURE_TYPE_DEVICE_MEMORY_IMAGE_COPY_KHR,addressFlags: VK_ADDRESS_COMMAND_FULLY_BOUND_BIT_KHR or VK_ADDRESS_COMMAND_STORAGE_BUFFER_USAGE_BIT_KHR,imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,imageExtent: <depth: 1>
readback_address VkCopyDeviceMemoryImageInfoKHR sType: VK_STRUCTURE_TYPE_COPY_DEVICE_MEMORY_IMAGE_INFO_KHR,regionCount: 1,pRegions: readback_address_region
