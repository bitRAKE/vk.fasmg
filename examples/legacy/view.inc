; The camera, and the push constants each pipeline reads it through.
; The camera is double precision whatever the pipeline computes with.
PRECISION_FLOAT32 := 1
PRECISION_FLOAT64 := 2			; shaderFloat64
PRECISION_PAIRS := 3			; pairs of floats, where the device has no float64
PUSH_BYTES := 48
DEFAULT_ITERATIONS := 192
ITERATION_FLOOR := 16
ITERATION_LIMIT := 2048
; Virtual-key codes, as numbers: a quoted letter would reach fastcall as text.
KEY_PALETTE := 50h			; P
KEY_RESET := 52h			; R
KEY_DEEP := 44h				; D
KEY_TOUR := 54h				; T
KEY_EXPORT := 53h			; S
; What apply_key reports.
VIEW_MOVED := 1
VIEW_RECOLORED := 2

section '.text$view' code readable executable align 16
; Narrow views leave float32 behind: for doubles where the device enabled
; them, for float pairs where it did not.
proc select_precision
	mov [precision],PRECISION_FLOAT32
	movsd xmm0,[view_scale]
	ucomisd xmm0,[float_scale_floor]
	jae .done
	mov [precision],PRECISION_PAIRS
	test [active_caps],CAP_FLOAT64
	jz .done
	mov [precision],PRECISION_FLOAT64
.done:
	ret
endp

; Returns VIEW_MOVED or VIEW_RECOLORED when the key changed the picture.
proc apply_key key
	iterate <code,target>, VK_ADD,.zoom_in,0BBh,.zoom_in,VK_SUBTRACT,.zoom_out,0BDh,.zoom_out, \
		VK_LEFT,.left,VK_RIGHT,.right,VK_UP,.up,VK_DOWN,.down,KEY_PALETTE,.palette,KEY_RESET,.reset,KEY_DEEP,.deep
		cmp ecx,code
		je target
	end iterate
	xor eax,eax
	ret
.zoom_in:
	movsd xmm0,[view_scale]
	mulsd xmm0,[half_double]
	maxsd xmm0,[minimum_scale]
	jmp .scale
.zoom_out:
	movsd xmm0,[view_scale]
	addsd xmm0,xmm0
	minsd xmm0,[maximum_scale]
.scale:
	movsd [view_scale],xmm0
	jmp .moved
.left:
	movsd xmm0,[view_scale]
	mulsd xmm0,[pan_fraction]
	movsd xmm1,[center_x]
	subsd xmm1,xmm0
	movsd [center_x],xmm1
	jmp .moved
.right:
	movsd xmm0,[view_scale]
	mulsd xmm0,[pan_fraction]
	addsd xmm0,[center_x]
	movsd [center_x],xmm0
	jmp .moved
.up:
	movsd xmm0,[view_scale]
	mulsd xmm0,[pan_fraction]
	movsd xmm1,[center_y]
	subsd xmm1,xmm0
	movsd [center_y],xmm1
	jmp .moved
.down:
	movsd xmm0,[view_scale]
	mulsd xmm0,[pan_fraction]
	addsd xmm0,[center_y]
	movsd [center_y],xmm0
	jmp .moved
.palette:
	inc [palette]
	and [palette],7
	mov eax,VIEW_RECOLORED
	ret
.reset:
	mov rax,[default_x]
	mov [center_x],rax
	mov [center_y],0
	mov rax,[default_scale]
	mov [view_scale],rax
	mov [palette],0
	mov [iterations],DEFAULT_ITERATIONS
	jmp .moved
.deep:
	mov rax,[deep_x]
	mov [center_x],rax
	mov rax,[deep_y]
	mov [center_y],rax
	mov rax,[deep_scale]
	mov [view_scale],rax
.moved:
	fastcall select_precision
	mov eax,VIEW_MOVED
	ret
endp

; Halve the scale, or double it when `outward` is set, about the pixel in
; `position`: client x in the low word, y in the next. The point under the
; cursor stays under it, so the same click undoes the other button's.
proc zoom_at position,outward
	movsx eax,cx
	shr ecx,16
	movsx ecx,cx
	movsd xmm4,[view_scale]
	movapd xmm5,xmm4
	test edx,edx
	jnz .outward
	mulsd xmm5,[half_double]
	maxsd xmm5,[minimum_scale]
	jmp .scaled
.outward:
	addsd xmm5,xmm5
	minsd xmm5,[maximum_scale]
.scaled:
	; A pixel's width in the plane shrinks or grows by this much; the center
	; moves by that for each pixel between it and the cursor.
	subsd xmm4,xmm5
	cvtsi2sd xmm3,dword [frame_height]
	divsd xmm4,xmm3
	iterate <coordinate,extent,center>, eax,frame_width,center_x, ecx,frame_height,center_y
		cvtsi2sd xmm0,coordinate
		addsd xmm0,[half_double]
		cvtsi2sd xmm1,dword [extent]
		mulsd xmm1,[half_double]
		subsd xmm0,xmm1
		mulsd xmm0,xmm4
		addsd xmm0,[center]
		movsd [center],xmm0
	end iterate
	movsd [view_scale],xmm5
	fastcall select_precision
	ret
endp

; A wheel notch forward is a quarter more iterations; back, a fifth fewer.
proc change_iterations notches
	mov eax,[iterations]
	test ecx,ecx
	jle .fewer
	lea eax,[rax+rax*4]
	shr eax,2
	cmp eax,ITERATION_LIMIT
	jbe .store
	mov eax,ITERATION_LIMIT
	jmp .store
.fewer:
	shl eax,2
	xor edx,edx
	mov ecx,5
	div ecx
	cmp eax,ITERATION_FLOOR
	jae .store
	mov eax,ITERATION_FLOOR
.store:
	mov [iterations],eax
	ret
endp

; Fill the push constants for a target whose top-left pixel is that one of the
; whole picture, and choose the pipeline that reads them.
proc write_view origin_x,origin_y
	cvtsi2ss xmm4,ecx
	cvtsi2ss xmm5,edx
	cvtsi2ss xmm2,dword [frame_width]
	cvtsi2ss xmm3,dword [frame_height]
	mov eax,[palette]
	mov edx,[iterations]
	cmp [precision],PRECISION_FLOAT32
	jne .deep
	; fractal.frag: center, scale, palette, origin, size, iterations
	mov [push_data+12],eax
	mov [push_data+32],edx
	cvtsd2ss xmm0,[center_x]
	movss [push_data],xmm0
	cvtsd2ss xmm0,[center_y]
	movss [push_data+4],xmm0
	cvtsd2ss xmm0,[view_scale]
	movss [push_data+8],xmm0
	movss [push_data+16],xmm4
	movss [push_data+20],xmm5
	movss [push_data+24],xmm2
	movss [push_data+28],xmm3
	mov rax,[pipeline]
	mov [draw_pipeline],rax
	ret
.deep:
	; Both deep shaders: palette, iterations, origin and size after 24 bytes of camera.
	mov [push_data+24],eax
	mov [push_data+28],edx
	movss [push_data+32],xmm4
	movss [push_data+36],xmm5
	movss [push_data+40],xmm2
	movss [push_data+44],xmm3
	mov rax,[deep_pipeline]
	mov [draw_pipeline],rax
	cmp [precision],PRECISION_FLOAT64
	jne .pairs
	; fractal64.frag: the camera as it is
	mov rax,[center_x]
	mov [push_data],rax
	mov rax,[center_y]
	mov [push_data+8],rax
	mov rax,[view_scale]
	mov [push_data+16],rax
	ret
.pairs:
	; fractal32x2.frag: each double as the nearest float and what that left
	; out, and the size of one pixel in place of the scale.
	movsd xmm0,[view_scale]
	cvtsi2sd xmm1,dword [frame_height]
	divsd xmm0,xmm1
	movsd [pixel_step],xmm0
	iterate <value,high,low>, center_x,0,8,center_y,4,12,pixel_step,16,20
		movsd xmm0,[value]
		cvtsd2ss xmm1,xmm0
		movss [push_data+high],xmm1
		cvtss2sd xmm1,xmm1
		subsd xmm0,xmm1
		cvtsd2ss xmm0,xmm0
		movss [push_data+low],xmm0
	end iterate
	ret
endp

section '.data$view' data readable writeable align 16
center_x dq -0.5
center_y dq 0.0
view_scale dq 3.0
minimum_scale dq 0.0000000000001
pixel_step dq 0.0
draw_pipeline dq 0
push_data:
	rb PUSH_BYTES
palette dd 0
iterations dd DEFAULT_ITERATIONS
precision dd PRECISION_FLOAT32

section '.rdata$view' data readable align 8
half_double dq 0.5
float_scale_floor dq 0.0001
; Where a pixel is still several steps of the arithmetic wide.
double_minimum_scale dq 0.0000000000001
pairs_minimum_scale dq 0.0000000001
maximum_scale dq 8.0
pan_fraction dq 0.15
default_x dq -0.5
default_scale dq 3.0
deep_x dq -0.743643887037151
deep_y dq 0.13182590420533
deep_scale dq 0.00001
