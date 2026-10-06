; Readback is allocated and submitted only for export/tests, never presentation.
section '.text$cube_capture' code readable executable align 16
proc capture_frame uses rbx rsi rdi
	fastcall wsi_wait_work
	test eax,eax
	jnz .failed
	cmp [capture_color.handle],0
	jne .draw
	fastcall create_capture_target
	test eax,eax
	jz .failed
.draw:
	mov rax,[capture_command_buffer]
	mov [command_buffer],rax
	require_vk fastcall begin_commands
	mov rax,[capture_color.handle]
	mov [draw_color_image],rax
	mov rax,[capture_color.view]
	mov [render_color.imageView],rax
	mov rax,[capture_framebuffer]
	mov [renderpass_begin.framebuffer],rax
	fastcall record_scene

	fastcall transition_image,[capture_color.handle],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_READ_BIT
	test [active_caps],CAP_COMMAND_ADDRESS
	jz .copy_buffer
	mov rax,[capture_color.handle]
	mov [readback_address.image],rax
	mov rax,[readback_buffer.address]
	mov [readback_address_region.addressRange.address],rax
	mov edx,[frame_width]
	imul edx,[frame_height]
	shl rdx,2
	mov [readback_address_region.addressRange.size],rdx
	mov eax,[frame_width]
	mov [readback_address_region.imageExtent.width],eax
	mov eax,[frame_height]
	mov [readback_address_region.imageExtent.height],eax
	vkCmdCopyImageToMemoryKHR [command_buffer],addr readback_address
	jmp .host
.copy_buffer:
	test [active_caps],CAP_COPY
	jz .copy1
	mov rax,[capture_color.handle]
	mov [readback2.srcImage],rax
	mov rax,[readback_buffer.handle]
	mov [readback2.dstBuffer],rax
	mov eax,[frame_width]
	mov [readback2_region.imageExtent.width],eax
	mov eax,[frame_height]
	mov [readback2_region.imageExtent.height],eax
	vkCmdCopyImageToBuffer2 [command_buffer],addr readback2
	jmp .host
.copy1:
	vkCmdCopyImageToBuffer [command_buffer],[capture_color.handle],VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,[readback_buffer.handle],1,addr readback_region
.host:
	fastcall memory_barrier,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT
	require_vk fastcall submit_commands
	fastcall invalidate_buffer,addr readback_buffer
	test eax,eax
	jz .failed
.pixels:
	mov rsi,[readback_buffer.mapped]
	mov rdi,[pixels]
	mov ecx,[frame_width]
	imul ecx,[frame_height]
	rep movsd
	cmp [target_format],VK_FORMAT_R8G8B8A8_SRGB
	je .swizzle
	cmp [target_format],VK_FORMAT_R8G8B8A8_UNORM
	jne .ready
.swizzle:
	mov rdi,[pixels]
	mov ecx,[frame_width]
	imul ecx,[frame_height]
.pixel:
	mov al,[rdi]
	mov dl,[rdi+2]
	mov [rdi],dl
	mov [rdi+2],al
	add rdi,4
	loop .pixel
.ready:
	inc [capture_count]
	mov eax,1
	ret
.failed:
	mov [gpu_error],eax
	xor eax,eax
	ret
endp

proc create_capture_target
	fastcall create_image,addr capture_color,addr color_image_info,addr color_view_info
	test eax,eax
	jz .failed
	mov rax,[capture_color.view]
	mov [framebuffer_views],rax
	test [active_caps],CAP_RENDER
	jnz .buffer
	require_vk vkCreateFramebuffer [device],addr framebuffer_info,0,addr capture_framebuffer
.buffer:
	mov edx,[frame_width]
	imul edx,[frame_height]
	shl rdx,2
	xor r9d,r9d
	test [active_caps],CAP_COMMAND_ADDRESS
	setnz r9b
	fastcall create_buffer,addr readback_buffer,rdx,VK_BUFFER_USAGE_TRANSFER_DST_BIT or VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,r9
	test eax,eax
	jz .failed
	mov edx,[frame_width]
	imul edx,[frame_height]
	shl rdx,2
	fastcall VirtualAlloc,0,rdx,MEM_COMMIT or MEM_RESERVE,PAGE_READWRITE
	test rax,rax
	jz .failed
	mov [pixels],rax
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc destroy_capture_target
	cmp [capture_framebuffer],0
	je .image
	vkDestroyFramebuffer [device],[capture_framebuffer],0
	mov [capture_framebuffer],0
.image:
	fastcall destroy_image,addr capture_color
	fastcall destroy_buffer,addr readback_buffer
	cmp [pixels],0
	je .done
	fastcall VirtualFree,[pixels],0,MEM_RELEASE
	mov [pixels],0
.done:
	ret
endp

section '.data$cube_capture' data readable writeable align 8
capture_color GpuImage
capture_framebuffer dq 0
