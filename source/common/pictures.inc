; The pictures, from the CPU's side: the packer's table and texels go into
; host-visible memory once, three passes on the device turn them into every
; frame's texels and masks in memory only shaders touch, and the packer's copy
; is let go. The shaders are in pictures.slang; art.txt lists the frames.
;
; A program includes this after machine.inc, embeds the three passes, and at
; startup, with the device idle:
;
;	pictures_create		RCX = the Pictures block at the head of its World
;	(flush that World and point Root.world at it)
;	pictures_develop	the three passes; returns when the device has run them
;
; and in release_world, pictures_release.
include 'build\myhits_art.inc'

macro art_frame name*,texels*,mask*,width*,height*,flags*,recipe*,argument*,solid*,checksum*
	dd texels,mask,width,height,flags,recipe,argument,solid,checksum
end macro
macro art_stroke from_x*,from_y*,to_x*,to_y*,radius*,outline*,color*
	dd from_x,from_y,to_x,to_y,radius,outline,color
end macro
assert sizeof.Picture = 36 & sizeof.Stroke = 28

PACKED_BYTES := ART_FRAMES * sizeof.Picture + ART_STROKES * sizeof.Stroke + ART_BAKED_TEXELS * 4
PICTURES_BYTES := sizeof.Census + ART_FRAMES * sizeof.Picture + ART_TEXELS * 4 + ART_MASK_WORDS * 4
PICTURES_PASSES := 3

section '.text$pictures' code readable executable align 16

proc pictures_create uses rbx rsi rdi,header
	mov rbx,rcx
	require_ok fastcall create_buffer,addr pictures_buffer,PICTURES_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_DEVICE
	require_ok fastcall create_buffer,addr packed_buffer,PACKED_BYTES,VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,MEMORY_UPLOAD
	mov rdi,[packed_buffer.mapped]
	lea rsi,[packed_art]
	mov ecx,PACKED_BYTES
	rep movsb
	require_ok fastcall flush_buffer,addr packed_buffer
	mov rax,[pictures_buffer.address]
	mov [rbx+Pictures.census],rax
	add rax,sizeof.Census
	mov [rbx+Pictures.frames],rax
	add rax,ART_FRAMES*sizeof.Picture
	mov [rbx+Pictures.texels],rax
	add rax,ART_TEXELS*4
	mov [rbx+Pictures.masks],rax
	mov rax,[packed_buffer.address]
	mov [rbx+Pictures.packed_frames],rax
	add rax,ART_FRAMES*sizeof.Picture
	mov [rbx+Pictures.strokes],rax
	add rax,ART_STROKES*sizeof.Stroke
	mov [rbx+Pictures.packed_texels],rax
	mov dword [rbx+Pictures.count],ART_FRAMES
	mov dword [rbx+Pictures.baked_texels],ART_BAKED_TEXELS
	mov dword [rbx+Pictures.texel_count],ART_TEXELS
	mov dword [rbx+Pictures.mask_words],ART_MASK_WORDS
	iterate name, develop,chart,census
		require_ok fastcall machine_compute,addr name#_code,name#_code.size,addr name#_pipeline
	end iterate
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

; Texels, then the masks that read them, then the count that reads both.
proc pictures_develop
	require_ok fastcall machine_serial_open
	fastcall machine_dispatch,[develop_pipeline],(ART_TEXELS+63)/64
	fastcall machine_settle
	fastcall machine_dispatch,[chart_pipeline],(ART_MASK_WORDS+63)/64
	fastcall machine_settle
	fastcall machine_dispatch,[census_pipeline],ART_FRAMES
	require_ok fastcall machine_serial_close
	; The device has its own copy of everything now.
	fastcall destroy_buffer,addr packed_buffer
	mov eax,1
	ret
.failed:
	xor eax,eax
	ret
endp

proc pictures_release
	iterate name, develop,chart,census
		cmp [name#_pipeline],0
		je .skip_#name
		vkDestroyPipeline [device],[name#_pipeline],0
		mov [name#_pipeline],0
	.skip_#name:
	end iterate
	fastcall destroy_buffer,addr packed_buffer
	fastcall destroy_buffer,addr pictures_buffer
	ret
endp

section '.data$pictures' data readable writeable align 16
pictures_buffer GpuBuffer
packed_buffer GpuBuffer
develop_pipeline dq 0
chart_pipeline dq 0
census_pipeline dq 0

; As the device first sees them: the table, the strokes, the cut texels.
section '.rdata$pictures' data readable align 16
packed_art:
	art_frames
	art_strokes
	file 'build\myhits_art.bin'
assert $ - packed_art = PACKED_BYTES
