; Export draws the view a second time, offscreen, and reads that back; the
; frames on screen never leave the GPU. The image it draws into is at most
; tile_size on a side, so a larger picture is drawn in tiles. Each tile's
; push constants carry its origin in the whole picture: a tiled export has
; the pixels of an untiled one.
section '.text$export' code readable executable align 16

; The tile image, its staging buffer and the host copy, sized for the picture
; as it is now. A resize destroys them; the next export makes them again.
proc prepare_export
	cmp [pixels],0
	jne .ready
	mov eax,[frame_width]
	cmp eax,[tile_size]
	jbe .width
	mov eax,[tile_size]
.width:
	mov [tile_image_info.extent.width],eax
	mov edx,[frame_height]
	cmp edx,[tile_size]
	jbe .height
	mov edx,[tile_size]
.height:
	mov [tile_image_info.extent.height],edx
	require_ok fastcall create_image,addr tile_image,addr tile_image_info,addr tile_view_info
	alternate CAP_RENDER,.buffer
		mov rax,[tile_image.view]
		mov [framebuffer_view],rax
		mov eax,[tile_image_info.extent.width]
		mov [framebuffer_info.width],eax
		mov eax,[tile_image_info.extent.height]
		mov [framebuffer_info.height],eax
		require_vk vkCreateFramebuffer [device],addr framebuffer_info,0,addr tile_framebuffer
	end alternate
.buffer:
	mov edx,[tile_image_info.extent.width]
	imul edx,[tile_image_info.extent.height]
	shl rdx,2
	require_ok fastcall create_buffer,addr readback_buffer,rdx,VK_BUFFER_USAGE_TRANSFER_DST_BIT,0
	mov edx,[frame_width]
	imul edx,[frame_height]
	shl rdx,2
	fastcall VirtualAlloc,0,rdx,MEM_COMMIT or MEM_RESERVE,PAGE_READWRITE
	test rax,rax
	jz .failed
	mov [pixels],rax
.ready:
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

; Returns nonzero with the whole view in `pixels`: top row first, BGRA.
proc export_view uses rbx rsi rdi r12 r13 r14
	mov [failure_stage],7
	require_vk fastcall wsi_wait_work
	require_ok fastcall prepare_export
	mov [tile_count],0
	xor r13d,r13d
.row:
	xor r12d,r12d
.tile:
	; R12, R13: the tile's place in the picture. EBX, R14D: its extent.
	mov ebx,[frame_width]
	sub ebx,r12d
	cmp ebx,[tile_image_info.extent.width]
	jbe .extent
	mov ebx,[tile_image_info.extent.width]
.extent:
	mov r14d,[frame_height]
	sub r14d,r13d
	cmp r14d,[tile_image_info.extent.height]
	jbe .record
	mov r14d,[tile_image_info.extent.height]
.record:
	; Frames record into their own command buffers; export keeps the serial one.
	mov rax,[export_command_buffer]
	mov [command_buffer],rax
	require_vk fastcall begin_commands
	mov rax,[tile_image.handle]
	mov [draw_image],rax
	route CAP_RENDER
		mov rax,[tile_image.view]
		mov [render_color.imageView],rax
	end route
	alternate CAP_RENDER
		mov rax,[tile_framebuffer]
		mov [renderpass_begin.framebuffer],rax
	end alternate
	fastcall record_view,rbx,r14,r12,r13
	fastcall transition_image,[tile_image.handle],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_READ_BIT
	route CAP_COPY,.copy1
		mov rax,[tile_image.handle]
		mov [readback2.srcImage],rax
		mov rax,[readback_buffer.handle]
		mov [readback2.dstBuffer],rax
		mov [readback2_region.imageExtent.width],ebx
		mov [readback2_region.imageExtent.height],r14d
		vkCmdCopyImageToBuffer2 [command_buffer],addr readback2
		jmp .host
	end route
	alternate CAP_COPY
	.copy1:
		mov [readback_region.imageExtent.width],ebx
		mov [readback_region.imageExtent.height],r14d
		vkCmdCopyImageToBuffer [command_buffer],[tile_image.handle],VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,[readback_buffer.handle],1,addr readback_region
	end alternate
.host:
	fastcall memory_barrier,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT
	; Serial: the tile is complete, and its image free again, on return.
	require_vk fastcall submit_commands
	require_ok fastcall invalidate_buffer,addr readback_buffer
	mov eax,r13d
	imul eax,[frame_width]
	add eax,r12d
	mov rdi,[pixels]
	lea rdi,[rdi+rax*4]
	mov rsi,[readback_buffer.mapped]
	mov edx,r14d
.pixels:
	mov ecx,ebx
	rep movsd
	mov eax,[frame_width]
	sub eax,ebx
	lea rdi,[rdi+rax*4]
	dec edx
	jnz .pixels
	inc [tile_count]
	add r12d,[tile_image_info.extent.width]
	cmp r12d,[frame_width]
	jb .tile
	add r13d,[tile_image_info.extent.height]
	cmp r13d,[frame_height]
	jb .row
	cmp [target_format],VK_FORMAT_R8G8B8A8_UNORM
	jne .ready
	; The surface offered the other channel order; the bitmap wants BGRA.
	mov rdi,[pixels]
	mov ecx,[frame_width]
	imul ecx,[frame_height]
.swap:
	mov al,[rdi]
	mov dl,[rdi+2]
	mov [rdi],dl
	mov [rdi+2],al
	add rdi,4
	dec ecx
	jnz .swap
.ready:
	inc [export_count]
	mov [failure_stage],0
	mov eax,1
	ret
.result:
	mov [gpu_error],eax
.failed:
	xor eax,eax
	ret
endp

proc destroy_export_target
	alternate CAP_RENDER
		cmp [tile_framebuffer],0
		je .image
		vkDestroyFramebuffer [device],[tile_framebuffer],0
		mov [tile_framebuffer],0
	end alternate
.image:
	fastcall destroy_image,addr tile_image
	fastcall destroy_buffer,addr readback_buffer
	cmp [pixels],0
	je .done
	fastcall VirtualFree,[pixels],0,MEM_RELEASE
	mov [pixels],0
.done:
	ret
endp

section '.data$export' data readable writeable align 8
pixels dq 0
tile_image GpuImage
readback_buffer GpuBuffer
tile_count dd 0
export_count dd 0
tile_image_info VkImageCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,imageType: VK_IMAGE_TYPE_2D,extent: <depth: 1>,mipLevels: 1,arrayLayers: 1, \
	samples: VK_SAMPLE_COUNT_1_BIT,tiling: VK_IMAGE_TILING_OPTIMAL,usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT
tile_view_info VkImageViewCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,viewType: VK_IMAGE_VIEW_TYPE_2D, \
	subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
route CAP_COPY
	readback2_region VkBufferImageCopy2 sType: VK_STRUCTURE_TYPE_BUFFER_IMAGE_COPY_2,imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageExtent: <depth: 1>
	readback2 VkCopyImageToBufferInfo2 sType: VK_STRUCTURE_TYPE_COPY_IMAGE_TO_BUFFER_INFO_2,srcImageLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,regionCount: 1,pRegions: readback2_region
end route
alternate CAP_COPY
	readback_region VkBufferImageCopy imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageExtent: <depth: 1>
end alternate
alternate CAP_RENDER
	tile_framebuffer dq 0
end alternate
