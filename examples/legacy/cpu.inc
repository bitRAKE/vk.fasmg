; SSE2 double precision is an application alternate, not emulated shaderFloat64.
; All controls/export use the same camera and palette, whichever renderer wins.
section '.text$cpu' code readable executable align 16
proc render_cpu uses rbx rsi rdi
	movsd xmm0,[view_scale]
	divsd xmm0,[frame_height_double]
	movsd [cpu_step],xmm0
	movsd xmm1,[half_width]
	mulsd xmm1,xmm0
	movsd xmm2,[center_x]
	subsd xmm2,xmm1
	movsd [cpu_first_x],xmm2
	movsd xmm1,[half_height]
	mulsd xmm1,xmm0
	movsd xmm2,[center_y]
	subsd xmm2,xmm1
	movsd [cpu_y],xmm2
	lea rdi,[pixels]
	mov r8d,FRAME_HEIGHT
	mov ebx,[palette]
	imul ebx,41
.row:
	movsd xmm0,[cpu_first_x]
	movsd [cpu_x],xmm0
	mov r9d,FRAME_WIDTH
.pixel:
	xorpd xmm0,xmm0
	xorpd xmm1,xmm1
	xor ecx,ecx
.iterate:
	movapd xmm2,xmm0
	mulsd xmm2,xmm2
	movapd xmm3,xmm1
	mulsd xmm3,xmm3
	movapd xmm4,xmm2
	addsd xmm4,xmm3
	ucomisd xmm4,[escape_radius]
	ja .color
	movapd xmm5,xmm0
	mulsd xmm5,xmm1
	addsd xmm5,xmm5
	addsd xmm5,[cpu_y]
	movapd xmm0,xmm2
	subsd xmm0,xmm3
	addsd xmm0,[cpu_x]
	movapd xmm1,xmm5
	inc ecx
	cmp ecx,192
	jb .iterate
.color:
	mov eax,0FF0A0F1Ah
	cmp ecx,192
	je .store
	imul ecx,7
	add ecx,ebx
	imul eax,ecx,3
	and eax,255
	shl eax,16
	imul edx,ecx,5
	add edx,64
	and edx,255
	shl edx,8
	or eax,edx
	imul edx,ecx,7
	add edx,128
	and edx,255
	or eax,edx
	or eax,0FF000000h
.store:
	stosd
	movsd xmm0,[cpu_x]
	addsd xmm0,[cpu_step]
	movsd [cpu_x],xmm0
	dec r9d
	jnz .pixel
	movsd xmm0,[cpu_y]
	addsd xmm0,[cpu_step]
	movsd [cpu_y],xmm0
	dec r8d
	jnz .row
	ret
endp

proc render_frame uses rbx
	fastcall GetTickCount64
	mov rbx,rax
	mov [last_backend],0
	cmp [gpu_ready],0
	je .cpu
	cmp [software_override],0
	jne .cpu
	; Host double precision retains the camera when float coordinates collapse.
	movsd xmm0,[view_scale]
	ucomisd xmm0,[float_scale_floor]
	jb .cpu
	fastcall render_gpu
	test eax,eax
	jz .lost
	mov [last_backend],1
	jmp .done
.lost:
	mov [gpu_ready],0
	fastcall destroy_gpu
.cpu:
	fastcall render_cpu
.done:
	fastcall GetTickCount64
	sub rax,rbx
	mov [render_ms],eax
	inc [frame_count]
	ret
endp

section '.data$camera' data readable writeable align 16
center_x dq -0.5
center_y dq 0.0
view_scale dq 3.0
palette dd 0
gpu_ready dd 0
software_override dd 0
last_backend dd 0
render_ms dd 0
frame_count dd 0
cpu_x dq 0.0
cpu_y dq 0.0
cpu_first_x dq 0.0
cpu_step dq 0.0

section '.rdata$camera' data readable align 8
frame_height_double dq FRAME_HEIGHT * 1.0
half_width dq FRAME_WIDTH * 0.5 - 0.5
half_height dq FRAME_HEIGHT * 0.5 - 0.5
escape_radius dq 4.0
float_scale_floor dq 0.0001
minimum_scale dq 0.0000000000001
maximum_scale dq 8.0
two_double dq 2.0
pan_fraction dq 0.15
default_x dq -0.5
default_scale dq 3.0
deep_x dq -0.743643887037151
deep_y dq 0.13182590420533
deep_scale dq 0.00001

section '.bss$pixels' readable writeable align 64
pixels rb FRAME_BYTES
