; Pictures of chosen frames. A scripted run draws to a window nobody sees; a
; claim about what is on screen is better looked at. A program that wants
; pictures defines MACHINE_SNAPSHOT before it includes machine.inc, keeps its
; draws in a procedure of its own,
;
;	draw_world	every machine_draw of a frame, and nothing else
;
; which it calls itself between machine_canvas and machine_close, and asks:
;
;	snapshot_start	once, when pictures are wanted (the checks)
;	snapshot_take	ECX = the number for the file's name; before machine_close
;
; The frame's draws are then recorded a second time into an image of the
; whole playfield, 1920 by 1080 whatever the window is, and when the frame has
; retired that image is written as build\myhits_<tag>.<number>.bmp. The proof
; runner turns those into PNGs beside each proof's log.
;
; Not for a program whose fragments count themselves: they would count twice.

SNAPSHOT_BYTES := PLAYFIELD_WIDTH * PLAYFIELD_HEIGHT * 4

section '.text$snapshot' code readable executable align 16

; (It has no section of its own: it goes where it is included.)
include '..\..\examples\common\bitmap.inc'

proc snapshot_start
	mov eax,[target_format]
	mov [snapshot_image_info.format],eax
	mov [snapshot_view_info.format],eax
	require_ok fastcall create_image,addr snapshot_image,addr snapshot_image_info,addr snapshot_view_info
	require_ok fastcall create_buffer,addr snapshot_buffer,SNAPSHOT_BYTES,VK_BUFFER_USAGE_TRANSFER_DST_BIT,MEMORY_READBACK
	mov [snapshot_ready],1
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc snapshot_take number
	cmp [snapshot_ready],0
	je .done
	inc ecx
	mov [snapshot_wanted],ecx
.done:
	ret
endp

; From machine_close, between the picture on screen and the frame's
; submission: the same draws again, into the picture's own image, and that
; image into memory the CPU can read.
proc snapshot_record uses rbx rsi
	fastcall transition_image,[snapshot_image.handle],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_UNDEFINED,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,0,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
	mov rbx,[render_color.imageView]
	mov rsi,qword [rendering_info.renderArea.extent]
	mov rax,[snapshot_image.view]
	mov [render_color.imageView],rax
	mov [rendering_info.renderArea.extent.width],PLAYFIELD_WIDTH
	mov [rendering_info.renderArea.extent.height],PLAYFIELD_HEIGHT
	vkCmdBeginRendering [command_buffer],addr rendering_info
	vkCmdSetViewport [command_buffer],0,1,addr snapshot_viewport
	vkCmdSetScissor [command_buffer],0,1,addr snapshot_rect
	mov [render_color.imageView],rbx
	mov qword [rendering_info.renderArea.extent],rsi
	; The picture's draws are not the frame's: the count is the frame's.
	mov ebx,[draw_count]
	fastcall draw_world
	mov [draw_count],ebx
	vkCmdEndRendering [command_buffer]
	fastcall transition_image,[snapshot_image.handle],VK_IMAGE_ASPECT_COLOR_BIT,VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_READ_BIT
	vkCmdCopyImageToBuffer [command_buffer],[snapshot_image.handle],VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,[snapshot_buffer.handle],1,addr snapshot_region
	fastcall memory_barrier,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_PIPELINE_STAGE_HOST_BIT,VK_ACCESS_HOST_READ_BIT
	mov eax,[snapshot_wanted]
	mov [snapshot_recorded],eax
	mov [snapshot_wanted],0
	ret
endp

; Once the frame that recorded a picture has retired: write it out.
proc snapshot_save
	cmp [snapshot_recorded],0
	je .done
	fastcall invalidate_buffer,addr snapshot_buffer
	mov r8d,[snapshot_recorded]
	dec r8d
	mov [snapshot_recorded],0
	fastcall wsprintfW,addr snapshot_path,<W,'build\myhits_' bappend MACHINE_TAG bappend '.%u.bmp'>,r8
	fastcall save_bitmap,addr snapshot_path,[snapshot_buffer.mapped],PLAYFIELD_WIDTH,PLAYFIELD_HEIGHT
.done:
	ret
endp

proc snapshot_stop
	cmp [snapshot_ready],0
	je .done
	mov [snapshot_ready],0
	fastcall destroy_buffer,addr snapshot_buffer
	fastcall destroy_image,addr snapshot_image
.done:
	ret
endp

section '.data$snapshot' data readable writeable align 16
snapshot_image GpuImage
snapshot_buffer GpuBuffer
snapshot_ready dd 0
snapshot_wanted dd 0			; the number of the picture this frame is to be, plus one
snapshot_recorded dd 0			; the same, of the one a submitted frame recorded
save_byte_count dd 0
snapshot_image_info VkImageCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,imageType: VK_IMAGE_TYPE_2D,extent: <width: PLAYFIELD_WIDTH,height: PLAYFIELD_HEIGHT,depth: 1>, \
	mipLevels: 1,arrayLayers: 1,samples: VK_SAMPLE_COUNT_1_BIT,tiling: VK_IMAGE_TILING_OPTIMAL,usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT or VK_IMAGE_USAGE_TRANSFER_SRC_BIT
snapshot_view_info VkImageViewCreateInfo sType: VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,viewType: VK_IMAGE_VIEW_TYPE_2D, \
	subresourceRange: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,levelCount: 1,layerCount: 1>
snapshot_region VkBufferImageCopy imageSubresource: <aspectMask: VK_IMAGE_ASPECT_COLOR_BIT,layerCount: 1>,imageExtent: <width: PLAYFIELD_WIDTH,height: PLAYFIELD_HEIGHT,depth: 1>
snapshot_viewport VkViewport width: 1920.0,height: 1080.0,minDepth: 0.0,maxDepth: 1.0
snapshot_rect VkRect2D extent: <width: PLAYFIELD_WIDTH,height: PLAYFIELD_HEIGHT>
; A bitmap's header: 14 bytes of file and 40 of picture, 32 bits a pixel.
bitmap_file_header:
	db 'BM'
.length dd 0
	dw 0,0
	dd 54
.info:
	dd 40
.info.biWidth dd 0
.info.biHeight dd 0
	dw 1,32
	dd 0
.info.biSizeImage dd 0
	dd 0,0,0,0

section '.bss$snapshot' readable writeable align 8
snapshot_path rw 96
