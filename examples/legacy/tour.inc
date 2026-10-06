; T tours well-known places of the set. A leg is one or two segments. Each
; eases the scale along its logarithm and the destination's offset on screen
; to nothing, so the motion looks alike at every depth. Where the next stop is
; out of sight, a first segment backs out about the center the view has until
; it is not; the second closes in.
TOUR_IDLE := 0
TOUR_TRAVEL := 1
TOUR_DWELL := 2

struct TourStop
	x dq ?
	y dq ?
	scale dq ?
	title dq ?
ends

section '.text$tour' code readable executable align 16

; T: set out for the next stop from wherever the view is. Pressed on the way,
; it passes that stop by.
proc tour_go
	cmp [tour_state],TOUR_TRAVEL
	jne .leg
	mov eax,[tour_next]
	inc eax
	cmp eax,TOUR_STOPS
	jb .passed
	xor eax,eax
.passed:
	mov [tour_next],eax
.leg:
	fastcall QueryPerformanceCounter,addr tour_clock
	fastcall tour_begin_leg
	ret
endp

; Plan the way from the view as it is to the stop at tour_next.
proc tour_begin_leg
	mov eax,[tour_next]
	imul eax,sizeof.TourStop
	lea rdx,[tour_stops]
	add rdx,rax
	; The scale at which the stop comes within reach of the view's center.
	iterate <register,to,center>, xmm0,x,center_x, xmm1,y,center_y
		movsd register,[rdx+TourStop.to]
		subsd register,[center]
		xorpd xmm2,xmm2
		subsd xmm2,register
		maxsd register,xmm2
	end iterate
	maxsd xmm0,xmm1
	divsd xmm0,[tour_reach]
	minsd xmm0,[maximum_scale]
	movsd xmm1,[view_scale]
	mulsd xmm1,[tour_slack]
	ucomisd xmm0,xmm1
	jbe .approach
	; Out of sight: back out first, about the center the view has.
	mov [tour_backing],1
	movsd [tour_to_scale],xmm0
	mov rax,[center_x]
	mov [tour_to_x],rax
	mov rax,[center_y]
	mov [tour_to_y],rax
	jmp .segment
.approach:
	mov [tour_backing],0
	iterate field, x,y,scale
		mov rax,[rdx+TourStop.field]
		mov [tour_to_#field],rax
	end iterate
.segment:
	fastcall tour_begin_segment
	mov [tour_state],TOUR_TRAVEL
	ret
endp

; Begin a segment from the view as it is to tour_to.
proc tour_begin_segment
	movsd xmm3,[view_scale]
	movsd [tour_from_scale],xmm3
	; Where the destination is on screen now, in view heights from the center.
	iterate <to,center,offset>, tour_to_x,center_x,tour_offset_x, tour_to_y,center_y,tour_offset_y
		movsd xmm0,[to]
		subsd xmm0,[center]
		divsd xmm0,xmm3
		movsd [offset],xmm0
	end iterate
	; Octaves of scale to cover: log2(to / from).
	movsd xmm0,[tour_to_scale]
	divsd xmm0,xmm3
	movsd [tour_octaves],xmm0
	fld1
	fld qword [tour_octaves]
	fyl2x
	fstp qword [tour_octaves]
	; A steady pace per octave, and time enough when there is only a pan.
	movsd xmm0,[tour_octaves]
	xorpd xmm1,xmm1
	subsd xmm1,xmm0
	maxsd xmm0,xmm1
	mulsd xmm0,[tour_octave_seconds]
	maxsd xmm0,[tour_shortest]
	movsd [tour_duration],xmm0
	mov [tour_progress],0
	ret
endp

; Move the tour on by XMM0 seconds. Returns nonzero when the view changed.
proc tour_advance
	cmp [tour_state],TOUR_TRAVEL
	je .travel
	cmp [tour_state],TOUR_DWELL
	jne .still
	addsd xmm0,[tour_rested]
	movsd [tour_rested],xmm0
	ucomisd xmm0,[tour_rest]
	jb .still
	fastcall tour_begin_leg
.still:
	xor eax,eax
	ret
.travel:
	divsd xmm0,[tour_duration]
	addsd xmm0,[tour_progress]
	ucomisd xmm0,[one_double]
	jae .arrive
	movsd [tour_progress],xmm0
	; Ease: u * u * (3 - 2u) starts and ends at rest.
	movapd xmm1,xmm0
	addsd xmm1,xmm1
	movsd xmm2,[three_double]
	subsd xmm2,xmm1
	mulsd xmm0,xmm0
	mulsd xmm0,xmm2
	; scale = from * 2^(eased * octaves), whole and fractional powers apart.
	movapd xmm1,xmm0
	mulsd xmm1,[tour_octaves]
	movsd [tour_power],xmm1
	fld qword [tour_power]
	fld st0
	frndint
	fsub st1,st0
	fxch st1
	f2xm1
	fld1
	faddp st1,st0
	fscale
	fstp st1
	fmul qword [tour_from_scale]
	fstp qword [view_scale]
	; The destination's offset on screen eases to nothing.
	movsd xmm1,[one_double]
	subsd xmm1,xmm0
	mulsd xmm1,[view_scale]
	iterate <to,offset,center>, tour_to_x,tour_offset_x,center_x, tour_to_y,tour_offset_y,center_y
		movsd xmm2,[offset]
		mulsd xmm2,xmm1
		movsd xmm3,[to]
		subsd xmm3,xmm2
		movsd [center],xmm3
	end iterate
	jmp .moved
.arrive:
	; Exactly there, whatever the steps added up to.
	iterate <to,view>, tour_to_x,center_x, tour_to_y,center_y, tour_to_scale,view_scale
		mov rax,[to]
		mov [view],rax
	end iterate
	cmp [tour_backing],0
	je .there
	; The stop is in sight: close in on it.
	mov [tour_backing],0
	mov eax,[tour_next]
	imul eax,sizeof.TourStop
	lea rdx,[tour_stops]
	iterate field, x,y,scale
		mov rcx,[rdx+rax+TourStop.field]
		mov [tour_to_#field],rcx
	end iterate
	fastcall tour_begin_segment
	jmp .moved
.there:
	mov eax,[tour_next]
	mov [tour_at],eax
	inc eax
	mov [tour_state],TOUR_DWELL
	mov [tour_rested],0
	cmp eax,TOUR_STOPS
	jb .next
	; The last stop is the first view, and the end of the tour.
	xor eax,eax
	mov [tour_state],TOUR_IDLE
.next:
	mov [tour_next],eax
.moved:
	fastcall select_precision
	mov eax,1
	ret
endp

; One frame of the tour, timed by the clock; the scripted run steps evenly.
; Returns nonzero when it drew.
proc tour_frame
	cmp [tour_state],TOUR_IDLE
	je .none
	movsd xmm0,[tour_scripted_step]
	cmp [test_mode],0
	jne .advance
	fastcall QueryPerformanceCounter,addr tour_now
	mov rax,[tour_now]
	mov rdx,rax
	sub rax,[tour_clock]
	mov [tour_clock],rdx
	cvtsi2sd xmm0,rax
	cvtsi2sd xmm1,qword [tour_frequency]
	divsd xmm0,xmm1
	; A stall, in a dialog or a dragged window, is not a jump in the tour.
	minsd xmm0,[tour_longest_step]
.advance:
	fastcall tour_advance
	test eax,eax
	jz .none
	fastcall redraw
	mov eax,1
	ret
.none:
	xor eax,eax
	ret
endp

section '.data$tour' data readable writeable align 8
tour_clock dq 0
tour_now dq 0
tour_frequency dq 1
tour_to_x dq 0.0
tour_to_y dq 0.0
tour_to_scale dq 0.0
tour_from_scale dq 0.0
tour_offset_x dq 0.0
tour_offset_y dq 0.0
tour_octaves dq 0.0
tour_power dq 0.0
tour_duration dq 1.0
tour_progress dq 0.0
tour_rested dq 0.0
tour_state dd TOUR_IDLE
tour_next dd 0				; the stop a leg heads for
tour_at dd 0				; the stop last reached
tour_backing dd 0

section '.rdata$tour' data readable align 8
one_double dq 1.0
three_double dq 3.0
tour_reach dq 0.45			; of the view's height: near enough to its center
tour_slack dq 1.001
tour_octave_seconds dq 0.7		; the scale halves in about this long
tour_shortest dq 1.2
tour_rest dq 3.0			; seconds at a stop
tour_longest_step dq 0.1
tour_scripted_step dq 0.1

macro tour_stop name*,real*,imaginary*,height*
	local text
	text GLOBWSTR name,0
	TourStop x: real,y: imaginary,scale: height,title: text
end macro
tour_stops:
	tour_stop 'Seahorse Valley',-0.7453,0.1127,0.0065
	tour_stop 'a seahorse tail',-0.743643887037151,0.13182590420533,0.00001
	tour_stop 'Elephant Valley',0.285,0.0125,0.012
	tour_stop 'Quad Spiral Valley',0.274,0.482,0.01
	tour_stop 'Triple Spiral Valley',-0.088,0.654,0.012
	tour_stop 'Double Scepter Valley',-0.1002,0.8383,0.01
	tour_stop 'a Mandelbrot beyond the bulb',-0.1592,1.0317,0.03
	tour_stop 'Scepter Valley',-1.3775,0.012,0.02
	tour_stop 'the Mandelbrot on the needle',-1.7548776662466927,0.0,0.06
	tour_stop 'the whole set',-0.5,0.0,3.0
TOUR_STOPS := ($ - tour_stops) / sizeof.TourStop
